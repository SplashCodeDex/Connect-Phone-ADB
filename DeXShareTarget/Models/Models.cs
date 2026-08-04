using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;
using DeXShareTarget.Services;

namespace DeXShareTarget.Models
{
    public class RegisterDto
    {
        [JsonPropertyName("alias")] public string Alias { get; set; } = Environment.MachineName;
        [JsonPropertyName("version")] public string Version { get; set; } = "2.0";
        [JsonPropertyName("deviceModel")] public string DeviceModel { get; set; } = "Windows PC";
        [JsonPropertyName("deviceType")] public string DeviceType { get; set; } = "desktop";
        [JsonPropertyName("fingerprint")] public string Fingerprint { get; set; } = IdentityManager.Fingerprint;
        [JsonPropertyName("port")] public int Port { get; set; } = 53317;
        [JsonPropertyName("protocol")] public string Protocol { get; set; } = "https";
        [JsonPropertyName("download")] public bool Download { get; set; } = true;
        [JsonPropertyName("identityHash")] public string? IdentityHash { get; set; }
    }

    public class PrepareUploadRequestDto
    {
        [JsonPropertyName("info")] public RegisterDto Info { get; set; } = new();
        [JsonPropertyName("files")] public Dictionary<string, FileDto> Files { get; set; } = new();
    }

    public class FileDto
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("fileName")] public string FileName { get; set; } = "";
        [JsonPropertyName("size")] public long Size { get; set; }
        [JsonPropertyName("fileType")] public string FileType { get; set; } = "";
    }

    public class PrepareUploadResponseDto
    {
        [JsonPropertyName("sessionId")] public string SessionId { get; set; } = "";
        [JsonPropertyName("files")] public Dictionary<string, string> Files { get; set; } = new();
    }

    public class PairRequestDto
    {
        [JsonPropertyName("alias")] public string Alias { get; set; } = "";
        [JsonPropertyName("fingerprint")] public string Fingerprint { get; set; } = "";
        [JsonPropertyName("pin")] public string Pin { get; set; } = "";
    }

    public class DiscoveredDevice
    {
        public string Ip { get; set; } = "";
        public RegisterDto Info { get; set; } = new();
        public long LastSeen { get; set; }
        public bool IsPaired { get; set; }
        public bool IsAutoTrusted { get; set; }
    }

    public enum PairResult { Reject, AcceptPermanent, AcceptGuest }
}
