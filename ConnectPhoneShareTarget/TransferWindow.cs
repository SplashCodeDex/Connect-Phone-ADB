using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shell;

namespace ConnectPhoneShareTarget
{
    class TransferWindow : Window
    {
        private List<string> files;
        private TextBlock txtStatus;
        private Border progressIndicator;
        private TextBlock txtSpeed;

        public TransferWindow(List<string> filePaths)
        {
            files = filePaths;
            Title = "Connect Phone ADB - Share";
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

        private string RunAdbCommand(string arguments)
        {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string adbPath = Path.Combine(exeDir, "bin", "adb.exe");
            var proc = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = adbPath,
                    Arguments = arguments,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                }
            };
            proc.Start();
            string output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit();
            return output.Trim();
        }

        public async Task StartTransferAsync()
        {
            try
            {
                string targetDevice = await GetTargetDeviceAsync();
                if (string.IsNullOrEmpty(targetDevice))
                {
                    txtStatus.Text = "No phone connected.";
                    await Task.Delay(3000);
                    return;
                }

                long totalBytes = files.Sum(f => new FileInfo(f).Length);
                long totalSent = 0;
                
                Stopwatch globalSw = Stopwatch.StartNew();

                foreach (var file in files)
                {
                    if (!File.Exists(file)) continue;

                    string fileName = Path.GetFileName(file);
                    string destPath = $"/sdcard/Download/{fileName}";
                    
                    string ext = Path.GetExtension(file).ToLower();
                    if (new[] { ".mp3", ".m4a", ".wav", ".ogg", ".flac" }.Contains(ext)) destPath = $"/sdcard/Music/{fileName}";
                    if (new[] { ".mp4", ".mkv", ".mov", ".avi" }.Contains(ext)) destPath = $"/sdcard/Movies/{fileName}";
                    if (new[] { ".jpg", ".jpeg", ".png", ".gif" }.Contains(ext)) destPath = $"/sdcard/Pictures/{fileName}";

                    string partDestPath = destPath + ".part";
                    string safePartPath = partDestPath.Replace("'", "'\\''");
                    string safeDestPath = destPath.Replace("'", "'\\''");

                    txtStatus.Text = $"Transferring {fileName}...";

                    FileInfo fi = new FileInfo(file);
                    
                    string finalStatOut = await Task.Run(() => RunAdbCommand($"-s {targetDevice} shell \"stat -c %s '{safeDestPath}' 2>/dev/null\""));
                    if (long.TryParse(finalStatOut, out long finalSz) && finalSz == fi.Length)
                    {
                        totalSent += fi.Length;
                        continue;
                    }

                    long existingSize = 0;
                    string statOut = await Task.Run(() => RunAdbCommand($"-s {targetDevice} shell \"stat -c %s '{safePartPath}' 2>/dev/null\""));
                    if (long.TryParse(statOut, out long sz))
                    {
                        existingSize = sz;
                    }

                    if (existingSize > fi.Length)
                    {
                        await Task.Run(() => RunAdbCommand($"-s {targetDevice} shell \"rm '{safePartPath}' 2>/dev/null\""));
                        existingSize = 0;
                    }

                    string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                    string adbPath = Path.Combine(exeDir, "bin", "adb.exe");
                    
                    if (!File.Exists(adbPath))
                    {
                        throw new FileNotFoundException("adb.exe is missing from the bin folder.");
                    }
                    
                    var pushProc = new Process
                    {
                        StartInfo = new ProcessStartInfo
                        {
                            FileName = adbPath,
                            Arguments = $"-s {targetDevice} shell \"cat >> '{safePartPath}'\"",
                            UseShellExecute = false,
                            RedirectStandardInput = true,
                            CreateNoWindow = true
                        }
                    };
                    
                    pushProc.Start();
                    
                    using (var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read))
                    {
                        if (existingSize > 0)
                        {
                            fs.Seek(existingSize, SeekOrigin.Begin);
                        }

                        byte[] buffer = new byte[1024 * 1024];
                        int bytesRead;
                        
                        Stopwatch speedSw = Stopwatch.StartNew();
                        long recentBytes = 0;

                        while ((bytesRead = await fs.ReadAsync(buffer, 0, buffer.Length)) > 0)
                        {
                            await pushProc.StandardInput.BaseStream.WriteAsync(buffer, 0, bytesRead);
                            totalSent += bytesRead;
                            recentBytes += bytesRead;

                            if (speedSw.ElapsedMilliseconds > 500)
                            {
                                double speedMb = (recentBytes / 1048576.0) / (speedSw.ElapsedMilliseconds / 1000.0);
                                txtSpeed.Text = $"{speedMb:F1} MB/s";
                                double pct = (double)totalSent / totalBytes * 100;
                                
                                // Smooth animation for progress bar width
                                var parentBorder = (Border)progressIndicator.Parent;
                                double targetWidth = parentBorder.ActualWidth * (pct / 100.0);
                                if (targetWidth > 0 && !double.IsNaN(targetWidth)) {
                                    var anim = new System.Windows.Media.Animation.DoubleAnimation {
                                        To = targetWidth,
                                        Duration = TimeSpan.FromMilliseconds(250),
                                        EasingFunction = new System.Windows.Media.Animation.QuadraticEase { EasingMode = System.Windows.Media.Animation.EasingMode.EaseOut }
                                    };
                                    progressIndicator.BeginAnimation(Border.WidthProperty, anim);
                                }
                                
                                TaskbarItemInfo.ProgressValue = pct / 100.0;
                                
                                recentBytes = 0;
                                speedSw.Restart();
                            }
                        }
                    }
                    
                    pushProc.StandardInput.Close();
                    await Task.Run(() => pushProc.WaitForExit());
                    
                    await Task.Run(() => RunAdbCommand($"-s {targetDevice} shell \"mv '{safePartPath}' '{safeDestPath}'\""));
                }

                globalSw.Stop();
                txtStatus.Text = "Transfer Complete!";
                txtSpeed.Text = $"{totalBytes / 1048576.0:F1} MB in {globalSw.Elapsed.TotalSeconds:F1}s";
                
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
            catch (Exception ex)
            {
                txtStatus.Text = "Error: " + ex.Message;
                await Task.Delay(5000);
            }
        }

        private async Task<string> GetTargetDeviceAsync()
        {
            return await Task.Run(() =>
            {
                string devOut = RunAdbCommand("devices");
                string[] lines = devOut.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                foreach (var line in lines)
                {
                    if (line.EndsWith("device") && !line.Contains("List of"))
                    {
                        return line.Split('\t')[0];
                    }
                }
                return string.Empty;
            });
        }
    }
}
