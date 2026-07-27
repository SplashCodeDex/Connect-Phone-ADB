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
                    foreach (var item in items)
                    {
                        string filePath = item.Path;
                        
                        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                        string ps1Path = Path.Combine(exeDir, "bin", "Send-To-Phone.ps1");
                        
                        var startInfo = new ProcessStartInfo
                        {
                            FileName = "powershell.exe",
                            Arguments = $"-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File \"{ps1Path}\" -FilePath \"{filePath}\"",
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
