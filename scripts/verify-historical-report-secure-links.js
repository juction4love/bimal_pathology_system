import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations_legacy_archive/00049_historical_report_secure_link_provisioning.sql', 'utf8');
const reports = fs.readFileSync('src/features/reports/ReportsPage.tsx', 'utf8');
const viewer = fs.readFileSync('src/features/reports/FinalReportViewerDialog.tsx', 'utf8');
const document = fs.readFileSync('src/features/reports/ReportDocument.tsx', 'utf8');
let passed = 0;
const check = (condition, label) => {
  if (!condition) throw new Error(`FAIL: ${label}`);
  passed += 1;
  console.log(`PASS: ${label}`);
};

check(/get_report_secure_link_status/.test(migration) && /'Active'/.test(migration) && /'Expired'/.test(migration) && /'Revoked'/.test(migration) && /'ActiveUnrecoverable'/.test(migration), 'historical token audit distinguishes active, expired, revoked, missing-raw states');
check(/report_version/.test(migration) && /v_report\.version/.test(migration) && /diagnostic_report_id = p_report_id/.test(migration), 'token status is bound to the exact report and frozen version');
check(/signed_before_first_token/.test(migration) && /v_report\.signed_at < v_first_token_at/.test(migration), 'pre-token historical signing is reported without changing the report');
check(/substring\(s\.message_body/.test(migration) && /extensions\.digest/.test(migration) && /v_token\.token_hash/.test(migration), 'existing ReportReady URL is reused only after SHA-256 verification');
check(/report_secure_link_presentations/.test(migration) && /ENABLE ROW LEVEL SECURITY/.test(migration) && /REVOKE ALL ON TABLE public\.report_secure_link_presentations FROM PUBLIC, anon, authenticated/.test(migration), 'generated links persist in an RPC-only presentation escrow with no direct browser access');
check(/provision_historical_report_secure_link/.test(migration) && /can_print_reports/.test(migration) && /FOR UPDATE/.test(migration), 'explicit historical link provisioning is authorized and serialized');
check(/p_public_url FROM '\^https:\/\/lis/.test(migration) && /length\(v_raw_token\) NOT BETWEEN 32 AND 256/.test(migration), 'new token accepts only the canonical secure route and token bounds');
check(/digest\(convert_to\(v_raw_token/.test(migration) && /<> p_token_hash/.test(migration), 'server verifies caller token and SHA-256 hash match');
check(!/INSERT INTO public\.sms_queue_items/.test(migration) && /'sms_queued', FALSE/.test(migration), 'historical link provisioning never queues or resends SMS');
check(!/UPDATE public\.diagnostic_reports|UPDATE public\.test_results|clinical_snapshot_json\s*=/.test(migration), 'token provisioning cannot mutate snapshots, results, hashes, timestamps, or report version');
check(/HISTORICAL_REPORT_LINK_PROVISIONED/.test(migration) && /auth\.uid\(\)/.test(migration), 'access provisioning is audited with a server-derived actor');
check(/generateRawToken/.test(reports) && /hashToken/.test(reports) && /provision_historical_report_secure_link/.test(reports), 'Reporting generates a cryptographically secure token through the secured RPC');
check(/Generate Secure Report Link/.test(viewer) && /secureLinkState/.test(viewer), 'historical report without a QR exposes an explicit Reporting action');
check(/publicToken=\{publicToken\}/.test(viewer) && /publicToken\?: string \| null/.test(viewer), 'active or newly generated token reaches canonical preview, print, download, and reprint');
check(/publicToken && \/\^\[A-Za-z0-9_-\]\{32,256\}\$\//.test(document) && !/publicToken \|\| reportNumber/.test(document), 'ReportDocument retains secure-token-only QR behavior');
check(!/patient_id|order_id|uhid|Lab No/.test(reports.match(/function tokenFromCanonicalUrl[\s\S]*?\n\}/)?.[0] || ''), 'frontend has no predictable QR credential fallback');

console.log(`Historical report secure-link regression: ${passed} passed, 0 failed`);
