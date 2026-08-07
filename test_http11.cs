using System;
using System.Net.Http;
using System.Threading.Tasks;

class Program {
    static async Task Main() {
        var handler = new HttpClientHandler {
            ServerCertificateCustomValidationCallback = (m, c, ch, e) => true
        };
        var client = new HttpClient(handler);
        client.DefaultRequestVersion = new Version(1, 1);
        client.DefaultVersionPolicy = HttpVersionPolicy.RequestVersionExact;
        client.Timeout = TimeSpan.FromSeconds(5);
        try {
            var res = await client.GetAsync("https://10.13.135.18:53317/api/localsend/v2/info");
            Console.WriteLine("Status: " + res.StatusCode);
        } catch (Exception ex) {
            Console.WriteLine("Error: " + ex.Message);
        }
    }
}
