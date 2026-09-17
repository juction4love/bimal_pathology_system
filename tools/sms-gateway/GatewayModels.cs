using System;

namespace BimalPathology.SmsGateway
{
    public sealed class GatewayOptions
    {
        public TimeSpan PollInterval { get; set; } = TimeSpan.FromSeconds(20);
        public int LeaseSeconds { get; set; } = 300;
        public Guid WorkerId { get; set; } = Guid.NewGuid();
    }

    public sealed class GatewayHealthStatus
    {
        public DateTimeOffset? last_successful_send_at { get; set; }
        public int queue_error_count { get; set; }
        public DateTimeOffset? last_heartbeat_at { get; set; }
        public string worker_status { get; set; } = "Running";
    }
}
