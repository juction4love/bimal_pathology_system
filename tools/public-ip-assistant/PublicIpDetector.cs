using System.Net;
using System.Net.Sockets;

namespace BimalPathology.PublicIpAssistant;

public sealed class PublicIpDetector
{
    private static readonly Uri[] Providers =
    [
        new("https://api.ipify.org"),
        new("https://ipv4.icanhazip.com")
    ];
    private readonly HttpClient _client;

    public PublicIpDetector(HttpMessageHandler? handler = null)
    {
        _client = handler is null ? new HttpClient() : new HttpClient(handler);
        _client.Timeout = TimeSpan.FromSeconds(5);
        _client.DefaultRequestHeaders.UserAgent.ParseAdd("BimalPathology-PublicIpAssistant/1.0");
    }

    public async Task<string> DetectAsync(CancellationToken cancellationToken = default)
    {
        var failures = new List<string>();
        foreach (var provider in Providers)
        {
            for (var attempt = 1; attempt <= 2; attempt++)
            {
                try
                {
                    var response = await _client.GetStringAsync(provider, cancellationToken);
                    if (TryNormalizePublicIpv4(response, out var address)) return address!;
                    failures.Add($"{provider.Host}: invalid response");
                    break;
                }
                catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException)
                {
                    failures.Add($"{provider.Host}: attempt {attempt} failed");
                }
            }
        }
        throw new PublicIpDetectionException("Unable to detect a valid public IPv4 address. Check the internet connection and try again.", failures);
    }

    public static bool TryNormalizePublicIpv4(string? value, out string? normalized)
    {
        normalized = null;
        if (!IPAddress.TryParse(value?.Trim(), out var ip) || ip.AddressFamily != AddressFamily.InterNetwork) return false;
        var b = ip.GetAddressBytes();
        var invalid = b[0] is 0 or 10 or 127 || b[0] >= 224 ||
            (b[0] == 169 && b[1] == 254) || (b[0] == 172 && b[1] is >= 16 and <= 31) ||
            (b[0] == 192 && b[1] == 168) || (b[0] == 100 && b[1] is >= 64 and <= 127) ||
            (b[0] == 198 && b[1] is 18 or 19);
        if (invalid) return false;
        normalized = ip.ToString();
        return true;
    }
}

public sealed class PublicIpDetectionException(string message, IReadOnlyList<string> failures) : Exception(message)
{
    public IReadOnlyList<string> Failures { get; } = failures;
}

