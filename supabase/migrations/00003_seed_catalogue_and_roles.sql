-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Seed Data: Roles, Permissions, Test Catalogue & Parameters (Phase 0)
-- ============================================================================

-- 1. Insert Standard Roles
INSERT INTO roles (id, code, name, description, is_system) VALUES
    ('00000000-0000-0000-0000-000000000001', 'admin', 'Administrator', 'Full system administration, security, catalogue and audit permissions', TRUE),
    ('00000000-0000-0000-0000-000000000002', 'pathologist', 'Consultant Pathologist', 'Clinical verification, critical value acknowledgement, final report authorization and sign-off', TRUE),
    ('00000000-0000-0000-0000-000000000003', 'lab_technologist', 'Lab Technologist', 'Sample collection, accessioning, result entry, first-level verification, critical value alert handling', TRUE),
    ('00000000-0000-0000-0000-000000000004', 'lab_technician', 'Lab Technician', 'Sample collection, lab reception, barcode tracking, routine parameter result entry', TRUE),
    ('00000000-0000-0000-0000-000000000005', 'reception', 'Receptionist', 'Patient registration, billing, financial payments, receipt generation, report dispatch', TRUE),
    ('00000000-0000-0000-0000-000000000006', 'other_staff', 'General Staff', 'General dashboard and operational overview', TRUE)
ON CONFLICT (code) DO NOTHING;

-- 2. Insert Permissions for Administrator (All Permissions)
INSERT INTO role_permissions (role_id, permission_key) VALUES
    ('00000000-0000-0000-0000-000000000001', 'can_view_dashboard'),
    ('00000000-0000-0000-0000-000000000001', 'can_create_bill'),
    ('00000000-0000-0000-0000-000000000001', 'can_edit_patient'),
    ('00000000-0000-0000-0000-000000000001', 'can_collect_sample'),
    ('00000000-0000-0000-0000-000000000001', 'can_receive_sample'),
    ('00000000-0000-0000-0000-000000000001', 'can_reject_sample'),
    ('00000000-0000-0000-0000-000000000001', 'can_enter_results'),
    ('00000000-0000-0000-0000-000000000001', 'can_verify_results'),
    ('00000000-0000-0000-0000-000000000001', 'can_acknowledge_critical'),
    ('00000000-0000-0000-0000-000000000001', 'can_sign_reports'),
    ('00000000-0000-0000-0000-000000000001', 'can_amend_reports'),
    ('00000000-0000-0000-0000-000000000001', 'can_print_reports'),
    ('00000000-0000-0000-0000-000000000001', 'can_manage_catalogue'),
    ('00000000-0000-0000-0000-000000000001', 'can_manage_referring_doctors'),
    ('00000000-0000-0000-0000-000000000001', 'can_manage_personnel'),
    ('00000000-0000-0000-0000-000000000001', 'can_view_financials'),
    ('00000000-0000-0000-0000-000000000001', 'can_manage_users'),
    ('00000000-0000-0000-0000-000000000001', 'can_manage_roles'),
    ('00000000-0000-0000-0000-000000000001', 'can_view_audit_logs')
ON CONFLICT (role_id, permission_key) DO NOTHING;

-- 3. Pathologist Permissions
INSERT INTO role_permissions (role_id, permission_key) VALUES
    ('00000000-0000-0000-0000-000000000002', 'can_view_dashboard'),
    ('00000000-0000-0000-0000-000000000002', 'can_enter_results'),
    ('00000000-0000-0000-0000-000000000002', 'can_verify_results'),
    ('00000000-0000-0000-0000-000000000002', 'can_acknowledge_critical'),
    ('00000000-0000-0000-0000-000000000002', 'can_sign_reports'),
    ('00000000-0000-0000-0000-000000000002', 'can_amend_reports'),
    ('00000000-0000-0000-0000-000000000002', 'can_print_reports'),
    ('00000000-0000-0000-0000-000000000002', 'can_view_audit_logs')
ON CONFLICT (role_id, permission_key) DO NOTHING;

-- 4. Lab Technologist Permissions
INSERT INTO role_permissions (role_id, permission_key) VALUES
    ('00000000-0000-0000-0000-000000000003', 'can_view_dashboard'),
    ('00000000-0000-0000-0000-000000000003', 'can_collect_sample'),
    ('00000000-0000-0000-0000-000000000003', 'can_receive_sample'),
    ('00000000-0000-0000-0000-000000000003', 'can_reject_sample'),
    ('00000000-0000-0000-0000-000000000003', 'can_enter_results'),
    ('00000000-0000-0000-0000-000000000003', 'can_verify_results'),
    ('00000000-0000-0000-0000-000000000003', 'can_acknowledge_critical'),
    ('00000000-0000-0000-0000-000000000003', 'can_print_reports')
ON CONFLICT (role_id, permission_key) DO NOTHING;

-- 5. Reception Permissions
INSERT INTO role_permissions (role_id, permission_key) VALUES
    ('00000000-0000-0000-0000-000000000005', 'can_view_dashboard'),
    ('00000000-0000-0000-0000-000000000005', 'can_create_bill'),
    ('00000000-0000-0000-0000-000000000005', 'can_edit_patient'),
    ('00000000-0000-0000-0000-000000000005', 'can_collect_sample'),
    ('00000000-0000-0000-0000-000000000005', 'can_print_reports')
ON CONFLICT (role_id, permission_key) DO NOTHING;

-- 6. Seed Sample Tests (Amounts in PAISA)
INSERT INTO tests (id, code, name, department, category, reporting_type, price_paisa, sample_type, container, is_active, display_order) VALUES
    ('10000000-0000-0000-0000-000000000001', 'CBC', 'Complete Blood Count (CBC / Hemogram)', 'Hematology', 'Routine Hematology', 'InHouse', 40000, 'Whole Blood (EDTA)', 'Lavender Top (EDTA)', TRUE, 1),
    ('10000000-0000-0000-0000-000000000002', 'LFT', 'Liver Function Test (LFT)', 'Clinical Biochemistry', 'Biochemistry Profiles', 'InHouse', 90000, 'Serum', 'Yellow Top (SST)', TRUE, 2),
    ('10000000-0000-0000-0000-000000000003', 'RFT', 'Renal Function Test (RFT)', 'Clinical Biochemistry', 'Biochemistry Profiles', 'InHouse', 85000, 'Serum', 'Yellow Top (SST)', TRUE, 3),
    ('10000000-0000-0000-0000-000000000004', 'LIPID', 'Lipid Profile', 'Clinical Biochemistry', 'Biochemistry Profiles', 'InHouse', 75000, 'Serum', 'Yellow Top (SST)', TRUE, 4),
    ('10000000-0000-0000-0000-000000000005', 'THYROID_ECLIA', 'Thyroid Function Panel (FT3, FT4, Sensitive TSH)', 'Immunology & Serology', 'Endocrinology', 'OutsourceWithBimalReport', 150000, 'Serum', 'Yellow Top (SST)', TRUE, 5)
ON CONFLICT (code) DO NOTHING;
