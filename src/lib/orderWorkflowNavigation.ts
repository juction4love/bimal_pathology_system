/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Centralized Smart Auto-Next Workflow Resolver (Phase 00092)
 * Evaluates authoritative order, sample, result, report-group, and outsource state
 * to determine the single highest-priority next actionable workflow step.
 */

import type { SupabaseClient } from '@supabase/supabase-js';

export type OrderNextActionKind =
  | 'COLLECT_SAMPLE'
  | 'RECEIVE_SAMPLE'
  | 'ACKNOWLEDGE_CRITICAL'
  | 'ENTER_RESULT'
  | 'VERIFY_RESULT'
  | 'SIGN_REPORT_GROUP'
  | 'OUTSOURCE_DISPATCH'
  | 'OUTSOURCE_REVIEW'
  | 'WAITING_EXTERNAL'
  | 'VIEW_REPORTS'
  | 'COMPLETE';

export interface OrderNextAction {
  kind: OrderNextActionKind;
  orderId: string;
  route: string;
  message: string;
  orderItemId?: string;
  reportGroupId?: string;
  sampleId?: string;
}

export type SampleState = {
  id: string;
  status: string;
  barcode?: string;
  recollected_from_sample_id?: string | null;
  created_at?: string;
};

export type WorkspaceRow = {
  report_group_id: string;
  order_id: string;
  group_key?: string | null;
  title?: string | null;
  clinical_section?: string | null;
  display_order?: number | null;
  lifecycle_state?: string | null;
  order_item_id: string;
  test_id?: string;
  frozen_test_code?: string;
  frozen_test_name?: string;
  item_display_order?: number | null;
  result_state?: string | null;
  sample_id?: string | null;
  sample_state?: string | null;
  latest_report_id?: string | null;
  latest_report_version?: number | null;
  report_state?: string | null;
  pdf_state?: string | null;
  execution_route?: 'INTERNAL' | 'OUTSOURCE' | null;
  outsource_state?: string | null;
  outsource_lab_name?: string | null;
};

export type ClinicalItemState = {
  id: string;
  order_id?: string;
  status?: string;
  results?: Array<{
    id?: string;
    is_critical?: boolean;
    critical_acknowledged?: boolean;
    status?: string;
  }>;
};

export const itemRoute = (orderId: string, itemId: string, extra = '') =>
  `/worklist/order/${encodeURIComponent(orderId)}?item=${encodeURIComponent(itemId)}${extra}`;

export const sampleRoute = (orderId: string, orderNumber: string, stage: 'collect' | 'receive', sampleId?: string) =>
  `/samples?orderId=${encodeURIComponent(orderId)}&search=${encodeURIComponent(orderNumber)}&stage=${stage}${sampleId ? `&sampleId=${encodeURIComponent(sampleId)}` : ''}`;

export const outsourceRoute = (orderId: string, itemId?: string, action?: 'dispatch' | 'review') =>
  `/outsource?orderId=${encodeURIComponent(orderId)}${itemId ? `&item=${encodeURIComponent(itemId)}` : ''}${action ? `&action=${encodeURIComponent(action)}` : ''}`;

export const reportsRoute = (orderId: string) =>
  `/reports?orderId=${encodeURIComponent(orderId)}`;

export const firstByOrder = (rows: WorkspaceRow[]): WorkspaceRow[] =>
  [...rows].sort((a, b) =>
    Number(a.display_order ?? 0) - Number(b.display_order ?? 0) ||
    Number(a.item_display_order ?? 0) - Number(b.item_display_order ?? 0)
  );

/**
 * Resolves the highest-priority actionable order_item_id from workspace rows
 * when an order workspace is loaded without an explicit ?item= parameter.
 */
export function getHighestPriorityOrderItem(
  rows: WorkspaceRow[],
  clinicalItems: ClinicalItemState[] = [],
): string | null {
  if (!rows || rows.length === 0) return null;
  const ordered = firstByOrder(rows);

  // 1. Critical unacknowledged item
  const criticalItem = ordered.find((row) => {
    const item = clinicalItems.find((c) => c.id === row.order_item_id);
    return item?.results?.some((r) => r.is_critical && !r.critical_acknowledged);
  });
  if (criticalItem) return criticalItem.order_item_id;

  // 2. Actionable internal result entry (Draft / Returned / not yet submitted)
  const internalEntry = ordered.find(
    (row) =>
      row.execution_route !== 'OUTSOURCE' &&
      !['SubmittedForVerification', 'Verified', 'SignedOff'].includes(row.result_state || '')
  );
  if (internalEntry) return internalEntry.order_item_id;

  // 3. Actionable internal verification
  const internalVerify = ordered.find(
    (row) =>
      row.execution_route !== 'OUTSOURCE' &&
      row.result_state === 'SubmittedForVerification'
  );
  if (internalVerify) return internalVerify.order_item_id;

  // 4. Outsource items needing review
  const outsourceReview = ordered.find(
    (row) =>
      row.execution_route === 'OUTSOURCE' &&
      ['ResultReceived', 'InternalReview'].includes(row.outsource_state || '')
  );
  if (outsourceReview) return outsourceReview.order_item_id;

  // 5. Outsource items needing dispatch
  const outsourceDispatch = ordered.find(
    (row) =>
      row.execution_route === 'OUTSOURCE' &&
      ['AwaitingDispatch', 'RecollectionRequired'].includes(row.outsource_state || '')
  );
  if (outsourceDispatch) return outsourceDispatch.order_item_id;

  // 6. Default to first investigation in display order
  return ordered[0].order_item_id;
}

/**
 * Computes progress metrics for the persistent order context header.
 */
export function getOrderProgressMetrics(rows: WorkspaceRow[]) {
  const totalItems = rows.length;
  const completedItems = rows.filter((r) =>
    ['Verified', 'SignedOff'].includes(r.result_state || '')
  ).length;

  const groupMap = new Map<string, WorkspaceRow>();
  for (const row of rows) {
    if (row.report_group_id && !groupMap.has(row.report_group_id)) {
      groupMap.set(row.report_group_id, row);
    }
  }
  const totalGroups = groupMap.size;
  const signedGroups = [...groupMap.values()].filter((g) =>
    ['SignedOff', 'Amended'].includes(g.report_state || '')
  ).length;

  return {
    totalItems,
    completedItems,
    totalGroups,
    signedGroups,
    isFullyComplete: totalGroups > 0 && signedGroups === totalGroups,
  };
}

/**
 * Centralized Server-State-Aware Next-Action Resolver
 * Evaluates authoritative order state in strict clinical priority:
 *
 * 1. COLLECT_SAMPLE (including recollection)
 * 2. RECEIVE_SAMPLE (collected specimen awaiting lab receipt)
 * 3. ACKNOWLEDGE_CRITICAL (unacknowledged panic alert)
 * 4. ENTER_RESULT (internal bench result entry)
 * 5. VERIFY_RESULT (submitted results awaiting verification)
 * 6. SIGN_REPORT_GROUP (report group ready for sign-off)
 * 7. OUTSOURCE_DISPATCH (outsource items ready for dispatch)
 * 8. OUTSOURCE_REVIEW (external result received and requiring review)
 * 9. WAITING_EXTERNAL (all internal complete, waiting on outsource results)
 * 10. VIEW_REPORTS / COMPLETE (all report groups finalized)
 */
export async function getNextOrderAction(
  client: SupabaseClient,
  orderId: string,
): Promise<OrderNextAction> {
  const [
    { data: sampleData, error: sampleError },
    { data: workspaceData, error: workspaceError },
    { data: itemData, error: itemError },
    { data: orderData, error: orderError },
  ] = await Promise.all([
    client
      .from('samples')
      .select('id,barcode,status,recollected_from_sample_id,created_at')
      .eq('order_id', orderId)
      .order('created_at'),
    client
      .from('order_report_group_workspace' as never)
      .select('*')
      .eq('order_id', orderId)
      .order('display_order')
      .order('item_display_order'),
    client
      .from('clinical_order_items')
      .select('id,order_id,status,results:test_results(id,is_critical,critical_acknowledged,status)')
      .eq('order_id', orderId),
    client
      .from('clinical_orders')
      .select('id,order_number')
      .eq('id', orderId)
      .maybeSingle(),
  ]);

  if (sampleError) throw sampleError;
  if (workspaceError) throw workspaceError;
  if (itemError) throw itemError;
  if (orderError) throw orderError;

  const orderNumber = String(orderData?.order_number || '');
  const samples = (sampleData || []) as SampleState[];
  const rows = firstByOrder((workspaceData || []) as unknown as WorkspaceRow[]);
  const clinicalItems = (itemData || []) as ClinicalItemState[];

  // -------------------------------------------------------------
  // 1. COLLECT_SAMPLE (Prioritize recollection samples first)
  // -------------------------------------------------------------
  const recollectionSample = samples.find(
    (sample) => sample.status === 'Pending' && sample.recollected_from_sample_id
  );
  const pendingSample =
    recollectionSample || samples.find((sample) => sample.status === 'Pending');

  if (pendingSample) {
    return {
      kind: 'COLLECT_SAMPLE',
      orderId,
      sampleId: pendingSample.id,
      route: sampleRoute(orderId, orderNumber, 'collect', pendingSample.id),
      message: recollectionSample
        ? 'Recollection required — opening Sample Collection…'
        : 'Bill created — opening Sample Collection…',
    };
  }

  // -------------------------------------------------------------
  // 2. RECEIVE_SAMPLE (Collected specimen awaiting lab accessioning)
  // -------------------------------------------------------------
  const collectedSample = samples.find((sample) => sample.status === 'Collected');
  if (collectedSample) {
    return {
      kind: 'RECEIVE_SAMPLE',
      orderId,
      sampleId: collectedSample.id,
      route: sampleRoute(orderId, orderNumber, 'receive', collectedSample.id),
      message: 'Sample collected — opening Lab Receipt…',
    };
  }

  // -------------------------------------------------------------
  // 3. ACKNOWLEDGE_CRITICAL (Unresolved panic alerts on entered results)
  // -------------------------------------------------------------
  const criticalItem = clinicalItems.find((item) =>
    item.results?.some((result) => result.is_critical && !result.critical_acknowledged)
  );
  if (criticalItem) {
    return {
      kind: 'ACKNOWLEDGE_CRITICAL',
      orderId,
      orderItemId: criticalItem.id,
      route: itemRoute(orderId, criticalItem.id, '&action=critical'),
      message: 'Critical panic value requires clinician notification & acknowledgement…',
    };
  }

  // -------------------------------------------------------------
  // 4. SIGN_REPORT_GROUP (Report groups whose items are fully ready)
  // -------------------------------------------------------------
  const groupMap = new Map<string, WorkspaceRow>();
  for (const row of rows) {
    if (row.report_group_id && !groupMap.has(row.report_group_id)) {
      groupMap.set(row.report_group_id, row);
    }
  }
  const groups = [...groupMap.values()];

  for (const group of groups) {
    if (group.report_state === 'SignedOff' || group.report_state === 'Amended') {
      continue;
    }
    const { data: readyData, error: readyErr } = await client.rpc(
      'check_report_group_readiness',
      { p_report_group_id: group.report_group_id }
    );
    if (readyErr) throw readyErr;

    if (readyData?.is_ready) {
      return {
        kind: 'SIGN_REPORT_GROUP',
        orderId,
        orderItemId: group.order_item_id,
        reportGroupId: group.report_group_id,
        route: itemRoute(
          orderId,
          group.order_item_id,
          `&action=sign&group=${encodeURIComponent(group.report_group_id)}`
        ),
        message: `${group.title || 'Report group'} is verified & ready — opening sign-off…`,
      };
    }
  }

  // -------------------------------------------------------------
  // 5. VERIFY_RESULT (Results submitted for verification)
  // -------------------------------------------------------------
  const internalRows = rows.filter((row) => row.execution_route !== 'OUTSOURCE');
  const verifyReady = internalRows.find(
    (row) => row.result_state === 'SubmittedForVerification'
  );
  if (verifyReady) {
    return {
      kind: 'VERIFY_RESULT',
      orderId,
      orderItemId: verifyReady.order_item_id,
      route: itemRoute(orderId, verifyReady.order_item_id, '&action=verify'),
      message: 'Opening investigation awaiting pathologist verification…',
    };
  }

  // -------------------------------------------------------------
  // 6. ENTER_RESULT (Actionable internal bench work)
  // -------------------------------------------------------------
  const resultReady = internalRows.find(
    (row) =>
      !['SubmittedForVerification', 'Verified', 'SignedOff'].includes(
        row.result_state || ''
      )
  );
  if (resultReady) {
    return {
      kind: 'ENTER_RESULT',
      orderId,
      orderItemId: resultReady.order_item_id,
      route: itemRoute(orderId, resultReady.order_item_id),
      message: 'Opening next investigation for result entry…',
    };
  }

  // -------------------------------------------------------------
  // 7. OUTSOURCE_DISPATCH (Outsource items ready for dispatch)
  // (Actionable internal bench work took priority above)
  // -------------------------------------------------------------
  const outsourceDispatch = rows.find(
    (row) =>
      row.execution_route === 'OUTSOURCE' &&
      ['AwaitingDispatch', 'RecollectionRequired'].includes(row.outsource_state || '')
  );
  if (outsourceDispatch) {
    return {
      kind: 'OUTSOURCE_DISPATCH',
      orderId,
      orderItemId: outsourceDispatch.order_item_id,
      route: outsourceRoute(orderId, outsourceDispatch.order_item_id, 'dispatch'),
      message: 'Internal work complete — opening Outsource Tracking for dispatch…',
    };
  }

  // -------------------------------------------------------------
  // 8. OUTSOURCE_REVIEW (External result received, awaiting review/verify)
  // -------------------------------------------------------------
  const outsourceReview = rows.find(
    (row) =>
      row.execution_route === 'OUTSOURCE' &&
      ['ResultReceived', 'InternalReview'].includes(row.outsource_state || '')
  );
  if (outsourceReview) {
    return {
      kind: 'OUTSOURCE_REVIEW',
      orderId,
      orderItemId: outsourceReview.order_item_id,
      route: outsourceRoute(orderId, outsourceReview.order_item_id, 'review'),
      message: 'External result received — opening internal review…',
    };
  }

  // -------------------------------------------------------------
  // 9. Check All Groups Finalized vs Outsource Waiting
  // -------------------------------------------------------------
  const allGroupsFinalized =
    groups.length > 0 &&
    groups.every((group) =>
      ['SignedOff', 'Amended'].includes(group.report_state || '')
    );

  if (allGroupsFinalized) {
    return {
      kind: 'VIEW_REPORTS',
      orderId,
      route: reportsRoute(orderId),
      message: 'Order completed — opening Reports & Delivery Summary…',
    };
  }

  const outsourceWaiting = rows.find(
    (row) =>
      row.execution_route === 'OUTSOURCE' &&
      ['Dispatched', 'AwaitingExternalResult', 'ProcessingAtReferenceLab'].includes(
        row.outsource_state || ''
      )
  );

  if (outsourceWaiting) {
    return {
      kind: 'WAITING_EXTERNAL',
      orderId,
      orderItemId: outsourceWaiting.order_item_id,
      route: itemRoute(orderId, outsourceWaiting.order_item_id, '&summary=waiting'),
      message: 'Internal investigations complete; awaiting external reference lab results.',
    };
  }

  // -------------------------------------------------------------
  // 10. Fallback / COMPLETE
  // -------------------------------------------------------------
  return {
    kind: 'COMPLETE',
    orderId,
    route: reportsRoute(orderId),
    message: 'Opening Order Delivery Summary…',
  };
}

/**
 * Schedules a delayed navigation with concise toast feedback.
 * Returns a cancellation handle.
 */
export function scheduleOrderNavigation(
  navigate: (route: string) => void,
  action: OrderNextAction,
  delayMs = 650
): number {
  return window.setTimeout(() => {
    navigate(action.route);
  }, delayMs);
}
