using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace DeXShareTarget.Services
{
    public static class IdentityManager
    {
        public static string Fingerprint { get; set; } = "";
        public static string IdentityHash { get; set; } = "";
        public static string Email { get; set; } = "";
        public static HashSet<string> PairedFingerprints { get; set; } = new();
        public static Dictionary<string, string> PairedTokens { get; set; } = new();
        private static readonly object _fileLock = new object();
        
        public static void Initialize()
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX");
            Directory.CreateDirectory(dir);
            var file = Path.Combine(dir, "identity.json");
            
            if (File.Exists(file))
            {
                try {
                    var json = File.ReadAllText(file);
                    var doc = JsonDocument.Parse(json);
                    Fingerprint = doc.RootElement.GetProperty("fingerprint").GetString() ?? Guid.NewGuid().ToString();
                    Email = doc.RootElement.TryGetProperty("email", out var e) ? e.GetString() ?? "" : "";
                    
                    if (!string.IsNullOrWhiteSpace(Email))
                    {
                        using var sha = SHA256.Create();
                        var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(Email.Trim().ToLowerInvariant()));
                        IdentityHash = BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
                    }
                    else
                    {
                        IdentityHash = doc.RootElement.TryGetProperty("identityHash", out var h) ? h.GetString() ?? Guid.NewGuid().ToString() : Guid.NewGuid().ToString();
                    }
                } catch {}
            }
            else
            {
                Fingerprint = Guid.NewGuid().ToString();
                IdentityHash = Guid.NewGuid().ToString();
                lock (_fileLock)
                {
                    File.WriteAllText(file, JsonSerializer.Serialize(new { fingerprint = Fingerprint, identityHash = IdentityHash, email = Email }));
                }
            }
            
            LoadPairedDevices();
            LoadDeviceAliases();
            LoadPairedTokens();
        }

        private static void LoadPairedDevices()
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX");
            var file = Path.Combine(dir, "paired_devices.json");
            if (File.Exists(file))
            {
                try {
                    string json;
                    lock (_fileLock) { json = File.ReadAllText(file); }
                    var list = JsonSerializer.Deserialize<List<string>>(json);
                    if (list != null) PairedFingerprints = new HashSet<string>(list);
                } catch {}
            }
        }

        public static void SavePairedDevice(string fp)
        {
            PairedFingerprints.Add(fp);
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX");
            var file = Path.Combine(dir, "paired_devices.json");
            lock (_fileLock)
            {
                File.WriteAllText(file, JsonSerializer.Serialize(PairedFingerprints.ToList()));
            }
        }

        public static void RemovePairedDevice(string fp)
        {
            if (PairedFingerprints.Remove(fp))
            {
                var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX");
                var file = Path.Combine(dir, "paired_devices.json");
                lock (_fileLock)
                {
                    File.WriteAllText(file, JsonSerializer.Serialize(PairedFingerprints.ToList()));
                }
            }
            if (PairedTokens.Remove(fp))
            {
                var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX");
                var file = Path.Combine(dir, "paired_tokens.json");
                lock (_fileLock)
                {
                    File.WriteAllText(file, JsonSerializer.Serialize(PairedTokens));
                }
            }
        }

        private static void LoadPairedTokens()
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX");
            var file = Path.Combine(dir, "paired_tokens.json");
            if (File.Exists(file))
            {
                try {
                    string json;
                    lock (_fileLock) { json = File.ReadAllText(file); }
                    var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(json);
                    if (dict != null) PairedTokens = new Dictionary<string, string>(dict);
                } catch {}
            }
        }

        public static void SavePairedToken(string fp, string token)
        {
            PairedTokens[fp] = token;
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX");
            var file = Path.Combine(dir, "paired_tokens.json");
            lock (_fileLock)
            {
                File.WriteAllText(file, JsonSerializer.Serialize(PairedTokens));
            }
        }

        private static void LoadDeviceAliases()
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX");
            var file = Path.Combine(dir, "paired_aliases.json");
            if (File.Exists(file))
            {
                try {
                    string json;
                    lock (_fileLock) { json = File.ReadAllText(file); }
                    var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(json);
                    if (dict != null) DeviceAliases = new Dictionary<string, string>(dict);
                } catch {}
            }
        }

        public static Dictionary<string, string> DeviceAliases { get; set; } = new();

        public static void SetDeviceAlias(string fp, string alias)
        {
            DeviceAliases[fp] = alias;
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX");
            var file = Path.Combine(dir, "paired_aliases.json");
            lock (_fileLock)
            {
                File.WriteAllText(file, JsonSerializer.Serialize(DeviceAliases));
            }
        }

        public static string GetDeviceAlias(string fp)
        {
            return DeviceAliases.TryGetValue(fp, out var a) ? a : "";
        }

        public static void SetEmail(string email)
        {
            Email = email;
            if (!string.IsNullOrWhiteSpace(Email))
            {
                using var sha = SHA256.Create();
                var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(Email.Trim().ToLowerInvariant()));
                IdentityHash = BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
            }
            else
            {
                IdentityHash = Guid.NewGuid().ToString();
            }
            
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX");
            var file = Path.Combine(dir, "identity.json");
            lock (_fileLock)
            {
                File.WriteAllText(file, JsonSerializer.Serialize(new { fingerprint = Fingerprint, identityHash = IdentityHash, email = Email }));
            }
        }
    }
}
