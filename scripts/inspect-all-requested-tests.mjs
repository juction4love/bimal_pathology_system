import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const querySql = `
WITH matched_tests AS (
    SELECT 
        t.id,
        t.code,
        t.name,
        t.short_name,
        t.department,
        t.test_type,
        t.sample_type,
        t.specimen_type,
        t.container,
        t.method,
        t.unit,
        t.price_paisa,
        t.is_active,
        t.billing_enabled,
        t.clinical_reporting_enabled,
        t.validation_status,
        t.configuration_status,
        t.lifecycle_status,
        t.report_data_type,
        (SELECT json_agg(json_build_object('id', p.id, 'code', p.code, 'name', p.name, 'value_type', p.value_type, 'unit', p.unit)) FROM public.parameters p WHERE p.test_id = t.id) AS parameters,
        (SELECT json_agg(json_build_object('alias_name', a.alias_name, 'alias_type', a.alias_type)) FROM public.test_aliases a WHERE a.test_id = t.id) AS aliases,
        (SELECT json_agg(json_build_object('preferred_specimen', r.preferred_specimen, 'allowed_specimens', r.allowed_specimens)) FROM public.assay_specimen_governance_rules r WHERE r.test_id = t.id) AS specimen_rules
    FROM public.tests t
    WHERE 
        t.code ILIKE '%TROP%' OR t.name ILIKE '%Troponin%' OR t.short_name ILIKE '%Trop%' OR t.short_name ILIKE '%cTn%'
        OR t.code ILIKE '%CK%' OR t.name ILIKE '%CK-MB%' OR t.name ILIKE '%Creatine Kinase%'
        OR t.code ILIKE '%MYO%' OR t.name ILIKE '%Myoglobin%'
        OR t.code ILIKE '%BNP%' OR t.name ILIKE '%proBNP%' OR t.name ILIKE '%BNP%'
        OR t.code ILIKE '%DIMER%' OR t.name ILIKE '%D-Dimer%'
        OR t.code ILIKE '%CRP%' OR t.name ILIKE '%CRP%' OR t.name ILIKE '%C-Reactive%'
        OR t.code ILIKE '%PCT%' OR t.name ILIKE '%Procalcitonin%'
        OR t.code ILIKE '%IL%' OR t.name ILIKE '%Interleukin%'
        OR t.code ILIKE '%FER%' OR t.name ILIKE '%Ferritin%'
        OR t.code ILIKE '%HBA1C%' OR t.name ILIKE '%HbA1c%' OR t.name ILIKE '%Glycated%'
        OR t.code ILIKE '%ALB%' OR t.name ILIKE '%Microalbumin%' OR t.name ILIKE '%Albumin%'
        OR t.code ILIKE '%CYS%' OR t.name ILIKE '%Cystatin%'
        OR t.code ILIKE '%TSH%' OR t.name ILIKE '%Thyroid%' OR t.name ILIKE '%Thyrotropin%' OR t.name ILIKE '%Triiodo%' OR t.name ILIKE '%Thyroxine%' OR t.code IN ('END-0001','END-0002','END-0003','END-0004','END-0005')
        OR t.code ILIKE '%HCG%' OR t.name ILIKE '%HCG%' OR t.name ILIKE '%Human Chorionic%'
        OR t.code ILIKE '%TESTO%' OR t.name ILIKE '%Testosterone%'
        OR t.code ILIKE '%LH%' OR t.name ILIKE '%Luteinizing%'
        OR t.code ILIKE '%FSH%' OR t.name ILIKE '%Follicle%'
        OR t.code ILIKE '%PRL%' OR t.code ILIKE '%PROL%' OR t.name ILIKE '%Prolactin%'
        OR t.code ILIKE '%AMH%' OR t.name ILIKE '%Mullerian%'
        OR t.code ILIKE '%VIT%' OR t.name ILIKE '%Vitamin D%'
        OR t.code ILIKE '%SCRUB%' OR t.name ILIKE '%Scrub%' OR t.name ILIKE '%Tsutsugamushi%'
        OR t.code ILIKE '%DENG%' OR t.name ILIKE '%Dengue%'
        OR t.code ILIKE '%HCV%' OR t.name ILIKE '%HCV%' OR t.name ILIKE '%Hepatitis C%'
        OR t.code ILIKE '%HBS%' OR t.name ILIKE '%HBsAg%' OR t.name ILIKE '%Hepatitis B%'
        OR t.code ILIKE '%PYLORI%' OR t.name ILIKE '%Pylori%'
        OR t.code ILIKE '%CCP%' OR t.name ILIKE '%CCP%' OR t.name ILIKE '%Citrullinated%'
        OR t.code ILIKE '%ASO%' OR t.name ILIKE '%Antistreptolysin%'
        OR t.code ILIKE '%RF%' OR t.name ILIKE '%Rheumatoid%'
        OR t.code ILIKE '%IGE%' OR t.name ILIKE '%IgE%' OR t.name ILIKE '%Immunoglobulin E%'
        OR t.code ILIKE '%PSA%' OR t.name ILIKE '%Prostate%'
        OR t.code ILIKE '%AFP%' OR t.name ILIKE '%Alpha-Fetoprotein%'
        OR t.code ILIKE '%CEA%' OR t.name ILIKE '%Carcinoembryonic%'
    ORDER BY t.department, t.code
),
panels_list AS (
    SELECT 
        p.id,
        p.code AS panel_code,
        p.name AS panel_name,
        p.department,
        p.price_paisa,
        p.is_active,
        p.billing_enabled,
        (
            SELECT json_agg(json_build_object(
                'component_test_id', cpc.component_test_id,
                'test_code', t.code,
                'test_name', t.name,
                'display_order', cpc.display_order,
                'is_required', cpc.is_required
            ) ORDER BY cpc.display_order)
            FROM public.catalogue_panel_components cpc
            JOIN public.tests t ON t.id = cpc.component_test_id
            WHERE cpc.panel_id = p.id
        ) AS components
    FROM public.tests p
    WHERE p.test_type = 'Panel'
)
SELECT json_build_object(
    'total_tests_count', (SELECT count(*) FROM public.tests),
    'matched_tests', (SELECT json_agg(row_to_json(matched_tests.*)) FROM matched_tests),
    'panels', (SELECT json_agg(row_to_json(panels_list.*)) FROM panels_list)
) AS audit_data;
`;

async function run() {
  const tmpFile = path.resolve('tmp_audit.sql');
  writeFileSync(tmpFile, querySql, 'utf8');

  try {
    const res = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
      maxBuffer: 50 * 1024 * 1024,
    });

    const jsonStart = res.indexOf('[');
    const jsonStartObj = res.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    if (start === -1) {
      console.error('No JSON returned:', res);
      process.exit(1);
    }
    const parsed = JSON.parse(res.slice(start));
    const payload = Array.isArray(parsed) ? parsed[0]?.audit_data : parsed.rows?.[0]?.audit_data;
    writeFileSync('scripts/audit_output.json', JSON.stringify(payload, null, 2), 'utf8');
    console.log('Audit completed! Total tests in DB:', payload.total_tests_count);
    console.log('Matched tests count:', payload.matched_tests?.length);
    console.log('Panels count:', payload.panels?.length);
  } catch (err) {
    console.error('Error executing query:');
    console.error('stdout:', err.stdout);
    console.error('stderr:', err.stderr);
    console.error('message:', err.message);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

run();
