using System;
using System.IO;
using System.Text.Json;

namespace BimalPathology.SmsGateway
{
    public sealed class JsonFileLogger
    {
        private readonly string _logFilePath;
        private readonly object _lock = new();

        public JsonFileLogger(string logFilePath)
        {
            _logFilePath = logFilePath;
        }

        public void LogInfo(string message, object? context = null)
        {
            WriteLog("INFO", Redaction.SafeProviderMessage(message), context);
        }

        public void LogWarning(string message, object? context = null)
        {
            WriteLog("WARN", Redaction.SafeProviderMessage(message), context);
        }

        public void LogError(string message, Exception? ex = null, object? context = null)
        {
            var msg = Redaction.SafeProviderMessage(message);
            if (ex != null)
            {
                msg += $" | Exception: {ex.Message}";
            }
            WriteLog("ERROR", msg, context);
        }

        private void WriteLog(string level, string message, object? context)
        {
            try
            {
                lock (_lock)
                {
                    var entry = new
                    {
                        timestamp = DateTimeOffset.UtcNow.ToString("o"),
                        level,
                        message,
                        context
                    };
                    var line = JsonSerializer.Serialize(entry);
                    var dir = Path.GetDirectoryName(_logFilePath);
                    if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                    {
                        Directory.CreateDirectory(dir);
                    }
                    File.AppendAllLines(_logFilePath, new[] { line });
                }
            }
            catch
            {
                // Failed to write log
            }
        }
    }
}
