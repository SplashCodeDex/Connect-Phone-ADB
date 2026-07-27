using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace ConnectPhoneShareTarget
{
    public class FileNode
    {
        public string Name { get; set; }
        public string FullPath { get; set; }
        public bool IsDirectory { get; set; }
    }

    public partial class PickerWindow : Window
    {
        [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        private string _targetDevice;
        private string _adbPath;

        public PickerWindow(string targetDevice)
        {
            InitializeComponent();
            _targetDevice = targetDevice;
            
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            _adbPath = Path.Combine(exeDir, "bin", "adb.exe");
            
            try
            {
                this.Icon = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri(Path.Combine(exeDir, "bin", "app-icon.ico")));
            }
            catch { }

            LoadRoot();
            
            this.Loaded += (s, e) => 
            {
                try 
                {
                    var interopHelper = new System.Windows.Interop.WindowInteropHelper(this);
                    int trueValue = 1;
                    DwmSetWindowAttribute(interopHelper.Handle, 20, ref trueValue, sizeof(int)); // DWMWA_USE_IMMERSIVE_DARK_MODE
                    
                    int backdropType = 3; // 3 = Acrylic, 2 = Mica
                    DwmSetWindowAttribute(interopHelper.Handle, 38, ref backdropType, sizeof(int)); // DWMWA_SYSTEMBACKDROP_TYPE

                    if (tvFiles.Items.Count > 0 && tvFiles.Items[0] is TreeViewItem rootNode)
                    {
                        rootNode.IsExpanded = true;
                    }
                }
                catch { }
            };
            
            this.Closed += (s, e) => 
            {
                // Cleanup if needed
            };
        }

        private void LoadRoot()
        {
            var rootNode = new TreeViewItem
            {
                Header = new FileNode { Name = "Internal Storage (/sdcard/)", FullPath = "/sdcard/", IsDirectory = true },
                HeaderTemplate = (DataTemplate)FindResource("DirectoryTemplate"),
                Tag = "/sdcard/"
            };
            rootNode.Items.Add(new TreeViewItem { Header = new FileNode { Name = "Loading..." }, HeaderTemplate = (DataTemplate)FindResource("LoadingTemplate") });
            rootNode.Expanded += Node_Expanded;
            
            tvFiles.Items.Add(rootNode);
        }

        private async void Node_Expanded(object sender, RoutedEventArgs e)
        {
            var item = e.Source as TreeViewItem;
            if (item == null) return;

            if (item.Items.Count == 1 && item.Items[0] is TreeViewItem dummy && ((FileNode)dummy.Header).Name == "Loading...")
            {
                item.Items.Clear();
                string dirPath = item.Tag as string;
                if (string.IsNullOrEmpty(dirPath)) return;

                var children = await Task.Run(() => GetFiles(dirPath));
                
                if (children == null)
                {
                    item.Items.Add(new TreeViewItem { Header = new FileNode { Name = "(Access Denied / Offline)" }, HeaderTemplate = (DataTemplate)FindResource("LoadingTemplate") });
                    return;
                }
                
                if (children.Count == 0)
                {
                    item.Items.Add(new TreeViewItem { Header = new FileNode { Name = "(Empty)" }, HeaderTemplate = (DataTemplate)FindResource("LoadingTemplate") });
                    return;
                }

                foreach (var child in children.Where(c => c.IsDirectory))
                {
                    var tvi = new TreeViewItem
                    {
                        Header = child,
                        HeaderTemplate = (DataTemplate)FindResource("DirectoryTemplate"),
                        Tag = child.FullPath
                    };
                    tvi.Items.Add(new TreeViewItem { Header = new FileNode { Name = "Loading..." }, HeaderTemplate = (DataTemplate)FindResource("LoadingTemplate") });
                    tvi.Expanded += Node_Expanded;
                    item.Items.Add(tvi);
                }

                foreach (var child in children.Where(c => !c.IsDirectory))
                {
                    var tvi = new TreeViewItem
                    {
                        Header = child,
                        HeaderTemplate = (DataTemplate)FindResource("FileTemplate"),
                        Tag = child.FullPath
                    };
                    item.Items.Add(tvi);
                }
            }
        }

        private List<FileNode> GetFiles(string dirPath)
        {
            try
            {
                var proc = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = _adbPath,
                        Arguments = $"-s {_targetDevice} shell ls -1aF \"'{dirPath.Replace("'", "'\\''")}'\"",
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true
                    }
                };
                proc.Start();
                string output = proc.StandardOutput.ReadToEnd();
                string err = proc.StandardError.ReadToEnd();
                proc.WaitForExit();

                if (err.Contains("Permission denied") || err.Contains("No such file") || err.Contains("device offline") || err.Contains("not found"))
                {
                    return null; // Error
                }

                var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                var result = new List<FileNode>();

                foreach (var line in lines)
                {
                    string trimmed = line.Trim();
                    if (trimmed == "./" || trimmed == "../") continue;

                    if (trimmed.EndsWith("/"))
                    {
                        string name = trimmed.TrimEnd('/');
                        result.Add(new FileNode { Name = name, FullPath = dirPath + name + "/", IsDirectory = true });
                    }
                    else
                    {
                        string clean = trimmed.TrimEnd('@', '*', '=');
                        result.Add(new FileNode { Name = clean, FullPath = dirPath + clean, IsDirectory = false });
                    }
                }
                return result;
            }
            catch
            {
                return null;
            }
        }

        private void btnPullItems_Click(object sender, RoutedEventArgs e)
        {
            var selected = tvFiles.SelectedItem as TreeViewItem;
            if (selected == null) return;

            var fileNode = selected.Header as FileNode;
            if (fileNode == null) return;

            string remotePath = fileNode.FullPath;
            string name = fileNode.Name;
            
            string outDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "Phone_ADB");
            if (!Directory.Exists(outDir))
            {
                Directory.CreateDirectory(outDir);
            }

            // Fire and forget
            Task.Run(() =>
            {
                var proc = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = _adbPath,
                        Arguments = $"-s {_targetDevice} pull \"{remotePath.Replace("\"", "\\\"")}\" \"{outDir}\"",
                        UseShellExecute = false,
                        CreateNoWindow = true
                    }
                };
                proc.Start();
                proc.WaitForExit();

                // Show toast using PowerShell snippet to avoid UWP complex XML building locally if we want to stay ponytail
                // Wait, UWP Toast is better done safely via PS if we don't want to import Microsoft.Toolkit.Uwp.Notifications
                // Or we can just use Process.Start("explorer.exe", outDir); directly as UI feedback!
                Process.Start("explorer.exe", outDir);
            });

            this.Close();
        }
    }
}
