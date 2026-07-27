using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using Windows.ApplicationModel;
using Windows.ApplicationModel.Activation;
using Windows.ApplicationModel.DataTransfer.ShareTarget;

namespace ConnectPhoneShareTarget
{
    class Program
    {
        [STAThread]
        static async Task Main(string[] args)
        {
            AppDomain.CurrentDomain.UnhandledException += (s, e) => File.WriteAllText(Path.Combine(Path.GetTempPath(), $"ConnectPhoneCrash_{DateTime.Now:yyyyMMdd_HHmmss}.txt"), e.ExceptionObject.ToString());
            
            var activatedArgs = AppInstance.GetActivatedEventArgs();
            
            if (activatedArgs != null && activatedArgs.Kind == ActivationKind.ShareTarget)
            {
                var shareArgs = (ShareTargetActivatedEventArgs)activatedArgs;
                ShareOperation shareOperation = shareArgs.ShareOperation;
                
                if (shareOperation.Data.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.StorageItems))
                {
                    var items = await shareOperation.Data.GetStorageItemsAsync();
                    var filePaths = new System.Collections.Generic.List<string>();
                    foreach (var item in items)
                    {
                        filePaths.Add(item.Path);
                    }
                    
                    if (filePaths.Count > 0)
                    {
                        string tempFile = Path.Combine(Path.GetTempPath(), $"ConnectPhoneShare_{Guid.NewGuid():N}.txt");
                        File.WriteAllLines(tempFile, filePaths);
                        
                        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                        string ps1Path = Path.Combine(exeDir, "bin", "Send-To-Phone.ps1");
                        
                        var startInfo = new ProcessStartInfo
                        {
                            FileName = "powershell.exe",
                            Arguments = $"-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File \"{ps1Path}\" -FileList \"{tempFile}\"",
                            CreateNoWindow = true,
                            UseShellExecute = false
                        };
                        
                        Process.Start(startInfo);
                    }
                }
                
                shareOperation.ReportCompleted();
            }
            else
            {
                // Normal Launch (e.g. from Start Menu or Startup Task)
                string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                string ps1Path = Path.Combine(exeDir, "bin", "Connect-Engine.ps1");
                
                var startInfo = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File \"{ps1Path}\"",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                
                Process.Start(startInfo);
            }
        }
    }
}
