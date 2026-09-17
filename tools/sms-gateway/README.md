# Bimal Pathology SMS Gateway

Transactional SMS dispatch worker for Bimal Pathology Cloud LIS.

## Architecture

- **Supabase RPCs**: Claims SMS queue items atomically using `claim_next_sms_gateway_item` and marks completion with `complete_sms_gateway_item`.
- **Sparrow SMS Transport**: Sends transactional SMS via Sparrow SMS API.
- **Reliability & Idempotency Notes**:
  - Sparrow does not accept an idempotency key directly on their HTTP API.
  - If an HTTP response is lost during communication, the queue item transitions safely through quarantined statuses to prevent duplicate arbitrary re-sends.
