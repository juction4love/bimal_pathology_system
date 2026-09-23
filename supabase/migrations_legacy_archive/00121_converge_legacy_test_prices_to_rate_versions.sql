-- Migration: 00121_converge_legacy_test_prices_to_rate_versions.sql
-- Goal: Reconcile the 29 direct-price-only tests into canonical catalogue_rate_versions.
--
-- Invariants:
--  - Reconciles ONLY the verified 29 direct-price-only tests where tests.price_paisa > 0 and no active catalogue_rate_versions exists.
--  - Copies tests.price_paisa exactly (preserves integer paisa).
--  - Does NOT alter any existing rate amounts or prices in migrations 00114-00120.
--  - Does NOT modify historical bills, orders, or reports.
--  - Ensures idempotency and avoids duplicate or overlapping active rate versions.
--  - Ensures tests.price_configured = TRUE for canonical rate discovery.

BEGIN;

-- 1. Insert active rate-version records for the 29 direct-price-only tests
INSERT INTO public.catalogue_rate_versions (
  entity_type,
  test_id,
  version_number,
  price_paisa,
  effective_from,
  status
)
SELECT
  'Test'::public.catalogue_billable_entity_enum,
  t.id,
  COALESCE((SELECT MAX(r.version_number) + 1 FROM public.catalogue_rate_versions r WHERE r.test_id = t.id), 1),
  t.price_paisa,
  clock_timestamp(),
  'Active'
FROM public.tests t
WHERE t.price_paisa > 0
  AND t.code IN (
    'BIO-0001', 'BIO-0002', 'BIO-0003', 'BIO-0008', 'BIO-0009',
    'BIO-0010', 'BIO-0012', 'BIO-0037', 'BIO-0038', 'BIO-0041',
    'BIO-0043', 'BIO-0058', 'BIO-0059', 'CLP-0001', 'CLP-0021',
    'COA-0002', 'COA-0003', 'HEM-0001', 'HEM-0002', 'HEM-0006',
    'HEM-0026', 'HEM-0027', 'PRO-0001', 'PRO-0003', 'SER-0001',
    'SER-0004', 'SER-0010', 'SER-0016', 'SER-0086'
  )
  AND NOT EXISTS (
    SELECT 1 
    FROM public.catalogue_rate_versions r 
    WHERE r.test_id = t.id 
      AND r.status = 'Active' 
      AND (r.effective_to IS NULL OR r.effective_to > clock_timestamp())
  );

-- 2. Mark price_configured = TRUE and pricing_policy = 'Fixed' on tests table
UPDATE public.tests
SET 
  price_configured = TRUE,
  pricing_policy = 'Fixed',
  updated_at = clock_timestamp()
WHERE code IN (
    'BIO-0001', 'BIO-0002', 'BIO-0003', 'BIO-0008', 'BIO-0009',
    'BIO-0010', 'BIO-0012', 'BIO-0037', 'BIO-0038', 'BIO-0041',
    'BIO-0043', 'BIO-0058', 'BIO-0059', 'CLP-0001', 'CLP-0021',
    'COA-0002', 'COA-0003', 'HEM-0001', 'HEM-0002', 'HEM-0006',
    'HEM-0026', 'HEM-0027', 'PRO-0001', 'PRO-0003', 'SER-0001',
    'SER-0004', 'SER-0010', 'SER-0016', 'SER-0086'
  )
  AND (price_configured IS NOT TRUE OR pricing_policy IS DISTINCT FROM 'Fixed');

COMMIT;
