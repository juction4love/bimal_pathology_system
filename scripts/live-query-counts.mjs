import { execSync } from 'node:child_process';
import fs from 'node:fs';

const sql = `
SELECT 
  'patients' AS tbl, count(*) AS cnt FROM public.patients
UNION ALL SELECT 'bills', count(*) FROM public.bills
UNION ALL SELECT 'bill_lines', count(*) FROM public.bill_lines
UNION ALL SELECT 'clinical_orders', count(*) FROM public.clinical_orders
UNION ALL SELECT 'clinical_order_items', count(*) FROM public.clinical_order_items
UNION ALL SELECT 'samples', count(*) FROM public.samples
UNION ALL SELECT 'test_results', count(*) FROM public.test_results
UNION ALL SELECT 'diagnostic_reports', count(*) FROM public.diagnostic_reports
UNION ALL SELECT 'payment_transactions', count(*) FROM public.payment_transactions
UNION ALL SELECT 'audit_events', count(*) FROM public.audit_events;
`;

fs.writeFileSync('tmp_q1_transactional.sql', sql, 'utf8');
const res = execSync('npx supabase db query --linked -f tmp_q1_transactional.sql', { encoding: 'utf8' });
console.log(res);
