import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sqlScript = `
WITH time_calc AS (
    SELECT
        now() AS utc_now,
        now() AT TIME ZONE 'Asia/Kathmandu' AS nepal_now,
        (date_trunc('day', now() AT TIME ZONE 'Asia/Kathmandu')) AT TIME ZONE 'Asia/Kathmandu' AS nepal_today_start,
        date_trunc('day', now()) AS utc_today_start
),
kpis AS (
    SELECT
        (SELECT count(*)::int FROM public.patients WHERE created_at >= (SELECT nepal_today_start FROM time_calc)) AS patients_today_nepal,
        (SELECT count(*)::int FROM public.patients WHERE created_at >= (SELECT utc_today_start FROM time_calc)) AS patients_today_utc,
        (SELECT count(*)::int FROM public.patients) AS patients_total,

        (SELECT count(*)::int FROM public.bills WHERE created_at >= (SELECT nepal_today_start FROM time_calc)) AS bills_today_nepal,
        (SELECT count(*)::int FROM public.bills WHERE created_at >= (SELECT utc_today_start FROM time_calc)) AS bills_today_utc,
        (SELECT count(*)::int FROM public.bills) AS bills_total,

        (SELECT COALESCE(sum(amount_paisa), 0)::bigint FROM public.payment_transactions WHERE created_at >= (SELECT nepal_today_start FROM time_calc)) AS collection_today_nepal_paisa,
        (SELECT COALESCE(sum(amount_paisa), 0)::bigint FROM public.payment_transactions WHERE created_at >= (SELECT utc_today_start FROM time_calc)) AS collection_today_utc_paisa,

        (SELECT COALESCE(sum(due_amount_paisa), 0)::bigint FROM public.bills WHERE due_amount_paisa > 0) AS outstanding_due_paisa,

        (SELECT count(*)::int FROM public.samples WHERE status = 'Pending') AS samples_pending,
        (SELECT count(*)::int FROM public.samples WHERE status = 'Received') AS samples_received,
        (SELECT count(*)::int FROM public.samples WHERE status = 'Rejected') AS samples_rejected,
        (SELECT count(*)::int FROM public.samples) AS samples_total,

        (SELECT count(*)::int FROM public.clinical_order_items WHERE status IN ('SampleReceived', 'ResultDrafted')) AS results_pending_total,
        (SELECT count(*)::int FROM public.clinical_order_items WHERE status = 'SampleReceived') AS result_entry_pending,
        (SELECT count(*)::int FROM public.clinical_order_items WHERE status = 'ResultDrafted') AS result_drafted,
        (SELECT count(*)::int FROM public.clinical_order_items WHERE status = 'Verified') AS order_items_verified,

        (SELECT count(DISTINCT order_item_id)::int FROM public.test_results WHERE status = 'SubmittedForVerification') AS awaiting_verification_items,

        (SELECT count(*)::int FROM public.diagnostic_reports WHERE status IN ('SignedOff', 'Amended') AND created_at >= (SELECT nepal_today_start FROM time_calc)) AS reports_signed_today_nepal,
        (SELECT count(*)::int FROM public.diagnostic_reports WHERE status IN ('SignedOff', 'Amended')) AS reports_signed_all_time,
        (SELECT count(*)::int FROM public.diagnostic_reports WHERE status = 'Draft') AS reports_draft,

        (SELECT count(*)::int FROM public.test_results WHERE is_critical = TRUE AND critical_acknowledged = FALSE) AS critical_unacknowledged
),
target_tests AS (
    SELECT json_agg(json_build_object(
        'id', t.id,
        'code', t.code,
        'name', t.name,
        'is_active', t.is_active,
        'lifecycle_status', t.lifecycle_status,
        'billing_enabled', t.billing_enabled,
        'price_paisa', t.price_paisa,
        'reporting_type', t.reporting_type,
        'workflow_type', t.workflow_type,
        'workflow_supported', t.workflow_supported,
        'clinical_reporting_enabled', t.clinical_reporting_enabled,
        'sample_type', t.sample_type,
        'container', t.container,
        'method', t.method,
        'readiness_state', r.state,
        'readiness_reason', r.decision_reason
    )) AS tests_info
    FROM public.tests t
    LEFT JOIN public.catalogue_service_readiness r ON r.test_id = t.id
    WHERE t.code IN ('IMM-0093', 'BIO-0141', 'SER-0089', 'SER-0088', 'PUS_CULTURE_AND_SENSITIVITY', 'HEM-0001', 'BIO-0001')
),
roles_summary AS (
    SELECT json_agg(json_build_object(
        'code', r.code,
        'name', r.name,
        'user_count', (SELECT count(*)::int FROM public.user_roles ur WHERE ur.role_id = r.id),
        'permissions', (SELECT json_agg(rp.permission_key ORDER BY rp.permission_key) FROM public.role_permissions rp WHERE rp.role_id = r.id)
    ) ORDER BY r.code) AS roles
    FROM public.roles r
),
recent_orders_check AS (
    SELECT json_agg(json_build_object(
        'order_number', o.order_number,
        'status', o.status,
        'created_at', o.created_at,
        'patient_name', p.full_name,
        'uhid', p.uhid
    ) ORDER BY o.created_at DESC) AS orders
    FROM (
        SELECT id, order_number, status, created_at, patient_id
        FROM public.clinical_orders
        ORDER BY created_at DESC
        LIMIT 5
    ) o
    JOIN public.patients p ON p.id = o.patient_id
)
SELECT json_build_object(
    'time', (SELECT row_to_json(time_calc.*) FROM time_calc),
    'kpis', (SELECT row_to_json(kpis.*) FROM kpis),
    'target_tests', (SELECT tests_info FROM target_tests),
    'roles_summary', (SELECT roles FROM roles_summary),
    'recent_orders', (SELECT orders FROM recent_orders_check)
) AS audit_data;
`;

async function run() {
  const tmpFile = path.resolve('tmp_dashboard_audit.sql');
  writeFileSync(tmpFile, sqlScript, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
      maxBuffer: 50 * 1024 * 1024,
    });

    const jsonStart = raw.indexOf('[');
    const jsonStartObj = raw.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    const parsed = JSON.parse(raw.slice(start));
    const data = Array.isArray(parsed) ? parsed[0]?.audit_data : parsed.rows?.[0]?.audit_data;
    console.log(JSON.stringify(data, null, 2));
  } catch (err) {
    console.error('Error executing query:', err.message, err.stderr);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

run();
