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
        private static Mutex? _instanceMutex;

        [STAThread]
        static void Main(string[] args)
        {
            _instanceMutex = new Mutex(true, "DeXShareTarget_SingleInstance_Mutex", out bool isNewInstance);
            if (!isNewInstance && (args == null || args.Length == 0))
            {
                // Another background instance is already running
                return;
            }

            try 
            {
                var program = new Program();
                program.Run(args);
            }
            catch
            {
                // Silent catch in production
            }
        }

        public void Run(string[] args)
        {
            Windows.ApplicationModel.Activation.IActivatedEventArgs? activatedArgs = null;
            try { activatedArgs = AppInstance.GetActivatedEventArgs(); } catch { }
            
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
                string extraArgs = (activatedArgs != null && activatedArgs.Kind == ActivationKind.StartupTask) ? " -Background" : "";
                var startInfo = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-STA -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command \"& '{ps1Path}'{extraArgs}\"",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                
                var proc = Process.Start(startInfo);
                
                var app = new System.Windows.Application();
                app.Startup += (s, e) => 
                {
                    try 
                    {
                        _ = LocalSendServer.StartAsync();
                    } 
                    catch 
                    {
                        // Ignore server start failures in production
                    }
                };
                app.Run();
            }
        }
    }


}
