using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace BimalPathology.SmsGateway
{
    public sealed class SparrowClient
    {
        private readonly HttpClient _httpClient;
        private readonly string _token;
        private readonly string _fromIdentity;
        private const string SparrowEndpoint = "https://api.sparrowsms.com/v2/sms/";

        // 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1010, 1011, 1012, 1013
        private static readonly HashSet<int> PermanentErrorCodes = new()
        {
            1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1010, 1011, 1012, 1013
        };

        public SparrowClient(HttpClient httpClient, string token, string fromIdentity)
        {
            _httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
            _token = token ?? throw new ArgumentNullException(nameof(token));
            _fromIdentity = fromIdentity ?? throw new ArgumentNullException(nameof(fromIdentity));
        }

        public async Task<SparrowSendResult> SendSmsAsync(string recipientPhone, string messageBody, CancellationToken ct = default)
        {
            var form = new List<KeyValuePair<string, string>>
            {
                new("token", _token),
                new("from", _fromIdentity),
                new("to", recipientPhone),
                new("text", messageBody)
            };

            using var content = new FormUrlEncodedContent(form);
            HttpResponseMessage response;
            try
            {
                response = await _httpClient.PostAsync(SparrowEndpoint, content, ct);
            }
            catch (HttpRequestException ex)
            {
                return new SparrowSendResult(false, null, null, null, ex.Message, "HttpRequestException", true);
            }
            catch (TaskCanceledException ex) when (!ct.IsCancellationRequested)
            {
                return new SparrowSendResult(false, null, null, null, "Request timed out", "TimeoutException", true);
            }
            catch (Exception ex)
            {
                return new SparrowSendResult(false, null, null, null, ex.Message, "NetworkOrTransportError", true);
            }

            var httpStatus = (int)response.StatusCode;
            var responseBody = await response.Content.ReadAsStringAsync(ct);

            if (httpStatus is 408 or 429 || httpStatus >= 500)
            {
                return new SparrowSendResult(false, null, responseBody, httpStatus.ToString(), "Transient HTTP error from SMS provider", "TransientProviderError", true);
            }

            if (httpStatus == 200)
            {
                try
                {
                    var parsed = JsonSerializer.Deserialize<SparrowSuccessPayload>(responseBody);
                    if (parsed != null && parsed.ResponseCode == 200 && parsed.Count >= 1)
                    {
                        return new SparrowSendResult(true, parsed.Response, responseBody, parsed.ResponseCode.ToString(), null, null, false);
                    }
                }
                catch
                {
                    // JSON parsing error
                }
            }

            return new SparrowSendResult(false, null, responseBody, httpStatus.ToString(), "Non-retryable SMS provider rejection", "PermanentProviderRejection", false);
        }
    }

    public sealed class SparrowSuccessPayload
    {
        public int Count { get; set; }
        public string? Response { get; set; }
        public int ResponseCode { get; set; }
    }

    public record SparrowSendResult(
        bool Accepted,
        string? ProviderMessageId,
        string? RawResponse,
        string? ResponseCode,
        string? ErrorMessage,
        string? ErrorClassification,
        bool IsRetryable
    );
}
