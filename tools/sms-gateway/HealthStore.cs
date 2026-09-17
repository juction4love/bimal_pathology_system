using System;
using System.IO;
using System.Text.Json;

namespace BimalPathology.SmsGateway
{
    public sealed class HealthStore
    {
        private readonly string _healthFilePath;
        private readonly object _lock = new();

        public HealthStore(string healthFilePath)
        {
            _healthFilePath = healthFilePath;
        }

        public void RecordSuccess()
        {
            lock (_lock)
            {
                var current = Read();
                current.last_successful_send_at = DateTimeOffset.UtcNow;
                current.last_heartbeat_at = DateTimeOffset.UtcNow;
                Write(current);
            }
        }

        public void RecordError()
        {
            lock (_lock)
            {
                var current = Read();
                current.queue_error_count++;
                current.last_heartbeat_at = DateTimeOffset.UtcNow;
                Write(current);
            }
        }

        public GatewayHealthStatus Read()
        {
            try
            {
                if (File.Exists(_healthFilePath))
                {
                    var text = File.ReadAllText(_healthFilePath);
                    return JsonSerializer.Deserialize<GatewayHealthStatus>(text) ?? new GatewayHealthStatus();
                }
            }
            catch
            {
                // Fallback to fresh status
            }
            return new GatewayHealthStatus();
        }

        private void Write(GatewayHealthStatus status)
        {
            try
            {
                var json = JsonSerializer.Serialize(status, new JsonSerializerOptions { WriteIndented = true });
                var dir = Path.GetDirectoryName(_healthFilePath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                File.WriteAllText(_healthFilePath, json);
            }
            catch
            {
                // File write error
            }
        }
    }
}
