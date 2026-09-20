import fs from 'node:fs';

const data = JSON.parse(fs.readFileSync('scratch/deep_audit_result.json', 'utf8'));

console.log('--- AUDITING ANALYZER MAPPINGS ---');
const mappings = data.all_mappings;
console.log('Total mappings:', mappings.length);

const analyzerCounts = {};
for (const m of mappings) {
  analyzerCounts[m.analyzer_name] = (analyzerCounts[m.analyzer_name] || 0) + 1;
}
console.log('Mappings by Analyzer Name:', analyzerCounts);

// Let's see unique tests mapped to each analyzer
const testsByAnalyzer = {};
for (const m of mappings) {
  const an = m.analyzer_name;
  if (!testsByAnalyzer[an]) testsByAnalyzer[an] = new Set();
  testsByAnalyzer[an].add(m.test_code);
}
for (const [an, set] of Object.entries(testsByAnalyzer)) {
  console.log(`Analyzer ${an} has ${set.size} mapped tests:`, Array.from(set).slice(0, 10));
}

// Let's see test breakdown
const tests = data.tests_by_source_breakdown;
console.log('Total active tests:', tests.length);

// Let's check the test codes and names in tests
const testMap = new Map(tests.map(t => [t.code, t]));

// Test classification:
// 1. CounCell 23 Excel (COUNCELL_23_EXCEL)
// 2. CORALAB ACE (CORALAB_ACE)
// 3. FIAcheck (FIACHECK)
// 4. Manual Microscopy / Manual rapid / Manual urine / ESR
// 5. Calculated
// 6. Outsource
// 7. Profile / Panel (derive from children or Mixed)
// 8. Unknown

let countCellCount = 0;
let coralabCount = 0;
let fiacheckCount = 0;
let manualCount = 0;
let calculatedCount = 0;
let outsourceCount = 0;
let mixedCount = 0;
let unknownCount = 0;

const testSourceAudit = [];

for (const t of tests) {
  const anList = t.analyzer_mappings || [];
  const hasCounCell = anList.includes('COUNCELL_23_EXCEL');
  const hasCoralab = anList.includes('CORALAB_ACE');
  const hasFiacheck = anList.includes('FIACHECK');
  const hasManualMicroscopy = anList.includes('MANUAL_MICROSCOPY');

  let resolvedSource = 'Unknown';
  let sourceCategory = 'UNKNOWN';

  if (t.reporting_type === 'OutsourceWithBimalReport' || t.reporting_type === 'Outsource' || t.reporting_type === 'OutsourceWithoutReport') {
    resolvedSource = 'Outsource';
    sourceCategory = 'OUTSOURCE';
    outsourceCount++;
  } else if (t.test_kind === 'Profile') {
    // Check if profile children / mappings
    const analyzerSet = new Set(anList.filter(a => a !== 'MANUAL_MICROSCOPY'));
    if (analyzerSet.size > 1 || (analyzerSet.size === 1 && (t.calc_count > 0 || hasManualMicroscopy))) {
      resolvedSource = 'Mixed / Multiple Sources';
      sourceCategory = 'MIXED_PROFILE';
      mixedCount++;
    } else if (analyzerSet.size === 1) {
      const single = Array.from(analyzerSet)[0];
      if (single === 'COUNCELL_23_EXCEL') {
        resolvedSource = 'CounCell 23 Excel';
        sourceCategory = 'COUNTCELL';
        countCellCount++;
      } else if (single === 'CORALAB_ACE') {
        resolvedSource = 'CORALAB ACE';
        sourceCategory = 'CORALAB';
        coralabCount++;
      } else if (single === 'FIACHECK') {
        resolvedSource = 'FIAcheck';
        sourceCategory = 'FIACHECK';
        fiacheckCount++;
      }
    } else if (t.calc_count > 0 && t.param_count === t.calc_count) {
      resolvedSource = 'Calculated';
      sourceCategory = 'CALCULATED';
      calculatedCount++;
    } else {
      resolvedSource = 'Manual';
      sourceCategory = 'MANUAL';
      manualCount++;
    }
  } else if (hasCounCell && !hasCoralab && !hasFiacheck) {
    resolvedSource = 'CounCell 23 Excel';
    sourceCategory = 'COUNTCELL';
    countCellCount++;
  } else if (hasCoralab && !hasCounCell && !hasFiacheck) {
    resolvedSource = 'CORALAB ACE';
    sourceCategory = 'CORALAB';
    coralabCount++;
  } else if (hasFiacheck && !hasCounCell && !hasCoralab) {
    resolvedSource = 'FIAcheck';
    sourceCategory = 'FIACHECK';
    fiacheckCount++;
  } else if (anList.length > 1) {
    resolvedSource = 'Mixed / Multiple Sources';
    sourceCategory = 'MIXED_PROFILE';
    mixedCount++;
  } else if (t.calc_count > 0 && t.param_count === t.calc_count) {
    resolvedSource = 'Calculated';
    sourceCategory = 'CALCULATED';
    calculatedCount++;
  } else if (hasManualMicroscopy || t.name.toLowerCase().includes('microscopy') || t.name.toLowerCase().includes('stool') || t.name.toLowerCase().includes('urine') || t.name.toLowerCase().includes('westergren') || t.name.toLowerCase().includes('rapid') || t.name.toLowerCase().includes('card') || t.name.toLowerCase().includes('strip') || t.name.toLowerCase().includes('smear') || t.reporting_type === 'InHouse' || t.reporting_type === 'NoReporting') {
    resolvedSource = 'Manual';
    sourceCategory = 'MANUAL';
    manualCount++;
  } else {
    resolvedSource = 'Unknown';
    sourceCategory = 'UNKNOWN';
    unknownCount++;
  }

  testSourceAudit.push({
    code: t.code,
    name: t.name,
    resolvedSource,
    sourceCategory,
    anList
  });
}

console.log('\n--- AUDIT COUNTS ---');
console.log('COUNTCELL_COUNT:', countCellCount);
console.log('CORALAB_COUNT:', coralabCount);
console.log('FIACHECK_COUNT:', fiacheckCount);
console.log('MANUAL_COUNT:', manualCount);
console.log('CALCULATED_COUNT:', calculatedCount);
console.log('OUTSOURCE_COUNT:', outsourceCount);
console.log('MIXED_COUNT:', mixedCount);
console.log('UNKNOWN_COUNT:', unknownCount);
console.log('TOTAL:', countCellCount + coralabCount + fiacheckCount + manualCount + calculatedCount + outsourceCount + mixedCount + unknownCount);

// Verify examples from user request:
const examples = [
  'HEM-0001', // CBC -> CounCell 23 Excel
  'BIO-0010', // Creatinine -> CORALAB ACE
  'BIO-0037', // Sodium -> CORALAB ACE
  'END-0001', // TSH -> FIAcheck
  'BIO-0053', // Vitamin D -> FIAcheck
  'BIO-0050', // Ferritin -> FIAcheck
  'HEM-0015', // manual Neutrophil -> Manual
  'HEM-0027', // ESR Westergren -> Manual
];

console.log('\n--- VERIFYING PROMPT EXAMPLES ---');
for (const code of examples) {
  const item = testSourceAudit.find(x => x.code === code);
  console.log(`${code} (${item?.name}): resolved -> "${item?.resolvedSource}" [Category: ${item?.sourceCategory}], mappings: ${JSON.stringify(item?.anList)}`);
}
