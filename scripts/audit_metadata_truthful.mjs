import fs from 'node:fs';

const live = JSON.parse(fs.readFileSync('scripts/output/live_audit_dump.json', 'utf8'));

const tests = live.tests;
const params = live.parameters;
const panelComps = live.panel_components;
const refRanges = live.reference_ranges.filter(r => r.is_active);
const rates = live.rates;

console.log(`Total Active Tests: ${tests.length}`);

// Group parameters by test_id
const paramsByTest = new Map();
params.forEach(p => {
  if (!p.is_active || (p.unit?.toLowerCase() === 'panel') || ['panel', 'profile'].includes(p.value_type?.toLowerCase())) return;
  if (!paramsByTest.has(p.test_id)) paramsByTest.set(p.test_id, []);
  paramsByTest.get(p.test_id).push(p);
});

// Group panel components by panel_id
const compsByPanel = new Map();
panelComps.forEach(c => {
  if (!compsByPanel.has(c.panel_id)) compsByPanel.set(c.panel_id, []);
  compsByPanel.get(c.panel_id).push(c);
});

// Group reference ranges by parameter_id
const rrByParam = new Map();
refRanges.forEach(r => {
  if (!rrByParam.has(r.parameter_code)) rrByParam.set(r.parameter_code, []);
  rrByParam.get(r.parameter_code).push(r);
});

// Group rates by test_id / test_code
const rateTestIds = new Set(rates.map(r => r.test_id).filter(Boolean));
const rateTestCodes = new Set(rates.map(r => r.test_code).filter(Boolean));

let reportingOperational = 0;
let referenceComplete = 0;
let referencePending = 0;
let rateConfigured = 0;
let ratePending = 0;

tests.forEach(t => {
  const directParams = paramsByTest.get(t.id) || [];
  const comps = compsByPanel.get(t.id) || [];
  
  // Reporting operational: has direct parameters or child panel components
  const isOperational = directParams.length > 0 || comps.length > 0;
  if (isOperational) reportingOperational++;
  
  // Reference ranges complete check
  let hasRefRanges = false;
  if (directParams.length > 0) {
    hasRefRanges = directParams.some(p => (rrByParam.get(p.code)?.length || 0) > 0);
  } else if (comps.length > 0) {
    hasRefRanges = comps.some(c => (rrByParam.get(c.component_parameter_code)?.length || 0) > 0);
  }
  
  if (hasRefRanges) {
    referenceComplete++;
  } else {
    referencePending++;
  }
  
  // Rate configured
  if (rateTestIds.has(t.id) || rateTestCodes.has(t.code)) {
    rateConfigured++;
  } else {
    ratePending++;
  }
});

console.log(`REPORTING_OPERATIONAL: ${reportingOperational}`);
console.log(`REFERENCE_COMPLETE: ${referenceComplete}`);
console.log(`REFERENCE_PENDING: ${referencePending}`);
console.log(`RATE_CONFIGURED: ${rateConfigured}`);
console.log(`RATE_PENDING: ${ratePending}`);
