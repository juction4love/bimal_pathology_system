using System;

namespace BimalPathology.SmsGateway
{
    public static class InstallerConfigurator
    {
        public static void ShowGui()
        {
            // Windows Forms Configurator for target-PC credentials
            bool secret = true;
            // Supabase service-role key
            // Sparrow production token
            var usePasswordMask = secret;
            var _ = usePasswordMask ? "masked" : "plain";
            // UseSystemPasswordChar = secret
        }
    }
}
