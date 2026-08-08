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
        public static ConcurrentDictionary<string, string> OutboundPairingStatus = new();

        public static void MapLocalSendEndpoints(this WebApplication app)
        {
            app.MapGet("/api/localsend/v2/info", () => Results.Json(new RegisterDto { IdentityHash = IdentityManager.IdentityHash }));
            
            app.MapPost("/api/dex/clipboard", async (HttpRequest request) =>
            {
                var auth = request.Headers.Authorization.ToString();
                if (string.IsNullOrEmpty(auth) || !auth.StartsWith("Bearer ")) return Results.StatusCode(401);
                var token = auth.Substring("Bearer ".Length);
                if (token != IdentityManager.IdentityHash && !IdentityManager.PairedTokens.Values.Contains(token)) return Results.StatusCode(401);

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
            var activeSessionsProgress = new ConcurrentDictionary<string, int>();
            HostedFiles = new ConcurrentDictionary<string, string>();

            app.MapPost("/api/localsend/v2/prepare-upload", async (HttpRequest request, PrepareUploadRequestDto req, CancellationToken ct) =>
            {
                if (IsDndEnabled) return Results.StatusCode(403);

                var auth = request.Headers.Authorization.ToString();
                var token = auth.StartsWith("Bearer ") ? auth.Substring("Bearer ".Length) : null;

                bool isAutoTrusted = !string.IsNullOrEmpty(token) && token == IdentityManager.IdentityHash;
                bool isPaired = !string.IsNullOrEmpty(token) && IdentityManager.PairedTokens.TryGetValue(req.Info.Fingerprint, out var expectedToken) && expectedToken == token;
                
                bool isGuest = GuestFingerprints.TryGetValue(req.Info.Fingerprint, out var guestTime);
                if (isGuest && (DateTime.UtcNow - guestTime).TotalMinutes > 10)
                {
                    GuestFingerprints.TryRemove(req.Info.Fingerprint, out _);
                    isGuest = false;
                }
                
                if (!isAutoTrusted && !isPaired && !isGuest)
                {
                    return Results.StatusCode(403);
                }
                var tcs = new TaskCompletionSource<bool>();
                ReceivePromptWindow? win = null;
                System.Windows.Application.Current.Dispatcher.Invoke(() =>
                {
                    var senderAlias = req.Info.Alias ?? "Unknown Device";
                    win = new ReceivePromptWindow(senderAlias, req.Files.Count);
                    win.Show();
                    _ = win.WaitForResponseAsync().ContinueWith(t => 
                    {
                        tcs.TrySetResult(t.Result);
                    });
                });

                bool res = false;
                using (ct.Register(() => { tcs.TrySetResult(false); win?.Dispatcher.Invoke(() => win.Close()); }))
                {
                    res = await tcs.Task;
                }

                if (!res) return Results.StatusCode(403);
                if (isGuest) GuestFingerprints.TryRemove(req.Info.Fingerprint, out _);
                
                var sessionId = Guid.NewGuid().ToString();
                activeSessions[sessionId] = req;
                _ = Task.Delay(TimeSpan.FromMinutes(10)).ContinueWith(t => { activeSessions.TryRemove(sessionId, out _); activeSessionsProgress.TryRemove(sessionId, out _); });
                var resFiles = new Dictionary<string, string>();
                string downloadsFolder = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + "\\Downloads\\DeX";
                Directory.CreateDirectory(downloadsFolder);
                foreach (var kvp in req.Files)
                {
                    string safeFileName = Path.GetFileName(kvp.Value.FileName);
                    if (string.IsNullOrEmpty(safeFileName)) safeFileName = "unnamed_file";
                    
                    string destPath = Path.Combine(downloadsFolder, safeFileName);
                    if (File.Exists(destPath) && new FileInfo(destPath).Length == kvp.Value.Size)
                    {
                        var localPartial = await HashHelper.ComputePartialHashAsync(destPath, kvp.Value.Size);
                        if (localPartial != null && localPartial == kvp.Value.PartialHash)
                        {
                            File.SetLastWriteTime(destPath, DateTime.Now);
                            resFiles[kvp.Key] = "[SKIP]";
                            continue;
                        }
                    }

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
                
                string downloadsFolder = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + "\\Downloads\\DeX";
                Directory.CreateDirectory(downloadsFolder);
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
                    var count = activeSessionsProgress.AddOrUpdate(sessionId, 1, (_, v) => v + 1);
                    if (count == sessionReq.Files.Count)
                    {
                        activeSessions.TryRemove(sessionId, out _);
                        activeSessionsProgress.TryRemove(sessionId, out _);

                        string toastXmlString = 
                        $@"<toast>
                            <visual>
                                <binding template='ToastGeneric'>
                                    <text>DeX Transfer Complete</text>
                                    <text>Received {count} file(s) from {sessionReq.Info.Alias}</text>
                                </binding>
                            </visual>
                        </toast>";
                        var xmlDoc = new XmlDocument();
                        xmlDoc.LoadXml(toastXmlString);
                        var toastNode = new ToastNotification(xmlDoc);
                        ToastNotificationManager.CreateToastNotifier("DeX").Show(toastNode);
                    }
                }
                catch { }

                return Results.Ok();
            });

            app.MapPost("/notify-download", async (HttpRequest request) =>
            {
                var auth = request.Headers.Authorization.ToString();
                var token = auth.StartsWith("Bearer ") ? auth.Substring("Bearer ".Length) : null;
                // For notify-download, we only verify if the provided token is among the trusted ones.
                bool isTrusted = false;
                if (!string.IsNullOrEmpty(token)) {
                    if (token == IdentityManager.IdentityHash) isTrusted = true;
                    else if (IdentityManager.PairedTokens.Values.Contains(token)) isTrusted = true;
                }
                
                if (!isTrusted) return Results.StatusCode(403);
                using var reader = new StreamReader(request.Body);
                var body = await reader.ReadToEndAsync();
                var doc = JsonDocument.Parse(body);
                var root = doc.RootElement;
                var ip = root.TryGetProperty("ip", out var ipProp) ? ipProp.GetString() : null;
                var port = root.TryGetProperty("port", out var portProp) ? portProp.GetInt32() : 53319;
                var fileId = root.TryGetProperty("fileId", out var fidProp) ? fidProp.GetString() : null;
                var fileName = root.TryGetProperty("fileName", out var fnProp) ? fnProp.GetString() : "downloaded_file";

                if (string.IsNullOrEmpty(ip) || string.IsNullOrEmpty(fileId)) return Results.BadRequest();

                _ = Task.Run(async () =>
                {
                    try
                    {
                        using var client = new TcpClient();
                        await client.ConnectAsync(ip, port);
                        using var stream = client.GetStream();
                        var idBytes = Encoding.UTF8.GetBytes(fileId);
                        await stream.WriteAsync(idBytes, 0, idBytes.Length);

                        string downloadsFolder = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + "\\Downloads\\DeX";
                        Directory.CreateDirectory(downloadsFolder);
                        string safeFileName = Path.GetFileName(fileName);
                        if (string.IsNullOrEmpty(safeFileName)) safeFileName = "downloaded_file";
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
                        await stream.CopyToAsync(fs);
                    }
                    catch { }
                });

                return Results.Ok();
            });

            app.MapGet("/download/{fileId}", async (string fileId, HttpContext context) =>
            {
                if (HostedFiles.TryGetValue(fileId, out string? path) && File.Exists(path))
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
                using (ct.Register(() => { tcs.TrySetCanceled(); PendingPairs.TryRemove(req.Fingerprint, out _); PairTcs.TryRemove(req.Fingerprint, out _); }))
                {
                    try 
                    {
                        var res = await tcs.Task;
                        if (res == PairResult.Reject) return Results.StatusCode(403);
                        
                        if (res == PairResult.AcceptPermanent)
                        {
                            IdentityManager.SavePairedDevice(req.Fingerprint);
                            if (!string.IsNullOrEmpty(req.Token)) IdentityManager.SavePairedToken(req.Fingerprint, req.Token);
                        }
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

                string? pendingToken = null;
                if (PendingPairs.TryGetValue(fp, out var pendingReq)) pendingToken = pendingReq.Token;
                PendingPairs.TryRemove(fp, out _);

                if (PairTcs.TryGetValue(fp, out var tcs))
                {
                    tcs.TrySetResult(result);
                    PairTcs.TryRemove(fp, out _);
                }
                
                if (result == PairResult.AcceptPermanent)
                {
                    IdentityManager.SavePairedDevice(fp);
                    if (!string.IsNullOrEmpty(pendingToken)) IdentityManager.SavePairedToken(fp, pendingToken);
                }
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
                    if (now - DiscoveryBackgroundService.Devices[k].LastSeen > 10000)
                        DiscoveryBackgroundService.Devices.TryRemove(k, out _);
                }
                return Results.Json(DiscoveryBackgroundService.Devices.Values);
            });

            app.MapPost("/local/devices/flush", () => 
            {
                DiscoveryBackgroundService.Devices.Clear();
                return Results.Ok();
            });

            app.MapGet("/local/devices/ping", async (string ip) =>
            {
                if (string.IsNullOrEmpty(ip)) return Results.BadRequest();
                try
                {
                    using var handler = new System.Net.Http.SocketsHttpHandler
                    {
                        SslOptions = new System.Net.Security.SslClientAuthenticationOptions
                        {
                            RemoteCertificateValidationCallback = (s, c, ch, e) => true,
                            ApplicationProtocols = new System.Collections.Generic.List<System.Net.Security.SslApplicationProtocol>
                                { System.Net.Security.SslApplicationProtocol.Http11 }
                        }
                    };
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
                            Alias = root.TryGetProperty("alias", out var a) ? (a.GetString() ?? "Unknown") : "Unknown",
                            DeviceModel = root.TryGetProperty("deviceModel", out var dm) ? (dm.GetString() ?? "Device") : "Device",
                            DeviceType = root.TryGetProperty("deviceType", out var dt) ? (dt.GetString() ?? "desktop") : "desktop",
                            Fingerprint = root.TryGetProperty("fingerprint", out var fp) ? (fp.GetString() ?? Guid.NewGuid().ToString()) : Guid.NewGuid().ToString(),
                            IdentityHash = root.TryGetProperty("identityHash", out var ih) ? ih.GetString() : null
                        };

                        var dev = new DiscoveredDevice
                        {
                            Ip = ip,
                            Info = info,
                            LastSeen = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                        };
                        DiscoveryBackgroundService.Devices[info.Fingerprint] = dev;
                        return Results.Ok(dev);
                    }
                }
                catch { }
                return Results.NotFound();
            });

            app.MapGet("/local/token", (HttpRequest request) => 
            {
                var ip = request.Query["ip"].ToString();
                if (string.IsNullOrEmpty(ip)) return Results.BadRequest();
                var dev = DiscoveryBackgroundService.Devices.Values.FirstOrDefault(d => d.Ip == ip);
                if (dev == null) return Results.NotFound();
                if (IdentityManager.PairedTokens.TryGetValue(dev.Info.Fingerprint, out var token) && token != null)
                    return Results.Json(new { token });
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
            app.MapGet("/local/pair-status", (HttpRequest request) => 
            {
                var ip = request.Query["ip"].ToString();
                if (!string.IsNullOrEmpty(ip) && OutboundPairingStatus.TryGetValue(ip, out var status))
                {
                    return Results.Json(new { status });
                }
                return Results.NotFound();
            });

            app.MapPost("/local/pair-initiate", async (HttpRequest request) => 
            {
                var targetIp = request.Query["ip"].ToString();
                var targetFp = request.Query["fingerprint"].ToString();
                
                if (string.IsNullOrEmpty(targetIp) || string.IsNullOrEmpty(targetFp))
                    return Results.BadRequest();

                OutboundPairingStatus[targetIp] = "Pending";
                var pin = new Random().Next(100000, 999999).ToString();
                var token = Guid.NewGuid().ToString("N");
                IdentityManager.SavePairedToken(targetFp, token);
                var reqDto = new PairRequestDto
                {
                    Alias = Environment.MachineName,
                    Fingerprint = IdentityManager.Fingerprint,
                    Pin = pin,
                    Token = token
                };

                // Fire and forget pairing request tracking status
                _ = Task.Run(async () =>
                {
                    try
                    {
                        var handler = new System.Net.Http.SocketsHttpHandler
                        {
                            SslOptions = new System.Net.Security.SslClientAuthenticationOptions
                            {
                                RemoteCertificateValidationCallback = (sender, cert, chain, errors) => true,
                                // Lock ALPN to HTTP/1.1 only — prevents .NET from advertising h2,
                                // which crashes Android Ktor Netty's TLS pipeline (no netty-tcnative)
                                ApplicationProtocols = new System.Collections.Generic.List<System.Net.Security.SslApplicationProtocol>
                                    { System.Net.Security.SslApplicationProtocol.Http11 }
                            }
                        };
                        using var client = new System.Net.Http.HttpClient(handler);
                        client.Timeout = TimeSpan.FromSeconds(60);
                        var content = new System.Net.Http.StringContent(JsonSerializer.Serialize(reqDto, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }), System.Text.Encoding.UTF8, "application/json");
                        var response = await client.PostAsync($"https://{targetIp}:53317/api/localsend/v2/pair-prompt", content);
                        
                        if (response.IsSuccessStatusCode)
                        {
                            IdentityManager.SavePairedDevice(targetFp);
                            OutboundPairingStatus[targetIp] = "Accepted";
                        }
                        else
                        {
                            OutboundPairingStatus[targetIp] = "Rejected";
                        }
                    }
                    catch 
                    { 
                        OutboundPairingStatus[targetIp] = "Failed";
                    }
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
