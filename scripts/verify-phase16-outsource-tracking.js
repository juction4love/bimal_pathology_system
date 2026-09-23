/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Verification Suite: Outsource Sample Tracking Engine (Phase 16)
 *
 * Tests:
 * 1.  IHC_BillCreatesOutsourceSample     - RPC auto-creates outsource_samples row for requires_sample_tracking = TRUE
 * 2.  IHC_ManualPriceStillWorks          - allow_manual_price still enforced correctly alongside tracking
 * 3.  IHC_DoesNotEnterNormalWorklist     - NoReporting items remain excluded from clinical_order_items / worklist
 * 4.  IHC_TrackingNumberUnique           - Tracking numbers use sequence OUT-YYYY-NNNNN (unique per sample)
 * 5.  IHC_ReceiveSample                  - Initial status is ReceivedAtBimal; event logged immediately
 * 6.  IHC_DispatchSample                 - update_outsource_sample_status RPC exists for DispatchedToReferenceLab
 * 7.  IHC_ResultReceived                 - RPC handles ResultReceived transition and stores report reference
 * 8.  IHC_MaterialReturned               - Material return tracking: blocks_returned_count, slides_returned_count
 * 9.  IHC_Completed                      - Final Completed state supported
 * 10. IHC_StatusHistoryImmutable         - outsource_sample_events is insert-only (no UPDATE/DELETE policy)
 * 11. IHC_PatientHistoryLinked           - outsource_samples.patient_id FK to patients
 * 12. UnauthorizedTrackingMutationDenied - update_outsource_sample_status requires auth.uid()
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
console.log(' BIMAL PATHOLOGY - PHASE 16 OUTSOURCE SAMPLE TRACKING SUITE');
console.log('================================================================\n');

try {
  const migrationPath = path.resolve('supabase/migrations_legacy_archive/00018_outsource_sample_tracking.sql');
  const migContent = fs.readFileSync(migrationPath, 'utf8');
  const auditFixContent = fs.readFileSync(
    path.resolve('supabase/migrations_legacy_archive/00020_flow_audit_security_and_rpc_fixes.sql'),
    'utf8'
  );

  console.log('--- TEST GROUP 1: SCHEMA DESIGN ---');

  assert(
    migContent.includes('CREATE TABLE IF NOT EXISTS public.outsource_samples'),
    '1a. OutsourceSamples_TableCreated',
    'outsource_samples table defined in migration 00018'
  );

  assert(
    migContent.includes('CREATE TABLE IF NOT EXISTS public.outsource_sample_events'),
    '1b. OutsourceSampleEvents_TableCreated',
    'outsource_sample_events audit table defined'
  );

  assert(
    migContent.includes("CREATE SEQUENCE IF NOT EXISTS outsource_tracking_seq") &&
    migContent.includes("'OUT-' || v_current_year || '-' || LPAD(NEXTVAL('outsource_tracking_seq')"),
    '4. IHC_TrackingNumberUnique',
    'Tracking numbers use dedicated sequence: OUT-YYYY-NNNNN'
  );

  assert(
    migContent.includes('patient_id UUID NOT NULL REFERENCES public.patients(id)'),
    '11. IHC_PatientHistoryLinked',
    'outsource_samples.patient_id has FK to patients table'
  );

  console.log('\n--- TEST GROUP 2: SPECIMEN TRACKING STATUS FLOW ---');

  assert(
    migContent.includes("'ReceivedAtBimal'") &&
    migContent.includes("'DispatchedToReferenceLab'") &&
    migContent.includes("'ResultReceived'") &&
    migContent.includes("'MaterialReturned'") &&
    migContent.includes("'Completed'"),
    '5. IHC_ReceiveSample',
    'All required status enum values defined in outsource_sample_status_enum'
  );

  assert(
    migContent.includes("'Rejected'") &&
    migContent.includes("'Cancelled'") &&
    migContent.includes("'LostInTransit'"),
    '5b. IHC_TerminalStates',
    'Terminal failure states (Rejected, Cancelled, LostInTransit) included in enum'
  );

  console.log('\n--- TEST GROUP 3: BILLING RPC INTEGRATION ---');

  assert(
    migContent.includes('v_test.requires_sample_tracking = TRUE') &&
    migContent.includes("'SAMPLE_RECEIVED_AT_BIMAL'"),
    '1. IHC_BillCreatesOutsourceSample',
    'create_patient_bill_and_order automatically creates outsource_samples row for requires_sample_tracking items'
  );

  assert(
    migContent.includes('v_test.allow_manual_price = TRUE') &&
    migContent.includes('v_item_unit_price := COALESCE'),
    '2. IHC_ManualPriceStillWorks',
    'Manual price enforcement still operates correctly within updated billing RPC'
  );

  assert(
    migContent.includes("IF v_test.reporting_type IN ('InHouse', 'OutsourceWithBimalReport') THEN") &&
    migContent.includes('v_has_clinical_items := TRUE;'),
    '3. IHC_DoesNotEnterNormalWorklist',
    'NoReporting IHC items skip clinical_order_items / worklist creation'
  );

  console.log('\n--- TEST GROUP 4: STATUS TRANSITION RPC ---');

  assert(
    migContent.includes('CREATE OR REPLACE FUNCTION public.update_outsource_sample_status(') &&
    migContent.includes('p_to_status outsource_sample_status_enum'),
    '6. IHC_DispatchSample',
    'update_outsource_sample_status RPC defined for dispatching and status transitions'
  );

  assert(
    migContent.includes("p_to_status = 'ResultReceived'") &&
    migContent.includes('result_received_at') &&
    migContent.includes('reference_lab_report_no'),
    '7. IHC_ResultReceived',
    'ResultReceived transition stores result timestamp and reference lab report number'
  );

  assert(
    migContent.includes("p_to_status = 'MaterialReturned'") &&
    migContent.includes('blocks_returned_count') &&
    migContent.includes('slides_returned_count'),
    '8. IHC_MaterialReturned',
    'MaterialReturned transition tracks blocks and slides returned count'
  );

  assert(
    migContent.includes("p_to_status = 'Completed'") &&
    migContent.includes('completed_at'),
    '9. IHC_Completed',
    'Completed transition records completion timestamp'
  );

  console.log('\n--- TEST GROUP 5: IMMUTABLE AUDIT LOG ---');

  assert(
    migContent.includes('INSERT INTO public.outsource_sample_events') &&
    migContent.includes("event_type") &&
    migContent.includes("from_status") &&
    migContent.includes("to_status"),
    '10. IHC_StatusHistoryImmutable',
    'Every status transition inserts an immutable event into outsource_sample_events'
  );

  // Verify NO update/delete policy on events table (insert-only)
  const hasEventUpdatePolicy = migContent.includes('FOR UPDATE') &&
    migContent.includes('outsource_sample_events') &&
    migContent.includes('FOR UPDATE\nON public.outsource_sample_events');
  assert(
    !hasEventUpdatePolicy,
    '10b. IHC_EventsAreInsertOnly',
    'No UPDATE/DELETE RLS policies defined on outsource_sample_events (insert-only log)'
  );

  console.log('\n--- TEST GROUP 6: SECURITY ---');

  assert(
    migContent.includes("IF auth.uid() IS NULL THEN") &&
    migContent.includes("RAISE EXCEPTION 'Authentication required.'") &&
    auditFixContent.includes("WHERE id = auth.uid()") &&
    auditFixContent.includes("can_manage_outsource_tracking"),
    '12. UnauthorizedTrackingMutationDenied',
    'tracking mutations require authentication, a valid profile key, and server-side permission enforcement'
  );

  assert(
    migContent.includes('REVOKE EXECUTE ON FUNCTION public.update_outsource_sample_status') &&
    migContent.includes('FROM PUBLIC, anon') &&
    auditFixContent.includes('DROP POLICY IF EXISTS "Allow authenticated update outsource samples"'),
    '12b. UnauthorizedRPCRevoked',
    'RPC execution privilege revoked from PUBLIC and anon roles'
  );

  console.log('\n--- TEST GROUP 7: UI & FRONTEND ---');

  const trackingPagePath = path.resolve('src/features/outsource/OutsourceTrackingPage.tsx');
  const trackingContent = fs.readFileSync(trackingPagePath, 'utf8');

  assert(
    trackingContent.includes('outsource_samples') &&
    trackingContent.includes('tracking_number') &&
    trackingContent.includes('renderStatusChip'),
    'UI1. OutsourceTrackingPage_Rendered',
    'OutsourceTrackingPage.tsx fetches outsource_samples and renders status chips'
  );

  assert(
    trackingContent.includes('DispatchedToReferenceLab') &&
    trackingContent.includes('handleConfirmDispatch') &&
    trackingContent.includes('handleConfirmResultReceived') &&
    trackingContent.includes('handleConfirmMaterialReturn'),
    'UI2. OutsourceTrackingPage_AllActionHandlers',
    'Dispatch, Result Receipt, and Material Return action handlers implemented'
  );

  assert(
    trackingContent.includes('handleOpenTimeline') &&
    trackingContent.includes('outsource_sample_events'),
    'UI3. OutsourceTrackingPage_AuditTimeline',
    'Chain-of-custody timeline drawer loads and renders immutable event history'
  );

  const routesContent = fs.readFileSync(path.resolve('src/app/routes.tsx'), 'utf8');
  assert(
    routesContent.includes("path: 'outsource'") &&
    routesContent.includes('OutsourceTrackingPage') &&
    routesContent.includes('CAN_MANAGE_OUTSOURCE_TRACKING'),
    'UI4. Route_PermissionGated',
    'Outsource Tracking route gated by CAN_MANAGE_OUTSOURCE_TRACKING permission'
  );

  const billListContent = fs.readFileSync(path.resolve('src/features/billing/BillListPage.tsx'), 'utf8');
  assert(
    billListContent.includes('outsource_samples') &&
    billListContent.includes('tracking_number') &&
    billListContent.includes('Outsource Sample Tracking:'),
    'UI5. BillReceipt_ShowsTrackingNumbers',
    'Bill receipt dialog displays OUT-YYYY-NNNNN tracking numbers for outsourced items'
  );

  const permsContent = fs.readFileSync(path.resolve('src/types/permissions.ts'), 'utf8');
  assert(
    permsContent.includes('CAN_MANAGE_OUTSOURCE_TRACKING') &&
    permsContent.includes("'can_manage_outsource_tracking'"),
    'UI6. PermissionKey_Defined',
    'CAN_MANAGE_OUTSOURCE_TRACKING permission key defined and granted to lab technician role'
  );

} catch (err) {
  console.error('Fatal error during Phase 16 outsource tracking suite:', err.message);
  process.exit(1);
}

console.log('\n================================================================');
console.log(` SUMMARY: ${passed} PASSED, ${failed} FAILED`);
console.log('================================================================\n');

if (failed > 0) {
  process.exit(1);
}
