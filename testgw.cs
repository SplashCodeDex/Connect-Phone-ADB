using System;
using System.Net;
using System.Net.Sockets;
using System.Net.NetworkInformation;

class Program {
    static void Main() {
        foreach (var iface in NetworkInterface.GetAllNetworkInterfaces()) {
            if (iface.OperationalStatus != OperationalStatus.Up) continue;
            var ipProps = iface.GetIPProperties();
            foreach (var gateway in ipProps.GatewayAddresses) {
                if (gateway.Address.AddressFamily == AddressFamily.InterNetwork) {
                    Console.WriteLine("Gateway: " + gateway.Address);
                }
            }
        }
    }
}
