import { execSync } from 'node:child_process';
import fs from 'node:fs';

const tables = [
  'patients',
  'bills',
  'bill_items',
  'bill_panel_selections',
  'bill_panel_components',
  'bill_package_selections',
  'bill_package_components',
  'billing_idempotency_requests',
  'clinical_orders',
  'clinical_order_items',
  'clinical_report_groups',
  'clinical_report_group_items',
  'order_report_group_workspace',
  'samples',
  'sample_lifecycle_events',
  'test_results',
  'diagnostic_reports',
  'payment_transactions',
  'payment_idempotency_requests',
  'sms_queue_items',
  'audit_logs',
  'outsource_samples',
  'outsource_sample_events',
  'critical_alert_events',
  'report_pdf_artifacts',
  'report_pdf_delivery_intents',
  'order_report_delivery_tokens',
  'public_report_tokens'
];

const unions = tables.map(t => `SELECT '${t}' AS table_name, count(*) AS row_count FROM public.${t}`).join('\nUNION ALL\n');
const sql = `${unions} ORDER BY table_name;`;

fs.writeFileSync('tmp_q8_txn2.sql', sql, 'utf8');
const res = execSync('npx supabase db query --linked -f tmp_q8_txn2.sql', { encoding: 'utf8' });
console.log(res);
