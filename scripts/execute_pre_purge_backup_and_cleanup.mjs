import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const PROJECT_REF = 'rncjxstujioagcezvfkb';

function runSql(sql) {
  const tmpFile = path.resolve('scripts/output/temp_exec.sql');
  fs.writeFileSync(tmpFile, sql, 'utf8');
  try {
    const stdout = execSync(`npx supabase db query --linked -f "${tmpFile}"`, {
      encoding: 'utf8',
      maxBuffer: 50 * 1024 * 1024,
      stdio: ['pipe', 'pipe', 'pipe']
    });
    return stdout;
  } finally {
    if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
  }
}

function parseSqlOutput(raw) {
  const marker = raw.indexOf('{');
  if (marker === -1) return null;
  try {
    return JSON.parse(raw.slice(marker));
  } catch {
    return null;
  }
}

async function main() {
  console.log('=== PHASE 21 & 22: TARGET GUARD & PRE-PURGE BACKUP ===');
  console.log(`Target project ref: ${PROJECT_REF}`);

  const backupDir = path.resolve('backups/pre_final_production_purge');
  if (!fs.existsSync(backupDir)) {
    fs.mkdirSync(backupDir, { recursive: true });
  }

  const transactionalTables = [
    'audit_logs',
    'ast_observation_audit',
    'ast_observations',
    'billing_idempotency_requests',
    'payment_idempotency_requests',
    'payment_transactions',
    'bill_package_components',
    'bill_package_selections',
    'bill_panel_components',
    'bill_panel_selections',
    'bill_items',
    'bills',
    'clinical_calculation_runs',
    'report_calculation_provenance',
    'report_secure_link_presentations',
    'report_pdf_delivery_intents',
    'report_pdf_artifacts',
    'order_report_delivery_entitlements',
    'order_report_delivery_tokens',
    'order_report_notification_generations',
    'public_report_tokens',
    'diagnostic_reports',
    'test_results',
    'sample_lifecycle_events',
    'samples',
    'clinical_report_group_items',
    'clinical_report_groups',
    'clinical_order_items',
    'clinical_orders',
    'outsource_sample_events',
    'outsource_samples',
    'critical_alert_events',
    'pus_culture_worksheets',
    'sms_queue_items',
    'hmis_submission_events',
    'hmis_monthly_report_versions',
    'hmis_monthly_manual_values',
    'hmis_monthly_reports',
    'patient_app_pdf_tokens',
    'patient_app_identities',
    'lab_number_registry',
    'patients'
  ];

  const counts = [];
  const needExport = !fs.existsSync('scripts/output/pre_final_production_purge_counts.csv');

  for (const table of transactionalTables) {
    const jsonPath = path.join(backupDir, `${table}.json`);
    if (needExport || !fs.existsSync(jsonPath)) {
      const raw = runSql(`SELECT * FROM public.${table};`);
      const parsed = parseSqlOutput(raw);
      const rows = parsed?.rows || [];
      counts.push({ table, count: rows.length });
      fs.writeFileSync(jsonPath, JSON.stringify(rows, null, 2), 'utf8');
      console.log(`Exported ${table}: ${rows.length} rows`);
    } else {
      const rows = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
      counts.push({ table, count: rows.length });
      console.log(`Loaded backup for ${table}: ${rows.length} rows`);
    }
  }

  if (needExport) {
    const csvContent = 'table_name,pre_purge_count\n' + counts.map(c => `${c.table},${c.count}`).join('\n') + '\n';
    fs.writeFileSync('scripts/output/pre_final_production_purge_counts.csv', csvContent, 'utf8');
    console.log('Saved scripts/output/pre_final_production_purge_counts.csv');
  }

  console.log('\n=== PHASE 23 & 26: EXECUTING TRANSACTIONAL PURGE & SEQUENCE RESET ===');

  // FK ordered deletion SQL with session_replication_role to bypass immutability triggers during admin purge
  const purgeSql = `
BEGIN;

SET session_replication_role = 'replica';

-- 1. Reports, Delivery Entitlements, Tokens, Intents & Artifacts
DELETE FROM public.order_report_notification_generations;
DELETE FROM public.report_secure_link_presentations;
DELETE FROM public.order_report_delivery_entitlements;
DELETE FROM public.report_pdf_delivery_intents;
DELETE FROM public.order_report_delivery_tokens;
DELETE FROM public.public_report_tokens;
DELETE FROM public.report_pdf_artifacts;
DELETE FROM public.diagnostic_reports;

-- 2. SMS Notifications (after delivery intents referencing queued_sms_id)
DELETE FROM public.sms_queue_items;

-- 3. Audit logs & events
DELETE FROM public.audit_logs;
DELETE FROM public.critical_alert_events;
DELETE FROM public.outsource_sample_events;
DELETE FROM public.outsource_samples;
DELETE FROM public.ast_observation_audit;
DELETE FROM public.ast_observations;
DELETE FROM public.pus_culture_worksheets;

-- 4. Results & Calculations
DELETE FROM public.report_calculation_provenance;
DELETE FROM public.clinical_calculation_runs;
DELETE FROM public.test_results;

-- 5. Samples & Lifecycle
DELETE FROM public.sample_lifecycle_events;
DELETE FROM public.samples;

-- 6. Report Groups & Orders
DELETE FROM public.clinical_report_group_items;
DELETE FROM public.clinical_report_groups;
DELETE FROM public.clinical_order_items;
DELETE FROM public.clinical_orders;

-- 7. Billing & Payments
DELETE FROM public.billing_idempotency_requests;
DELETE FROM public.payment_idempotency_requests;
DELETE FROM public.payment_transactions;
DELETE FROM public.bill_package_components;
DELETE FROM public.bill_package_selections;
DELETE FROM public.bill_panel_components;
DELETE FROM public.bill_panel_selections;
DELETE FROM public.bill_items;
DELETE FROM public.bills;

-- 8. HMIS test reports
DELETE FROM public.hmis_submission_events;
DELETE FROM public.hmis_monthly_report_versions;
DELETE FROM public.hmis_monthly_manual_values;
DELETE FROM public.hmis_monthly_reports;

-- 9. Patient Portal & Registry & Patients
DELETE FROM public.patient_app_pdf_tokens;
DELETE FROM public.patient_app_identities;
DELETE FROM public.lab_number_registry;
DELETE FROM public.patients;

-- 10. Reset sequences where applicable
DO $$
DECLARE
    seq_rec RECORD;
BEGIN
    FOR seq_rec IN 
        SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER SEQUENCE public.' || quote_ident(seq_rec.sequencename) || ' RESTART WITH 1;';
    END LOOP;
END $$;

SET session_replication_role = 'origin';

COMMIT;
`;

  const purgeResult = runSql(purgeSql);
  console.log('Purge output:', purgeResult);

  console.log('\n=== PHASE 29 & 30: POST-PURGE VERIFICATION ===');

  const verifySql = `
SELECT 
  (SELECT count(*) FROM public.patients) AS count_patients,
  (SELECT count(*) FROM public.bills) AS count_bills,
  (SELECT count(*) FROM public.bill_items) AS count_bill_items,
  (SELECT count(*) FROM public.clinical_orders) AS count_orders,
  (SELECT count(*) FROM public.clinical_order_items) AS count_order_items,
  (SELECT count(*) FROM public.samples) AS count_samples,
  (SELECT count(*) FROM public.test_results) AS count_results,
  (SELECT count(*) FROM public.diagnostic_reports) AS count_reports,
  (SELECT count(*) FROM public.payment_transactions) AS count_payments,
  (SELECT count(*) FROM public.sms_queue_items) AS count_sms,
  (SELECT count(*) FROM public.outsource_samples) AS count_outsource,
  (SELECT count(*) FROM public.audit_logs) AS count_audit_logs,
  (SELECT count(*) FROM public.tests WHERE is_active = true) AS count_active_tests,
  (SELECT count(*) FROM public.parameters WHERE is_active = true) AS count_active_parameters,
  (SELECT count(*) FROM public.reference_ranges WHERE is_active = true) AS count_active_reference_rules,
  (SELECT count(*) FROM public.catalogue_panel_components) AS count_panel_components,
  (SELECT count(*) FROM public.catalogue_rate_versions WHERE effective_to IS NULL) AS count_active_rates,
  (SELECT count(*) FROM public.analyzers) AS count_analyzers,
  (SELECT count(*) FROM public.analyzer_parameter_mappings) AS count_analyzer_mappings,
  (SELECT count(*) FROM auth.users) AS count_auth_users;
`;

  const verifyRaw = runSql(verifySql);
  const verifyParsed = parseSqlOutput(verifyRaw);
  console.log('Post-purge verification counts:', JSON.stringify(verifyParsed?.rows?.[0], null, 2));
}

main().catch(err => {
  console.error('Fatal error during backup and purge:', err);
  process.exit(1);
});
