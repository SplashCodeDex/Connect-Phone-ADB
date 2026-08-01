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
using Windows.ApplicationModel;
using Windows.ApplicationModel.Activation;
using Windows.ApplicationModel.DataTransfer.ShareTarget;

namespace DeXShareTarget
{
    class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            File.WriteAllText(Path.Combine(Path.GetTempPath(), "DeXArgs.txt"), $"Args Length: {args.Length}, Args: {string.Join(" | ", args)}");
            try 
            {
                var program = new Program();
                program.Run(args);
            }
            catch (Exception ex)
            {
                File.WriteAllText(Path.Combine(Path.GetTempPath(), $"DeXCrash_Main_{DateTime.Now:yyyyMMdd_HHmmss}.txt"), ex.ToString());
            }
        }

        public void Run(string[] args)
        {
            AppDomain.CurrentDomain.UnhandledException += (s, e) => File.WriteAllText(Path.Combine(Path.GetTempPath(), $"DeXCrash_{DateTime.Now:yyyyMMdd_HHmmss}.txt"), e.ExceptionObject.ToString());
            
            var activatedArgs = AppInstance.GetActivatedEventArgs();
            
            // 1. Direct CLI invocation (e.g. from UI)
            if (args != null && args.Length >= 3 && args[0].Equals("-IP", StringComparison.OrdinalIgnoreCase))
            {
                string targetIp = args[1];
                var filePaths = new List<string>();
                for (int i = 2; i < args.Length; i++)
                {
                    if (File.Exists(args[i])) filePaths.Add(args[i]);
                }
                
                if (filePaths.Count > 0)
                {
                    Application app = new Application();
                    app.Startup += async (s, e) =>
                    {
                        var window = new TransferWindow(filePaths);
                        window.TargetIp = targetIp;
                        window.Show();
                        await window.StartTransferAsync();
                        app.Shutdown();
                    };
                    app.Run();
                    return;
                }
            }

            // 2. Windows Share Target Invocation
            if (activatedArgs != null && activatedArgs.Kind == ActivationKind.ShareTarget)
            {
                var shareArgs = (ShareTargetActivatedEventArgs)activatedArgs;
                ShareOperation shareOperation = shareArgs.ShareOperation;
                
                var filesTask = shareOperation.Data.GetStorageItemsAsync().AsTask();
                filesTask.Wait();
                var items = filesTask.Result;
                
                var filePaths = new List<string>();
                foreach (var item in items)
                {
                    filePaths.Add(item.Path);
                }
                
                shareOperation.ReportCompleted();
                
                if (filePaths.Count > 0)
                {
                    Application app = new Application();
                    app.Startup += async (s, e) =>
                    {
                        var window = new TransferWindow(filePaths);
                        window.Show();
                        await window.StartTransferAsync();
                        app.Shutdown();
                    };
                    app.Run();
                }
            }
            else
            {
                string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                string ps1Path = Path.Combine(exeDir, "bin", "Connect-Engine.ps1");
                string logPath = Path.Combine(Path.GetTempPath(), "DeXEngine_Errors.txt");
                
                // Rotate the stderr log so it stays forensically useful (keep last 500 lines when > 512 KB)
                try
                {
                    if (File.Exists(logPath) && new FileInfo(logPath).Length > 512 * 1024)
                    {
                        var lines = File.ReadAllLines(logPath);
                        File.WriteAllLines(logPath, lines.Skip(Math.Max(0, lines.Length - 500)));
                    }
                }
                catch { }
                
                string extraArgs = (activatedArgs != null && activatedArgs.Kind == ActivationKind.StartupTask) ? " -Background" : "";
                var startInfo = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-STA -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command \"& '{ps1Path}'{extraArgs} 2>> '{logPath}'\"",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                
                var proc = Process.Start(startInfo);
                
                try 
                {
                    LocalSendServer.StartAsync().Wait();
                } 
                catch (Exception ex)
                {
                    File.WriteAllText(Path.Combine(Path.GetTempPath(), "LocalSendServerCrash.txt"), ex.ToString());
                }

                proc?.WaitForExit();
            }
        }
    }


}
