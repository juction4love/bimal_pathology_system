using System;
using System.Threading;
using System.Threading.Tasks;

namespace BimalPathology.SmsGateway
{
    public static class Program
    {
        public static async Task<int> Main(string[] args)
        {
            if (args.Length > 0 && args[0] == "--configure-gui")
            {
                InstallerConfigurator.ShowGui();
                return 0;
            }

            if (args.Length > 0 && args[0] == "--preflight")
            {
                var secretsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BimalPathology", "SmsGateway", "gateway.secrets.bin");
                var sec = ProtectedSettings.LoadProtectedSecrets(secretsPath);
                return await GatewayPreflight.RunPreflightAsync(sec.SupabaseUrl, sec.ServiceRoleKey);
            }

            var cts = new CancellationTokenSource();
            // Normal service execution
            return 0;
        }
    }
}
