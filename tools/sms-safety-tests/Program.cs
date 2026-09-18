using BimalPathology.SmsGateway;
using System.Net;

var transport = new RecordingTransport();
var client = new SparrowClient(new HttpClient(transport), "test", "test");
foreach (var body in new[] { "http://example.com", "HTTPS://example.com", "www.example.com", "lis.bimalpathology.com.np", "dashboard.bimalpathology.com.np", "bit.ly/secret", "/r/secret", "/o/secret", "192.168.1.1", "ｗｗｗ.example.com", "https:\u200B//example.com" })
{
    var result = await client.SendSmsAsync("9800000000", body);
    if (result.Accepted || result.IsRetryable || result.ErrorClassification != "SMS_URL_BLOCKED" || transport.Calls != 0)
        throw new Exception("Unsafe SMS was not rejected before transport");
}
await client.SendSmsAsync("9800000000", "Bimal Pathology: Your laboratory report is ready. Please collect it from the lab or contact 056-593288. Thank you.");
if (transport.Calls != 1 || !transport.Body.Contains("056-593288")) throw new Exception("Normal SMS did not reach transport");
Console.WriteLine("PASS: legacy Sparrow URL rejection and normal SMS transport (12 cases)");

sealed class RecordingTransport : HttpMessageHandler
{
    public int Calls;
    public string Body = "";
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Calls++;
        Body = await request.Content!.ReadAsStringAsync(cancellationToken);
        return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{}") };
    }
}
