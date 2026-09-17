import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

async function main() {
  console.log('================================================================');
  console.log(' BIMAL PATHOLOGY LIS - PHASE 18 DATABASE INTEGRITY AUDIT');
  console.log('================================================================\n');

  const sql = `
  SELECT json_build_object(
    'duplicate_patient_mobiles', (
      SELECT count(*) FROM (
        SELECT mobile FROM public.patients WHERE mobile IS NOT NULL AND mobile <> '' GROUP BY mobile HAVING count(*) > 1
      ) d
    ),
    'orphan_bill_items', (
      SELECT count(*) FROM public.bill_items bi LEFT JOIN public.bills b ON b.id = bi.bill_id WHERE b.id IS NULL
    ),
    'orphan_payments', (
      SELECT count(*) FROM public.payment_transactions pt LEFT JOIN public.bills b ON b.id = pt.bill_id WHERE b.id IS NULL
    ),
    'orphan_clinical_order_items', (
      SELECT count(*) FROM public.clinical_order_items coi LEFT JOIN public.clinical_orders co ON co.id = coi.order_id WHERE co.id IS NULL
    ),
    'orphan_samples', (
      SELECT count(*) FROM public.samples s LEFT JOIN public.patients p ON p.id = s.patient_id WHERE p.id IS NULL
    ),
    'orphan_test_results', (
      SELECT count(*) FROM public.test_results tr LEFT JOIN public.clinical_order_items coi ON coi.id = tr.order_item_id WHERE coi.id IS NULL
    ),
    'orphan_diagnostic_reports', (
      SELECT count(*) FROM public.diagnostic_reports dr LEFT JOIN public.clinical_orders co ON co.id = dr.order_id WHERE co.id IS NULL
    ),
    'duplicate_canonical_test_codes', (
      SELECT count(*) FROM (
        SELECT code FROM public.tests WHERE is_active = true GROUP BY code HAVING count(*) > 1
      ) d
    ),
    'duplicate_canonical_names', (
      SELECT count(*) FROM (
        SELECT lower(name) FROM public.tests WHERE is_active = true GROUP BY lower(name) HAVING count(*) > 1
      ) d
    ),
    'orphan_test_parameters', (
      SELECT count(*) FROM public.parameters p LEFT JOIN public.tests t ON t.id = p.test_id WHERE t.id IS NULL
    ),
    'orphan_reference_ranges', (
      SELECT count(*) FROM public.reference_ranges rr LEFT JOIN public.parameters p ON p.id = rr.parameter_id WHERE p.id IS NULL
    ),
    'orphan_analyzer_mappings', (
      SELECT count(*) FROM public.analyzer_parameter_mappings apm LEFT JOIN public.parameters p ON p.id = apm.parameter_id WHERE p.id IS NULL
    ),
    'duplicate_panel_components', (
      SELECT count(*) FROM (
        SELECT panel_id, component_test_id FROM public.catalogue_panel_components GROUP BY panel_id, component_test_id HAVING count(*) > 1
      ) d
    )
  ) AS audit_summary;
  `;

  const tmpFile = path.resolve('tmp_integrity_audit.sql');
  fs.writeFileSync(tmpFile, sql, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      shell: true,
      maxBuffer: 10 * 1024 * 1024,
    });

    const jsonStart = raw.indexOf('[');
    const jsonStartObj = raw.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    const parsed = JSON.parse(raw.slice(start));
    const data = Array.isArray(parsed) ? parsed[0]?.audit_summary : parsed.rows?.[0]?.audit_summary;

    console.log('DATABASE INTEGRITY EXACT AUDIT COUNTS:');
    console.log(JSON.stringify(data, null, 2));
  } finally {
    if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
  }
}

main().catch(console.error);
