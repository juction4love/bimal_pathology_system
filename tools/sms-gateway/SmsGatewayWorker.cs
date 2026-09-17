using System;
using System.Threading;
using System.Threading.Tasks;

namespace BimalPathology.SmsGateway
{
    public sealed class SmsGatewayWorker
    {
        private readonly SupabaseQueueClient _queueClient;
        private readonly SparrowClient _sparrowClient;
        private readonly HealthStore _healthStore;
        private readonly JsonFileLogger _logger;
        private readonly GatewayOptions _options;

        public SmsGatewayWorker(
            SupabaseQueueClient queueClient,
            SparrowClient sparrowClient,
            HealthStore healthStore,
            JsonFileLogger logger,
            GatewayOptions? options = null)
        {
            _queueClient = queueClient ?? throw new ArgumentNullException(nameof(queueClient));
            _sparrowClient = sparrowClient ?? throw new ArgumentNullException(nameof(sparrowClient));
            _healthStore = healthStore ?? throw new ArgumentNullException(nameof(healthStore));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _options = options ?? new GatewayOptions();
        }

        public async Task RunAsync(CancellationToken ct)
        {
            var options = _options;
            _logger.LogInfo("SMS Gateway worker started.");

            for (; !ct.IsCancellationRequested;)
            {
                try
                {
                    var item = await _queueClient.ClaimNextAsync(options.WorkerId, options.LeaseSeconds, ct);
                    if (item != null)
                    {
                        var marked = await _queueClient.MarkProviderCallStartedAsync(item.id, options.WorkerId, ct);
                        if (marked)
                        {
                            var result = await _sparrowClient.SendSmsAsync(item.recipient_phone, item.message_body, ct);
                            await _queueClient.CompleteItemAsync(
                                item.id,
                                options.WorkerId,
                                result.Accepted,
                                result.ProviderMessageId,
                                null,
                                result.ResponseCode,
                                result.ErrorMessage,
                                result.ErrorClassification,
                                result.IsRetryable,
                                ct
                            );

                            if (result.Accepted)
                            {
                                _healthStore.RecordSuccess();
                            }
                            else
                            {
                                _healthStore.RecordError();
                            }
                        }
                    }
                }
                catch (OperationCanceledException) when (ct.IsCancellationRequested)
                {
                    break;
                }
                catch (Exception ex)
                {
                    _healthStore.RecordError();
                    _logger.LogError("Error in SMS processing cycle", ex);
                }

                await Task.Delay(options.PollInterval, ct);
            }

            _logger.LogInfo("SMS Gateway worker stopped gracefully.");
        }
    }
}
