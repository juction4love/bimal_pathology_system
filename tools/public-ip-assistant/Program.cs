namespace BimalPathology.PublicIpAssistant;

internal static class Program
{
    [STAThread]
    private static async Task<int> Main(string[] args)
    {
        if (args.Contains("--self-test")) { NativeMethods.AllocConsole(); return await SelfTests.RunAsync(); }
        if (args.Contains("--remove-startup")) { StartupRegistration.Remove(); return 0; }
        if (args.Contains("--install-startup")) return StartupRegistration.TryInstall(out _) ? 0 : 4;
        StartupRegistration.TryInstall(out _);
        using var singleInstance = new Mutex(true, "Local\\BimalPathology.PublicIpAssistant", out var ownsMutex);
        if (!ownsMutex) return 0;
        ApplicationConfiguration.Initialize();
        var store = new StateStore(); var engine = new AssistantEngine(store); var detector = new PublicIpDetector();
        try
        {
            var result = await engine.CheckAsync(() => detector.DetectAsync());
            if (result.Outcome == DetectionOutcome.Unchanged) return 0;
            using var dialog = new IpChangedDialog(result.PublicIp);
            if (dialog.ShowDialog() == DialogResult.OK && dialog.Confirmed) engine.Confirm(result.PublicIp);
            return 0;
        }
        catch (PublicIpDetectionException exception)
        {
            MessageBox.Show(exception.Message + "\n\nThe previously confirmed IP was not changed.", "Public IP detection warning", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 2;
        }
        catch (Exception)
        {
            MessageBox.Show("The Public IP Assistant could not complete its startup check. The previously confirmed IP was not changed.", "Public IP Assistant", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 3;
        }
    }
}

internal static class NativeMethods
{
    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    internal static extern bool AllocConsole();
}
