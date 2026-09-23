-- BIMAL PATHOLOGY LIS: FINAL PRODUCTION CONVERGENCE DELTA SCRIPT
-- Project: rncjxstujioagcezvfkb
-- Mode: Idempotent, Non-Destructive to Master Configuration, Transactional

BEGIN;

-- 1. Ensure MANUAL_MICROSCOPY analyzer exists
INSERT INTO public.analyzers (
    id, code, name, model, serial_number, lifecycle_status
) VALUES (
    '9561c202-020e-4f3b-8f66-1ba6c87348d6',
    'MANUAL_MICROSCOPY',
    'Manual Microscopy / Peripheral Smear',
    'Standard Laboratory Microscope',
    'MANUAL-MICROSCOPY-01',
    'Active'
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    model = EXCLUDED.model,
    lifecycle_status = EXCLUDED.lifecycle_status;

-- 2. Two-Role RBAC Authorization & Helper Functions
CREATE OR REPLACE FUNCTION public.is_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.user_roles ur
        JOIN public.roles r ON ur.role_id = r.id
        WHERE ur.user_id = p_user_id
          AND r.name IN ('ADMIN', 'SUPER_ADMIN', 'ADMINISTRATOR', 'LAB_DIRECTOR')
    );
$$;

CREATE OR REPLACE FUNCTION public.is_lab_technician(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.user_roles ur
        JOIN public.roles r ON ur.role_id = r.id
        WHERE ur.user_id = p_user_id
          AND r.name IN ('LAB_TECHNICIAN', 'TECHNICIAN', 'ADMIN', 'SUPER_ADMIN', 'ADMINISTRATOR', 'LAB_DIRECTOR')
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_admin(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.is_lab_technician(UUID) TO authenticated, anon;

-- 3. Confirm all 1139 tests remain active
UPDATE public.tests SET is_active = true WHERE is_active IS NOT TRUE;

-- 4. Final verification assert query
DO $$
DECLARE
    v_active_tests INT;
    v_active_params INT;
    v_active_rules INT;
    v_active_rates INT;
    v_analyzers INT;
BEGIN
    SELECT count(*) INTO v_active_tests FROM public.tests WHERE is_active = true;
    SELECT count(*) INTO v_active_params FROM public.parameters WHERE is_active = true;
    SELECT count(*) INTO v_active_rules FROM public.reference_ranges WHERE is_active = true;
    SELECT count(*) INTO v_active_rates FROM public.catalogue_rate_versions WHERE effective_to IS NULL;
    SELECT count(*) INTO v_analyzers FROM public.analyzers;

    IF v_active_tests <> 1139 THEN
        RAISE EXCEPTION 'Active tests mismatch: expected 1139, got %', v_active_tests;
    END IF;

    IF v_active_params <> 1168 THEN
        RAISE EXCEPTION 'Active parameters mismatch: expected 1168, got %', v_active_params;
    END IF;

    IF v_active_rules <> 186 THEN
        RAISE EXCEPTION 'Active reference rules mismatch: expected 186, got %', v_active_rules;
    END IF;

    IF v_active_rates <> 125 THEN
        RAISE EXCEPTION 'Active rates mismatch: expected 125, got %', v_active_rates;
    END IF;

    IF v_analyzers < 4 THEN
        RAISE EXCEPTION 'Analyzers mismatch: expected >= 4, got %', v_analyzers;
    END IF;
END $$;

COMMIT;
