# Temporary URL-free SMS change

Prepared locally; not deployed. No live database or Sparrow requests were made.

## Complete sender/construction inventory

| Category/path | Finding and treatment |
| --- | --- |
| Report ready: create_public_report_token (00084) | Legacy immediate notification appended p_public_url_base. Migration 00122 replaces only SMS text. Secure token validation and report_secure_link_presentations remain unchanged. |
| Background report ready: complete_report_pdf_artifact_v2 (00092; prior 00083) | PDF completion appended intent.public_url. Replaced with neutral message; PDF readiness, delivery intents and queue idempotency unchanged. |
| Updated reports: notify_updated_order_reports (00092) | Appended i.public_url. Replaced with the same neutral message; entitlement and generation tracking unchanged. |
| Initial bill payment: create_patient_bill_and_order (00043) | Plain payment amount and Lab No; no link. Catalogue/package wrappers delegate into this path. |
| Additional payment: receive_bill_payment (00043) | Plain payment receipt; no link. |
| Legacy booking: queue_bill_sms (00006) | Plain booking/bill notification; execution revoked from application roles by 00028/00051. No separate appointment SMS path found. |
| Manual resend: retry_sms_delivery (00075), SmsDeliveryPage.tsx | Reuses queued body; both sender guards apply, including historical URL-bearing rows. No manual free-text/template composer found. |
| TypeScript Windows worker | GatewayWorker -> SparrowProvider -> Sparrow HTTP POST. Central content check before provider fence plus provider-level defense. |
| Legacy C# Windows worker | SmsGatewayWorker -> SparrowClient -> Sparrow HTTP POST. Same content policy before HTTP; existing completion RPC persists permanent failure and audit. |
| Supabase dispatch-sms and Cloudflare sms-dispatcher | Retired HTTP 410 non-sending tombstones; unchanged. Deferred cloud coordination SQL has no separate provider transport. |
| Sample status, standalone appointments, OTP/auth | No SMS construction/transmission path found. Auth is not a Sparrow SMS OTP flow. |

Earlier report URL templates also occur in historical migrations 00006, 00028, 00039, 00041, 00046 and 00083. These are superseded; historical migrations are retained rather than rewritten. Effective templates are replaced by forward migration 00122. Provider endpoint URLs and operational provisioning URLs are not SMS text.

## Policy

All new report-ready SMS use:

Bimal Pathology: Your laboratory report is ready. Please collect it from the lab or contact 056-593288. Thank you.

No patient SMS language preference exists in the current schema/application; English remains the default. The guard also permits the supplied neutral Nepali notification. No result, diagnosis, patient name or report identifier is interpolated into report-ready SMS.

SmsContentSafety.ts normalizes Unicode (NFKC), removes zero-width characters for detection, and rejects URI schemes, http/https, www, application-domain strings, generic bare domains, IPv4 addresses, and /r/ or /o/ token paths. The C# sender mirrors this policy. Detection is deliberately conservative: domain-shaped text is rejected even if intended as prose.

The TypeScript worker calls reject_sms_gateway_v2_local_validation with SMS_URL_BLOCKED before marking a provider call started. Migration 00122 adds this code to the existing allowlist: DeadLetter plus SMS_FAILED audit, with no body/token in logs. SparrowProvider independently rejects direct calls with permanent_failure. The legacy sender returns a non-retryable SMS_URL_BLOCKED result to its existing queue completion/audit path.

Historical queued messages are not rewritten: URL-bearing pending/retried messages fail safely. Historical records can still supply verified secure-link recovery. Printed QR, public report resolution/verification, token hash/expiry checks, link presentations, delivery intents and web routes are unchanged. No table, column, constraint or permission changes are introduced; the migration replaces four existing function bodies.

## Tests and validation

- scripts/verify-url-free-sms.test.mjs: effective report templates, exact function-body comparison proving only SMS text changes, retained public URL/QR consumers, rejection RPC allowlist/audit contract.
- SparrowProvider.test.ts: blocked URL/domain/token/Unicode variants never call transport; English, Nepali and payment messages reach transport unchanged.
- WorkerSafety.test.ts: URL queue rows rejected and logged before provider fence; existing normal worker delivery tests retained.
- tools/sms-safety-tests: executable C# transport tests, no live HTTP.
- Three older regression scripts now assert the current URL-free policy instead of the superseded URL-bearing SMS contract.

Database verification is source-contract verification, not an executed PostgreSQL integration test. Production activation requires the forward migration and the relevant Windows gateway update; a frontend build alone cannot change deployed SMS behavior. Apply through the normal reviewed release process; no automatic deployment was performed.
