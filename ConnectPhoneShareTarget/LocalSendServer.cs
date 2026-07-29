using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using Windows.Data.Xml.Dom;
using Windows.UI.Notifications;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace ConnectPhoneShareTarget
{
    public class RegisterDto
    {
        [JsonPropertyName("alias")] public string Alias { get; set; } = "DeXDesktop";
        [JsonPropertyName("version")] public string Version { get; set; } = "2.0";
        [JsonPropertyName("deviceModel")] public string DeviceModel { get; set; } = "Windows PC";
        [JsonPropertyName("deviceType")] public string DeviceType { get; set; } = "desktop";
        [JsonPropertyName("fingerprint")] public string Fingerprint { get; set; } = "dexdesktop-fingerprint";
        [JsonPropertyName("port")] public int Port { get; set; } = 53317;
        [JsonPropertyName("protocol")] public string Protocol { get; set; } = "https";
        [JsonPropertyName("download")] public bool Download { get; set; } = true;
    }

    public class PrepareUploadRequestDto
    {
        [JsonPropertyName("info")] public RegisterDto Info { get; set; } = new();
        [JsonPropertyName("files")] public Dictionary<string, FileDto> Files { get; set; } = new();
    }

    public class FileDto
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("fileName")] public string FileName { get; set; } = "";
        [JsonPropertyName("size")] public long Size { get; set; }
        [JsonPropertyName("fileType")] public string FileType { get; set; } = "";
    }

    public class PrepareUploadResponseDto
    {
        [JsonPropertyName("sessionId")] public string SessionId { get; set; } = "";
        [JsonPropertyName("files")] public Dictionary<string, string> Files { get; set; } = new();
    }

    public class DiscoveredDevice
    {
        public string Ip { get; set; } = "";
        public RegisterDto Info { get; set; } = new();
        public long LastSeen { get; set; }
    }

    public class DiscoveryBackgroundService : BackgroundService
    {
        public static readonly ConcurrentDictionary<string, DiscoveredDevice> Devices = new();

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            var myInfo = new RegisterDto { Fingerprint = "dexdesktop-fingerprint" };
            var myInfoBytes = JsonSerializer.SerializeToUtf8Bytes(myInfo);

            using var udpClient = new UdpClient();
            udpClient.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            udpClient.Client.Bind(new IPEndPoint(IPAddress.Any, 53317));

            // Broadcaster task
            _ = Task.Run(async () =>
            {
                using var broadcastClient = new UdpClient();
                broadcastClient.EnableBroadcast = true;
                while (!stoppingToken.IsCancellationRequested)
                {
                    try
                    {
                        await broadcastClient.SendAsync(myInfoBytes, myInfoBytes.Length, new IPEndPoint(IPAddress.Broadcast, 53317));
                    }
                    catch { }
                    await Task.Delay(2000, stoppingToken);
                }
            }, stoppingToken);

            // Listener task
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    var result = await udpClient.ReceiveAsync(stoppingToken);
                    var payload = Encoding.UTF8.GetString(result.Buffer);
                    var dto = JsonSerializer.Deserialize<RegisterDto>(payload);
                    if (dto != null && dto.Fingerprint != myInfo.Fingerprint)
                    {
                        Devices[dto.Fingerprint] = new DiscoveredDevice
                        {
                            Ip = result.RemoteEndPoint.Address.ToString(),
                            Info = dto,
                            LastSeen = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                        };
                    }
                }
                catch { }
            }
        }
    }

    public static class LocalSendServer
    {
        public static WebApplication? App;

        public static async Task StartAsync()
        {
            var builder = WebApplication.CreateBuilder();

            // Self-signed certificate for TLS
            using var rsa = RSA.Create(2048);
            var request = new CertificateRequest("cn=localsend", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            var cert = request.CreateSelfSigned(DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddYears(1));

            builder.WebHost.ConfigureKestrel(options =>
            {
                options.ListenAnyIP(53317, listenOptions =>
                {
                    listenOptions.UseHttps(cert);
                });
                
                // Add a local unencrypted port for PowerShell GUI to query discovered devices easily
                options.ListenLocalhost(53318);
            });

            builder.Services.AddHostedService<DiscoveryBackgroundService>();

            App = builder.Build();

            App.MapGet("/api/localsend/v2/info", () => Results.Json(new RegisterDto()));
            
            App.MapPost("/api/localsend/v2/register", (RegisterDto req) => 
            {
                return Results.Json(new { sessionId = Guid.NewGuid().ToString() });
            });

            var activeSessions = new ConcurrentDictionary<string, PrepareUploadRequestDto>();

            App.MapPost("/api/localsend/v2/prepare-upload", (PrepareUploadRequestDto req) =>
            {
                var sessionId = Guid.NewGuid().ToString();
                activeSessions[sessionId] = req;
                var resFiles = new Dictionary<string, string>();
                foreach (var kvp in req.Files)
                {
                    resFiles[kvp.Key] = Guid.NewGuid().ToString(); // Token for the file
                }
                return Results.Json(new PrepareUploadResponseDto { SessionId = sessionId, Files = resFiles });
            });

            App.MapPost("/api/localsend/v2/upload", async (HttpRequest request) =>
            {
                var sessionId = request.Query["sessionId"].ToString();
                var fileId = request.Query["fileId"].ToString();
                var token = request.Query["token"].ToString(); // Token unused in minimal impl

                if (!activeSessions.TryGetValue(sessionId, out var sessionReq)) return Results.BadRequest();
                if (!sessionReq.Files.TryGetValue(fileId, out var fileMeta)) return Results.BadRequest();

                string downloadsFolder = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + "\\Downloads";
                string destPath = Path.Combine(downloadsFolder, fileMeta.FileName);

                using var fs = new FileStream(destPath, FileMode.Create);
                await request.Body.CopyToAsync(fs);

                try
                {
                    string toastXmlString = 
                    $@"<toast>
                        <visual>
                            <binding template='ToastGeneric'>
                                <text>DeX File Received</text>
                                <text>{fileMeta.FileName}</text>
                            </binding>
                        </visual>
                    </toast>";
                    var xmlDoc = new XmlDocument();
                    xmlDoc.LoadXml(toastXmlString);
                    var toastNode = new ToastNotification(xmlDoc);
                    ToastNotificationManager.CreateToastNotifier("ConnectPhoneADB").Show(toastNode);
                }
                catch { }

                return Results.Ok();
            });

            // Local API for PowerShell to read discovered devices
            App.MapGet("/local/devices", () => 
            {
                // Clean up stale
                var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                foreach (var k in DiscoveryBackgroundService.Devices.Keys)
                {
                    if (now - DiscoveryBackgroundService.Devices[k].LastSeen > 20000)
                        DiscoveryBackgroundService.Devices.TryRemove(k, out _);
                }
                return Results.Json(DiscoveryBackgroundService.Devices.Values);
            });

            await App.StartAsync();
        }
    }
}
