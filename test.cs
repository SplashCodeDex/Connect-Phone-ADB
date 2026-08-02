using System;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;

class Program {
    static async Task Main() {
        var handler = new HttpClientHandler {
            ServerCertificateCustomValidationCallback = (sender, cert, chain, sslPolicyErrors) => true
        };
        using var client = new HttpClient(handler);
        var json = @"{""info"":{""alias"":""TestAndroid"",""version"":""2.0"",""deviceModel"":""Test""},""files"":{""test1234"":{""id"":""test1234"",""fileName"":""hello.txt"",""size"":12,""fileType"":""text/plain"",""sha256"":""b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9""}}}";
        var content = new StringContent(json, Encoding.UTF8, "application/json");
        try {
            var response = await client.PostAsync("https://127.0.0.1:53317/api/localsend/v2/prepare-upload", content);
            var respStr = await response.Content.ReadAsStringAsync();
            Console.WriteLine($"STATUS: {response.StatusCode}");
            Console.WriteLine($"BODY: {respStr}");
        } catch (Exception ex) {
            Console.WriteLine($"ERROR: {ex.Message}");
            if (ex.InnerException != null) Console.WriteLine($"INNER: {ex.InnerException.Message}");
        }
    }
}
