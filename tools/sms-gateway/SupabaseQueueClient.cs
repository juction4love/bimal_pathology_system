using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace BimalPathology.SmsGateway
{
    public sealed class SupabaseQueueClient
    {
        private readonly HttpClient _httpClient;
        private readonly string _supabaseUrl;
        private readonly string _serviceRoleKey;

        public SupabaseQueueClient(HttpClient httpClient, string supabaseUrl, string serviceRoleKey)
        {
            _httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
            _supabaseUrl = supabaseUrl ?? throw new ArgumentNullException(nameof(supabaseUrl));
            _serviceRoleKey = serviceRoleKey ?? throw new ArgumentNullException(nameof(serviceRoleKey));
        }

        public async Task<SmsQueueItem?> ClaimNextAsync(Guid workerId, int leaseSeconds = 300, CancellationToken ct = default)
        {
            var rpcUrl = $"{_supabaseUrl}/rest/v1/rpc/claim_next_sms_gateway_item";
            var payload = JsonSerializer.Serialize(new { p_worker_id = workerId, p_lease_seconds = leaseSeconds });
            using var request = new HttpRequestMessage(HttpMethod.Post, rpcUrl)
            {
                Content = new StringContent(payload, Encoding.UTF8, "application/json")
            };
            request.Headers.Add("apikey", _serviceRoleKey);
            request.Headers.Add("Authorization", $"Bearer {_serviceRoleKey}");

            var response = await _httpClient.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode) return null;

            var content = await response.Content.ReadAsStringAsync(ct);
            var items = JsonSerializer.Deserialize<SmsQueueItem[]>(content);
            return items != null && items.Length > 0 ? items[0] : null;
        }

        public async Task<bool> MarkProviderCallStartedAsync(Guid smsId, Guid workerId, CancellationToken ct = default)
        {
            var rpcUrl = $"{_supabaseUrl}/rest/v1/rpc/mark_sms_provider_call_started";
            var payload = JsonSerializer.Serialize(new { p_sms_id = smsId, p_worker_id = workerId });
            using var request = new HttpRequestMessage(HttpMethod.Post, rpcUrl)
            {
                Content = new StringContent(payload, Encoding.UTF8, "application/json")
            };
            request.Headers.Add("apikey", _serviceRoleKey);
            request.Headers.Add("Authorization", $"Bearer {_serviceRoleKey}");

            var response = await _httpClient.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode) return false;

            var content = await response.Content.ReadAsStringAsync(ct);
            return bool.TryParse(content, out var result) && result;
        }

        public async Task<bool> CompleteItemAsync(
            Guid smsId,
            Guid workerId,
            bool accepted,
            string? providerMsgId = null,
            JsonElement? providerResponse = null,
            string? providerResponseCode = null,
            string? errorMsg = null,
            string? errorClassification = null,
            bool retryable = false,
            CancellationToken ct = default)
        {
            var rpcUrl = $"{_supabaseUrl}/rest/v1/rpc/complete_sms_gateway_item";
            var payload = JsonSerializer.Serialize(new
            {
                p_sms_id = smsId,
                p_worker_id = workerId,
                p_accepted = accepted,
                p_provider_msg_id = providerMsgId,
                p_provider_response = providerResponse,
                p_provider_response_code = providerResponseCode,
                p_error_msg = errorMsg,
                p_error_classification = errorClassification,
                p_retryable = retryable
            });

            using var request = new HttpRequestMessage(HttpMethod.Post, rpcUrl)
            {
                Content = new StringContent(payload, Encoding.UTF8, "application/json")
            };
            request.Headers.Add("apikey", _serviceRoleKey);
            request.Headers.Add("Authorization", $"Bearer {_serviceRoleKey}");

            var response = await _httpClient.SendAsync(request, ct);
            return response.IsSuccessStatusCode;
        }
    }

    public sealed class SmsQueueItem
    {
        public Guid id { get; set; }
        public string sms_type { get; set; } = string.Empty;
        public string recipient_phone { get; set; } = string.Empty;
        public string message_body { get; set; } = string.Empty;
        public int retry_count { get; set; }
        public int max_attempts { get; set; }
        public string idempotency_key { get; set; } = string.Empty;
        public Guid? lease_owner { get; set; }
    }
}
