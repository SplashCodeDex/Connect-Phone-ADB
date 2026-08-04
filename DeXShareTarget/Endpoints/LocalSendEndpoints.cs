using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Windows.Data.Xml.Dom;
using Windows.UI.Notifications;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using DeXShareTarget.Models;
using DeXShareTarget.Services;

namespace DeXShareTarget.Endpoints
{
    public static class LocalSendEndpoints
    {
        public static ConcurrentDictionary<string, string> HostedFiles = new();
        public static ConcurrentDictionary<string, PairRequestDto> PendingPairs = new();
        public static bool IsDndEnabled { get; set; } = false;
        public static ConcurrentDictionary<string, TaskCompletionSource<PairResult>> PairTcs = new();
        public static ConcurrentDictionary<string, DateTime> GuestFingerprints = new();

        public static void MapLocalSendEndpoints(this WebApplication app)
        {
            app.MapGet("/api/localsend/v2/info", () => Results.Json(new RegisterDto()));
            
            app.MapPost("/api/dex/clipboard", async (HttpRequest request) =>
            {
                using var reader = new StreamReader(request.Body);
                var text = await reader.ReadToEndAsync();
                
                var psi = new System.Diagnostics.ProcessStartInfo("powershell", "-NoProfile -Command \"$input | Set-Clipboard\"")
                {
                    RedirectStandardInput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                var p = System.Diagnostics.Process.Start(psi);
                if (p != null)
                {
                    await p.StandardInput.WriteAsync(text);
                    p.StandardInput.Close();
                }
                
                return Results.Ok();
            });

            app.MapPost("/api/localsend/v2/register", (RegisterDto req) => 
            {
                return Results.Json(new { sessionId = Guid.NewGuid().ToString() });
            });

            var activeSessions = new ConcurrentDictionary<string, PrepareUploadRequestDto>();
            HostedFiles = new ConcurrentDictionary<string, string>();

            app.MapPost("/api/localsend/v2/prepare-upload", async (PrepareUploadRequestDto req) =>
            {
                if (IsDndEnabled) return Results.StatusCode(403);

                bool isAutoTrusted = !string.IsNullOrEmpty(req.Info.IdentityHash) && req.Info.IdentityHash == IdentityManager.IdentityHash;
                bool isPaired = IdentityManager.PairedFingerprints.Contains(req.Info.Fingerprint);
                bool isGuest = GuestFingerprints.ContainsKey(req.Info.Fingerprint);
                
                if (!isAutoTrusted && !isPaired && !isGuest)
                {
                    return Results.StatusCode(403);
                }
                if (isGuest) GuestFingerprints.TryRemove(req.Info.Fingerprint, out _);

                var tcs = new TaskCompletionSource<bool>();
                System.Windows.Application.Current.Dispatcher.Invoke(() =>
                {
                    var senderAlias = req.Info.Alias ?? "Unknown Device";
                    var win = new ReceivePromptWindow(senderAlias, req.Files.Count);
                    win.Show();
                    _ = win.WaitForResponseAsync().ContinueWith(t => 
                    {
                        tcs.TrySetResult(t.Result);
                    });
                });

                bool res = await tcs.Task;
                if (!res) return Results.StatusCode(403);
                
                var sessionId = Guid.NewGuid().ToString();
                activeSessions[sessionId] = req;
                var resFiles = new Dictionary<string, string>();
                string downloadsFolder = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + "\\Downloads";
                foreach (var kvp in req.Files)
                {
                    string safeFileName = Path.GetFileName(kvp.Value.FileName);
                    if (string.IsNullOrEmpty(safeFileName)) safeFileName = "unnamed_file";
                    string destPath = Path.Combine(downloadsFolder, safeFileName);
                    if (File.Exists(destPath) && new FileInfo(destPath).Length == kvp.Value.Size) continue;
                    resFiles[kvp.Key] = Guid.NewGuid().ToString(); // Token for the file
                }
                return Results.Json(new PrepareUploadResponseDto { SessionId = sessionId, Files = resFiles });
            });

            app.MapPost("/api/localsend/v2/upload", async (HttpRequest request) =>
            {
                var sessionId = request.Query["sessionId"].ToString();
                var fileId = request.Query["fileId"].ToString();
                var token = request.Query["token"].ToString(); // Token unused in minimal impl

                if (!activeSessions.TryGetValue(sessionId, out var sessionReq)) return Results.BadRequest();
                if (!sessionReq.Files.TryGetValue(fileId, out var fileMeta)) return Results.BadRequest();

                string safeFileName = Path.GetFileName(fileMeta.FileName);
                if (string.IsNullOrEmpty(safeFileName)) safeFileName = "unnamed_file";
                
                string downloadsFolder = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + "\\Downloads";
                string destPath = Path.Combine(downloadsFolder, safeFileName);

                int counter = 1;
                while (File.Exists(destPath))
                {
                    string nameNoExt = Path.GetFileNameWithoutExtension(safeFileName);
                    string ext = Path.GetExtension(safeFileName);
                    destPath = Path.Combine(downloadsFolder, $"{nameNoExt} ({counter}){ext}");
                    counter++;
                }

                using var fs = new FileStream(destPath, FileMode.CreateNew);
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

            app.MapGet("/download/{fileId}", async (string fileId, HttpContext context) =>
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

            var rateLimits = new ConcurrentDictionary<string, DateTime>();

            app.MapPost("/api/localsend/v2/pair-prompt", async (PairRequestDto req, CancellationToken ct) =>
            {
                if (IsDndEnabled) return Results.StatusCode(403);
                if (string.IsNullOrEmpty(req.Fingerprint)) return Results.BadRequest();
                if (rateLimits.TryGetValue(req.Fingerprint, out var lastTime) && DateTime.UtcNow - lastTime < TimeSpan.FromSeconds(3))
                {
                    return Results.StatusCode(429); // Rate limited
                }
                rateLimits[req.Fingerprint] = DateTime.UtcNow;

                PendingPairs[req.Fingerprint] = req;
                
                // Cancel any orphaned task for this fingerprint to avoid leaks
                if (PairTcs.TryGetValue(req.Fingerprint, out var oldTcs))
                {
                    oldTcs.TrySetCanceled();
                }

                var tcs = new TaskCompletionSource<PairResult>(TaskCreationOptions.RunContinuationsAsynchronously);
                PairTcs[req.Fingerprint] = tcs;
                
                // Tie the TCS to the client disconnect token
                using (ct.Register(() => tcs.TrySetCanceled()))
                {
                    try 
                    {
                        var res = await tcs.Task;
                        if (res == PairResult.Reject) return Results.StatusCode(403);
                        
                        if (res == PairResult.AcceptPermanent) IdentityManager.SavePairedDevice(req.Fingerprint);
                        if (res == PairResult.AcceptGuest) GuestFingerprints[req.Fingerprint] = DateTime.UtcNow;
                        return Results.Ok();
                    }
                    catch (TaskCanceledException)
                    {
                        return Results.StatusCode(499); // Client Closed Request
                    }
                }
            });

            app.MapGet("/local/pairing-requests", () => Results.Json(PendingPairs.Values));

            app.MapPost("/local/pairing-resolve", async (HttpRequest request) =>
            {
                var fp = request.Query["fingerprint"].ToString();
                var accept = request.Query["accept"].ToString() == "true";
                var guest = request.Query["guest"].ToString() == "true";
                var result = accept ? (guest ? PairResult.AcceptGuest : PairResult.AcceptPermanent) : PairResult.Reject;

                if (PairTcs.TryGetValue(fp, out var tcs))
                {
                    tcs.TrySetResult(result);
                    PairTcs.TryRemove(fp, out _);
                }
                PendingPairs.TryRemove(fp, out _);
                
                if (result == PairResult.AcceptPermanent) IdentityManager.SavePairedDevice(fp);
                if (result == PairResult.AcceptGuest) GuestFingerprints[fp] = DateTime.UtcNow;
                
                return Results.Ok();
            });

            // Local API for PowerShell to read discovered devices
            app.MapGet("/local/devices", () => 
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

            app.MapGet("/local/devices/ping", async (string ip) =>
            {
                if (string.IsNullOrEmpty(ip)) return Results.BadRequest();
                try
                {
                    using var handler = new System.Net.Http.HttpClientHandler();
                    handler.ServerCertificateCustomValidationCallback = (m, c, ch, e) => true;
                    using var http = new System.Net.Http.HttpClient(handler) { Timeout = TimeSpan.FromSeconds(2) };
                    
                    var response = await http.GetAsync($"https://{ip}:53317/api/localsend/v2/info");
                    if (!response.IsSuccessStatusCode)
                    {
                        response = await http.GetAsync($"http://{ip}:53317/api/localsend/v2/info");
                    }

                    if (response.IsSuccessStatusCode)
                    {
                        var json = await response.Content.ReadAsStringAsync();
                        var root = JsonDocument.Parse(json).RootElement;
                        var info = new RegisterDto
                        {
                            Alias = root.TryGetProperty("alias", out var a) ? a.GetString() : "Unknown",
                            DeviceModel = root.TryGetProperty("deviceModel", out var dm) ? dm.GetString() : "Device",
                            DeviceType = root.TryGetProperty("deviceType", out var dt) ? dt.GetString() : "desktop",
                            Fingerprint = root.TryGetProperty("fingerprint", out var fp) ? fp.GetString() : Guid.NewGuid().ToString()
                        };

                        var dev = new DiscoveredDevice
                        {
                            Ip = ip,
                            Info = info,
                            LastSeen = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                        };
                        DiscoveryBackgroundService.Devices[ip] = dev;
                        return Results.Ok(dev);
                    }
                }
                catch { }
                return Results.NotFound();
            });

            app.MapPost("/local/unpair", (HttpRequest request) => 
            {
                var fp = request.Query["fingerprint"].ToString();
                if (!string.IsNullOrEmpty(fp))
                {
                    IdentityManager.RemovePairedDevice(fp);
                    return Results.Ok();
                }
                return Results.BadRequest();
            });

            app.MapPost("/local/pair-initiate", async (HttpRequest request) => 
            {
                var targetIp = request.Query["ip"].ToString();
                var targetFp = request.Query["fingerprint"].ToString();
                
                if (string.IsNullOrEmpty(targetIp) || string.IsNullOrEmpty(targetFp))
                    return Results.BadRequest();

                var pin = new Random().Next(100000, 999999).ToString();
                var reqDto = new PairRequestDto
                {
                    Alias = Environment.MachineName,
                    Fingerprint = IdentityManager.Fingerprint,
                    Pin = pin
                };

                // Fire and forget pairing request
                _ = Task.Run(async () =>
                {
                    try
                    {
                        var handler = new System.Net.Http.HttpClientHandler
                        {
                            ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true
                        };
                        using var client = new System.Net.Http.HttpClient(handler);
                        var content = new System.Net.Http.StringContent(JsonSerializer.Serialize(reqDto, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }), System.Text.Encoding.UTF8, "application/json");
                        var response = await client.PostAsync($"https://{targetIp}:53317/api/localsend/v2/pair-prompt", content);
                        
                        if (response.IsSuccessStatusCode)
                        {
                            IdentityManager.SavePairedDevice(targetFp);
                        }
                    }
                    catch { }
                });

                return Results.Json(new { pin });
            });

            app.MapPost("/local/alias", (HttpRequest request) => 
            {
                var fp = request.Query["fingerprint"].ToString();
                var alias = request.Query["alias"].ToString();
                if (!string.IsNullOrEmpty(fp) && !string.IsNullOrEmpty(alias))
                {
                    IdentityManager.SetDeviceAlias(fp, alias);
                    return Results.Ok();
                }
                return Results.BadRequest();
            });

            app.MapGet("/local/qr", (HttpRequest request) => 
            {
                var ip = request.Query["ip"].ToString();
                if (string.IsNullOrEmpty(ip)) return Results.BadRequest();

                string payload = $"http://{ip}:53317";
                using var qrGenerator = new QRCoder.QRCodeGenerator();
                using var qrCodeData = qrGenerator.CreateQrCode(payload, QRCoder.QRCodeGenerator.ECCLevel.M);
                using var qrCode = new QRCoder.PngByteQRCode(qrCodeData);
                var qrCodeImage = qrCode.GetGraphic(10); // 10 pixels per module
                
                return Results.File(qrCodeImage, "image/png");
            });

            app.MapPost("/local/dnd", (HttpRequest request) => 
            {
                var enabled = request.Query["enabled"].ToString() == "true";
                IsDndEnabled = enabled;
                return Results.Ok(new { dnd = IsDndEnabled });
            });

            app.MapPost("/local/settings/email", async (HttpRequest req) => 
            {
                using var reader = new StreamReader(req.Body);
                var email = await reader.ReadToEndAsync();
                IdentityManager.SetEmail(email);
                return Results.Ok();
            });

            _ = Task.Run(StartTcpServerAsync);
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
