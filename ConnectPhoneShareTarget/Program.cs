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
        }
    }
}
