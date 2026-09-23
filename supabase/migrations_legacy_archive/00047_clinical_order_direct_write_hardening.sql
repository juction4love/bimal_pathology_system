-- Close the remaining browser-table bypass around the transactional clinical
-- order workflow. All legitimate writes already execute inside the billing,
-- sample lifecycle, secured result, and report sign-off SECURITY DEFINER RPCs.

DROP POLICY IF EXISTS "clinical_orders_insert" ON public.clinical_orders;
DROP POLICY IF EXISTS "clinical_orders_update" ON public.clinical_orders;
DROP POLICY IF EXISTS "clinical_order_items_insert" ON public.clinical_order_items;
DROP POLICY IF EXISTS "clinical_order_items_update" ON public.clinical_order_items;

REVOKE INSERT, UPDATE, DELETE ON public.clinical_orders FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON public.clinical_order_items FROM authenticated, anon;

-- Diagnostic report rows have no supported browser-authored Draft workflow.
-- Keep all report mutations behind the existing guarded server functions.
DROP POLICY IF EXISTS "diagnostic_reports_update_draft" ON public.diagnostic_reports;
REVOKE UPDATE, DELETE ON public.diagnostic_reports FROM authenticated, anon;

-- Retire the pre-00046 acknowledgement RPC. It predates signed-result state
-- enforcement and could update a result row by UUID after sign-off. The current
-- UI uses record_critical_value_acknowledgement plus save_test_results.
REVOKE ALL ON FUNCTION public.acknowledge_critical_result(UUID, VARCHAR, VARCHAR, TEXT)
FROM PUBLIC, anon, authenticated;
DROP FUNCTION public.acknowledge_critical_result(UUID, VARCHAR, VARCHAR, TEXT);

-- Calculation recomputation is an internal sign-off helper. Leaving the
-- SECURITY DEFINER helper executable by PUBLIC would allow direct mutation of
-- calculated result rows outside save_test_results/sign-off.
REVOKE ALL ON FUNCTION public.recompute_order_item_calculated_results(UUID)
FROM PUBLIC, anon, authenticated;

-- The legacy artifact attachment RPC accepts a caller-supplied path and hash
-- and can rewrite a signed report integrity hash. No current client or trusted
-- PDF producer uses it; retire it instead of preserving an unsafe capability.
REVOKE ALL ON FUNCTION public.attach_report_artifact(UUID, TEXT, VARCHAR)
FROM PUBLIC, anon, authenticated;
DROP FUNCTION public.attach_report_artifact(UUID, TEXT, VARCHAR);

COMMENT ON TABLE public.clinical_orders IS
  'Clinical order header. Browser roles are read-only; mutations are RPC-only.';
COMMENT ON TABLE public.clinical_order_items IS
  'Clinical order investigation rows. Browser roles are read-only; mutations are RPC-only.';
