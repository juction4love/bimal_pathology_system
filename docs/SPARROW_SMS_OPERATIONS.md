# Sparrow SMS production transport

The only production SMS transport is:

`Cloud LIS -> Supabase sms_queue_items -> BimalPathologySMSGateway (Windows) -> Sparrow`

Billing and report issuance enqueue SMS asynchronously and remain successful when the provider is unavailable. Database idempotency keys, bounded retry, `DeadLetter`, Admin delivery visibility, and service-role-only leases are authoritative. Sparrow credentials exist only in the Windows Gateway's machine-scoped DPAPI configuration.

## Dynamic IP policy

Sparrow stated that dynamic-IP support was configured, and its dashboard shows the token Allowed IP value as `0.0.0.0/0`. Controlled live requests from the Supabase Edge Function nevertheless returned HTTP `403`, Sparrow `response_code` `1001`, and `Invalid IP Address` while the reported outbound IP changed between requests.

This mismatch is a provider-side configuration issue. The application must not attempt to work around it by hard-coding rotating egress addresses, modifying the provider allowlist, scraping the provider dashboard, exposing credentials, or introducing a PC relay, VPS, proxy, or paid service.

The Windows Gateway calls Sparrow. A Sparrow `1001 Invalid IP Address` response is a permanent provider-configuration failure and moves the item to `DeadLetter` without automatic retry. The retired Edge and Cloudflare surfaces return HTTP 410 and cannot access the queue or provider.
