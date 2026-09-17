using System.Text.Json.Serialization;

namespace BimalPathology.PublicIpAssistant;

public sealed record AssistantState(
    [property: JsonPropertyName("last_confirmed_public_ip")] string? LastConfirmedPublicIp,
    [property: JsonPropertyName("detected_public_ip")] string? DetectedPublicIp,
    [property: JsonPropertyName("detected_at")] DateTimeOffset? DetectedAt,
    [property: JsonPropertyName("confirmed_at")] DateTimeOffset? ConfirmedAt);

