using System;
using System.IO;
using System.Security.Cryptography;
using System.Threading.Tasks;

namespace DeXShareTarget.Services
{
    public static class HashHelper
    {
        private const int PartialSize = 32768; // 32KB

        public static async Task<string?> ComputePartialHashAsync(string filePath, long fileSize)
        {
            if (fileSize == 0) return null;
            try
            {
                using var hasher = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                using var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, PartialSize, true);

                byte[] buffer = new byte[PartialSize];
                int bytesReadHead = await fs.ReadAsync(buffer, 0, PartialSize);
                if (bytesReadHead > 0)
                {
                    hasher.AppendData(buffer, 0, bytesReadHead);
                }

                if (fileSize > PartialSize * 2)
                {
                    fs.Position = fileSize - PartialSize;
                    int bytesReadTail = await fs.ReadAsync(buffer, 0, PartialSize);
                    if (bytesReadTail > 0)
                    {
                        hasher.AppendData(buffer, 0, bytesReadTail);
                    }
                }
                else if (fileSize > bytesReadHead)
                {
                    int remaining = (int)(fileSize - bytesReadHead);
                    while (remaining > 0)
                    {
                        int read = await fs.ReadAsync(buffer, 0, Math.Min(remaining, PartialSize));
                        if (read == 0) break;
                        hasher.AppendData(buffer, 0, read);
                        remaining -= read;
                    }
                }

                byte[] hashBytes = hasher.GetHashAndReset();
                return Convert.ToHexString(hashBytes).ToUpperInvariant();
            }
            catch
            {
                return null;
            }
        }
    }
}
