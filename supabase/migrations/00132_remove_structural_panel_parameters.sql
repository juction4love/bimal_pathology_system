-- Migration 00132: Remove Structural Panel Pseudo-Parameters from Master Catalogue
-- Purpose: Safely deactivate and archive dummy panel parameter rows (e.g. HEM-0001 / unit="Panel")
-- so that active result entry, calculation graphs, and reports operate exclusively on actual reportable leaf analytes.

BEGIN;

-- 1. Deactivate reference ranges for any dummy panel parameters (unit = 'Panel' or value_type = 'Panel' / 'Profile' or code = test_code on multi-parameter tests)
UPDATE public.reference_ranges
SET is_active = FALSE
WHERE parameter_id IN (
    SELECT p.id 
    FROM public.parameters p
    JOIN public.tests t ON t.id = p.test_id
    WHERE p.unit ILIKE 'Panel' 
       OR p.value_type::text ILIKE 'Panel' 
       OR p.value_type::text ILIKE 'Profile'
       OR (p.code = t.code AND (p.unit ILIKE 'Panel' OR p.name = t.name))
);

-- 2. Delete analyzer parameter mappings for any dummy panel parameters
DELETE FROM public.analyzer_parameter_mappings
WHERE parameter_id IN (
    SELECT p.id 
    FROM public.parameters p
    JOIN public.tests t ON t.id = p.test_id
    WHERE p.unit ILIKE 'Panel' 
       OR p.value_type::text ILIKE 'Panel' 
       OR p.value_type::text ILIKE 'Profile'
       OR (p.code = t.code AND (p.unit ILIKE 'Panel' OR p.name = t.name))
);

-- 3. Deactivate all dummy panel parameters from public.parameters
UPDATE public.parameters p
SET is_active = FALSE,
    lifecycle_status = 'Archived',
    updated_at = NOW()
FROM public.tests t
WHERE t.id = p.test_id
  AND (
    p.unit ILIKE 'Panel' 
    OR p.value_type::text ILIKE 'Panel' 
    OR p.value_type::text ILIKE 'Profile'
    OR (p.code = t.code AND (p.unit ILIKE 'Panel' OR p.name = t.name))
  );

-- 4. Specifically verify HEM-0001 (Complete Blood Count) retains strictly 24 active leaf parameters
DO $$
DECLARE
    v_cbc_id UUID;
    v_active_param_count INT;
BEGIN
    SELECT id INTO v_cbc_id FROM public.tests WHERE code = 'HEM-0001';
    IF v_cbc_id IS NOT NULL THEN
        -- Ensure any dummy parameter with code 'HEM-0001' under CBC is deactivated
        UPDATE public.parameters
        SET is_active = FALSE,
            lifecycle_status = 'Archived',
            updated_at = NOW()
        WHERE test_id = v_cbc_id AND code = 'HEM-0001';

        SELECT COUNT(*) INTO v_active_param_count
        FROM public.parameters
        WHERE test_id = v_cbc_id AND is_active = TRUE;

        IF v_active_param_count <> 24 THEN
            RAISE EXCEPTION 'HEM-0001 CBC active parameter count is % (expected 24 leaf parameters).', v_active_param_count USING ERRCODE = '23514';
        END IF;
    END IF;
END $$;

COMMIT;
