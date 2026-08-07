using System;
using System.Text.Json;

public class PairRequestDto
{
    public string Alias { get; set; } = "";
    public string Fingerprint { get; set; } = "";
    public string Pin { get; set; } = "";
    public string Token { get; set; }
}
public class Program {
    public static void Main() {
        var reqDto = new PairRequestDto { Alias = "PC", Fingerprint = "test-pc-fp", Pin = "123456", Token = "xyz" };
        var json = JsonSerializer.Serialize(reqDto, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        Console.WriteLine(json);
    }
}
