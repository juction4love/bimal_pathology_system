-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00010: Reference Range Management, Approval & Extended Clinical Metadata
-- Adds reference_text, method, effective dates, approval workflow & active flags
-- ============================================================================

-- 1. Add extended columns to reference_ranges table
ALTER TABLE public.reference_ranges
    ADD COLUMN IF NOT EXISTS reference_text TEXT,
    ADD COLUMN IF NOT EXISTS method VARCHAR(100),
    ADD COLUMN IF NOT EXISTS effective_from DATE DEFAULT CURRENT_DATE,
    ADD COLUMN IF NOT EXISTS effective_to DATE,
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES public.user_profiles(id),
    ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

-- 2. Indexes for fast lookup by parameter_id, active, and approval status
CREATE INDEX IF NOT EXISTS idx_ref_ranges_param_approved
    ON public.reference_ranges(parameter_id, is_active, is_approved);

CREATE INDEX IF NOT EXISTS idx_ref_ranges_gender_age
    ON public.reference_ranges(parameter_id, gender, age_min_days, age_max_days);

-- 3. RLS policy update to allow can_manage_catalogue to insert/update/delete reference_ranges
DROP POLICY IF EXISTS "ref_ranges_write" ON public.reference_ranges;
CREATE POLICY "ref_ranges_write" ON public.reference_ranges
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_catalogue'))
    WITH CHECK (public.has_permission('can_manage_catalogue'));
