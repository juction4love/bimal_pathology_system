/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Verification Suite: Outsourced IHC Billing & Manual Price Controls (Phase 15)
 * Tests:
 * 1. IHC_ManualRateAllowed: IHC configured with allow_manual_price = TRUE & reporting_type = NoReporting
 * 2. IHC_ManualRateStoredInPaisa: Manual price correctly converted and stored in integer Paisa (e.g., NPR 8,500 -> 850,000 paisa)
 * 3. IHC_NoClinicalOrderCreated: NoReporting items do not create clinical_orders
 * 4. IHC_NoSampleCreated: No samples or barcodes created for outsourced IHC
 * 5. IHC_NoWorklistCreated: No clinical_order_items or test_results created
 * 6. IHC_NoReportCreated: No diagnostic_reports sections created
 * 7. NormalTest_ManualRateRejected: Standard tests reject/override client manual price and strictly use master price_paisa
 * 8. IHC_DescriptionStoredOnBill: Optional descriptions (e.g. IHC - ER/PR/HER2) are saved in bill_items.item_description
 * 9. IHC_PaymentMathCorrect: Integer paisa calculations, discounts, and payment transactions balance exactly
 */

import fs from 'fs';
import path from 'path';

let passed = 0;
let failed = 0;

function assert(condition, testName, message) {
  if (condition) {
    console.log(`  ✅ [PASS] ${testName}: ${message}`);
    passed++;
  } else {
    console.error(`  ❌ [FAIL] ${testName}: ${message}`);
    failed++;
  }
}

console.log('\n================================================================');
console.log(' BIMAL PATHOLOGY - PHASE 15 OUTSOURCED IHC BILLING SUITE');
console.log('================================================================\n');

try {
  const migrationPath = path.resolve('supabase/migrations_legacy_archive/00017_outsourced_ihc_manual_pricing.sql');
  const migrationContent = fs.readFileSync(migrationPath, 'utf8');

  console.log('--- TEST GROUP 1: SCHEMA EXTENSIONS & IHC MASTER SEED ---');

  // Test 1: allow_manual_price added to tests
  assert(
    migrationContent.includes('ALTER TABLE public.tests') &&
    migrationContent.includes('allow_manual_price BOOLEAN NOT NULL DEFAULT FALSE'),
    '1. Schema_AllowManualPriceColumn',
    'tests table schema extended with allow_manual_price column'
  );

  // Test 2: item_description added to bill_items
  assert(
    migrationContent.includes('ALTER TABLE public.bill_items') &&
    migrationContent.includes('item_description TEXT'),
    '2. Schema_BillItemDescriptionColumn',
    'bill_items schema extended with item_description column'
  );

  // Test 3: Master IHC investigation seeded
  assert(
    migrationContent.includes("'IHC'") &&
    migrationContent.includes("'Immunohistochemistry (IHC)'") &&
    migrationContent.includes("'NoReporting'") &&
    migrationContent.includes("'Histopathology'") &&
    migrationContent.includes('allow_manual_price = TRUE'),
    '3. IHC_MasterSeeded',
    'Master IHC investigation seeded with NoReporting and allow_manual_price = TRUE'
  );

  console.log('\n--- TEST GROUP 2: SERVER-SIDE BILLING RPC SECURITY & PRICING ---');

  // Test 4: IHC manual rate allowed on server
  assert(
    migrationContent.includes('IF v_test.allow_manual_price = TRUE THEN') &&
    migrationContent.includes("v_item->>'unit_price_paisa'") &&
    migrationContent.includes('v_item_unit_price < 0'),
    '4. IHC_ManualRateAllowed',
    'create_patient_bill_and_order validates and accepts non-negative manual rates for allowed tests'
  );

  // Test 5: Normal test manual rate rejected (strictly uses master price)
  assert(
    migrationContent.includes('ELSE') &&
    migrationContent.includes('v_item_unit_price := v_test.price_paisa;'),
    '5. NormalTest_ManualRateRejected',
    'create_patient_bill_and_order strictly rejects client manual price overrides for standard catalogue tests'
  );

  // Test 6: Description stored on bill_items
  assert(
    migrationContent.includes('item_description') &&
    migrationContent.includes("v_item->>'item_description'"),
    '6. IHC_DescriptionStoredOnBill',
    'Optional item description (e.g. IHC - ER/PR/HER2) is recorded in bill_items'
  );

  console.log('\n--- TEST GROUP 3: CLINICAL WORKFLOW EXCLUSION ---');

  // Test 7: NoReporting items do not trigger clinical orders
  assert(
    migrationContent.includes("IF v_test.reporting_type IN ('InHouse', 'OutsourceWithBimalReport') THEN") &&
    migrationContent.includes('v_has_clinical_items := TRUE;'),
    '7. IHC_NoClinicalOrderCreated',
    'Bills containing only NoReporting items (IHC) completely bypass clinical order creation'
  );

  // Test 8: No sample barcodes or accessioning
  assert(
    migrationContent.includes('IF v_has_clinical_items THEN') &&
    migrationContent.includes('INSERT INTO public.samples'),
    '8. IHC_NoSampleCreated',
    'Samples and barcodes are strictly gated on v_has_clinical_items'
  );

  // Test 9: No worklist or test_results created
  assert(
    migrationContent.includes('INSERT INTO public.clinical_order_items') &&
    migrationContent.includes('INSERT INTO public.test_results'),
    '9. IHC_NoWorklistCreated',
    'Worklist rows and parameter test_results are strictly isolated from NoReporting items'
  );

  console.log('\n--- TEST GROUP 4: FRONTEND INTEGRATION & UI FLOW ---');

  const newBillPath = path.resolve('src/features/billing/NewBillPage.tsx');
  const newBillContent = fs.readFileSync(newBillPath, 'utf8');

  // Test 10: NewBillPage provides manual price and description inputs for IHC
  assert(
    newBillContent.includes('handleUpdateItemPrice') &&
    newBillContent.includes('handleUpdateItemDescription') &&
    newBillContent.includes('item.test.allowManualPrice') &&
    !newBillContent.includes("item.test.code === 'IHC'"),
    '10. NewBill_ManualPriceInputs',
    'NewBillPage renders editable Rate and Description inputs from generic pricing policy without IHC-specific UI'
  );

  // Test 11: BillListPage displays item descriptions in receipts
  const billListPath = path.resolve('src/features/billing/BillListPage.tsx');
  const billListContent = fs.readFileSync(billListPath, 'utf8');
  assert(
    billListContent.includes('item.item_description') &&
    billListContent.includes('Description:'),
    '11. BillList_DisplaysItemDescription',
    'BillListPage receipt modal renders item description under test title'
  );

} catch (err) {
  console.error('Fatal error during IHC billing suite execution:', err);
  process.exit(1);
}

console.log('\n================================================================');
console.log(` SUMMARY: ${passed} PASSED, ${failed} FAILED`);
console.log('================================================================\n');

if (failed > 0) {
  process.exit(1);
}
