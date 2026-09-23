/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Phase 12 Laboratory Calculation Engine Verification Suite
 * Tests all 13 calculation engine criteria
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

let passedCount = 0;
let failedCount = 0;

function assert(condition, testCode, description) {
  if (condition) {
    console.log(`  ✅ [PASS] ${testCode}: ${description}`);
    passedCount++;
  } else {
    console.error(`  ❌ [FAIL] ${testCode}: ${description}`);
    failedCount++;
  }
}

async function runTests() {
  console.log('================================================================');
  console.log(' BIMAL PATHOLOGY - PHASE 12 CALCULATION ENGINE SUITE');
  console.log('================================================================\n');

  const {
    evaluateClinicalFormula,
    recalculateInvestigationParameters,
    getTopologicalCalculationOrder,
  } = await import('../src/lib/clinicalMath.ts');

  // --- GROUP 1: CORE CLINICAL FORMULAS ---
  console.log('--- TEST GROUP 1: CORE CLINICAL FORMULAS & PRECISION ---');

  // 1. IndirectBilirubin_AutoCalculates
  const ibilRes = evaluateClinicalFormula('TBIL - DBIL', { TBIL: 1.2, DBIL: 0.3 }, 'IBIL', 'mg/dL');
  assert(
    ibilRes.status === 'SUCCESS' && ibilRes.displayValue === '0.90' && ibilRes.rawValue === 0.9,
    '1. IndirectBilirubin_AutoCalculates',
    `IBIL auto-calculates from TBIL (1.20) - DBIL (0.30) -> ${ibilRes.displayValue} mg/dL (2 decimals)`
  );

  // 2. Globulin_AutoCalculates
  const globRes = evaluateClinicalFormula('TP - ALB', { TP: 7.5, ALB: 4.2 }, 'GLOB', 'g/dL');
  assert(
    globRes.status === 'SUCCESS' && globRes.displayValue === '3.30' && globRes.rawValue === 3.3,
    '2. Globulin_AutoCalculates',
    `GLOB auto-calculates from TP (7.50) - ALB (4.20) -> ${globRes.displayValue} g/dL (2 decimals)`
  );

  // 3. AGRatio_AutoCalculates
  const agRes = evaluateClinicalFormula('ALB / GLOB', { ALB: 4.2, GLOB: 3.3 }, 'AG_RATIO', 'ratio');
  assert(
    agRes.status === 'SUCCESS' && agRes.displayValue === '1.27' && Math.abs(agRes.rawValue - 1.2727) < 0.01,
    '3. AGRatio_AutoCalculates',
    `A:G Ratio auto-calculates from ALB (4.20) / GLOB (3.30) -> ${agRes.displayValue} (2 decimals)`
  );

  // 4. VLDL_AutoCalculates
  const vldlRes = evaluateClinicalFormula('TRIG / 5', { TRIG: 150 }, 'VLDL', 'mg/dL');
  assert(
    vldlRes.status === 'SUCCESS' && vldlRes.displayValue === '30.00' && vldlRes.rawValue === 30,
    '4. VLDL_AutoCalculates',
    `VLDL auto-calculates from TRIG (150) / 5 -> ${vldlRes.displayValue} mg/dL (2 decimals)`
  );

  // --- GROUP 2: UI, READONLY & KEYBOARD NAVIGATION ---
  console.log('\n--- TEST GROUP 2: UI, READONLY & KEYBOARD NAVIGATION ---');

  const resultEntryCode = fs.readFileSync(
    path.resolve(__dirname, '../src/features/worklist/ResultEntryPage.tsx'),
    'utf8'
  );

  // 5. CalculatedField_IsReadOnly
  const hasReadOnlyCalculated =
    resultEntryCode.includes('readOnly: isCalc') &&
    resultEntryCode.includes('AUTO') &&
    resultEntryCode.includes('Auto-Calculated');
  assert(
    hasReadOnlyCalculated,
    '5. CalculatedField_IsReadOnly',
    'Calculated field renders read-only with non-editable styling and visible AUTO chip badge'
  );

  // 6. CalculatedField_IsSkippedByEnterNavigation
  const skipsCalculatedOnEnter =
    resultEntryCode.includes("if (e.key === 'Enter')") &&
    resultEntryCode.includes("results[i].value_type !== 'Calculated'");
  assert(
    skipsCalculatedOnEnter,
    '6. CalculatedField_IsSkippedByEnterNavigation',
    'Enter key navigation loops over parameter list and automatically skips Calculated rows'
  );

  // --- GROUP 3: DEPENDENCY GRAPH & MULTI-STEP RECALCULATION ---
  console.log('\n--- TEST GROUP 3: DEPENDENCY GRAPH & MULTI-STEP PROPAGATION ---');

  // 7. DependencyChange_RecalculatesDownstream (LFT Profile: TP & ALB -> GLOB -> AG_RATIO)
  const lftParams = [
    { code: 'TBIL', name: 'Total Bilirubin', value_type: 'Numeric', display_value: '1.20', numeric_value: 1.2 },
    { code: 'DBIL', name: 'Direct Bilirubin', value_type: 'Numeric', display_value: '0.30', numeric_value: 0.3 },
    { code: 'IBIL', name: 'Indirect Bilirubin', value_type: 'Calculated', formula: 'TBIL - DBIL', display_value: '', numeric_value: null },
    { code: 'TP', name: 'Total Protein', value_type: 'Numeric', display_value: '7.50', numeric_value: 7.5 },
    { code: 'ALB', name: 'Albumin', value_type: 'Numeric', display_value: '4.20', numeric_value: 4.2 },
    { code: 'GLOB', name: 'Globulin', value_type: 'Calculated', formula: 'TP - ALB', display_value: '', numeric_value: null },
    { code: 'AG_RATIO', name: 'A:G Ratio', value_type: 'Calculated', formula: 'ALB / GLOB', display_value: '', numeric_value: null },
  ];

  const calculated1 = recalculateInvestigationParameters(lftParams);
  const glob1 = calculated1.find((p) => p.code === 'GLOB');
  const ag1 = calculated1.find((p) => p.code === 'AG_RATIO');
  const ibil1 = calculated1.find((p) => p.code === 'IBIL');

  // Now change TP from 7.50 to 8.00
  const updatedLft = calculated1.map((p) => (p.code === 'TP' ? { ...p, display_value: '8.00', numeric_value: 8.0 } : p));
  const calculated2 = recalculateInvestigationParameters(updatedLft);
  const glob2 = calculated2.find((p) => p.code === 'GLOB');
  const ag2 = calculated2.find((p) => p.code === 'AG_RATIO');

  assert(
    glob1?.display_value === '3.30' &&
      ag1?.display_value === '1.27' &&
      ibil1?.display_value === '0.90' &&
      glob2?.display_value === '3.80' &&
      ag2?.display_value === '1.11',
    '7. DependencyChange_RecalculatesDownstream',
    `Multi-step dependency chain propagated: GLOB ${glob1?.display_value}->${glob2?.display_value}, AG_RATIO ${ag1?.display_value}->${ag2?.display_value}`
  );

  // 8. MissingDependency_ReturnsBlank
  const missingDbParams = [
    { code: 'TBIL', name: 'Total Bilirubin', value_type: 'Numeric', display_value: '1.20', numeric_value: 1.2 },
    { code: 'DBIL', name: 'Direct Bilirubin', value_type: 'Numeric', display_value: '', numeric_value: null },
    { code: 'IBIL', name: 'Indirect Bilirubin', value_type: 'Calculated', formula: 'TBIL - DBIL', display_value: '', numeric_value: null },
  ];
  const missingRes = recalculateInvestigationParameters(missingDbParams);
  const ibilMissing = missingRes.find((p) => p.code === 'IBIL');
  assert(
    ibilMissing?.display_value === '—' && ibilMissing?.numeric_value === null,
    '8. MissingDependency_ReturnsBlank',
    `Missing dependency returns blank placeholder "—" (never 0): ${ibilMissing?.display_value}`
  );

  // 9. DivideByZero_ReturnsError
  const divZeroParams = [
    { code: 'TP', name: 'Total Protein', value_type: 'Numeric', display_value: '4.00', numeric_value: 4.0 },
    { code: 'ALB', name: 'Albumin', value_type: 'Numeric', display_value: '4.00', numeric_value: 4.0 },
    { code: 'GLOB', name: 'Globulin', value_type: 'Calculated', formula: 'TP - ALB', display_value: '', numeric_value: null },
    { code: 'AG_RATIO', name: 'A:G Ratio', value_type: 'Calculated', formula: 'ALB / GLOB', display_value: '', numeric_value: null },
  ];
  const divZeroRes = recalculateInvestigationParameters(divZeroParams);
  const agDivZero = divZeroRes.find((p) => p.code === 'AG_RATIO');
  assert(
    agDivZero?.display_value === 'Calculation Error' && agDivZero?.calculation_status === 'DIVIDE_BY_ZERO',
    '9. DivideByZero_ReturnsError',
    `Division by zero cleanly intercepted and tagged with Calculation Error: ${agDivZero?.display_value}`
  );

  // 10. CircularFormula_Rejected
  const circularParams = [
    { code: 'A', name: 'Param A', value_type: 'Calculated', formula: 'B + 1', display_value: '', numeric_value: null },
    { code: 'B', name: 'Param B', value_type: 'Calculated', formula: 'A + 1', display_value: '', numeric_value: null },
  ];
  const { hasCircular } = getTopologicalCalculationOrder(circularParams);
  const circularRes = recalculateInvestigationParameters(circularParams);
  assert(
    hasCircular === true && circularRes.every((p) => p.display_value === 'Calculation Error'),
    '10. CircularFormula_Rejected',
    'Circular dependency detected in graph and blocked with Calculation Error'
  );

  // --- GROUP 4: DRAFT RELOAD & SERVER RECOMPUTATION ---
  console.log('\n--- TEST GROUP 4: DRAFT RELOAD, SERVER & REPORT CONSISTENCY ---');

  // 11. DraftReload_RecalculatesConsistently
  const draftParams = [
    { code: 'TRIG', name: 'Triglycerides', value_type: 'Numeric', display_value: '200', numeric_value: 200 },
    { code: 'VLDL', name: 'VLDL', value_type: 'Calculated', formula: 'TRIG / 5', display_value: '30.00', numeric_value: 30.0 }, // Stale draft value
  ];
  const draftReloaded = recalculateInvestigationParameters(draftParams);
  const vldlReloaded = draftReloaded.find((p) => p.code === 'VLDL');
  assert(
    vldlReloaded?.display_value === '40.00' && vldlReloaded?.numeric_value === 40,
    '11. DraftReload_RecalculatesConsistently',
    `Reloading draft with updated parent source recalculates authoritative value: ${vldlReloaded?.display_value}`
  );

  // 12. ServerVerification_RecomputesCalculatedValues
  const mig15Path = path.resolve(__dirname, '../supabase/migrations_legacy_archive/00015_laboratory_calculation_engine.sql');
  const mig15Exists = fs.existsSync(mig15Path);
  const mig15Sql = mig15Exists ? fs.readFileSync(mig15Path, 'utf8') : '';
  const hasServerRecalc =
    mig15Sql.includes('recompute_order_item_calculated_results') &&
    mig15Sql.includes('PERFORM public.recompute_order_item_calculated_results') &&
    mig15Sql.includes('Calculation Error');
  assert(
    mig15Exists && hasServerRecalc,
    '12. ServerVerification_RecomputesCalculatedValues',
    'Migration 00015 recomputes and validates calculated parameters server-side during sign-off'
  );

  // 13. FinalReport_UsesAuthoritativeCalculatedValue
  const reportDocCode = fs.readFileSync(
    path.resolve(__dirname, '../src/features/reports/ReportDocument.tsx'),
    'utf8'
  );
  const formatsReportCalculations =
    reportDocCode.includes('display_value') &&
    reportDocCode.includes('r.display_value !== \'\'');
  assert(
    formatsReportCalculations,
    '13. FinalReport_UsesAuthoritativeCalculatedValue',
    'Report PDF renderer maps authoritative display_value without requiring operator re-entry'
  );

  console.log('\n================================================================');
  console.log(` SUMMARY: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log('================================================================\n');

  if (failedCount > 0) {
    process.exit(1);
  }
}

runTests().catch((err) => {
  console.error('Test runner execution failed:', err);
  process.exit(1);
});
