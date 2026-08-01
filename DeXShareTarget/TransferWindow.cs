using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shell;

namespace DeXShareTarget
{
    public partial class TransferWindow : Window
    {
        private List<string> files;
        public string TargetIp { get; set; }
        private TextBlock txtStatus;
        private Border progressIndicator;
        private TextBlock txtSpeed;

        public TransferWindow(List<string> filePaths)
        {
            files = filePaths;
            Title = "DeX - Share";
            Width = 420;
            Height = 160;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = Brushes.Transparent;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            Topmost = true;
            AllowsTransparency = true;

            string xaml = @"
            <Border xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
                    xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml""
                    Background=""#1E1E1E"" CornerRadius=""12"" BorderBrush=""#333333"" BorderThickness=""1"" Margin=""10"">
                <Border.Effect>
                    <DropShadowEffect Color=""Black"" BlurRadius=""15"" ShadowDepth=""0"" Opacity=""0.5""/>
                </Border.Effect>
                <Grid Margin=""20,15,20,15"">
                    <Grid.RowDefinitions>
                        <RowDefinition Height=""Auto""/>
                        <RowDefinition Height=""*"" />
                        <RowDefinition Height=""Auto""/>
                        <RowDefinition Height=""Auto""/>
                    </Grid.RowDefinitions>
                    
                    <TextBlock Text=""Sending to Android Device"" FontSize=""14"" FontWeight=""Bold"" Foreground=""#FFFFFF"" Grid.Row=""0"" Margin=""0,0,0,5""/>
                    
                    <TextBlock x:Name=""txtStatus"" Text=""Initializing transfer..."" FontSize=""12"" Foreground=""#A0A0A0"" Grid.Row=""1"" Margin=""0,0,0,15"" TextTrimming=""CharacterEllipsis""/>
                    
                    <Border Grid.Row=""2"" Height=""8"" Background=""#2C2C2E"" CornerRadius=""4"" Margin=""0,0,0,5"" ClipToBounds=""True"">
                        <Border x:Name=""progressIndicator"" Background=""#00E676"" CornerRadius=""4"" Width=""0"" HorizontalAlignment=""Left""/>
                    </Border>
                    
                    <TextBlock x:Name=""txtSpeed"" Text=""0 MB/s"" FontSize=""11"" Foreground=""#A0A0A0"" HorizontalAlignment=""Right"" Grid.Row=""3""/>
                </Grid>
            </Border>";

            var rootBorder = (Border)System.Windows.Markup.XamlReader.Parse(xaml);
            txtStatus = (TextBlock)rootBorder.FindName("txtStatus");
            progressIndicator = (Border)rootBorder.FindName("progressIndicator");
            txtSpeed = (TextBlock)rootBorder.FindName("txtSpeed");

            Content = rootBorder;
            
            TaskbarItemInfo = new TaskbarItemInfo { ProgressState = TaskbarItemProgressState.Normal };
            
            // Allow drag to move
            this.MouseLeftButtonDown += (s, e) => this.DragMove();
        }


        public async Task StartTransferAsync()
        {
            try
            {
                if (!string.IsNullOrEmpty(TargetIp))
                {
                    var directDevice = new DiscoveredDevice { Ip = TargetIp, Info = new RegisterDto { Port = 53317 } };
                    await PerformLocalSendTransferAsync(directDevice);
                    return;
                }

                // Try LocalSend Wi-Fi discovery first!
                var wifiDevice = await GetLocalSendDeviceAsync();
                if (wifiDevice != null)
                {
                    await PerformLocalSendTransferAsync(wifiDevice);
                    return;
                }


                // Fallback to QUIC PC-to-PC (Internet / NAT Hole Punching)
                await PerformThrufluxHostAsync();
            }
            catch (Exception ex)
            {
                txtStatus.Text = "Error: " + ex.Message;
                await Task.Delay(5000);
            }
        }

        private async Task PerformLocalSendTransferAsync(DiscoveredDevice device)
        {
            long totalBytes = files.Sum(f => new FileInfo(f).Length);
            Stopwatch globalSw = Stopwatch.StartNew();

            // Ignore cert errors
            var handler = new HttpClientHandler
            {
                ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true
            };
            using var http = new HttpClient(handler);
            http.Timeout = TimeSpan.FromSeconds(15);

            var baseUrl = $"https://{device.Ip}:{device.Info.Port}";
            
            // Get local IP used to reach the device
            string localIp = "127.0.0.1";
            try
            {
                using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, 0);
                socket.Connect(device.Ip, 53317);
                localIp = (socket.LocalEndPoint as IPEndPoint)?.Address.ToString() ?? "127.0.0.1";
            } catch {}

            foreach (var f in files)
            {
                var fi = new FileInfo(f);
                var fileId = Guid.NewGuid().ToString();
                
                // 1. Host the file in Kestrel
                LocalSendServer.HostedFiles[fileId] = f;

                txtStatus.Text = $"Notifying Android to pull {fi.Name}...";

                // 2. Send the notify-download signal
                var notifyReq = new Dictionary<string, string>
                {
                    { "ip", localIp },
                    { "port", "53319" },
                    { "fileId", fileId },
                    { "fileName", fi.Name },
                    { "fileSize", fi.Length.ToString() }
                };

                var content = new StringContent(JsonSerializer.Serialize(notifyReq), System.Text.Encoding.UTF8, "application/json");
                await http.PostAsync($"{baseUrl}/notify-download", content);
            }

            globalSw.Stop();
            txtStatus.Text = "Transfer Signal Sent!";
            txtSpeed.Text = $"{totalBytes / 1048576.0:F1} MB triggered in {globalSw.Elapsed.TotalSeconds:F1}s";
            
            var parentFinal = (Border)progressIndicator.Parent;
            var animFinal = new System.Windows.Media.Animation.DoubleAnimation {
                To = parentFinal.ActualWidth,
                Duration = TimeSpan.FromMilliseconds(250),
                EasingFunction = new System.Windows.Media.Animation.QuadraticEase { EasingMode = System.Windows.Media.Animation.EasingMode.EaseOut }
            };
            progressIndicator.BeginAnimation(Border.WidthProperty, animFinal);
            
            TaskbarItemInfo.ProgressValue = 1.0;
            await Task.Delay(3000);
            
            // Clean up hosted files memory after a while so we don't leak memory (not deleting the physical file)
            _ = Task.Run(async () => {
                await Task.Delay(TimeSpan.FromMinutes(5));
                LocalSendServer.HostedFiles.Clear();
            });
        }

        private async Task PerformThrufluxHostAsync()
        {
            txtStatus.Text = "Starting QUIC P2P Host...";
            
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string thruPath = Path.Combine(exeDir, "bin", "thru.exe");
            
            if (!File.Exists(thruPath))
            {
                txtStatus.Text = "QUIC engine (thru.exe) not found.";
                await Task.Delay(3000);
                return;
            }
            
            string args = "host ";
            foreach(var f in files) {
                args += $"\"{f}\" ";
            }
            
            var proc = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = thruPath,
                    Arguments = args,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                }
            };
            
            proc.Start();
            
            string joinCode = "";
            
            _ = Task.Run(() => 
            {
                while (!proc.StandardOutput.EndOfStream)
                {
                    string line = proc.StandardOutput.ReadLine();
                    if (line != null && line.Contains("thru join"))
                    {
                        int idx = line.IndexOf("thru join");
                        joinCode = line.Substring(idx + 10).Trim();
                        Dispatcher.Invoke(() => {
                            txtStatus.Text = $"QUIC Code: {joinCode} (Waiting...)";
                            Clipboard.SetText(joinCode);
                        });
                    }
                    if (line != null && line.Contains("Transfer complete")) 
                    {
                        Dispatcher.Invoke(() => txtStatus.Text = "QUIC Transfer Complete!");
                    }
                }
            });
            
            await Task.Run(() => proc.WaitForExit());
            
            if (txtStatus.Text.Contains("Waiting")) {
                txtStatus.Text = "QUIC Session Closed.";
            } else {
                txtStatus.Text = "QUIC Transfer Complete!";
            }
            
            var parentFinal = (Border)progressIndicator.Parent;
            var animFinal = new System.Windows.Media.Animation.DoubleAnimation {
                To = parentFinal.ActualWidth,
                Duration = TimeSpan.FromMilliseconds(250),
                EasingFunction = new System.Windows.Media.Animation.QuadraticEase { EasingMode = System.Windows.Media.Animation.EasingMode.EaseOut }
            };
            progressIndicator.BeginAnimation(Border.WidthProperty, animFinal);
            
            TaskbarItemInfo.ProgressValue = 1.0;
            await Task.Delay(3000);
        }

        private async Task<DiscoveredDevice?> GetLocalSendDeviceAsync()
        {
            try 
            {
                using var http = new HttpClient();
                http.Timeout = TimeSpan.FromSeconds(2);
                var res = await http.GetStringAsync("http://127.0.0.1:53318/local/devices");
                var list = JsonSerializer.Deserialize<List<DiscoveredDevice>>(res, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                return list?.FirstOrDefault(); // return first found Wi-Fi device
            } 
            catch { return null; }
        }
    }

    public class ProgressableStreamContent : HttpContent
    {
        private readonly Stream content;
        private readonly Action<int> onRead;

        public ProgressableStreamContent(Stream content, Action<int> onRead)
        {
            this.content = content;
            this.onRead = onRead;
        }

        protected override async Task SerializeToStreamAsync(Stream stream, TransportContext? context)
        {
            var buffer = new byte[81920];
            int length;
            while ((length = await content.ReadAsync(buffer, 0, buffer.Length)) > 0)
            {
                await stream.WriteAsync(buffer, 0, length);
                onRead(length);
            }
        }

        protected override bool TryComputeLength(out long length)
        {
            length = content.Length;
            return true;
        }
    }
}
