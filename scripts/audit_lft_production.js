import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.resolve(__dirname, '../.env.local');

const envContent = fs.readFileSync(envPath, 'utf8');
const envVars = {};

envContent.split('\n').forEach((line) => {
  const trimmed = line.trim();
  if (trimmed && !trimmed.startsWith('#')) {
    const match = trimmed.match(/^([^=]+)=(.*)$/);
    if (match) {
      const key = match[1].trim();
      let value = match[2].trim();
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      envVars[key] = value;
    }
  }
});

const supabaseUrl = envVars.VITE_SUPABASE_URL;
const supabaseKey = envVars.VITE_SUPABASE_SERVICE_ROLE_KEY || envVars.VITE_SUPABASE_ANON_KEY;

const supabase = createClient(supabaseUrl, supabaseKey);

async function runAudit() {
  console.log('=== 1. AUDIT TESTS TABLE FOR PRO-0001 ===');
  const { data: testRows, error: testErr } = await supabase
    .from('tests')
    .select('id, code, name, is_active, billing_enabled, clinical_reporting_enabled, test_kind, test_type, reporting_model')
    .eq('code', 'PRO-0001');

  if (testErr) {
    console.error('Error fetching tests:', testErr);
    return;
  }
  console.log('PRO-0001 test row:', JSON.stringify(testRows, null, 2));

  if (!testRows || testRows.length === 0) {
    console.log('PRO-0001 not found in tests table.');
    return;
  }

  const pro0001Id = testRows[0].id;

  console.log('\n=== 2. AUDIT PARAMETERS DIRECTLY ON PRO-0001 ===');
  const { data: directParams, error: paramErr } = await supabase
    .from('parameters')
    .select('id, code, name, unit, value_type, is_active, lifecycle_status, is_mandatory, display_order, source')
    .eq('test_id', pro0001Id);

  if (paramErr) console.error('Error fetching parameters:', paramErr);
  console.log(`Direct parameters count for PRO-0001 (${pro0001Id}):`, directParams?.length || 0);
  console.log(JSON.stringify(directParams, null, 2));

  console.log('\n=== 3. AUDIT CATALOGUE_PANEL_COMPONENTS FOR PRO-0001 ===');
  const { data: panelComponents, error: panelErr } = await supabase
    .from('catalogue_panel_components')
    .select('panel_id, panel_test_id, component_test_id, component_parameter_id, display_order, is_required, component_role')
    .or(`panel_id.eq.${pro0001Id},panel_test_id.eq.${pro0001Id}`)
    .order('display_order', { ascending: true });

  if (panelErr) console.error('Error fetching panel components:', panelErr);
  console.log('Panel components for PRO-0001 count:', panelComponents?.length || 0);
  console.log(JSON.stringify(panelComponents, null, 2));

  if (panelComponents && panelComponents.length > 0) {
    const compTestIds = panelComponents.map(c => c.component_test_id).filter(Boolean);
    console.log('\n=== 4. AUDIT CHILD TESTS FOR PRO-0001 COMPONENTS ===');
    const { data: childTests, error: childTestsErr } = await supabase
      .from('tests')
      .select('id, code, name, is_active, billing_enabled, clinical_reporting_enabled')
      .in('id', compTestIds);

    if (childTestsErr) console.error('Error fetching child tests:', childTestsErr);
    console.log('Child tests count:', childTests?.length || 0);
    console.log(JSON.stringify(childTests, null, 2));

    console.log('\n=== 5. AUDIT PARAMETERS OF CHILD TESTS ===');
    const { data: childParams, error: childParamsErr } = await supabase
      .from('parameters')
      .select('id, test_id, code, name, unit, value_type, is_active, lifecycle_status, is_mandatory, display_order, source')
      .in('test_id', compTestIds)
      .order('display_order', { ascending: true });

    if (childParamsErr) console.error('Error fetching child params:', childParamsErr);
    console.log('Child parameters count:', childParams?.length || 0);
    console.log(JSON.stringify(childParams, null, 2));

    const childParamIds = (childParams || []).map(p => p.id);
    console.log('\n=== 6. AUDIT REFERENCE RANGES OF CHILD PARAMS ===');
    const { data: refRanges, error: refRangesErr } = await supabase
      .from('reference_ranges')
      .select('id, parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active')
      .in('parameter_id', childParamIds);

    if (refRangesErr) console.error('Error fetching reference ranges:', refRangesErr);
    console.log('Reference ranges count:', refRanges?.length || 0);
    console.log(JSON.stringify(refRanges, null, 2));
  }

  console.log('\n=== 7. AUDIT PRO-0002 (KFT) AND PRO-0003 (LIPID) ===');
  const { data: otherProfiles } = await supabase
    .from('tests')
    .select('id, code, name, is_active')
    .in('code', ['PRO-0002', 'PRO-0003', 'HEM-0001', 'CLP-0001', 'SER-0024']);
  console.log('Other profiles/tests:', JSON.stringify(otherProfiles, null, 2));

  for (const prof of otherProfiles || []) {
    const { data: dParams } = await supabase
      .from('parameters')
      .select('id, code, name, is_active')
      .eq('test_id', prof.id);
    const { data: pComps } = await supabase
      .from('catalogue_panel_components')
      .select('component_test_id, display_order')
      .or(`panel_id.eq.${prof.id},panel_test_id.eq.${prof.id}`);
    console.log(`Profile/Test ${prof.code} (${prof.name}): Direct params = ${dParams?.length || 0}, Panel components = ${pComps?.length || 0}`);
  }

  console.log('\n=== 8. AUDIT RECENT CLINICAL ORDERS FOR LFT ===');
  const { data: orderItems, error: oiErr } = await supabase
    .from('clinical_order_items')
    .select('id, order_id, test_id, test_name, status, workflow_type, clinical_reporting_enabled, created_at')
    .eq('test_id', pro0001Id)
    .order('created_at', { ascending: false })
    .limit(5);

  if (oiErr) console.error('Error fetching order items:', oiErr);
  console.log('Recent LFT order items count:', orderItems?.length || 0);
  console.log(JSON.stringify(orderItems, null, 2));
}

runAudit();
