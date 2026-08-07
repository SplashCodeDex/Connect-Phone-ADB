using System;
using System.Text.Json;
using System.Net.Http;
using System.Threading.Tasks;

public class PairRequestDto
{
    public string Alias { get; set; } = "";
    public string Fingerprint { get; set; } = "";
    public string Pin { get; set; } = "";
    public string Token { get; set; }
}

public class Program {
    public static async Task Main() {
        try {
            var reqDto = new PairRequestDto { Alias = "PC", Fingerprint = "test-pc-fp", Pin = "123456", Token = "xyz" };
            var json = JsonSerializer.Serialize(reqDto, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
            
            var handler = new HttpClientHandler
            {
                ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true
            };
            using var client = new HttpClient(handler);
            client.Timeout = TimeSpan.FromSeconds(5);
            client.DefaultRequestVersion = new Version(1, 1);
            client.DefaultVersionPolicy = HttpVersionPolicy.RequestVersionExact;

            var content = new StringContent(json, System.Text.Encoding.UTF8, "application/json");
            var request = new HttpRequestMessage(HttpMethod.Post, "https://10.16.50.207:53317/api/localsend/v2/pair-prompt") { Content = content, Version = new Version(1,1) };
            
            var response = await client.SendAsync(request);
            
            Console.WriteLine("Status: " + response.StatusCode);
        } catch (Exception ex) {
            Console.WriteLine("Exception: " + ex.Message);
        }
    }
}
