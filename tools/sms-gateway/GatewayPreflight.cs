using System;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace BimalPathology.SmsGateway
{
    public static class GatewayPreflight
    {
        public static async Task<int> RunPreflightAsync(string supabaseUrl, string serviceRoleKey, CancellationToken ct = default)
        {
            using var client = new HttpClient();
            var checkUrl = $"{supabaseUrl}/rest/v1/sms_queue_items?select=id&limit=0";
            using var request = new HttpRequestMessage(HttpMethod.Get, checkUrl);
            request.Headers.Add("apikey", serviceRoleKey);
            request.Headers.Add("Authorization", $"Bearer {serviceRoleKey}");

            try
            {
                var response = await client.SendAsync(request, ct);
                if (response.StatusCode == HttpStatusCode.OK)
                {
                    return 0; // Success
                }
                if (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden)
                {
                    return 40; // Authorization failure
                }
                return (int)response.StatusCode;
            }
            catch
            {
                return 1;
            }
        }
    }
}
