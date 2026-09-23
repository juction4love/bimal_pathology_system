import fs from 'node:fs';

const live = JSON.parse(fs.readFileSync('scripts/output/live_audit_dump.json', 'utf8'));

const tests = live.tests;
const params = live.parameters;
const panelComps = live.panel_components;

const testsByCode = new Map(tests.map(t => [t.code, t]));
const testsById = new Map(tests.map(t => [t.id, t]));

// Helper to resolve leaf components
function getResolvedParameters(testCode) {
  const t = testsByCode.get(testCode);
  if (!t) return { error: `Test ${testCode} not found` };
  
  const directParams = params.filter(p => p.test_id === t.id && p.is_active && (p.unit?.toLowerCase() !== 'panel') && !['panel', 'profile'].includes(p.value_type?.toLowerCase()));
  
  if (directParams.length > 0) {
    return { type: 'DIRECT', count: directParams.length, params: directParams };
  }
  
  // Look in panel components
  const comps = panelComps.filter(c => c.panel_code === testCode);
  const resolved = [];
  
  for (const c of comps) {
    if (c.component_parameter_code) {
      resolved.push({ code: c.component_parameter_code, name: c.component_parameter_name, source: 'param' });
    } else if (c.component_test_code) {
      const child = testsByCode.get(c.component_test_code);
      const childParams = params.filter(p => p.test_id === child?.id && p.is_active && (p.unit?.toLowerCase() !== 'panel') && !['panel', 'profile'].includes(p.value_type?.toLowerCase()));
      if (childParams.length > 0) {
        childParams.forEach(cp => resolved.push({ code: cp.code, name: cp.name, source: `test:${c.component_test_code}` }));
      } else {
        resolved.push({ code: c.component_test_code, name: c.component_test_name, source: 'test' });
      }
    }
  }
  
  return { type: 'PANEL', count: resolved.length, params: resolved };
}

const targetProfiles = [
  { code: 'PRO-0001', name: 'Liver Function Test (LFT)', expected: 11 },
  { code: 'PRO-0002', name: 'Renal Function Test (RFT/KFT)', expected: 4 },
  { code: 'PRO-0003', name: 'Lipid Profile', expected: 5 },
  { code: 'HEM-0001', name: 'Complete Blood Count (CBC)', expected: 24 },
  { code: 'CLP-0001', name: 'Urine Routine Examination (RE/ME)', expected: 14 },
  { code: 'SER-0024', name: 'Widal Test', expected: 4 },
  { code: 'POC-0002', name: 'Venous Blood Gas (VBG)', expected: 7 }
];

console.log('=== CLINICAL PROFILE LEAF PARAMETER RESOLUTION ===');
for (const p of targetProfiles) {
  const res = getResolvedParameters(p.code);
  console.log(`\nProfile ${p.code} (${p.name}): Expected=${p.expected}, Actual=${res.count} (${res.count === p.expected ? 'PASS' : 'FAIL'})`);
  if (res.params) {
    res.params.forEach((param, idx) => {
      console.log(`  ${idx + 1}. [${param.code}] ${param.name}`);
    });
  }
}

// Check VBG specifically
console.log('\n--- VBG (POC-0002) DETAILS ---');
const vbgRes = getResolvedParameters('POC-0002');
const vbgCodes = vbgRes.params?.map(p => p.code) || [];
const vbgNames = vbgRes.params?.map(p => p.name) || [];
const hasLactate = vbgCodes.includes('LACTATE') || vbgNames.some(n => n.toLowerCase().includes('lactate'));
const hasTotalCO2 = vbgCodes.includes('TCO2') || vbgNames.some(n => n.toLowerCase().includes('total co2'));
console.log(`VBG_HAS_LACTATE: ${hasLactate}`);
console.log(`VBG_HAS_TOTAL_CO2: ${hasTotalCO2}`);
