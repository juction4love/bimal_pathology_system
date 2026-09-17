using System.Text.RegularExpressions;

namespace BimalPathology.SmsGateway
{
    public static class Redaction
    {
        private static readonly Regex MobileRegex = new(@"(9[78]\d{8})", RegexOptions.Compiled);

        public static string RedactMobile(string text)
        {
            if (string.IsNullOrEmpty(text)) return string.Empty;
            return MobileRegex.Replace(text, "[mobile-redacted]");
        }

        public static string SafeProviderMessage(string rawMessage)
        {
            if (string.IsNullOrEmpty(rawMessage)) return string.Empty;
            return RedactMobile(rawMessage);
        }
    }
}
