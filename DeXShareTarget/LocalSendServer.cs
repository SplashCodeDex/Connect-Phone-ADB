using System;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using DeXShareTarget.Services;
using DeXShareTarget.Endpoints;

namespace DeXShareTarget
{
    public static class LocalSendServer
    {
        public static WebApplication? App;

        public static async Task StartAsync()
        {
            IdentityManager.Initialize();
            var builder = WebApplication.CreateBuilder();
            
            // Silence Kestrel verbose logs
            builder.Logging.SetMinimumLevel(LogLevel.Warning);

            // Self-signed certificate for TLS
            using var rsa = RSA.Create(2048);
            var request = new CertificateRequest("cn=localsend", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            var ephemeralCert = request.CreateSelfSigned(DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddYears(1));
            // Windows MsQuic requires the cert to be persisted/exportable, so we export to PFX and re-import
            var pfxBytes = ephemeralCert.Export(X509ContentType.Pfx, "password");
            var cert = new X509Certificate2(pfxBytes, "password", X509KeyStorageFlags.Exportable);

            builder.WebHost.ConfigureKestrel(options =>
            {
                // Endpoint 1: HTTP/1.1 and HTTP/2 on TCP 53317 (Does not block UDP 53317)
                options.ListenAnyIP(53317, listenOptions =>
                {
                    listenOptions.Protocols = Microsoft.AspNetCore.Server.Kestrel.Core.HttpProtocols.Http1AndHttp2;
                    listenOptions.UseHttps(cert);
                });
                
                // Endpoint 2: HTTP/3 (QUIC) on UDP 53316 (Exclusive QUIC socket)
                options.ListenAnyIP(53316, listenOptions =>
                {
                    listenOptions.Protocols = Microsoft.AspNetCore.Server.Kestrel.Core.HttpProtocols.Http3;
                    listenOptions.UseHttps(cert);
                });
                
                // Add a local unencrypted port for PowerShell GUI to query discovered devices easily
                options.ListenLocalhost(53318);
            });

            builder.Services.AddHostedService<DiscoveryBackgroundService>();

            App = builder.Build();

            // Custom Middleware to rewrite Alt-Svc to point to the dedicated HTTP/3 port (53316)
            App.Use(async (context, next) =>
            {
                context.Response.OnStarting(() =>
                {
                    context.Response.Headers["Alt-Svc"] = "h3=\":53316\"; ma=86400";
                    return Task.CompletedTask;
                });
                await next();
            });

            App.MapLocalSendEndpoints();

            await App.StartAsync();
        }
    }
}
