-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Row Level Security (RLS) & Granular Permission Architecture (Phase 0)
-- ============================================================================

-- ============================================================================
-- 1. SECURITY HELPER FUNCTIONS
-- ============================================================================

-- Function to check if the current caller is a Super Admin
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid()
        AND is_super_admin = TRUE
        AND is_active = TRUE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

-- Function to check if the current caller possesses a specific granular permission
CREATE OR REPLACE FUNCTION public.has_permission(p_permission_key VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE
    v_has_perm BOOLEAN := FALSE;
BEGIN
    -- Super Admin bypasses all checks
    IF public.is_super_admin() THEN
        RETURN TRUE;
    END IF;

    -- Check direct permission override first
    SELECT is_granted INTO v_has_perm
    FROM public.user_direct_permissions
    WHERE user_id = auth.uid() AND permission_key = p_permission_key;

    IF v_has_perm IS NOT NULL THEN
        RETURN v_has_perm;
    END IF;

    -- Check assigned role permissions
    RETURN EXISTS (
        SELECT 1
        FROM public.user_roles ur
        JOIN public.role_permissions rp ON ur.role_id = rp.role_id
        JOIN public.user_profiles up ON ur.user_id = up.id
        WHERE ur.user_id = auth.uid()
        AND up.is_active = TRUE
        AND rp.permission_key = p_permission_key
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

-- Explicitly control EXECUTE privileges
REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.has_permission(VARCHAR) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_permission(VARCHAR) TO authenticated;

-- ============================================================================
-- 2. ENABLE RLS ON ALL TABLES
-- ============================================================================

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_direct_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE referring_doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE reporting_personnel ENABLE ROW LEVEL SECURITY;
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE bill_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE tests ENABLE ROW LEVEL SECURITY;
ALTER TABLE parameters ENABLE ROW LEVEL SECURITY;
ALTER TABLE reference_ranges ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinical_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinical_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE samples ENABLE ROW LEVEL SECURITY;
ALTER TABLE sample_lifecycle_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE test_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE diagnostic_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 3. RLS POLICIES - USERS, ROLES & PERMISSIONS
-- ============================================================================

-- user_profiles: Users can read own profile; Admin with can_manage_users can read/write all
CREATE POLICY "user_profiles_select_own" ON user_profiles
    FOR SELECT TO authenticated
    USING (id = auth.uid() OR public.has_permission('can_manage_users'));

CREATE POLICY "user_profiles_admin_all" ON user_profiles
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_users'))
    WITH CHECK (public.has_permission('can_manage_users'));

-- roles & permissions: Authenticated can read; can_manage_roles can write
CREATE POLICY "roles_select" ON roles
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY "roles_write" ON roles
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_roles'))
    WITH CHECK (public.has_permission('can_manage_roles'));

CREATE POLICY "role_permissions_select" ON role_permissions
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY "role_permissions_write" ON role_permissions
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_roles'))
    WITH CHECK (public.has_permission('can_manage_roles'));

-- user_roles
CREATE POLICY "user_roles_select" ON user_roles
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.has_permission('can_manage_roles') OR public.has_permission('can_manage_users'));

CREATE POLICY "user_roles_write" ON user_roles
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_roles') OR public.has_permission('can_manage_users'))
    WITH CHECK (public.has_permission('can_manage_roles') OR public.has_permission('can_manage_users'));

-- user_direct_permissions
CREATE POLICY "user_direct_permissions_select" ON user_direct_permissions
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.has_permission('can_manage_roles') OR public.has_permission('can_manage_users'));

CREATE POLICY "user_direct_permissions_write" ON user_direct_permissions
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_roles') OR public.has_permission('can_manage_users'))
    WITH CHECK (public.has_permission('can_manage_roles') OR public.has_permission('can_manage_users'));

-- ============================================================================
-- 4. RLS POLICIES - MASTERS (TESTS, DOCTORS, PERSONNEL)
-- ============================================================================

-- tests, parameters, reference_ranges: Read by authenticated; Write with can_manage_catalogue
CREATE POLICY "tests_select" ON tests
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY "tests_write" ON tests
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_catalogue'))
    WITH CHECK (public.has_permission('can_manage_catalogue'));

CREATE POLICY "parameters_select" ON parameters
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY "parameters_write" ON parameters
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_catalogue'))
    WITH CHECK (public.has_permission('can_manage_catalogue'));

CREATE POLICY "ref_ranges_select" ON reference_ranges
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY "ref_ranges_write" ON reference_ranges
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_catalogue'))
    WITH CHECK (public.has_permission('can_manage_catalogue'));

-- referring_doctors
CREATE POLICY "referring_doctors_select" ON referring_doctors
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY "referring_doctors_write" ON referring_doctors
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_referring_doctors'))
    WITH CHECK (public.has_permission('can_manage_referring_doctors'));

-- reporting_personnel
CREATE POLICY "reporting_personnel_select" ON reporting_personnel
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY "reporting_personnel_write" ON reporting_personnel
    FOR ALL TO authenticated
    USING (public.has_permission('can_manage_personnel'))
    WITH CHECK (public.has_permission('can_manage_personnel'));

-- ============================================================================
-- 5. RLS POLICIES - PATIENT REGISTRY
-- ============================================================================

CREATE POLICY "patients_select" ON patients
    FOR SELECT TO authenticated
    USING (
        public.has_permission('can_create_bill') OR
        public.has_permission('can_edit_patient') OR
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_enter_results') OR
        public.has_permission('can_verify_results') OR
        public.has_permission('can_sign_reports') OR
        public.has_permission('can_print_reports')
    );

CREATE POLICY "patients_insert" ON patients
    FOR INSERT TO authenticated
    WITH CHECK (public.has_permission('can_create_bill'));

CREATE POLICY "patients_update" ON patients
    FOR UPDATE TO authenticated
    USING (public.has_permission('can_edit_patient'))
    WITH CHECK (public.has_permission('can_edit_patient'));

-- ============================================================================
-- 6. RLS POLICIES - FINANCIAL BILLING & PAYMENTS
-- ============================================================================

CREATE POLICY "bills_select" ON bills
    FOR SELECT TO authenticated
    USING (public.has_permission('can_create_bill') OR public.has_permission('can_view_financials'));

CREATE POLICY "bills_insert" ON bills
    FOR INSERT TO authenticated
    WITH CHECK (public.has_permission('can_create_bill'));

CREATE POLICY "bill_items_select" ON bill_items
    FOR SELECT TO authenticated
    USING (public.has_permission('can_create_bill') OR public.has_permission('can_view_financials'));

CREATE POLICY "bill_items_insert" ON bill_items
    FOR INSERT TO authenticated
    WITH CHECK (public.has_permission('can_create_bill'));

CREATE POLICY "payments_select" ON payment_transactions
    FOR SELECT TO authenticated
    USING (public.has_permission('can_create_bill') OR public.has_permission('can_view_financials'));

CREATE POLICY "payments_insert" ON payment_transactions
    FOR INSERT TO authenticated
    WITH CHECK (public.has_permission('can_create_bill'));

-- ============================================================================
-- 7. RLS POLICIES - CLINICAL ORDERS, ORDER ITEMS & SAMPLES
-- ============================================================================

CREATE POLICY "clinical_orders_select" ON clinical_orders
    FOR SELECT TO authenticated
    USING (
        public.has_permission('can_create_bill') OR
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_enter_results') OR
        public.has_permission('can_verify_results') OR
        public.has_permission('can_sign_reports') OR
        public.has_permission('can_print_reports')
    );

CREATE POLICY "clinical_orders_insert" ON clinical_orders
    FOR INSERT TO authenticated
    WITH CHECK (public.has_permission('can_create_bill'));

CREATE POLICY "clinical_orders_update" ON clinical_orders
    FOR UPDATE TO authenticated
    USING (
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_enter_results') OR
        public.has_permission('can_verify_results') OR
        public.has_permission('can_sign_reports')
    )
    WITH CHECK (
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_enter_results') OR
        public.has_permission('can_verify_results') OR
        public.has_permission('can_sign_reports')
    );

CREATE POLICY "clinical_order_items_select" ON clinical_order_items
    FOR SELECT TO authenticated
    USING (
        public.has_permission('can_create_bill') OR
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_enter_results') OR
        public.has_permission('can_verify_results') OR
        public.has_permission('can_sign_reports') OR
        public.has_permission('can_print_reports')
    );

CREATE POLICY "clinical_order_items_insert" ON clinical_order_items
    FOR INSERT TO authenticated
    WITH CHECK (public.has_permission('can_create_bill'));

CREATE POLICY "clinical_order_items_update" ON clinical_order_items
    FOR UPDATE TO authenticated
    USING (
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_enter_results') OR
        public.has_permission('can_verify_results') OR
        public.has_permission('can_sign_reports')
    )
    WITH CHECK (
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_enter_results') OR
        public.has_permission('can_verify_results') OR
        public.has_permission('can_sign_reports')
    );

CREATE POLICY "samples_select" ON samples
    FOR SELECT TO authenticated
    USING (
        public.has_permission('can_create_bill') OR
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_reject_sample') OR
        public.has_permission('can_enter_results') OR
        public.has_permission('can_verify_results') OR
        public.has_permission('can_sign_reports') OR
        public.has_permission('can_print_reports')
    );

CREATE POLICY "samples_insert" ON samples
    FOR INSERT TO authenticated
    WITH CHECK (public.has_permission('can_create_bill') OR public.has_permission('can_collect_sample'));

CREATE POLICY "samples_update" ON samples
    FOR UPDATE TO authenticated
    USING (
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_reject_sample')
    )
    WITH CHECK (
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_reject_sample')
    );

CREATE POLICY "sample_lifecycle_select" ON sample_lifecycle_events
    FOR SELECT TO authenticated
    USING (
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_reject_sample') OR
        public.has_permission('can_enter_results') OR
        public.has_permission('can_verify_results') OR
        public.has_permission('can_sign_reports')
    );

CREATE POLICY "sample_lifecycle_insert" ON sample_lifecycle_events
    FOR INSERT TO authenticated
    WITH CHECK (
        public.has_permission('can_collect_sample') OR
        public.has_permission('can_receive_sample') OR
        public.has_permission('can_reject_sample') OR
        public.has_permission('can_enter_results')
    );

-- ============================================================================
-- 8. RLS POLICIES - TEST RESULTS & VERIFICATION
-- ============================================================================

CREATE POLICY "test_results_select" ON test_results
    FOR SELECT TO authenticated
    USING (
        public.has_permission('can_enter_results') OR
        public.has_permission('can_verify_results') OR
        public.has_permission('can_sign_reports') OR
        public.has_permission('can_print_reports')
    );

CREATE POLICY "test_results_insert" ON test_results
    FOR INSERT TO authenticated
    WITH CHECK (public.has_permission('can_enter_results'));

CREATE POLICY "test_results_update" ON test_results
    FOR UPDATE TO authenticated
    USING (
        (status = 'Draft' AND public.has_permission('can_enter_results')) OR
        (status = 'SubmittedForVerification' AND public.has_permission('can_verify_results')) OR
        public.has_permission('can_sign_reports')
    )
    WITH CHECK (
        (status = 'Draft' AND public.has_permission('can_enter_results')) OR
        (status = 'SubmittedForVerification' AND public.has_permission('can_verify_results')) OR
        public.has_permission('can_sign_reports')
    );

-- ============================================================================
-- 9. RLS POLICIES - DIAGNOSTIC REPORTS (IMMUTABILITY ENFORCEMENT)
-- ============================================================================

CREATE POLICY "diagnostic_reports_select" ON diagnostic_reports
    FOR SELECT TO authenticated
    USING (
        public.has_permission('can_print_reports') OR
        public.has_permission('can_sign_reports') OR
        public.has_permission('can_amend_reports')
    );

-- Sign-off and report creation (or creating new amended version rows)
CREATE POLICY "diagnostic_reports_insert" ON diagnostic_reports
    FOR INSERT TO authenticated
    WITH CHECK (
        public.has_permission('can_sign_reports') OR
        public.has_permission('can_amend_reports')
    );

-- Signed reports are strictly IMMUTABLE: no in-place UPDATE of signed snapshots/hashes.
-- Only unfinalized Draft records (if any) can be updated before sign-off.
-- Amendments must be INSERTed as new version rows linked by amended_from_report_id.
CREATE POLICY "diagnostic_reports_update_draft" ON diagnostic_reports
    FOR UPDATE TO authenticated
    USING (status = 'Draft' AND public.has_permission('can_sign_reports'))
    WITH CHECK (status = 'Draft' AND public.has_permission('can_sign_reports'));

-- ============================================================================
-- 10. RLS POLICIES - AUDIT LOGS (STRICT APPEND-ONLY)
-- ============================================================================

CREATE POLICY "audit_logs_select" ON audit_logs
    FOR SELECT TO authenticated
    USING (public.has_permission('can_view_audit_logs'));

CREATE POLICY "audit_logs_insert" ON audit_logs
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() IS NOT NULL AND (user_id IS NULL OR user_id = auth.uid()));

-- Prevent any UPDATE or DELETE on audit logs for tamper resistance
-- (No UPDATE or DELETE policy is defined, so PostgreSQL defaults to denying all updates/deletions)
