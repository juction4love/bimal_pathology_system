namespace BimalPathology.PublicIpAssistant;

public enum DetectionOutcome { Unchanged, Changed }
public sealed record DetectionResult(DetectionOutcome Outcome, string PublicIp, AssistantState State);

public sealed class AssistantEngine(StateStore store, Func<DateTimeOffset>? clock = null)
{
    private readonly Func<DateTimeOffset> _clock = clock ?? (() => DateTimeOffset.Now);

    public async Task<DetectionResult> CheckAsync(Func<Task<string>> detect)
    {
        var previous = store.Load();
        var detected = await detect();
        if (!PublicIpDetector.TryNormalizePublicIpv4(detected, out var normalized))
            throw new PublicIpDetectionException("The public-IP service returned an invalid IPv4 address.", ["invalid response"]);
        var updated = previous with { DetectedPublicIp = normalized, DetectedAt = _clock() };
        store.Save(updated);
        return new(previous.LastConfirmedPublicIp == normalized ? DetectionOutcome.Unchanged : DetectionOutcome.Changed, normalized!, updated);
    }

    public AssistantState Confirm(string ip)
    {
        if (!PublicIpDetector.TryNormalizePublicIpv4(ip, out var normalized)) throw new ArgumentException("Invalid public IPv4.", nameof(ip));
        var state = store.Load();
        if (state.DetectedPublicIp != normalized) throw new InvalidOperationException("Only the currently detected IP can be confirmed.");
        var confirmed = state with { LastConfirmedPublicIp = normalized, ConfirmedAt = _clock() };
        store.Save(confirmed);
        return confirmed;
    }
}
