using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace BimalPathology.SmsGateway
{
    public static class GatewayConstants
    {
        public const string SupabaseUrl = "https://rncjxstujioagcezvfkb.supabase.co";
        public const string SparrowSender = "BimalPath";
    }

    public sealed class GatewaySecrets
    {
        public string SupabaseUrl { get; set; } = GatewayConstants.SupabaseUrl;
        public string ServiceRoleKey { get; set; } = string.Empty;
        public string SparrowToken { get; set; } = string.Empty;
        public string SparrowFromIdentity { get; set; } = GatewayConstants.SparrowSender;
    }

    public static class ProtectedSettings
    {
        public static void SaveProtectedSecrets(string filePath, GatewaySecrets secrets)
        {
            var json = JsonSerializer.Serialize(secrets);
            var bytes = Encoding.UTF8.GetBytes(json);
            var encrypted = ProtectedData.Protect(bytes, null, DataProtectionScope.LocalMachine);
            File.WriteAllBytes(filePath, encrypted);
        }

        public static GatewaySecrets LoadProtectedSecrets(string filePath)
        {
            if (!File.Exists(filePath))
            {
                throw new FileNotFoundException("Protected secrets file not found.", filePath);
            }

            var encrypted = File.ReadAllBytes(filePath);
            var decrypted = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.LocalMachine);
            var json = Encoding.UTF8.GetString(decrypted);
            return JsonSerializer.Deserialize<GatewaySecrets>(json) ?? throw new InvalidOperationException("Failed to deserialize secrets.");
        }
    }
}
