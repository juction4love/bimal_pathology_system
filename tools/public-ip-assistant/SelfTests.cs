namespace BimalPathology.PublicIpAssistant;

public static class SelfTests
{
    public static async Task<int> RunAsync()
    {
        var root = Path.Combine(Path.GetTempPath(), "BimalPathology-IpAssistant-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root); var path = Path.Combine(root, "state.json");
        var now = new DateTimeOffset(2026, 8, 28, 9, 0, 0, TimeSpan.FromHours(5.75));
        var store = new StateStore(path); var engine = new AssistantEngine(store, () => now); var failed = 0;
        void Check(string name, bool pass) { Console.WriteLine($"{(pass ? "PASS" : "FAIL")} {name}"); if (!pass) failed++; }
        try
        {
            var first = await engine.CheckAsync(() => Task.FromResult("8.8.8.8")); Check("first run prompts", first.Outcome == DetectionOutcome.Changed && store.Load().LastConfirmedPublicIp is null);
            engine.Confirm("8.8.8.8"); Check("confirmation persistence", store.Load().LastConfirmedPublicIp == "8.8.8.8" && store.Load().ConfirmedAt == now);
            var restarted = new AssistantEngine(new StateStore(path), () => now.AddMinutes(1)); var same = await restarted.CheckAsync(() => Task.FromResult("8.8.8.8")); Check("same IP exits silently", same.Outcome == DetectionOutcome.Unchanged);
            var changed = await restarted.CheckAsync(() => Task.FromResult("1.1.1.1")); Check("changed IP prompts without confirming", changed.Outcome == DetectionOutcome.Changed && store.Load().LastConfirmedPublicIp == "8.8.8.8");
            var beforeFailure = File.ReadAllText(path); try { await restarted.CheckAsync(() => throw new HttpRequestException("offline")); } catch (HttpRequestException) { } Check("internet unavailable preserves state", File.ReadAllText(path) == beforeFailure);
            try { await restarted.CheckAsync(() => Task.FromResult("not-an-ip")); Check("invalid response rejected", false); } catch (PublicIpDetectionException) { Check("invalid response rejected", store.Load().LastConfirmedPublicIp == "8.8.8.8"); }
            var handler = new FallbackHandler(); var detector = new PublicIpDetector(handler); var fallback = await detector.DetectAsync(); Check("primary unavailable fallback succeeds", fallback == "9.9.9.9" && handler.Calls >= 3);
            var diskFields = File.ReadAllText(path); Check("state contains only approved fields", diskFields.Contains("last_confirmed_public_ip") && diskFields.Contains("detected_public_ip") && diskFields.Contains("detected_at") && diskFields.Contains("confirmed_at") && !diskFields.Contains("password", StringComparison.OrdinalIgnoreCase));
            Check("Windows restart reloads confirmation", new StateStore(path).Load().LastConfirmedPublicIp == "8.8.8.8");
        }
        finally { Directory.Delete(root, true); }
        Console.WriteLine($"Public IP Assistant tests: {9 - failed} passed, {failed} failed"); return failed == 0 ? 0 : 1;
    }

    private sealed class FallbackHandler : HttpMessageHandler
    {
        public int Calls { get; private set; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            if (request.RequestUri?.Host == "api.ipify.org") throw new HttpRequestException("primary unavailable");
            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK) { Content = new StringContent("9.9.9.9\n") });
        }
    }
}

