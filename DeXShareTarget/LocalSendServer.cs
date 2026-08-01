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
using System.Linq;
using Windows.Data.Xml.Dom;
using Windows.UI.Notifications;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace DeXShareTarget
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

            using var mdns = new Makaretu.Dns.MulticastService();
            var service = new Makaretu.Dns.ServiceProfile("DeXDesktop", "_dex._udp", (ushort)53317);
            service.AddProperty("alias", myInfo.Alias);
            service.AddProperty("fingerprint", myInfo.Fingerprint);
            
            var sd = new Makaretu.Dns.ServiceDiscovery(mdns);
            sd.Advertise(service);

            sd.ServiceDiscovered += (s, serviceName) => {
                mdns.SendQuery(serviceName, Makaretu.Dns.DnsClass.IN, Makaretu.Dns.DnsType.ANY);
            };

            sd.ServiceInstanceDiscovered += (s, e) => {
                try {
                    if (e.Message.Answers.Count > 0)
                    {
                        var srv = e.Message.Answers.OfType<Makaretu.Dns.SRVRecord>().FirstOrDefault();
                        var txt = e.Message.Answers.OfType<Makaretu.Dns.TXTRecord>().FirstOrDefault();
                        var a = e.Message.Answers.OfType<Makaretu.Dns.ARecord>().FirstOrDefault();
                        
                        if (srv != null && txt != null && a != null)
                        {
                            var fp = txt.Strings.FirstOrDefault(x => x.StartsWith("fingerprint="))?.Split('=')[1];
                            var alias = txt.Strings.FirstOrDefault(x => x.StartsWith("alias="))?.Split('=')[1];
                            
                            if (!string.IsNullOrEmpty(fp) && fp != myInfo.Fingerprint)
                            {
                                var dto = new RegisterDto { Fingerprint = fp, Alias = alias ?? "Unknown", Port = srv.Port };
                                Devices[fp] = new DiscoveredDevice
                                {
                                    Ip = a.Address.ToString(),
                                    Info = dto,
                                    LastSeen = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                                };
                            }
                        }
                    }
                } catch { }
            };

            mdns.Start();
            
            var multicastAddress = IPAddress.Parse("224.0.0.167");
            var endPoint = new IPEndPoint(IPAddress.Any, 53317);
            using var udp = new UdpClient();
            udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            udp.Client.Bind(endPoint);
            udp.JoinMulticastGroup(multicastAddress);

            var myJson = JsonSerializer.Serialize(myInfo);
            var myBytes = Encoding.UTF8.GetBytes(myJson);

            _ = Task.Run(async () =>
            {
                while (!stoppingToken.IsCancellationRequested)
                {
                    try
                    {
                        var result = await udp.ReceiveAsync(stoppingToken);
                        var msg = Encoding.UTF8.GetString(result.Buffer);
                        var doc = JsonDocument.Parse(msg);
                        var root = doc.RootElement;
                        var fp = root.TryGetProperty("fingerprint", out var f) ? f.GetString() : "";
                        if (!string.IsNullOrEmpty(fp) && fp != myInfo.Fingerprint)
                        {
                            var dto = new RegisterDto
                            {
                                Fingerprint = fp,
                                Alias = root.TryGetProperty("alias", out var a) ? a.GetString() : "Unknown",
                                Port = root.TryGetProperty("port", out var p) ? p.GetInt32() : 53317,
                                DeviceModel = root.TryGetProperty("deviceModel", out var dm) ? dm.GetString() : "Unknown",
                                DeviceType = root.TryGetProperty("deviceType", out var dt) ? dt.GetString() : "unknown"
                            };
                            Devices[fp] = new DiscoveredDevice
                            {
                                Ip = result.RemoteEndPoint.Address.ToString(),
                                Info = dto,
                                LastSeen = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                            };
                        }
                    } catch { }
                }
            }, stoppingToken);

            _ = Task.Run(async () =>
            {
                var targetEp = new IPEndPoint(multicastAddress, 53317);
                while (!stoppingToken.IsCancellationRequested)
                {
                    try
                    {
                        await udp.SendAsync(myBytes, myBytes.Length, targetEp);
                    } catch { }
                    await Task.Delay(2000, stoppingToken);
                }
            }, stoppingToken);
            
            while (!stoppingToken.IsCancellationRequested)
            {
                await Task.Delay(2000, stoppingToken);
            }
            
            sd.Unadvertise(service);
            mdns.Stop();
        }
    }

    public static class LocalSendServer
    {
        public static WebApplication? App;
        public static ConcurrentDictionary<string, string> HostedFiles = new();

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
                    listenOptions.Protocols = Microsoft.AspNetCore.Server.Kestrel.Core.HttpProtocols.Http1AndHttp2AndHttp3;
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
            HostedFiles = new ConcurrentDictionary<string, string>();

            App.MapPost("/api/localsend/v2/prepare-upload", (PrepareUploadRequestDto req) =>
            {
                var res = System.Windows.MessageBox.Show(
                    $"Incoming transfer: {req.Files.Count} files. Accept?", 
                    "ConnectPhone", 
                    System.Windows.MessageBoxButton.YesNo,
                    System.Windows.MessageBoxImage.Question, 
                    System.Windows.MessageBoxResult.No,
                    System.Windows.MessageBoxOptions.DefaultDesktopOnly);
                    
                if (res != System.Windows.MessageBoxResult.Yes) return Results.StatusCode(403);
                
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
                    ToastNotificationManager.CreateToastNotifier("DeX").Show(toastNode);
                }
                catch { }

                return Results.Ok();
            });

            App.MapGet("/download/{fileId}", async (string fileId, HttpContext context) =>
            {
                if (HostedFiles.TryGetValue(fileId, out string path) && File.Exists(path))
                {
                    context.Response.ContentType = "application/octet-stream";
                    await context.Response.SendFileAsync(path);
                }
                else
                {
                    context.Response.StatusCode = 404;
                }
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

            _ = Task.Run(StartTcpServerAsync);

            await App.StartAsync();
        }

        private static async Task StartTcpServerAsync()
        {
            var listener = new TcpListener(IPAddress.Any, 53319);
            listener.Start();
            while (true)
            {
                try
                {
                    var client = await listener.AcceptTcpClientAsync();
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            using var stream = client.GetStream();
                            var buffer = new byte[36];
                            int read = await stream.ReadAsync(buffer, 0, 36);
                            if (read == 36)
                            {
                                var fileId = Encoding.UTF8.GetString(buffer);
                                if (HostedFiles.TryGetValue(fileId, out var path) && File.Exists(path))
                                {
                                    using var fs = new FileStream(path, FileMode.Open, FileAccess.Read);
                                    await fs.CopyToAsync(stream, 81920);
                                }
                            }
                        }
                        catch { }
                        finally { client.Close(); }
                    });
                }
                catch { }
            }
        }
    }
}
