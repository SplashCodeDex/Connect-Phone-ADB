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
        private ProgressBar progressBar;
        private TextBlock txtSpeed;

        public TransferWindow(List<string> filePaths)
        {
            files = filePaths;
            Title = "Connect Phone ADB";
            Width = 400;
            Height = 150;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = new SolidColorBrush(Color.FromRgb(30, 30, 30));
            Foreground = Brushes.White;
            WindowStyle = WindowStyle.ToolWindow;
            ResizeMode = ResizeMode.NoResize;
            Topmost = true;

            var grid = new Grid { Margin = new Thickness(15) };
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            txtStatus = new TextBlock
            {
                Text = "Initializing transfer...",
                FontSize = 14,
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 0, 0, 10),
                TextTrimming = TextTrimming.CharacterEllipsis
            };
            Grid.SetRow(txtStatus, 0);

            progressBar = new ProgressBar
            {
                Height = 20,
                Minimum = 0,
                Maximum = 100,
                Value = 0,
                Foreground = new SolidColorBrush(Color.FromRgb(0, 120, 215))
            };
            Grid.SetRow(progressBar, 1);

            txtSpeed = new TextBlock
            {
                Text = "0 MB/s",
                FontSize = 12,
                Foreground = Brushes.LightGray,
                HorizontalAlignment = HorizontalAlignment.Right,
                Margin = new Thickness(0, 10, 0, 0)
            };
            Grid.SetRow(txtSpeed, 2);

            grid.Children.Add(txtStatus);
            grid.Children.Add(progressBar);
            grid.Children.Add(txtSpeed);
            Content = grid;
            
            TaskbarItemInfo = new TaskbarItemInfo { ProgressState = TaskbarItemProgressState.Normal };
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
                                progressBar.Value = pct;
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
                progressBar.Value = 100;
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
