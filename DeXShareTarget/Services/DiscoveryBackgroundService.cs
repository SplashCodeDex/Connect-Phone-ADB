using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using DeXShareTarget.Models;

namespace DeXShareTarget.Services
{
    public class DiscoveryBackgroundService : BackgroundService
    {
        public static readonly ConcurrentDictionary<string, DiscoveredDevice> Devices = new();

        private static List<IPEndPoint> GetDirectedBroadcasts(int port)
        {
            var endpoints = new List<IPEndPoint> { new IPEndPoint(IPAddress.Broadcast, port) };
            try
            {
                foreach (var iface in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (iface.OperationalStatus != OperationalStatus.Up) continue;
                    var ipProps = iface.GetIPProperties();
                    
                    // 1. Add Default Gateway (The Ultimate Unicast Fallback for Android Hotspots)
                    foreach (var gateway in ipProps.GatewayAddresses)
                    {
                        if (gateway.Address.AddressFamily == AddressFamily.InterNetwork)
                        {
                            endpoints.Add(new IPEndPoint(gateway.Address, port));
                        }
                    }

                    // 2. Add Directed Subnet Broadcasts
                    foreach (var ip in ipProps.UnicastAddresses)
                    {
                        if (ip.Address.AddressFamily == AddressFamily.InterNetwork && ip.IPv4Mask != null)
                        {
                            var addressBytes = ip.Address.GetAddressBytes();
                            var maskBytes = ip.IPv4Mask.GetAddressBytes();
                            var broadcastBytes = new byte[4];
                            for (int i = 0; i < 4; i++)
                                broadcastBytes[i] = (byte)(addressBytes[i] | ~maskBytes[i]);
                            endpoints.Add(new IPEndPoint(new IPAddress(broadcastBytes), port));
                        }
                    }
                }
            } catch { }
            return endpoints.GroupBy(e => e.Address.ToString()).Select(g => g.First()).ToList();
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            var myInfo = new RegisterDto { 
                Fingerprint = IdentityManager.Fingerprint,
                IdentityHash = IdentityManager.IdentityHash
            };

            using var mdns = new Makaretu.Dns.MulticastService();
            var service = new Makaretu.Dns.ServiceProfile(myInfo.Alias, "_dex._udp", (ushort)53317);
            service.AddProperty("alias", myInfo.Alias);
            service.AddProperty("fingerprint", myInfo.Fingerprint);
            service.AddProperty("identityHash", myInfo.IdentityHash);
            
            var sd = new Makaretu.Dns.ServiceDiscovery(mdns);
            sd.Advertise(service);

            sd.ServiceDiscovered += (s, serviceName) => {
                mdns.SendQuery(serviceName, Makaretu.Dns.DnsClass.IN, Makaretu.Dns.DnsType.ANY);
            };

            sd.ServiceInstanceDiscovered += (s, e) => {
                try {
                    if (e.Message.Answers.Count > 0)
                    {
                        var srv = e.Message.Answers.OfType<Makaretu.Dns.SRVRecord>().FirstOrDefault();
                        var txt = e.Message.Answers.OfType<Makaretu.Dns.TXTRecord>().FirstOrDefault();
                        var a = e.Message.Answers.OfType<Makaretu.Dns.ARecord>().FirstOrDefault();
                        
                        if (srv != null && txt != null && a != null)
                        {
                            var fp = txt.Strings.FirstOrDefault(x => x.StartsWith("fingerprint="))?.Split('=')[1];
                            var alias = txt.Strings.FirstOrDefault(x => x.StartsWith("alias="))?.Split('=')[1];
                            var identityHash = txt.Strings.FirstOrDefault(x => x.StartsWith("identityHash="))?.Split('=')[1];
                            
                            if (!string.IsNullOrEmpty(fp) && fp != myInfo.Fingerprint)
                            {
                                var dto = new RegisterDto { Fingerprint = fp, Alias = alias ?? "Unknown", Port = srv.Port, IdentityHash = identityHash };
                                Devices[fp] = new DiscoveredDevice
                                {
                                    Ip = a.Address.ToString(),
                                    Info = dto,
                                    LastSeen = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                                    IsPaired = IdentityManager.PairedFingerprints.Contains(fp),
                                    IsAutoTrusted = !string.IsNullOrEmpty(identityHash) && identityHash == myInfo.IdentityHash
                                };
                            }
                        }
                    }
                } catch { }
            };

            mdns.Start();
            
            var multicastAddress = IPAddress.Parse("224.0.0.167");
            var endPoint = new IPEndPoint(IPAddress.Any, 53317);
            using var udp = new UdpClient();
            udp.EnableBroadcast = true;
            udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            udp.Client.Bind(endPoint);
            udp.JoinMulticastGroup(multicastAddress);

            var myJson = JsonSerializer.Serialize(myInfo);
            var myBytes = Encoding.UTF8.GetBytes(myJson);

            _ = Task.Run(async () =>
            {
                while (!stoppingToken.IsCancellationRequested)
                {
                    try
                    {
                        var result = await udp.ReceiveAsync(stoppingToken);
                        var msg = Encoding.UTF8.GetString(result.Buffer);
                        var doc = JsonDocument.Parse(msg);
                        var root = doc.RootElement;
                        var fp = root.TryGetProperty("fingerprint", out var f) ? f.GetString() : "";
                        if (!string.IsNullOrEmpty(fp) && fp != myInfo.Fingerprint)
                        {
                            var dto = new RegisterDto
                            {
                                Fingerprint = fp,
                                Alias = root.TryGetProperty("alias", out var a) ? (a.GetString() ?? "Unknown") : "Unknown",
                                Port = root.TryGetProperty("port", out var p) ? p.GetInt32() : 53317,
                                DeviceModel = root.TryGetProperty("deviceModel", out var dm) ? (dm.GetString() ?? "Unknown") : "Unknown",
                                DeviceType = root.TryGetProperty("deviceType", out var dt) ? (dt.GetString() ?? "unknown") : "unknown",
                                IdentityHash = root.TryGetProperty("identityHash", out var ih) ? ih.GetString() : null
                            };
                            Devices[fp] = new DiscoveredDevice
                            {
                                Ip = result.RemoteEndPoint.Address.ToString(),
                                Info = dto,
                                LastSeen = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                                IsPaired = IdentityManager.PairedFingerprints.Contains(fp),
                                IsAutoTrusted = !string.IsNullOrEmpty(dto.IdentityHash) && dto.IdentityHash == myInfo.IdentityHash
                            };
                        }
                    } catch { }
                }
            }, stoppingToken);

            _ = Task.Run(async () =>
            {
                var targetEp = new IPEndPoint(multicastAddress, 53317);
                while (!stoppingToken.IsCancellationRequested)
                {
                    try { await udp.SendAsync(myBytes, myBytes.Length, targetEp); } catch { }
                    foreach (var ep in GetDirectedBroadcasts(53317))
                    {
                        try { await udp.SendAsync(myBytes, myBytes.Length, ep); } catch { }
                    }
                    await Task.Delay(2000, stoppingToken);
                }
            }, stoppingToken);
            
            while (!stoppingToken.IsCancellationRequested)
            {
                await Task.Delay(2000, stoppingToken);
            }
            
            sd.Unadvertise(service);
            mdns.Stop();
        }
    }
}
