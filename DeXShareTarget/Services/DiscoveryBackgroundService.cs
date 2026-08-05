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
          try
          {
            var myInfo = new RegisterDto { 
                Fingerprint = IdentityManager.Fingerprint,
                IdentityHash = IdentityManager.IdentityHash,
                DeviceModel = "Windows PC",
                DeviceType = "desktop"
            };

            // Cache local IPs for self-discovery filtering
            var localIPs = new HashSet<string>();
            try {
                foreach (var iface in NetworkInterface.GetAllNetworkInterfaces()) {
                    if (iface.OperationalStatus != OperationalStatus.Up) continue;
                    foreach (var addr in iface.GetIPProperties().UnicastAddresses) {
                        if (addr.Address.AddressFamily == AddressFamily.InterNetwork)
                            localIPs.Add(addr.Address.ToString());
                    }
                }
            } catch { }

            bool IsSelf(string? fp, string? alias, string? senderIp = null) {
                if (!string.IsNullOrEmpty(fp) && fp == myInfo.Fingerprint) return true;
                if (!string.IsNullOrEmpty(alias) && alias == myInfo.Alias && !string.IsNullOrEmpty(senderIp) && localIPs.Contains(senderIp)) return true;
                return false;
            }

            using var mdns = new Makaretu.Dns.MulticastService();
            var service = new Makaretu.Dns.ServiceProfile(myInfo.Alias, "_dex._udp", (ushort)53317);
            service.AddProperty("alias", myInfo.Alias);
            service.AddProperty("fingerprint", myInfo.Fingerprint);
            service.AddProperty("identityHash", myInfo.IdentityHash);
            service.AddProperty("deviceModel", myInfo.DeviceModel);
            service.AddProperty("deviceType", myInfo.DeviceType);
            
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
                            var deviceModel = txt.Strings.FirstOrDefault(x => x.StartsWith("deviceModel="))?.Split('=')[1] ?? "Unknown";
                            var deviceType = txt.Strings.FirstOrDefault(x => x.StartsWith("deviceType="))?.Split('=')[1] ?? "unknown";
                            var senderIp = a.Address.ToString();
                            
                            if (!string.IsNullOrEmpty(fp) && !IsSelf(fp, alias, senderIp))
                            {
                                var dto = new RegisterDto { Fingerprint = fp, Alias = alias ?? "Unknown", Port = srv.Port, IdentityHash = identityHash, DeviceModel = deviceModel, DeviceType = deviceType };
                                Devices[fp] = new DiscoveredDevice
                                {
                                    Ip = senderIp,
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
                        var senderIp = result.RemoteEndPoint.Address.ToString();
                        var alias = root.TryGetProperty("alias", out var al) ? al.GetString() : null;
                        if (!string.IsNullOrEmpty(fp) && !IsSelf(fp, alias, senderIp))
                        {
                            var dto = new RegisterDto
                            {
                                Fingerprint = fp,
                                Alias = alias ?? "Unknown",
                                Port = root.TryGetProperty("port", out var p) ? p.GetInt32() : 53317,
                                DeviceModel = root.TryGetProperty("deviceModel", out var dm) ? (dm.GetString() ?? "Unknown") : "Unknown",
                                DeviceType = root.TryGetProperty("deviceType", out var dt) ? (dt.GetString() ?? "unknown") : "unknown",
                                IdentityHash = root.TryGetProperty("identityHash", out var ih) ? ih.GetString() : null
                            };
                            Devices[fp] = new DiscoveredDevice
                            {
                                Ip = senderIp,
                                Info = dto,
                                LastSeen = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                                IsPaired = IdentityManager.PairedFingerprints.Contains(fp),
                                IsAutoTrusted = !string.IsNullOrEmpty(dto.IdentityHash) && dto.IdentityHash == myInfo.IdentityHash
                            };
                        }
                    } catch (OperationCanceledException) { break; } catch { }
                }
            }, stoppingToken);

            _ = Task.Run(async () =>
            {
                while (!stoppingToken.IsCancellationRequested)
                {
                  try
                  {
                    myInfo.IdentityHash = IdentityManager.IdentityHash;
                    var dynamicJson = JsonSerializer.Serialize(myInfo);
                    var dynamicBytes = Encoding.UTF8.GetBytes(dynamicJson);

                    try { await udp.SendAsync(dynamicBytes, dynamicBytes.Length, new IPEndPoint(multicastAddress, 53317)); } catch { }
                    foreach (var ep in GetDirectedBroadcasts(53317))
                    {
                        try { await udp.SendAsync(dynamicBytes, dynamicBytes.Length, ep); } catch { }
                    }
                    await Task.Delay(2000, stoppingToken);
                  } catch (OperationCanceledException) { break; } catch { }
                }
            }, stoppingToken);
            
            while (!stoppingToken.IsCancellationRequested)
            {
                try { await Task.Delay(2000, stoppingToken); } catch (OperationCanceledException) { break; }
            }
            
            sd.Unadvertise(service);
            mdns.Stop();
          } catch (OperationCanceledException) { /* normal shutdown */ } catch { /* prevent host crash */ }
        }
    }
}
