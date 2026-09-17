using Microsoft.Win32;

namespace BimalPathology.PublicIpAssistant;

public static class StartupRegistration
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "BimalPathologyPublicIpAssistant";

    public static bool TryInstall(out string? error)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey, true);
            key.SetValue(ValueName, $"\"{Environment.ProcessPath}\" --startup", RegistryValueKind.String);
            error = null; return true;
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or System.Security.SecurityException)
        {
            error = "Windows did not permit startup registration for this user."; return false;
        }
    }

    public static void Remove()
    {
        try { using var key = Registry.CurrentUser.OpenSubKey(RunKey, true); key?.DeleteValue(ValueName, false); }
        catch (Exception exception) when (exception is UnauthorizedAccessException or System.Security.SecurityException) { }
    }
}
