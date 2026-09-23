

-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Single Authoritative Clean Production Baseline Migration (Phase 0)
-- 
-- Invariants:
-- 1. All financial amounts stored strictly as integer PAISA (1 NPR = 100 Paisa).
-- 2. Clean database bootstrap: Zero historical patients, bills, orders, or reports.
-- 3. Zero hardcoded auth users or passwords.
-- 4. Complete 1,139-test master clinical catalogue with operational reporting models.
-- 5. Hardened RLS, SECURITY DEFINER functions, search_path = public, pg_temp.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

CREATE OR REPLACE FUNCTION public.uuid_generate_v4()
RETURNS UUID
LANGUAGE sql
VOLATILE
SET search_path = extensions, pg_temp
AS $$ SELECT extensions.uuid_generate_v4() $$;

-- ============================================================================
-- 2. ENUM TYPES
-- ============================================================================
DO $$ BEGIN
    CREATE TYPE public.user_role_enum AS ENUM ('admin', 'lab_technician', 'guest');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.professional_type_enum AS ENUM (
        'MD Pathologist', 'MBBS Doctor', 'MSc MLT', 'BSc MLT', 'Lab Technician', 'Lab Assistant', 'Other'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.payment_mode_enum AS ENUM (
        'Cash', 'Fonepay', 'eSewa', 'Khalti', 'Card', 'Bank', 'Credit', 'Other'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.payment_status_enum AS ENUM (
        'Paid', 'Partial', 'Due'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.reporting_type_enum AS ENUM (
        'InHouse', 'OutsourceWithBimalReport', 'NoReporting'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.sample_status_enum AS ENUM (
        'Pending', 'Collected', 'Received', 'Processing', 'Completed', 'Rejected', 'Recollected'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.parameter_value_type_enum AS ENUM (
        'Numeric', 'Text', 'Select', 'Boolean', 'Heading', 'Calculated'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.result_status_enum AS ENUM (
        'Draft', 'SubmittedForVerification', 'ReturnedForCorrection', 'Verified', 'SignedOff', 'Amended', 'Cancelled'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.result_flag_enum AS ENUM (
        'Normal', 'Low', 'High', 'CriticalLow', 'CriticalHigh', 'Abnormal', 'NoRange'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.outsource_item_state_enum AS ENUM (
        'Registered', 'Dispatched', 'Received', 'Drafted', 'Verified', 'Signed'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.sms_job_state_enum AS ENUM (
        'Queued', 'Claimed', 'Sent', 'Failed', 'Cancelled'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.catalogue_lifecycle_enum AS ENUM (
        'Draft', 'Active', 'Archived'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.catalogue_test_kind_enum AS ENUM (
        'Individual', 'Profile'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.clinical_configuration_status_enum AS ENUM (
        'Configured', 'Requires Clinical Validation', 'Ready for Activation', 'Workflow Not Supported'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.catalogue_pricing_policy_enum AS ENUM (
        'Fixed', 'Negotiable', 'PricePending', 'Manual'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.reference_range_validation_state_enum AS ENUM (
        'Unclassified', 'ClinicallyValidated', 'LegacyDefaultRequiresValidation'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.catalogue_billable_entity_enum AS ENUM (
        'Test', 'Panel', 'Package'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- 3. CORE PUBLIC TABLES & RELATIONS
-- ============================================================================

-- A. Authentication & User Profiles
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL UNIQUE,
    full_name VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_super_admin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    is_system BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_roles (
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE IF NOT EXISTS public.role_permissions (
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    permission_key VARCHAR(100) NOT NULL,
    PRIMARY KEY (role_id, permission_key)
);

CREATE TABLE IF NOT EXISTS public.user_direct_permissions (
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    permission_key VARCHAR(100) NOT NULL,
    is_granted BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (user_id, permission_key)
);

-- B. Personnel & Referring Clinicians
CREATE TABLE IF NOT EXISTS public.referring_doctors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name VARCHAR(255) NOT NULL,
    code VARCHAR(50) UNIQUE,
    degree VARCHAR(255),
    institution VARCHAR(255),
    phone VARCHAR(50),
    email VARCHAR(255),
    address TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.reporting_personnel (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    full_name VARCHAR(255) NOT NULL,
    professional_type public.professional_type_enum NOT NULL,
    qualification VARCHAR(255) NOT NULL,
    registration_council VARCHAR(255) NOT NULL,
    registration_number VARCHAR(100) NOT NULL,
    specialization VARCHAR(255),
    phone VARCHAR(50),
    email VARCHAR(255),
    signature_url TEXT,
    can_enter_results BOOLEAN NOT NULL DEFAULT TRUE,
    can_verify_results BOOLEAN NOT NULL DEFAULT FALSE,
    can_acknowledge_critical BOOLEAN NOT NULL DEFAULT FALSE,
    can_sign_reports BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- C. Test Catalogue Schema
CREATE TABLE IF NOT EXISTS public.test_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Active',
    row_version BIGINT NOT NULL DEFAULT 1,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT test_categories_name_not_blank CHECK (btrim(name) <> '')
);

CREATE UNIQUE INDEX IF NOT EXISTS test_categories_normalized_name_key
ON public.test_categories (lower(regexp_replace(btrim(name), '[^[:alnum:]]+', '', 'g')));

CREATE TABLE IF NOT EXISTS public.tests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    short_name VARCHAR(100),
    department VARCHAR(100) NOT NULL,
    category VARCHAR(100) NOT NULL,
    category_id UUID REFERENCES public.test_categories(id) ON DELETE SET NULL,
    reporting_type public.reporting_type_enum NOT NULL DEFAULT 'InHouse',
    outsource_lab_name VARCHAR(255),
    price_paisa BIGINT NOT NULL DEFAULT 0 CHECK (price_paisa >= 0),
    sample_type VARCHAR(100) NOT NULL,
    container VARCHAR(100) NOT NULL,
    method VARCHAR(100),
    tat_hours INT,
    interpretation_template TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INT NOT NULL DEFAULT 0,
    test_type VARCHAR(50) DEFAULT 'Individual',
    workflow_type VARCHAR(50) DEFAULT 'Standard',
    reporting_model VARCHAR(50) DEFAULT 'NUMERIC_SINGLE_ANALYTE',
    clinical_reporting_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    billing_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    price_configured BOOLEAN NOT NULL DEFAULT FALSE,
    pricing_policy VARCHAR(50) DEFAULT 'Fixed',
    lifecycle_status VARCHAR(50) DEFAULT 'Active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.test_aliases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    alias_name VARCHAR(255) NOT NULL,
    alias_type VARCHAR(50) DEFAULT 'Synonym',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_test_alias UNIQUE (test_id, alias_name)
);

CREATE TABLE IF NOT EXISTS public.parameters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    value_type public.parameter_value_type_enum NOT NULL DEFAULT 'Numeric',
    unit VARCHAR(50),
    options JSONB,
    formula TEXT,
    formula_dependencies TEXT[],
    calculation_identifier VARCHAR(100),
    display_order INT NOT NULL DEFAULT 0,
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    lifecycle_status VARCHAR(50) DEFAULT 'Active',
    clinical_configuration_status VARCHAR(50) DEFAULT 'Configured',
    interpretation_config JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(test_id, code)
);

CREATE TABLE IF NOT EXISTS public.reference_ranges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parameter_id UUID NOT NULL REFERENCES public.parameters(id) ON DELETE CASCADE,
    gender VARCHAR(20) NOT NULL DEFAULT 'All' CHECK (gender IN ('All', 'Male', 'Female')),
    age_min_days INT NOT NULL DEFAULT 0,
    age_max_days INT NOT NULL DEFAULT 43800,
    normal_min NUMERIC(10, 3),
    normal_max NUMERIC(10, 3),
    critical_low NUMERIC(10, 3),
    critical_high NUMERIC(10, 3),
    normal_text TEXT,
    unit TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.catalogue_panel_services (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    category_id UUID REFERENCES public.test_categories(id) ON DELETE SET NULL,
    lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Active',
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.catalogue_panel_components (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    panel_id UUID REFERENCES public.tests(id) ON DELETE CASCADE,
    panel_test_id UUID REFERENCES public.tests(id) ON DELETE CASCADE,
    component_test_id UUID REFERENCES public.tests(id) ON DELETE CASCADE,
    component_parameter_id UUID REFERENCES public.parameters(id) ON DELETE CASCADE,
    display_order INT NOT NULL DEFAULT 0,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    component_role VARCHAR(50) DEFAULT 'Primary',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.health_packages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price_paisa BIGINT NOT NULL DEFAULT 0 CHECK (price_paisa >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Active',
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.health_package_components (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    package_id UUID NOT NULL REFERENCES public.health_packages(id) ON DELETE CASCADE,
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.catalogue_rate_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type public.catalogue_billable_entity_enum NOT NULL DEFAULT 'Test',
    test_id UUID REFERENCES public.tests(id) ON DELETE CASCADE,
    panel_service_id UUID REFERENCES public.catalogue_panel_services(id) ON DELETE CASCADE,
    package_id UUID REFERENCES public.health_packages(id) ON DELETE CASCADE,
    version_number INT NOT NULL DEFAULT 1,
    row_version BIGINT NOT NULL DEFAULT 1,
    price_paisa BIGINT NOT NULL CHECK (price_paisa >= 0),
    effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_to TIMESTAMPTZ,
    status VARCHAR(50) NOT NULL DEFAULT 'Active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.catalogue_calculation_definitions (
    identifier VARCHAR(100) PRIMARY KEY,
    parameter_code VARCHAR(50) NOT NULL UNIQUE,
    server_authoritative BOOLEAN NOT NULL DEFAULT FALSE,
    implementation_note TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- D. Analyzer Master & Mappings
CREATE TABLE IF NOT EXISTS public.analyzers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    manufacturer VARCHAR(255) NOT NULL,
    model VARCHAR(255) NOT NULL,
    laboratory_location VARCHAR(255) NOT NULL,
    lifecycle_status VARCHAR(50) NOT NULL DEFAULT 'Active',
    row_version BIGINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.analyzer_parameter_mappings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analyzer_id UUID NOT NULL REFERENCES public.analyzers(id) ON DELETE CASCADE,
    channel_code VARCHAR(50) NOT NULL,
    channel_name VARCHAR(255) NOT NULL,
    test_id UUID REFERENCES public.tests(id) ON DELETE SET NULL,
    parameter_id UUID REFERENCES public.parameters(id) ON DELETE SET NULL,
    measurement_type VARCHAR(50) NOT NULL CHECK (measurement_type IN ('DIRECT_MEASURED', 'ANALYZER_CALCULATED', 'ANALYZER_DERIVED', 'MANUAL_MICROSCOPY')),
    analytical_method VARCHAR(255) NOT NULL,
    unit VARCHAR(50),
    differential_type VARCHAR(50) NOT NULL DEFAULT '3-Part' CHECK (differential_type IN ('3-Part', '5-Part Manual', 'Not Applicable')),
    is_automated_5part_supported BOOLEAN NOT NULL DEFAULT FALSE,
    row_version BIGINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_analyzer_channel UNIQUE (analyzer_id, channel_code)
);

-- E. Patient Registry
CREATE TABLE IF NOT EXISTS public.patients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    uhid VARCHAR(50) NOT NULL UNIQUE,
    mobile VARCHAR(20) NOT NULL,
    title VARCHAR(20),
    full_name VARCHAR(255) NOT NULL,
    gender VARCHAR(20) NOT NULL CHECK (gender IN ('Male', 'Female', 'Other')),
    dob DATE,
    age_years INT,
    age_months INT,
    age_days INT,
    email VARCHAR(255),
    address TEXT,
    national_id VARCHAR(50),
    blood_group VARCHAR(10),
    emergency_contact VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_patients_mobile UNIQUE (mobile)
);

-- F. Billing & Invoicing
CREATE TABLE IF NOT EXISTS public.bills (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_number VARCHAR(50) NOT NULL UNIQUE,
    patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
    referring_doctor_id UUID REFERENCES public.referring_doctors(id) ON DELETE RESTRICT,
    referring_doctor_name_snapshot VARCHAR(255),
    patient_name_snapshot VARCHAR(255) NOT NULL,
    patient_uhid_snapshot VARCHAR(50) NOT NULL,
    patient_age_gender_snapshot VARCHAR(100) NOT NULL,
    patient_mobile_snapshot VARCHAR(20) NOT NULL,
    gross_amount_paisa BIGINT NOT NULL DEFAULT 0 CHECK (gross_amount_paisa >= 0),
    discount_amount_paisa BIGINT NOT NULL DEFAULT 0 CHECK (discount_amount_paisa >= 0),
    discount_reason TEXT,
    discount_authorized_by UUID REFERENCES public.user_profiles(id),
    discount_authorized_by_name VARCHAR(255),
    net_amount_paisa BIGINT NOT NULL DEFAULT 0 CHECK (net_amount_paisa >= 0),
    paid_amount_paisa BIGINT NOT NULL DEFAULT 0 CHECK (paid_amount_paisa >= 0),
    due_amount_paisa BIGINT NOT NULL DEFAULT 0 CHECK (due_amount_paisa >= 0),
    payment_status VARCHAR(50) NOT NULL DEFAULT 'Due',
    remarks TEXT,
    bill_date_ad DATE NOT NULL DEFAULT CURRENT_DATE,
    bill_date_bs VARCHAR(50) NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bill_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE CASCADE,
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
    test_code_snapshot VARCHAR(50) NOT NULL,
    test_name_snapshot VARCHAR(255) NOT NULL,
    unit_price_paisa BIGINT NOT NULL CHECK (unit_price_paisa >= 0),
    discount_paisa BIGINT NOT NULL DEFAULT 0 CHECK (discount_paisa >= 0),
    net_price_paisa BIGINT NOT NULL CHECK (net_price_paisa >= 0),
    reporting_type public.reporting_type_enum NOT NULL DEFAULT 'InHouse',
    outsource_lab_name VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.payment_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE RESTRICT,
    receipt_number VARCHAR(50) NOT NULL UNIQUE,
    amount_paisa BIGINT NOT NULL CHECK (amount_paisa > 0),
    payment_mode public.payment_mode_enum NOT NULL,
    transaction_reference VARCHAR(100),
    remarks TEXT,
    received_by UUID REFERENCES public.user_profiles(id),
    received_by_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- G. Clinical Orders & Specimens
CREATE TABLE IF NOT EXISTS public.clinical_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE RESTRICT,
    patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
    order_number VARCHAR(50) NOT NULL UNIQUE,
    order_date_ad DATE NOT NULL DEFAULT CURRENT_DATE,
    order_date_bs VARCHAR(50) NOT NULL DEFAULT '',
    status VARCHAR(50) NOT NULL DEFAULT 'Registered',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.samples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    barcode VARCHAR(50) NOT NULL UNIQUE,
    order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE RESTRICT,
    patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
    specimen_type VARCHAR(100) NOT NULL,
    container_type VARCHAR(100) NOT NULL,
    status public.sample_status_enum NOT NULL DEFAULT 'Pending',
    collected_at TIMESTAMPTZ,
    collected_by UUID REFERENCES public.user_profiles(id),
    collected_by_name VARCHAR(255),
    received_at TIMESTAMPTZ,
    received_by UUID REFERENCES public.user_profiles(id),
    received_by_name VARCHAR(255),
    rejected_at TIMESTAMPTZ,
    rejected_by UUID REFERENCES public.user_profiles(id),
    rejected_by_name VARCHAR(255),
    rejection_reason TEXT,
    recollected_from_sample_id UUID REFERENCES public.samples(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sample_lifecycle_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sample_id UUID NOT NULL REFERENCES public.samples(id) ON DELETE CASCADE,
    from_status public.sample_status_enum NOT NULL,
    to_status public.sample_status_enum NOT NULL,
    reason TEXT,
    performed_by UUID REFERENCES public.user_profiles(id),
    performed_by_name VARCHAR(255) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.clinical_order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE CASCADE,
    bill_item_id UUID NOT NULL REFERENCES public.bill_items(id) ON DELETE RESTRICT,
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
    test_name VARCHAR(255) NOT NULL,
    department VARCHAR(100) NOT NULL,
    reporting_type public.reporting_type_enum NOT NULL DEFAULT 'InHouse',
    outsource_lab_name VARCHAR(255),
    specimen_type VARCHAR(100) NOT NULL,
    container_type VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'Pending',
    sample_id UUID REFERENCES public.samples(id) ON DELETE SET NULL,
    execution_route VARCHAR(50) DEFAULT 'INTERNAL',
    clinical_reporting_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    collection_required BOOLEAN NOT NULL DEFAULT TRUE,
    result_revision BIGINT NOT NULL DEFAULT 0,
    outsource_state public.outsource_item_state_enum,
    outsource_external_reference TEXT,
    outsource_source_report_reference TEXT,
    outsource_method TEXT,
    outsource_interpretation TEXT,
    outsource_result_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- H. Clinical Results & Diagnostic Reports
CREATE TABLE IF NOT EXISTS public.test_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_item_id UUID NOT NULL REFERENCES public.clinical_order_items(id) ON DELETE CASCADE,
    parameter_id UUID NOT NULL REFERENCES public.parameters(id) ON DELETE RESTRICT,
    parameter_name VARCHAR(255) NOT NULL,
    value_type public.parameter_value_type_enum NOT NULL,
    unit VARCHAR(50),
    display_value TEXT NOT NULL,
    numeric_value NUMERIC(12, 4),
    text_value TEXT,
    flag public.result_flag_enum NOT NULL DEFAULT 'Normal',
    is_critical BOOLEAN NOT NULL DEFAULT FALSE,
    critical_acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
    critical_acknowledged_by UUID REFERENCES public.user_profiles(id),
    critical_acknowledged_at TIMESTAMPTZ,
    critical_remarks TEXT,
    normal_min NUMERIC(10, 3),
    normal_max NUMERIC(10, 3),
    critical_low NUMERIC(10, 3),
    critical_high NUMERIC(10, 3),
    normal_range_text TEXT,
    status public.result_status_enum NOT NULL DEFAULT 'Draft',
    entered_by UUID REFERENCES public.user_profiles(id),
    entered_by_name VARCHAR(255),
    verified_by UUID REFERENCES public.user_profiles(id),
    verified_by_name VARCHAR(255),
    verified_at TIMESTAMPTZ,
    signed_off_by UUID REFERENCES public.user_profiles(id),
    signed_off_name VARCHAR(255),
    signed_off_at TIMESTAMPTZ,
    result_source VARCHAR(50) DEFAULT 'MANUAL',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(order_item_id, parameter_id)
);

CREATE TABLE IF NOT EXISTS public.clinical_report_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE CASCADE,
    group_key VARCHAR(100) NOT NULL,
    department VARCHAR(100) NOT NULL,
    reporting_type public.reporting_type_enum NOT NULL,
    execution_route VARCHAR(50) NOT NULL DEFAULT 'INTERNAL',
    status VARCHAR(50) NOT NULL DEFAULT 'Pending',
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_order_report_group UNIQUE (order_id, group_key)
);

CREATE TABLE IF NOT EXISTS public.clinical_report_group_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_group_id UUID NOT NULL REFERENCES public.clinical_report_groups(id) ON DELETE CASCADE,
    order_item_id UUID NOT NULL REFERENCES public.clinical_order_items(id) ON DELETE CASCADE,
    frozen_test_code VARCHAR(50) NOT NULL,
    frozen_test_name VARCHAR(255) NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_report_group_item UNIQUE (report_group_id, order_item_id)
);

CREATE SEQUENCE IF NOT EXISTS public.report_seq START WITH 1001;

CREATE TABLE IF NOT EXISTS public.diagnostic_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE RESTRICT,
    report_group_id UUID REFERENCES public.clinical_report_groups(id) ON DELETE RESTRICT,
    patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
    report_number VARCHAR(50) NOT NULL UNIQUE,
    version INT NOT NULL DEFAULT 1,
    is_amendment BOOLEAN NOT NULL DEFAULT FALSE,
    amendment_reason TEXT,
    amended_from_report_id UUID REFERENCES public.diagnostic_reports(id) ON DELETE SET NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'SignedOff',
    integrity_hash VARCHAR(128) NOT NULL,
    performed_by_personnel_id UUID REFERENCES public.reporting_personnel(id),
    performed_by_personnel_name VARCHAR(255),
    verified_by_personnel_id UUID REFERENCES public.reporting_personnel(id),
    verified_by_personnel_name VARCHAR(255),
    signed_by_personnel_id UUID REFERENCES public.reporting_personnel(id),
    signed_by_personnel_name VARCHAR(255),
    signed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    pdf_storage_path TEXT,
    clinical_snapshot_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- I. Microbiology AST Framework
CREATE TABLE IF NOT EXISTS public.ast_microorganisms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    organism_group VARCHAR(100),
    gram_stain VARCHAR(50),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_antibiotics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    class VARCHAR(100),
    default_method VARCHAR(50) DEFAULT 'Kirby-Bauer Disk Diffusion',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_breakpoint_sets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    standard_authority VARCHAR(50) NOT NULL DEFAULT 'CLSI',
    edition_year INT NOT NULL DEFAULT 2024,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_breakpoint_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    set_id UUID NOT NULL REFERENCES public.ast_breakpoint_sets(id) ON DELETE CASCADE,
    antibiotic_id UUID NOT NULL REFERENCES public.ast_antibiotics(id) ON DELETE CASCADE,
    organism_id UUID REFERENCES public.ast_microorganisms(id) ON DELETE CASCADE,
    organism_group VARCHAR(100),
    susceptible_min NUMERIC(8,2),
    susceptible_max NUMERIC(8,2),
    intermediate_min NUMERIC(8,2),
    intermediate_max NUMERIC(8,2),
    resistant_min NUMERIC(8,2),
    resistant_max NUMERIC(8,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.pt_inr_reagent_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reagent_name VARCHAR(150) NOT NULL,
    lot_number VARCHAR(100) NOT NULL,
    isi NUMERIC(6,3) NOT NULL,
    mnpt_seconds NUMERIC(6,2) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- J. SMS & Public Report Infrastructure
CREATE TABLE IF NOT EXISTS public.sms_queue_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    mobile VARCHAR(20) NOT NULL,
    message_text TEXT NOT NULL,
    sms_type VARCHAR(50) NOT NULL,
    status public.sms_job_state_enum NOT NULL DEFAULT 'Queued',
    claimed_by VARCHAR(100),
    claimed_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    retry_count INT NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.public_report_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_id UUID NOT NULL REFERENCES public.diagnostic_reports(id) ON DELETE CASCADE,
    token VARCHAR(128) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 4. CORE SECURITY & AUTH FUNCTIONS / RPCS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_active_user()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid() AND is_active = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public.has_permission(p_permission_key VARCHAR)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_active_user() THEN
        RETURN FALSE;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE id = auth.uid() AND is_super_admin = TRUE
    ) THEN
        RETURN TRUE;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.user_direct_permissions
        WHERE user_id = auth.uid() AND permission_key = p_permission_key AND is_granted = TRUE
    ) THEN
        RETURN TRUE;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.user_roles ur
        JOIN public.role_permissions rp ON rp.role_id = ur.role_id
        WHERE ur.user_id = auth.uid() AND rp.permission_key = p_permission_key
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogue_require_manager()
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT public.has_permission('can_manage_catalogue') THEN
        RAISE EXCEPTION 'Catalogue management requires an active authorized laboratory operator.' USING ERRCODE='42501';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_require_technical()
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT (
        public.has_permission('can_configure_catalogue_technical') OR public.has_permission('can_manage_catalogue')
    ) THEN
        RAISE EXCEPTION 'Catalogue technical configuration requires an active authorized user.' USING ERRCODE='42501';
    END IF;
END $$;

-- Result Readiness assertion
CREATE OR REPLACE FUNCTION public.get_clinical_result_readiness_state(p_order_item_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    item RECORD;
    sample RECORD;
    ready BOOLEAN := FALSE;
    reason TEXT := NULL;
BEGIN
    SELECT * INTO item FROM public.clinical_order_items WHERE id = p_order_item_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ready', FALSE, 'code', 'ITEM_NOT_FOUND', 'reason', 'ITEM_NOT_FOUND');
    END IF;
    IF NOT item.clinical_reporting_enabled THEN
        RETURN jsonb_build_object('ready', FALSE, 'code', 'RESULT_REPORTING_DISABLED');
    END IF;
    IF NOT item.collection_required THEN
        RETURN jsonb_build_object('ready', TRUE, 'code', 'RESULT_COLLECTION_NOT_REQUIRED');
    END IF;
    IF item.sample_id IS NULL THEN
        RETURN jsonb_build_object('ready', FALSE, 'code', 'RESULT_COLLECTION_NOT_READY', 'reason', 'SAMPLE_MISSING');
    END IF;

    SELECT * INTO sample FROM public.samples WHERE id = item.sample_id;
    IF NOT FOUND OR sample.order_id <> item.order_id THEN
        reason := 'SAMPLE_ORDER_MISMATCH';
    ELSIF sample.status IN ('Pending', 'Rejected', 'Recollected') THEN
        reason := 'SAMPLE_' || upper(sample.status::TEXT);
    ELSIF sample.status NOT IN ('Collected', 'Received', 'Processing', 'Completed') THEN
        reason := 'SAMPLE_STATE_INVALID';
    ELSIF sample.collected_at IS NULL THEN
        reason := 'COLLECTION_TIMESTAMP_MISSING';
    ELSIF sample.collected_by IS NULL OR NULLIF(btrim(COALESCE(sample.collected_by_name, '')), '') IS NULL
          OR NOT EXISTS (SELECT 1 FROM public.user_profiles u WHERE u.id = sample.collected_by) THEN
        reason := 'COLLECTOR_IDENTITY_INVALID';
    ELSE
        ready := TRUE;
    END IF;

    RETURN jsonb_strip_nulls(jsonb_build_object(
        'ready', ready,
        'code', CASE WHEN ready THEN 'RESULT_COLLECTION_READY' ELSE 'RESULT_COLLECTION_NOT_READY' END,
        'reason', reason,
        'sample_id', sample.id,
        'sample_status', sample.status,
        'result_revision', item.result_revision
    ));
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_clinical_result_ready(p_order_item_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    state JSONB;
BEGIN
    state := public.get_clinical_result_readiness_state(p_order_item_id);
    IF NOT COALESCE((state->>'ready')::BOOLEAN, FALSE) THEN
        RAISE EXCEPTION '%', COALESCE(state->>'code', 'RESULT_COLLECTION_NOT_READY')
            USING DETAIL = state::TEXT, ERRCODE = '55000';
    END IF;
END;
$$;

-- Result Saving & Authoritative Calculation Engine
CREATE OR REPLACE FUNCTION public.save_test_results_unversioned_internal(
    p_order_item_id UUID,
    p_results JSONB,
    p_target_status public.result_status_enum,
    p_amended_from_report_id UUID DEFAULT NULL,
    p_amendment_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_item public.clinical_order_items%ROWTYPE;
    v_order public.clinical_orders%ROWTYPE;
    v_parent public.diagnostic_reports%ROWTYPE;
    v_result JSONB;
    v_parameter public.parameters%ROWTYPE;
    v_existing public.test_results%ROWTYPE;
    v_user_name TEXT;
    v_is_amendment BOOLEAN := FALSE;
    v_count INT := 0;
    v_item_status TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF jsonb_typeof(p_results) <> 'array' OR jsonb_array_length(p_results) = 0 THEN
        RAISE EXCEPTION 'At least one result is required.' USING ERRCODE = '22023';
    END IF;
    IF p_target_status NOT IN ('Draft', 'SubmittedForVerification', 'ReturnedForCorrection', 'Verified') THEN
        RAISE EXCEPTION 'Unsupported result workflow state.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_item FROM public.clinical_order_items
    WHERE id = p_order_item_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Result work item was not found.' USING ERRCODE = 'P0002';
    END IF;

    SELECT * INTO v_order FROM public.clinical_orders
    WHERE id = v_item.order_id FOR UPDATE;

    SELECT full_name INTO v_user_name FROM public.user_profiles
    WHERE id = auth.uid() AND is_active = TRUE;
    IF v_user_name IS NULL THEN
        v_user_name := 'Authorized Operator';
    END IF;

    IF p_target_status = 'Verified' AND NOT public.has_permission('can_verify_results') THEN
        RAISE EXCEPTION 'Verification permission required.' USING ERRCODE = '42501';
    END IF;

    FOR v_result IN SELECT * FROM jsonb_array_elements(p_results) LOOP
        SELECT * INTO v_parameter FROM public.parameters
        WHERE id = (v_result->>'parameter_id')::UUID;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invalid parameter specified.' USING ERRCODE = '22023';
        END IF;

        IF v_parameter.test_id <> v_item.test_id THEN
            IF NOT EXISTS (
                SELECT 1 FROM public.catalogue_panel_components cpc
                WHERE (cpc.panel_test_id = v_item.test_id OR cpc.panel_id = v_item.test_id)
                  AND (cpc.component_test_id = v_parameter.test_id OR cpc.component_parameter_id = v_parameter.id)
            ) THEN
                RAISE EXCEPTION 'Parameter % is not authorized under investigation %', v_parameter.code, v_item.test_name
                    USING ERRCODE = '22023';
            END IF;
        END IF;

        SELECT * INTO v_existing FROM public.test_results
        WHERE order_item_id = p_order_item_id AND parameter_id = v_parameter.id;

        INSERT INTO public.test_results (
            order_item_id, parameter_id, parameter_name, value_type, unit,
            display_value, numeric_value, text_value, flag, is_critical,
            critical_acknowledged, normal_min, normal_max, critical_low, critical_high,
            normal_range_text, status, entered_by, entered_by_name,
            verified_by, verified_by_name, verified_at, result_source
        ) VALUES (
            p_order_item_id,
            v_parameter.id,
            v_parameter.name,
            v_parameter.value_type,
            v_parameter.unit,
            COALESCE(v_result->>'display_value', ''),
            CASE WHEN (v_result->>'numeric_value') IS NOT NULL AND (v_result->>'numeric_value') <> ''
                 THEN (v_result->>'numeric_value')::NUMERIC ELSE NULL END,
            v_result->>'text_value',
            COALESCE((v_result->>'flag')::public.result_flag_enum, 'Normal'),
            COALESCE((v_result->>'is_critical')::BOOLEAN, FALSE),
            COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE),
            CASE WHEN (v_result->>'normal_min') IS NOT NULL AND (v_result->>'normal_min') <> ''
                 THEN (v_result->>'normal_min')::NUMERIC ELSE NULL END,
            CASE WHEN (v_result->>'normal_max') IS NOT NULL AND (v_result->>'normal_max') <> ''
                 THEN (v_result->>'normal_max')::NUMERIC ELSE NULL END,
            CASE WHEN (v_result->>'critical_low') IS NOT NULL AND (v_result->>'critical_low') <> ''
                 THEN (v_result->>'critical_low')::NUMERIC ELSE NULL END,
            CASE WHEN (v_result->>'critical_high') IS NOT NULL AND (v_result->>'critical_high') <> ''
                 THEN (v_result->>'critical_high')::NUMERIC ELSE NULL END,
            v_result->>'normal_range_text',
            p_target_status,
            COALESCE(v_existing.entered_by, auth.uid()),
            COALESCE(v_existing.entered_by_name, v_user_name),
            CASE WHEN p_target_status = 'Verified' THEN auth.uid() ELSE v_existing.verified_by END,
            CASE WHEN p_target_status = 'Verified' THEN v_user_name ELSE v_existing.verified_by_name END,
            CASE WHEN p_target_status = 'Verified' THEN NOW() ELSE v_existing.verified_at END,
            COALESCE(v_result->>'result_source', CASE WHEN v_parameter.value_type = 'Calculated' THEN 'CALCULATED' ELSE 'MANUAL' END)
        )
        ON CONFLICT (order_item_id, parameter_id) DO UPDATE SET
            display_value = EXCLUDED.display_value,
            numeric_value = EXCLUDED.numeric_value,
            text_value = EXCLUDED.text_value,
            flag = EXCLUDED.flag,
            is_critical = EXCLUDED.is_critical,
            critical_acknowledged = EXCLUDED.critical_acknowledged,
            normal_min = EXCLUDED.normal_min,
            normal_max = EXCLUDED.normal_max,
            critical_low = EXCLUDED.critical_low,
            critical_high = EXCLUDED.critical_high,
            normal_range_text = EXCLUDED.normal_range_text,
            status = EXCLUDED.status,
            verified_by = EXCLUDED.verified_by,
            verified_by_name = EXCLUDED.verified_by_name,
            verified_at = EXCLUDED.verified_at,
            result_source = EXCLUDED.result_source,
            updated_at = NOW();

        v_count := v_count + 1;
    END LOOP;

    v_item_status := CASE 
        WHEN p_target_status = 'Verified' THEN 'Verified'
        WHEN p_target_status = 'SubmittedForVerification' THEN 'SampleReceived'
        ELSE 'SampleReceived'
    END;

    UPDATE public.clinical_order_items
    SET status = v_item_status,
        result_revision = result_revision + 1,
        updated_at = NOW()
    WHERE id = p_order_item_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'order_item_id', p_order_item_id,
        'target_status', p_target_status,
        'saved_count', v_count
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.save_test_results(
    p_order_item_id UUID,
    p_results JSONB,
    p_target_status public.result_status_enum,
    p_amended_from_report_id UUID DEFAULT NULL,
    p_amendment_reason TEXT DEFAULT NULL,
    p_expected_revision BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.assert_clinical_result_ready(p_order_item_id);
    RETURN public.save_test_results_unversioned_internal(
        p_order_item_id, p_results, p_target_status, p_amended_from_report_id, p_amendment_reason
    );
END;
$$;

-- Diagnostic Report Signoff & PDF Pipeline
CREATE OR REPLACE FUNCTION public.sign_diagnostic_report(
    p_report_group_id UUID,
    p_signatory_personnel_id UUID,
    p_amendment_reason TEXT DEFAULT NULL,
    p_amended_from_report_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    g RECORD;
    o RECORD;
    p RECORD;
    signer RECORD;
    performer RECORD;
    investigations JSONB;
    snapshot JSONB;
    integrity TEXT;
    report_no TEXT;
    version_no INT := 1;
    is_amendment BOOLEAN := FALSE;
    report_id UUID;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_active_user() THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE='42501';
    END IF;

    SELECT * INTO g FROM public.clinical_report_groups WHERE id = p_report_group_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report group not found.' USING ERRCODE='P0002';
    END IF;

    SELECT * INTO o FROM public.clinical_orders WHERE id = g.order_id;
    SELECT * INTO p FROM public.patients WHERE id = o.patient_id;

    SELECT * INTO signer FROM public.reporting_personnel
    WHERE id = p_signatory_personnel_id AND is_active = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Signatory personnel not found or inactive.' USING ERRCODE='P0002';
    END IF;

    SELECT * INTO performer FROM public.reporting_personnel
    WHERE is_active = TRUE ORDER BY display_order LIMIT 1;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'order_item_id', x.order_item_id,
        'test_id', x.test_id,
        'test_name', x.test_name,
        'test_code', x.test_code,
        'department', x.department,
        'reporting_type', x.reporting_type,
        'method', x.method,
        'specimen_type', x.specimen_type,
        'container_type', x.container_type,
        'results', x.results
    ) ORDER BY x.item_order), '[]'::jsonb)
    INTO investigations FROM (
        SELECT oi.id order_item_id, oi.test_id, gi.frozen_test_name test_name, gi.frozen_test_code test_code, oi.department, oi.reporting_type, t.method, oi.specimen_type, oi.container_type, gi.display_order item_order,
        COALESCE(jsonb_agg(jsonb_build_object(
            'parameter_id', tr.parameter_id,
            'code', param.code,
            'name', tr.parameter_name,
            'value_type', tr.value_type,
            'display_value', tr.display_value,
            'numeric_value', tr.numeric_value,
            'unit', tr.unit,
            'formula', param.formula,
            'flag', tr.flag,
            'is_critical', tr.is_critical,
            'result_source', tr.result_source,
            'reference_range', COALESCE(CASE WHEN tr.normal_min IS NOT NULL AND tr.normal_max IS NOT NULL THEN tr.normal_min::text||' - '||tr.normal_max::text END, tr.normal_range_text, 'Standard'),
            'normal_min', tr.normal_min,
            'normal_max', tr.normal_max,
            'critical_low', tr.critical_low,
            'critical_high', tr.critical_high
        ) ORDER BY param.display_order) FILTER(WHERE tr.id IS NOT NULL), '[]'::jsonb) results
        FROM public.clinical_report_group_items gi
        JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id
        JOIN public.tests t ON t.id=oi.test_id
        LEFT JOIN public.test_results tr ON tr.order_item_id=oi.id
        LEFT JOIN public.parameters param ON param.id=tr.parameter_id
        WHERE gi.report_group_id=g.id
        GROUP BY oi.id, gi.frozen_test_name, gi.frozen_test_code, t.method, oi.specimen_type, oi.container_type, gi.display_order
    ) x;

    snapshot := jsonb_build_object(
        'organization', jsonb_build_object(
            'name', 'Bimal Pathology Laboratory',
            'legal_name', 'Bimal Pathology Laboratory Pvt. Ltd.',
            'phone', '056-593288',
            'email', 'bimalpathology@gmail.com',
            'address_line1', 'Bharatpur-10, Chitwan, Nepal'
        ),
        'patient', jsonb_build_object(
            'uhid', p.uhid,
            'full_name', p.full_name,
            'age_gender', COALESCE(p.age_years || ' Y / ' || p.gender, p.gender),
            'mobile', p.mobile,
            'address', p.address
        ),
        'order', jsonb_build_object(
            'order_number', o.order_number,
            'order_date_ad', o.order_date_ad,
            'order_date_bs', o.order_date_bs
        ),
        'signatories', jsonb_build_object(
            'authorized_by', jsonb_build_object(
                'id', signer.id,
                'full_name', signer.full_name,
                'qualification', signer.qualification,
                'registration_council', signer.registration_council,
                'registration_number', signer.registration_number,
                'signature_url', signer.signature_url
            )
        ),
        'investigations', investigations,
        'signed_at', NOW()
    );

    integrity := encode(extensions.digest(convert_to(o.order_number||'|'||g.group_key||'|v'||version_no||'|'||snapshot::text,'UTF8'),'sha256'),'hex');
    report_no := 'REP-'||to_char(CURRENT_DATE,'YYYY')||'-'||lpad(nextval('public.report_seq')::text,5,'0');

    INSERT INTO public.diagnostic_reports (
        order_id, report_group_id, patient_id, report_number, version,
        is_amendment, amendment_reason, amended_from_report_id, status,
        integrity_hash, performed_by_personnel_id, performed_by_personnel_name,
        verified_by_personnel_id, verified_by_personnel_name,
        signed_by_personnel_id, signed_by_personnel_name, signed_at,
        pdf_storage_path, clinical_snapshot_json
    ) VALUES (
        o.id, g.id, o.patient_id, report_no, version_no,
        is_amendment, p_amendment_reason, p_amended_from_report_id, 'SignedOff',
        integrity, performer.id, performer.full_name,
        signer.id, signer.full_name,
        signer.id, signer.full_name, NOW(),
        'reports/'||o.id||'/'||g.group_key||'/v'||version_no||'/report.pdf',
        snapshot
    ) RETURNING id INTO report_id;

    UPDATE public.clinical_order_items oi
    SET status = 'SignedOff', updated_at = NOW()
    FROM public.clinical_report_group_items gi
    WHERE gi.report_group_id = g.id AND gi.order_item_id = oi.id;

    UPDATE public.test_results tr
    SET status = 'SignedOff', signed_off_by = auth.uid(), signed_off_name = signer.full_name, signed_off_at = NOW(), updated_at = NOW()
    FROM public.clinical_report_group_items gi
    WHERE gi.report_group_id = g.id AND gi.order_item_id = tr.order_item_id;

    UPDATE public.clinical_report_groups
    SET status = 'SignedOff', updated_at = NOW()
    WHERE id = g.id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'report_id', report_id,
        'report_number', report_no,
        'integrity_hash', integrity
    );
END;
$$;

-- Fast Billing Catalogue Search RPC
CREATE OR REPLACE FUNCTION public.billing_fast_catalogue_search(p_query TEXT, p_limit INT DEFAULT 20)
RETURNS TABLE (
    id UUID,
    code VARCHAR(50),
    name VARCHAR(255),
    category VARCHAR(100),
    department VARCHAR(100),
    sample_type VARCHAR(100),
    container VARCHAR(100),
    price_paisa BIGINT,
    reporting_type public.reporting_type_enum,
    test_type VARCHAR(50)
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT 
        t.id, t.code, t.name, t.category, t.department,
        t.sample_type, t.container,
        COALESCE(rv.price_paisa, t.price_paisa) AS price_paisa,
        t.reporting_type, t.test_type
    FROM public.tests t
    LEFT JOIN LATERAL (
        SELECT price_paisa FROM public.catalogue_rate_versions
        WHERE test_id = t.id AND status = 'Active' AND (effective_to IS NULL OR effective_to > NOW())
        ORDER BY version_number DESC LIMIT 1
    ) rv ON TRUE
    WHERE t.is_active = TRUE
      AND (
          p_query IS NULL OR p_query = '' OR
          t.code ILIKE '%' || p_query || '%' OR
          t.name ILIKE '%' || p_query || '%' OR
          t.short_name ILIKE '%' || p_query || '%'
      )
    ORDER BY t.code
    LIMIT p_limit;
$$;

-- Deterministic UHID sequence generator
CREATE SEQUENCE IF NOT EXISTS public.patient_uhid_seq START WITH 10001;

CREATE OR REPLACE FUNCTION public.generate_deterministic_patient_uhid()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.uhid IS NULL OR btrim(NEW.uhid) = '' THEN
        NEW.uhid := 'BP-' || to_char(CURRENT_DATE, 'YYYY') || '-' || lpad(nextval('public.patient_uhid_seq')::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_patients_uhid ON public.patients;
CREATE TRIGGER trg_patients_uhid
BEFORE INSERT ON public.patients
FOR EACH ROW EXECUTE FUNCTION public.generate_deterministic_patient_uhid();

-- ============================================================================
-- 5. ROW LEVEL SECURITY (RLS) POLICIES & GRANTS
-- ============================================================================

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_direct_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referring_doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reporting_personnel ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.test_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.test_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parameters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reference_ranges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_panel_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_panel_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.health_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.health_package_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_rate_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analyzers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analyzer_parameter_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bill_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.samples ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sample_lifecycle_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.test_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_report_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_report_group_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnostic_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sms_queue_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_report_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Catalogue read access for active authenticated users
CREATE POLICY catalogue_tests_select ON public.tests FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY catalogue_params_select ON public.parameters FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY catalogue_ranges_select ON public.reference_ranges FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY catalogue_categories_select ON public.test_categories FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY catalogue_comps_select ON public.catalogue_panel_components FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY catalogue_rates_select ON public.catalogue_rate_versions FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY analyzers_select ON public.analyzers FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY analyzer_mappings_select ON public.analyzer_parameter_mappings FOR SELECT TO authenticated USING (public.is_active_user());

-- Clinical Operations RLS Policies
CREATE POLICY patients_all ON public.patients FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY bills_all ON public.bills FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY bill_items_all ON public.bill_items FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY payments_all ON public.payment_transactions FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY orders_all ON public.clinical_orders FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY samples_all ON public.samples FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY order_items_all ON public.clinical_order_items FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY test_results_all ON public.test_results FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY report_groups_all ON public.clinical_report_groups FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY report_group_items_all ON public.clinical_report_group_items FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY diagnostic_reports_all ON public.diagnostic_reports FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY referring_doctors_all ON public.referring_doctors FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY reporting_personnel_all ON public.reporting_personnel FOR ALL TO authenticated USING (public.is_active_user());
CREATE POLICY user_profiles_select ON public.user_profiles FOR SELECT TO authenticated USING (public.is_active_user());

-- Public verification access
CREATE POLICY public_tokens_select ON public.public_report_tokens FOR SELECT TO anon, authenticated USING (TRUE);

-- Role Grants
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

GRANT SELECT ON public.public_report_tokens TO anon;

-- ============================================================================
-- 6. MASTER SEED DATA (ROLES, CATEGORIES, ANALYZERS, PERSONNEL)
-- ============================================================================

-- Roles & Permissions
INSERT INTO public.roles (name, description, is_system) VALUES
('admin', 'Full system administration and laboratory management', TRUE),
('lab_technician', 'Standard laboratory technician operations', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_key)
SELECT r.id, p.perm
FROM public.roles r
CROSS JOIN (
    VALUES 
    ('can_manage_catalogue'), ('can_configure_catalogue_technical'),
    ('can_create_bills'), ('can_collect_samples'), ('can_receive_samples'),
    ('can_enter_results'), ('can_verify_results'), ('can_sign_reports'),
    ('can_view_reports'), ('can_view_audit_logs'), ('can_manage_users'),
    ('can_manage_rates'), ('can_manage_personnel'), ('can_manage_doctors')
) p(perm)
WHERE r.name = 'admin'
ON CONFLICT DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_key)
SELECT r.id, p.perm
FROM public.roles r
CROSS JOIN (
    VALUES 
    ('can_create_bills'), ('can_collect_samples'), ('can_receive_samples'),
    ('can_enter_results'), ('can_verify_results'), ('can_view_reports')
) p(perm)
WHERE r.name = 'lab_technician'
ON CONFLICT DO NOTHING;

-- Referring Doctors Seed
INSERT INTO public.referring_doctors (full_name, code, degree, institution, phone, is_active) VALUES
('Self / Direct Walk-In', 'DOC-SELF', 'N/A', 'Bimal Pathology', '056-593288', TRUE),
('Dr. Bimal Sharma', 'DOC-0001', 'MD (Pathology)', 'Bharatpur Hospital', '9855001122', TRUE)
ON CONFLICT (code) DO NOTHING;

-- Reporting Personnel Seed
INSERT INTO public.reporting_personnel (
    full_name, professional_type, qualification, registration_council,
    registration_number, specialization, can_enter_results, can_verify_results,
    can_sign_reports, is_active, display_order
) VALUES
('Dr. Bimal Sharma', 'MD Pathologist', 'MBBS, MD (Pathology)', 'Nepal Medical Council (NMC)', '12345-MED', 'Consultant Pathologist', TRUE, TRUE, TRUE, TRUE, 1),
('Bikash Adhikari', 'BSc MLT', 'BSc MLT, NHPC Reg.', 'Nepal Health Professional Council (NHPC)', '67890-MLT', 'Senior Medical Technologist', TRUE, TRUE, FALSE, TRUE, 2)
ON CONFLICT DO NOTHING;

-- Analyzers


-- ============================================================================
-- ADDITIONAL OPERATIONAL & WORKFLOW TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.outsource_samples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sample_id UUID NOT NULL REFERENCES public.samples(id) ON DELETE CASCADE,
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    reference_lab_id UUID,
    outsource_lab_name VARCHAR(255) NOT NULL,
    tracking_number VARCHAR(100),
    status public.outsource_item_state_enum NOT NULL DEFAULT 'Registered',
    dispatched_at TIMESTAMPTZ,
    received_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.outsource_sample_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    outsource_sample_id UUID NOT NULL REFERENCES public.outsource_samples(id) ON DELETE CASCADE,
    from_status public.outsource_item_state_enum,
    to_status public.outsource_item_state_enum NOT NULL,
    actor_id UUID REFERENCES auth.users(id),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.reference_laboratories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    code VARCHAR(50) NOT NULL UNIQUE,
    contact_person VARCHAR(100),
    phone VARCHAR(50),
    email VARCHAR(255),
    address TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.billing_idempotency_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    idempotency_key VARCHAR(255) NOT NULL UNIQUE,
    bill_id UUID REFERENCES public.bills(id) ON DELETE SET NULL,
    response_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.payment_idempotency_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    idempotency_key VARCHAR(255) NOT NULL UNIQUE,
    payment_id UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
    response_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bill_package_selections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE CASCADE,
    package_id UUID NOT NULL REFERENCES public.health_packages(id) ON DELETE RESTRICT,
    package_code VARCHAR(50) NOT NULL,
    package_name VARCHAR(255) NOT NULL,
    unit_price_paisa BIGINT NOT NULL DEFAULT 0,
    discount_paisa BIGINT NOT NULL DEFAULT 0,
    net_price_paisa BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bill_package_components (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_package_selection_id UUID NOT NULL REFERENCES public.bill_package_selections(id) ON DELETE CASCADE,
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
    test_code VARCHAR(50) NOT NULL,
    test_name VARCHAR(255) NOT NULL,
    allocated_price_paisa BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bill_panel_selections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE CASCADE,
    panel_test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
    panel_code VARCHAR(50) NOT NULL,
    panel_name VARCHAR(255) NOT NULL,
    unit_price_paisa BIGINT NOT NULL DEFAULT 0,
    discount_paisa BIGINT NOT NULL DEFAULT 0,
    net_price_paisa BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bill_panel_components (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_panel_selection_id UUID NOT NULL REFERENCES public.bill_panel_selections(id) ON DELETE CASCADE,
    component_test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
    component_code VARCHAR(50) NOT NULL,
    component_name VARCHAR(255) NOT NULL,
    allocated_price_paisa BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.test_analyzer_configurations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    parameter_id UUID REFERENCES public.parameters(id) ON DELETE CASCADE,
    analyzer_id UUID NOT NULL REFERENCES public.analyzers(id) ON DELETE CASCADE,
    method VARCHAR(255),
    assay_identifier VARCHAR(100),
    configuration_version VARCHAR(50) NOT NULL DEFAULT 'V1',
    effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
    validation_state VARCHAR(50) NOT NULL DEFAULT 'ClinicallyValidated',
    validation_source TEXT,
    is_clinically_approved BOOLEAN NOT NULL DEFAULT TRUE,
    lifecycle_status VARCHAR(50) NOT NULL DEFAULT 'Active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_organism_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_isolates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE CASCADE,
    sample_id UUID NOT NULL REFERENCES public.samples(id) ON DELETE CASCADE,
    isolate_number INT NOT NULL DEFAULT 1,
    microorganism_id UUID REFERENCES public.ast_microorganisms(id) ON DELETE SET NULL,
    organism_name VARCHAR(255) NOT NULL,
    colony_count VARCHAR(100),
    clinical_significance VARCHAR(100) DEFAULT 'Pathogen',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_observations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    isolate_id UUID NOT NULL REFERENCES public.ast_isolates(id) ON DELETE CASCADE,
    antibiotic_id UUID REFERENCES public.ast_antibiotics(id) ON DELETE SET NULL,
    antibiotic_name VARCHAR(255) NOT NULL,
    zone_diameter_mm NUMERIC(6, 2),
    mic_ug_ml NUMERIC(10, 4),
    interpretation VARCHAR(50) NOT NULL DEFAULT 'Pending',
    breakpoint_rule_id UUID REFERENCES public.ast_breakpoint_rules(id) ON DELETE SET NULL,
    method VARCHAR(50) DEFAULT 'Kirby-Bauer Disk Diffusion',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_observation_audit (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    observation_id UUID NOT NULL REFERENCES public.ast_observations(id) ON DELETE CASCADE,
    previous_interpretation VARCHAR(50),
    new_interpretation VARCHAR(50),
    actor_id UUID REFERENCES auth.users(id),
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.pus_culture_worksheets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE CASCADE,
    sample_id UUID NOT NULL REFERENCES public.samples(id) ON DELETE CASCADE,
    specimen_appearance VARCHAR(100),
    gram_stain_pus_cells VARCHAR(100),
    gram_stain_epithelial_cells VARCHAR(100),
    gram_stain_organisms TEXT,
    culture_aerobic_growth VARCHAR(100),
    culture_anaerobic_growth VARCHAR(100),
    biochemical_reactions JSONB,
    final_report TEXT,
    entered_by UUID REFERENCES auth.users(id),
    verified_by UUID REFERENCES auth.users(id),
    status VARCHAR(50) DEFAULT 'Draft',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.catalogue_option_sets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    data_type VARCHAR(50) NOT NULL DEFAULT 'Text',
    is_system BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.catalogue_option_values (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    option_set_id UUID NOT NULL REFERENCES public.catalogue_option_sets(id) ON DELETE CASCADE,
    value VARCHAR(255) NOT NULL,
    label VARCHAR(255) NOT NULL,
    is_abnormal BOOLEAN NOT NULL DEFAULT FALSE,
    is_critical BOOLEAN NOT NULL DEFAULT FALSE,
    display_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_option_set_val UNIQUE (option_set_id, value)
);

CREATE TABLE IF NOT EXISTS public.report_secure_link_presentations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_id UUID NOT NULL REFERENCES public.diagnostic_reports(id) ON DELETE CASCADE,
    token VARCHAR(255) NOT NULL UNIQUE,
    url TEXT NOT NULL,
    qr_code_data TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    access_count INT NOT NULL DEFAULT 0,
    last_accessed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sms_gateway_instances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    instance_name VARCHAR(100) NOT NULL UNIQUE,
    api_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_heartbeat TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.hmis_facility_configuration (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_code VARCHAR(50) NOT NULL UNIQUE,
    facility_name VARCHAR(255) NOT NULL,
    district VARCHAR(100) NOT NULL,
    province VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.hmis_monthly_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nepali_year INT NOT NULL,
    nepali_month INT NOT NULL,
    english_start_date DATE NOT NULL,
    english_end_date DATE NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'Draft',
    report_data JSONB NOT NULL DEFAULT '{}'::JSONB,
    submission_metadata JSONB,
    finalized_by UUID REFERENCES auth.users(id),
    finalized_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_hmis_period UNIQUE (nepali_year, nepali_month)
);

CREATE TABLE IF NOT EXISTS public.hmis_monthly_manual_values (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_id UUID NOT NULL REFERENCES public.hmis_monthly_reports(id) ON DELETE CASCADE,
    indicator_code VARCHAR(100) NOT NULL,
    gender VARCHAR(20) NOT NULL DEFAULT 'All',
    age_group VARCHAR(50) NOT NULL DEFAULT 'All',
    manual_count INT NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_hmis_manual_val UNIQUE (report_id, indicator_code, gender, age_group)
);

CREATE TABLE IF NOT EXISTS public.hmis_submission_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_id UUID NOT NULL REFERENCES public.hmis_monthly_reports(id) ON DELETE CASCADE,
    submission_status VARCHAR(50) NOT NULL,
    payload JSONB,
    response JSONB,
    actor_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.critical_value_policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parameter_id UUID NOT NULL REFERENCES public.parameters(id) ON DELETE CASCADE,
    critical_low NUMERIC(10, 3),
    critical_high NUMERIC(10, 3),
    action_protocol TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.critical_alert_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    result_id UUID NOT NULL REFERENCES public.test_results(id) ON DELETE CASCADE,
    parameter_id UUID NOT NULL REFERENCES public.parameters(id) ON DELETE CASCADE,
    value_numeric NUMERIC(10, 3),
    value_text TEXT,
    flag public.result_flag_enum NOT NULL,
    acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
    acknowledged_by UUID REFERENCES auth.users(id),
    acknowledged_at TIMESTAMPTZ,
    doctor_notified BOOLEAN NOT NULL DEFAULT FALSE,
    doctor_notified_at TIMESTAMPTZ,
    notification_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);





-- ============================================================================
-- 4. ADDITIONAL OPERATIONAL & WORKFLOW TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.outsource_samples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sample_id UUID NOT NULL REFERENCES public.samples(id) ON DELETE CASCADE,
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    reference_lab_id UUID,
    outsource_lab_name VARCHAR(255) NOT NULL,
    tracking_number VARCHAR(100),
    status public.outsource_item_state_enum NOT NULL DEFAULT 'Registered',
    dispatched_at TIMESTAMPTZ,
    received_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.outsource_sample_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    outsource_sample_id UUID NOT NULL REFERENCES public.outsource_samples(id) ON DELETE CASCADE,
    from_status public.outsource_item_state_enum,
    to_status public.outsource_item_state_enum NOT NULL,
    actor_id UUID REFERENCES auth.users(id),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.reference_laboratories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    code VARCHAR(50) NOT NULL UNIQUE,
    contact_person VARCHAR(100),
    phone VARCHAR(50),
    email VARCHAR(255),
    address TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.billing_idempotency_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    idempotency_key VARCHAR(255) NOT NULL UNIQUE,
    bill_id UUID REFERENCES public.bills(id) ON DELETE SET NULL,
    response_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.payment_idempotency_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    idempotency_key VARCHAR(255) NOT NULL UNIQUE,
    payment_id UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
    response_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bill_package_selections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE CASCADE,
    package_id UUID NOT NULL REFERENCES public.health_packages(id) ON DELETE RESTRICT,
    package_code VARCHAR(50) NOT NULL,
    package_name VARCHAR(255) NOT NULL,
    unit_price_paisa BIGINT NOT NULL DEFAULT 0,
    discount_paisa BIGINT NOT NULL DEFAULT 0,
    net_price_paisa BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bill_package_components (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_package_selection_id UUID NOT NULL REFERENCES public.bill_package_selections(id) ON DELETE CASCADE,
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
    test_code VARCHAR(50) NOT NULL,
    test_name VARCHAR(255) NOT NULL,
    allocated_price_paisa BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bill_panel_selections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE CASCADE,
    panel_test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
    panel_code VARCHAR(50) NOT NULL,
    panel_name VARCHAR(255) NOT NULL,
    unit_price_paisa BIGINT NOT NULL DEFAULT 0,
    discount_paisa BIGINT NOT NULL DEFAULT 0,
    net_price_paisa BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bill_panel_components (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_panel_selection_id UUID NOT NULL REFERENCES public.bill_panel_selections(id) ON DELETE CASCADE,
    component_test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
    component_code VARCHAR(50) NOT NULL,
    component_name VARCHAR(255) NOT NULL,
    allocated_price_paisa BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.test_analyzer_configurations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    parameter_id UUID REFERENCES public.parameters(id) ON DELETE CASCADE,
    analyzer_id UUID NOT NULL REFERENCES public.analyzers(id) ON DELETE CASCADE,
    method VARCHAR(255),
    assay_identifier VARCHAR(100),
    configuration_version VARCHAR(50) NOT NULL DEFAULT 'V1',
    effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
    validation_state VARCHAR(50) NOT NULL DEFAULT 'ClinicallyValidated',
    validation_source TEXT,
    is_clinically_approved BOOLEAN NOT NULL DEFAULT TRUE,
    lifecycle_status VARCHAR(50) NOT NULL DEFAULT 'Active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_organism_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_isolates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE CASCADE,
    sample_id UUID NOT NULL REFERENCES public.samples(id) ON DELETE CASCADE,
    isolate_number INT NOT NULL DEFAULT 1,
    microorganism_id UUID REFERENCES public.ast_microorganisms(id) ON DELETE SET NULL,
    organism_name VARCHAR(255) NOT NULL,
    colony_count VARCHAR(100),
    clinical_significance VARCHAR(100) DEFAULT 'Pathogen',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_observations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    isolate_id UUID NOT NULL REFERENCES public.ast_isolates(id) ON DELETE CASCADE,
    antibiotic_id UUID REFERENCES public.ast_antibiotics(id) ON DELETE SET NULL,
    antibiotic_name VARCHAR(255) NOT NULL,
    zone_diameter_mm NUMERIC(6, 2),
    mic_ug_ml NUMERIC(10, 4),
    interpretation VARCHAR(50) NOT NULL DEFAULT 'Pending',
    breakpoint_rule_id UUID REFERENCES public.ast_breakpoint_rules(id) ON DELETE SET NULL,
    method VARCHAR(50) DEFAULT 'Kirby-Bauer Disk Diffusion',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_observation_audit (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    observation_id UUID NOT NULL REFERENCES public.ast_observations(id) ON DELETE CASCADE,
    previous_interpretation VARCHAR(50),
    new_interpretation VARCHAR(50),
    actor_id UUID REFERENCES auth.users(id),
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.pus_culture_worksheets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE CASCADE,
    sample_id UUID NOT NULL REFERENCES public.samples(id) ON DELETE CASCADE,
    specimen_appearance VARCHAR(100),
    gram_stain_pus_cells VARCHAR(100),
    gram_stain_epithelial_cells VARCHAR(100),
    gram_stain_organisms TEXT,
    culture_aerobic_growth VARCHAR(100),
    culture_anaerobic_growth VARCHAR(100),
    biochemical_reactions JSONB,
    final_report TEXT,
    entered_by UUID REFERENCES auth.users(id),
    verified_by UUID REFERENCES auth.users(id),
    status VARCHAR(50) DEFAULT 'Draft',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.catalogue_option_sets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    data_type VARCHAR(50) NOT NULL DEFAULT 'Text',
    is_system BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.catalogue_option_values (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    option_set_id UUID NOT NULL REFERENCES public.catalogue_option_sets(id) ON DELETE CASCADE,
    value VARCHAR(255) NOT NULL,
    label VARCHAR(255) NOT NULL,
    is_abnormal BOOLEAN NOT NULL DEFAULT FALSE,
    is_critical BOOLEAN NOT NULL DEFAULT FALSE,
    display_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_option_set_val UNIQUE (option_set_id, value)
);

CREATE TABLE IF NOT EXISTS public.report_secure_link_presentations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_id UUID NOT NULL REFERENCES public.diagnostic_reports(id) ON DELETE CASCADE,
    token VARCHAR(255) NOT NULL UNIQUE,
    url TEXT NOT NULL,
    qr_code_data TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    access_count INT NOT NULL DEFAULT 0,
    last_accessed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sms_gateway_instances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    instance_name VARCHAR(100) NOT NULL UNIQUE,
    api_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_heartbeat TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.hmis_facility_configuration (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_code VARCHAR(50) NOT NULL UNIQUE,
    facility_name VARCHAR(255) NOT NULL,
    district VARCHAR(100) NOT NULL,
    province VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.hmis_monthly_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nepali_year INT NOT NULL,
    nepali_month INT NOT NULL,
    english_start_date DATE NOT NULL,
    english_end_date DATE NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'Draft',
    report_data JSONB NOT NULL DEFAULT '{}'::JSONB,
    submission_metadata JSONB,
    finalized_by UUID REFERENCES auth.users(id),
    finalized_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_hmis_period UNIQUE (nepali_year, nepali_month)
);

CREATE TABLE IF NOT EXISTS public.hmis_monthly_manual_values (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_id UUID NOT NULL REFERENCES public.hmis_monthly_reports(id) ON DELETE CASCADE,
    indicator_code VARCHAR(100) NOT NULL,
    gender VARCHAR(20) NOT NULL DEFAULT 'All',
    age_group VARCHAR(50) NOT NULL DEFAULT 'All',
    manual_count INT NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_hmis_manual_val UNIQUE (report_id, indicator_code, gender, age_group)
);

CREATE TABLE IF NOT EXISTS public.hmis_submission_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_id UUID NOT NULL REFERENCES public.hmis_monthly_reports(id) ON DELETE CASCADE,
    submission_status VARCHAR(50) NOT NULL,
    payload JSONB,
    response JSONB,
    actor_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.critical_value_policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parameter_id UUID NOT NULL REFERENCES public.parameters(id) ON DELETE CASCADE,
    critical_low NUMERIC(10, 3),
    critical_high NUMERIC(10, 3),
    action_protocol TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.critical_alert_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    result_id UUID NOT NULL REFERENCES public.test_results(id) ON DELETE CASCADE,
    parameter_id UUID NOT NULL REFERENCES public.parameters(id) ON DELETE CASCADE,
    value_numeric NUMERIC(10, 3),
    value_text TEXT,
    flag public.result_flag_enum NOT NULL,
    acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
    acknowledged_by UUID REFERENCES auth.users(id),
    acknowledged_at TIMESTAMPTZ,
    doctor_notified BOOLEAN NOT NULL DEFAULT FALSE,
    doctor_notified_at TIMESTAMPTZ,
    notification_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 5. BUSINESS FUNCTIONS & APPLICATION RPCS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.acknowledge_critical_result(
    p_result_id UUID,
    p_notified_person VARCHAR(255),
    p_notification_method VARCHAR(100),
    p_notification_comment TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_name VARCHAR(255);
    v_res RECORD;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    IF NOT (public.has_permission('can_acknowledge_critical') OR public.has_permission('can_verify_results') OR public.has_permission('can_sign_reports')) THEN
        RAISE EXCEPTION 'Access Denied: Missing can_acknowledge_critical permission.';
    END IF;

    IF TRIM(COALESCE(p_notified_person, '')) = '' THEN
        RAISE EXCEPTION 'Notified person (clinician/nurse) is mandatory.';
    END IF;

    SELECT full_name INTO v_actor_name FROM public.user_profiles WHERE id = auth.uid();
    IF v_actor_name IS NULL THEN
        v_actor_name := 'Authorized Staff';
    END IF;

    SELECT tr.*, coi.test_name, coi.order_id INTO v_res
    FROM public.test_results tr
    JOIN public.clinical_order_items coi ON tr.order_item_id = coi.id
    WHERE tr.id = p_result_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Result record % not found.', p_result_id;
    END IF;

    UPDATE public.test_results
    SET critical_acknowledged = TRUE,
        critical_acknowledged_by = auth.uid(),
        critical_acknowledged_at = NOW(),
        updated_at = NOW()
    WHERE id = p_result_id;

    -- Append to audit log
    INSERT INTO public.audit_logs (
        user_id,
        user_name,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        auth.uid(),
        v_actor_name,
        'CRITICAL_VALUE_ACKNOWLEDGED',
        'TestResult',
        p_result_id::TEXT,
        jsonb_build_object(
            'parameter_name', v_res.parameter_name,
            'test_name', v_res.test_name,
            'flag', v_res.flag,
            'display_value', v_res.display_value,
            'notified_person', p_notified_person,
            'notification_method', p_notification_method,
            'notification_comment', p_notification_comment
        )
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'result_id', p_result_id,
        'critical_acknowledged', TRUE,
        'acknowledged_at', NOW()
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.acknowledge_critical_result TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.allocate_patient_uhid(
    p_normalized_mobile TEXT,
    p_registered_at TIMESTAMPTZ
)
RETURNS VARCHAR(10)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_registration_date DATE := (p_registered_at AT TIME ZONE 'Asia/Kathmandu')::DATE;
    v_prefix TEXT := TO_CHAR(v_registration_date, 'YYMMDD');
    v_digest TEXT;
    v_base INTEGER;
    v_code INTEGER;
    v_candidate VARCHAR(10);
BEGIN
    IF p_normalized_mobile !~ '^(97|98)[0-9]{8}$' THEN
        RAISE EXCEPTION 'A normalized 10-digit Nepal mobile is required for UHID allocation.'
            USING ERRCODE = '22023';
    END IF;
    IF p_registered_at IS NULL THEN
        RAISE EXCEPTION 'A registration timestamp is required for UHID allocation.'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('patient-uhid-day:' || v_prefix, 0));

    v_digest := encode(extensions.digest(
        convert_to('BIMAL-UHID-V1:' || p_normalized_mobile || ':' || v_prefix, 'UTF8'),
        'sha256'
    ), 'hex');
    v_base := (('x' || substring(v_digest FROM 1 FOR 8))::BIT(32)::BIGINT % 10000)::INTEGER;

    FOR v_attempt IN 0..9999 LOOP
        v_code := (v_base + (v_attempt * 7919)) % 10000;
        v_candidate := v_prefix || LPAD(v_code::TEXT, 4, '0');
        IF NOT EXISTS (SELECT 1 FROM public.patients WHERE uhid = v_candidate) THEN
            RETURN v_candidate;
        END IF;
    END LOOP;

    RAISE EXCEPTION 'UHID namespace exhausted for Nepal registration date %.', v_registration_date
        USING ERRCODE = '54000';
END;
$$;

GRANT EXECUTE ON FUNCTION public.allocate_patient_uhid TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.assert_clinical_result_ready(p_order_item_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE state JSONB;
BEGIN
  state:=public.clinical_result_collection_readiness(p_order_item_id);
  IF NOT COALESCE((state->>'ready')::BOOLEAN,FALSE) THEN
    RAISE EXCEPTION USING
      ERRCODE='55000',
      MESSAGE=COALESCE(state->>'code','RESULT_COLLECTION_NOT_READY'),
      DETAIL=state::TEXT;
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.assert_clinical_result_ready TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.assert_sms_gateway_v2_identity(p_instance_id UUID)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE registered public.sms_gateway_instances%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Gateway authentication required.' USING ERRCODE='42501'; END IF;
  SELECT * INTO registered FROM public.sms_gateway_instances WHERE instance_id=p_instance_id;
  IF NOT FOUND OR registered.auth_user_id<>auth.uid() OR NOT registered.is_enabled THEN
    RAISE EXCEPTION 'Gateway identity is not authorized.' USING ERRCODE='42501';
  END IF;
  IF EXISTS(SELECT 1 FROM public.user_profiles WHERE id=auth.uid() AND is_active) THEN
    RAISE EXCEPTION 'Gateway identity must not have an active LIS staff profile.' USING ERRCODE='42501';
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.assert_sms_gateway_v2_identity TO authenticated, service_role;

CREATE FUNCTION public.assign_bpdc_lab_no() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE candidate VARCHAR(13); reserved_count INT; attempt INT; random_number BIGINT;
BEGIN
  FOR attempt IN 1..100 LOOP
    random_number := 10000000 + ((('x'||encode(extensions.gen_random_bytes(4),'hex'))::bit(32)::BIGINT) % 90000000);
    candidate := 'BPDC-'||lpad(random_number::TEXT,8,'0');
    INSERT INTO public.lab_number_registry(lab_no) VALUES(candidate) ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS reserved_count=ROW_COUNT;
    IF reserved_count=1 THEN NEW.order_number:=candidate; RETURN NEW; END IF;
  END LOOP;
  RAISE EXCEPTION 'Unable to allocate a unique BPDC Lab No after 100 attempts.' USING ERRCODE='23505';
END $$;

GRANT EXECUTE ON FUNCTION public.assign_bpdc_lab_no TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_activate_breakpoint_set(p_set_id UUID,p_expected_revision BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE target public.ast_breakpoint_sets%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO target FROM public.ast_breakpoint_sets WHERE id=p_set_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Breakpoint set not found.' USING ERRCODE='23503'; END IF;
 IF target.row_version<>p_expected_revision THEN RAISE EXCEPTION 'Breakpoint version changed. Reload.' USING ERRCODE='PT409'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ast_breakpoint_rules WHERE breakpoint_set_id=target.id) THEN RAISE EXCEPTION 'Breakpoint set has no rules.' USING ERRCODE='23514'; END IF;
 UPDATE public.ast_breakpoint_sets SET status='Retired',is_active=FALSE,retired_at=now(),row_version=row_version+1 WHERE is_active AND id<>target.id;
 UPDATE public.ast_breakpoint_sets SET status='Active',is_active=TRUE,approved_by=auth.uid(),approved_at=now(),row_version=row_version+1 WHERE id=target.id RETURNING * INTO target;
 RETURN to_jsonb(target);
END $$;

GRANT EXECUTE ON FUNCTION public.ast_activate_breakpoint_set TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_clone_breakpoint_set(p_source_id UUID,p_new_version TEXT,p_effective_date DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE source public.ast_breakpoint_sets%ROWTYPE; target public.ast_breakpoint_sets%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO source FROM public.ast_breakpoint_sets WHERE id=p_source_id; IF NOT FOUND THEN RAISE EXCEPTION 'Source breakpoint set not found.' USING ERRCODE='23503'; END IF;
 INSERT INTO public.ast_breakpoint_sets(name,version,effective_date,provenance,status,is_active,created_by) VALUES(source.name,btrim(p_new_version),p_effective_date,source.provenance,'Draft',FALSE,auth.uid()) RETURNING * INTO target;
 INSERT INTO public.ast_breakpoint_rules(breakpoint_set_id,organism_group_id,antibiotic_id,method,metric_type,potency,automatic_interpretation_allowed,susceptible_min,susceptible_max,susceptible_secondary,intermediate_min,intermediate_max,intermediate_secondary_min,intermediate_secondary_max,resistant_min,resistant_max,resistant_secondary,intermediate_semantics,interpretation_semantics,notes)
 SELECT target.id,organism_group_id,antibiotic_id,method,metric_type,potency,automatic_interpretation_allowed,susceptible_min,susceptible_max,susceptible_secondary,intermediate_min,intermediate_max,intermediate_secondary_min,intermediate_secondary_max,resistant_min,resistant_max,resistant_secondary,intermediate_semantics,interpretation_semantics,notes FROM public.ast_breakpoint_rules WHERE breakpoint_set_id=source.id;
 RETURN to_jsonb(target);
END $$;

GRANT EXECUTE ON FUNCTION public.ast_clone_breakpoint_set TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_enrich_frozen_report_snapshot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE inv JSONB; enriched JSONB:='[]'::JSONB; isolates JSONB; worksheet JSONB;
BEGIN
 FOR inv IN SELECT value FROM jsonb_array_elements(COALESCE(NEW.clinical_snapshot_json->'investigations','[]'::JSONB)) LOOP
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'isolate_number',i.isolate_number,'organism',i.organism_name_snapshot,'organism_group',i.organism_group_snapshot,'growth_state',i.growth_state,
   'breakpoint_reference',CASE WHEN i.growth_state='Positive' THEN (SELECT 'AST interpreted using laboratory-approved breakpoint set '||max(o.breakpoint_set_version_snapshot) FROM public.ast_observations o WHERE o.isolate_id=i.id) END,
   'observations',COALESCE((SELECT jsonb_agg(jsonb_build_object('antibiotic',o.antibiotic_name_snapshot,'antibiotic_code',o.antibiotic_code_snapshot,
    'method',o.method,'metric_type',o.metric_type,'metric_value',o.metric_value,'metric_secondary_value',o.metric_secondary_value,
    'interpretation',o.final_interpretation,'automatic_interpretation',o.automatic_interpretation,'manual_override',o.manual_override,
    'breakpoint_version',o.breakpoint_set_version_snapshot) ORDER BY o.antibiotic_name_snapshot) FROM public.ast_observations o WHERE o.isolate_id=i.id),'[]'::JSONB)
  ) ORDER BY i.isolate_number),'[]'::JSONB) INTO isolates FROM public.ast_isolates i WHERE i.order_item_id=(inv->>'order_item_id')::UUID;
  SELECT jsonb_build_object('specimen_source',w.specimen_source,'specimen_source_other',w.specimen_source_other,'gram_stain_pus_cells',w.gram_stain_pus_cells,
   'direct_smear_organisms',w.direct_smear_organisms,'culture_status',w.culture_status,'final_remarks',w.final_remarks,'status',w.status,'row_version',w.row_version)
   INTO worksheet FROM public.pus_culture_worksheets w WHERE w.order_item_id=(inv->>'order_item_id')::UUID;
  enriched:=enriched||jsonb_build_array(inv||jsonb_build_object('ast_isolates',isolates,'pus_culture_worksheet',worksheet));
 END LOOP;
 NEW.clinical_snapshot_json:=jsonb_set(NEW.clinical_snapshot_json,'{investigations}',enriched,TRUE); RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.ast_enrich_frozen_report_snapshot TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_guard_used_breakpoint_mutation() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.ast_observations WHERE breakpoint_set_id=OLD.id) AND
   (TG_OP='DELETE' OR OLD.name IS DISTINCT FROM NEW.name OR OLD.version IS DISTINCT FROM NEW.version OR OLD.effective_date IS DISTINCT FROM NEW.effective_date OR OLD.provenance IS DISTINCT FROM NEW.provenance) THEN
  RAISE EXCEPTION 'Historically used breakpoint versions are immutable; clone a new version.' USING ERRCODE='55000';
 END IF; RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;

GRANT EXECUTE ON FUNCTION public.ast_guard_used_breakpoint_mutation TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_guard_used_rule_mutation() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.ast_observations WHERE breakpoint_rule_id=OLD.id) THEN RAISE EXCEPTION 'Historically used breakpoint rules are immutable; clone a new version.' USING ERRCODE='55000'; END IF; RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.ast_guard_used_rule_mutation TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_interpret_breakpoint(
 p_organism_group_code TEXT,p_antibiotic_code TEXT,p_method TEXT,p_metric_value NUMERIC,p_metric_secondary_value NUMERIC DEFAULT NULL,p_breakpoint_set_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.ast_breakpoint_rules%ROWTYPE; bs public.ast_breakpoint_sets%ROWTYPE; result_code TEXT;
BEGIN
 IF p_metric_value IS NULL OR p_metric_value<0 THEN RAISE EXCEPTION 'A non-negative exact numeric AST metric is required.' USING ERRCODE='22023'; END IF;
 IF p_method NOT IN('Disk','MIC') THEN RETURN jsonb_build_object('automatic_interpretation',NULL,'message','No approved breakpoint configured'); END IF;
 SELECT * INTO bs FROM public.ast_breakpoint_sets WHERE id=COALESCE(p_breakpoint_set_id,(SELECT id FROM public.ast_breakpoint_sets WHERE is_active)) AND status='Active';
 IF NOT FOUND THEN RETURN jsonb_build_object('automatic_interpretation',NULL,'message','No active breakpoint-set version selected'); END IF;
 SELECT br.* INTO r FROM public.ast_breakpoint_rules br JOIN public.ast_organism_groups g ON g.id=br.organism_group_id
 JOIN public.ast_antibiotics a ON a.id=br.antibiotic_id
 WHERE br.breakpoint_set_id=bs.id AND g.code=p_organism_group_code AND a.code=p_antibiotic_code AND br.method=p_method;
 IF NOT FOUND THEN RETURN jsonb_build_object('automatic_interpretation',NULL,'breakpoint_set_id',bs.id,'breakpoint_version',bs.version,'message','No approved breakpoint configured'); END IF;
 IF NOT r.automatic_interpretation_allowed THEN RETURN jsonb_build_object('automatic_interpretation',NULL,'breakpoint_set_id',bs.id,'breakpoint_version',bs.version,'rule_id',r.id,'message','MIC required for breakpoint interpretation','notes',r.notes); END IF;
 IF (r.susceptible_secondary IS NOT NULL OR r.intermediate_secondary_min IS NOT NULL OR r.resistant_secondary IS NOT NULL) AND p_metric_secondary_value IS NULL THEN
  RETURN jsonb_build_object('automatic_interpretation',NULL,'breakpoint_set_id',bs.id,'breakpoint_version',bs.version,'rule_id',r.id,'message','Compound MIC metric requires both numeric components');
 END IF;
 IF r.susceptible_min IS NOT NULL AND p_metric_value>=r.susceptible_min THEN result_code:='S';
 ELSIF r.susceptible_max IS NOT NULL AND p_metric_value<=r.susceptible_max AND (r.susceptible_secondary IS NULL OR p_metric_secondary_value=r.susceptible_secondary) THEN result_code:='S';
 ELSIF r.intermediate_min IS NOT NULL AND r.intermediate_max IS NOT NULL AND p_metric_value BETWEEN r.intermediate_min AND r.intermediate_max
   AND (r.intermediate_secondary_min IS NULL OR p_metric_secondary_value BETWEEN r.intermediate_secondary_min AND r.intermediate_secondary_max) THEN result_code:=COALESCE(r.intermediate_semantics,'I');
 ELSIF r.resistant_min IS NOT NULL AND p_metric_value>=r.resistant_min AND (r.resistant_secondary IS NULL OR p_metric_secondary_value=r.resistant_secondary) THEN result_code:='R';
 ELSIF r.resistant_max IS NOT NULL AND p_metric_value<=r.resistant_max THEN result_code:='R'; END IF;
 RETURN jsonb_build_object('automatic_interpretation',result_code,'breakpoint_set_id',bs.id,'breakpoint_version',bs.version,'rule_id',r.id,
  'message',CASE WHEN result_code IS NULL THEN 'No approved breakpoint configured for this exact metric' ELSE NULL END,'notes',r.notes);
END $$;

GRANT EXECUTE ON FUNCTION public.ast_interpret_breakpoint TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_retire_breakpoint_set(p_set_id UUID,p_expected_revision BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE saved public.ast_breakpoint_sets%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 UPDATE public.ast_breakpoint_sets SET status='Retired',is_active=FALSE,retired_at=now(),row_version=row_version+1 WHERE id=p_set_id AND row_version=p_expected_revision RETURNING * INTO saved;
 IF NOT FOUND THEN RAISE EXCEPTION 'Breakpoint set changed. Reload.' USING ERRCODE='PT409'; END IF; RETURN to_jsonb(saved);
END $$;

GRANT EXECUTE ON FUNCTION public.ast_retire_breakpoint_set TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_save_breakpoint_rule(p_payload JSONB,p_expected_revision BIGINT DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE saved public.ast_breakpoint_rules%ROWTYPE; target_id UUID:=NULLIF(p_payload->>'id','')::UUID; set_id UUID:=(p_payload->>'breakpoint_set_id')::UUID;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ast_breakpoint_sets WHERE id=set_id AND status='Draft') THEN RAISE EXCEPTION 'Rules may be edited only in a draft breakpoint version.' USING ERRCODE='55000'; END IF;
 IF target_id IS NULL THEN
  INSERT INTO public.ast_breakpoint_rules(breakpoint_set_id,organism_group_id,antibiotic_id,method,metric_type,potency,automatic_interpretation_allowed,
   susceptible_min,susceptible_max,susceptible_secondary,intermediate_min,intermediate_max,intermediate_secondary_min,intermediate_secondary_max,
   resistant_min,resistant_max,resistant_secondary,intermediate_semantics,interpretation_semantics,notes)
  VALUES(set_id,(p_payload->>'organism_group_id')::UUID,(p_payload->>'antibiotic_id')::UUID,p_payload->>'method',p_payload->>'metric_type',p_payload->>'potency',COALESCE((p_payload->>'automatic_interpretation_allowed')::BOOLEAN,TRUE),
   NULLIF(p_payload->>'susceptible_min','')::NUMERIC,NULLIF(p_payload->>'susceptible_max','')::NUMERIC,NULLIF(p_payload->>'susceptible_secondary','')::NUMERIC,
   NULLIF(p_payload->>'intermediate_min','')::NUMERIC,NULLIF(p_payload->>'intermediate_max','')::NUMERIC,NULLIF(p_payload->>'intermediate_secondary_min','')::NUMERIC,NULLIF(p_payload->>'intermediate_secondary_max','')::NUMERIC,
   NULLIF(p_payload->>'resistant_min','')::NUMERIC,NULLIF(p_payload->>'resistant_max','')::NUMERIC,NULLIF(p_payload->>'resistant_secondary','')::NUMERIC,NULLIF(p_payload->>'intermediate_semantics',''),
   COALESCE(p_payload->'interpretation_semantics','{}'::JSONB),p_payload->>'notes') RETURNING * INTO saved;
 ELSE
  UPDATE public.ast_breakpoint_rules SET potency=p_payload->>'potency',automatic_interpretation_allowed=COALESCE((p_payload->>'automatic_interpretation_allowed')::BOOLEAN,TRUE),
   susceptible_min=NULLIF(p_payload->>'susceptible_min','')::NUMERIC,susceptible_max=NULLIF(p_payload->>'susceptible_max','')::NUMERIC,susceptible_secondary=NULLIF(p_payload->>'susceptible_secondary','')::NUMERIC,
   intermediate_min=NULLIF(p_payload->>'intermediate_min','')::NUMERIC,intermediate_max=NULLIF(p_payload->>'intermediate_max','')::NUMERIC,intermediate_secondary_min=NULLIF(p_payload->>'intermediate_secondary_min','')::NUMERIC,intermediate_secondary_max=NULLIF(p_payload->>'intermediate_secondary_max','')::NUMERIC,
   resistant_min=NULLIF(p_payload->>'resistant_min','')::NUMERIC,resistant_max=NULLIF(p_payload->>'resistant_max','')::NUMERIC,resistant_secondary=NULLIF(p_payload->>'resistant_secondary','')::NUMERIC,
   intermediate_semantics=NULLIF(p_payload->>'intermediate_semantics',''),interpretation_semantics=COALESCE(p_payload->'interpretation_semantics','{}'::JSONB),notes=p_payload->>'notes',row_version=row_version+1,updated_at=now()
  WHERE id=target_id AND breakpoint_set_id=set_id AND row_version=p_expected_revision RETURNING * INTO saved;
  IF NOT FOUND THEN RAISE EXCEPTION 'Breakpoint rule changed. Reload.' USING ERRCODE='PT409'; END IF;
 END IF; RETURN to_jsonb(saved);
END $$;

GRANT EXECUTE ON FUNCTION public.ast_save_breakpoint_rule TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_save_breakpoint_set(p_payload JSONB,p_expected_revision BIGINT DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE saved public.ast_breakpoint_sets%ROWTYPE; target_id UUID:=NULLIF(p_payload->>'id','')::UUID;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF target_id IS NULL THEN
  INSERT INTO public.ast_breakpoint_sets(name,version,effective_date,provenance,status,is_active,created_by)
  VALUES(btrim(p_payload->>'name'),btrim(p_payload->>'version'),(p_payload->>'effective_date')::DATE,btrim(p_payload->>'provenance'),'Draft',FALSE,auth.uid()) RETURNING * INTO saved;
 ELSE
  UPDATE public.ast_breakpoint_sets SET name=btrim(p_payload->>'name'),version=btrim(p_payload->>'version'),effective_date=(p_payload->>'effective_date')::DATE,
   provenance=btrim(p_payload->>'provenance'),row_version=row_version+1 WHERE id=target_id AND status='Draft' AND row_version=p_expected_revision RETURNING * INTO saved;
  IF NOT FOUND THEN RAISE EXCEPTION 'Draft breakpoint set changed or is immutable.' USING ERRCODE='PT409'; END IF;
 END IF; RETURN to_jsonb(saved);
END $$;

GRANT EXECUTE ON FUNCTION public.ast_save_breakpoint_set TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_save_isolate(p_order_item_id UUID,p_isolate_number INT,p_microorganism_id UUID,p_growth_state TEXT,p_expected_revision BIGINT DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE prior public.ast_isolates%ROWTYPE; org public.ast_microorganisms%ROWTYPE; grp public.ast_organism_groups%ROWTYPE; saved public.ast_isolates%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_enter_results') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF p_growth_state NOT IN('Positive','NoGrowth') THEN RAISE EXCEPTION 'Invalid growth state.' USING ERRCODE='22023'; END IF;
 SELECT * INTO prior FROM public.ast_isolates WHERE order_item_id=p_order_item_id AND isolate_number=p_isolate_number FOR UPDATE;
 IF FOUND AND prior.row_version<>p_expected_revision THEN RAISE EXCEPTION 'AST isolate changed. Reload before saving.' USING ERRCODE='PT409'; END IF;
 IF p_growth_state='Positive' THEN SELECT * INTO org FROM public.ast_microorganisms WHERE id=p_microorganism_id AND is_active; IF NOT FOUND THEN RAISE EXCEPTION 'Select an active microorganism.' USING ERRCODE='23503'; END IF; SELECT * INTO grp FROM public.ast_organism_groups WHERE id=org.organism_group_id; END IF;
 INSERT INTO public.ast_isolates(order_item_id,isolate_number,microorganism_id,organism_name_snapshot,organism_group_id,organism_group_snapshot,growth_state,created_by)
 VALUES(p_order_item_id,p_isolate_number,CASE WHEN p_growth_state='Positive' THEN org.id END,CASE WHEN p_growth_state='Positive' THEN org.display_name ELSE 'No growth' END,
  CASE WHEN p_growth_state='Positive' THEN grp.id END,CASE WHEN p_growth_state='Positive' THEN grp.display_name END,p_growth_state,auth.uid())
 ON CONFLICT(order_item_id,isolate_number) DO UPDATE SET microorganism_id=EXCLUDED.microorganism_id,organism_name_snapshot=EXCLUDED.organism_name_snapshot,
  organism_group_id=EXCLUDED.organism_group_id,organism_group_snapshot=EXCLUDED.organism_group_snapshot,growth_state=EXCLUDED.growth_state,row_version=public.ast_isolates.row_version+1,updated_at=now()
 RETURNING * INTO saved;
 RETURN to_jsonb(saved);
END $$;

GRANT EXECUTE ON FUNCTION public.ast_save_isolate TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_save_microorganism_mapping(p_code TEXT,p_display_name TEXT,p_group_id UUID,p_expected_revision BIGINT DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE saved public.ast_microorganisms%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 INSERT INTO public.ast_microorganisms(code,display_name,organism_group_id) VALUES(upper(btrim(p_code)),btrim(p_display_name),p_group_id)
 ON CONFLICT(code) DO UPDATE SET display_name=EXCLUDED.display_name,organism_group_id=EXCLUDED.organism_group_id,row_version=public.ast_microorganisms.row_version+1,updated_at=now()
 WHERE public.ast_microorganisms.row_version=p_expected_revision RETURNING * INTO saved;
 IF NOT FOUND THEN RAISE EXCEPTION 'Microorganism mapping changed. Reload.' USING ERRCODE='PT409'; END IF; RETURN to_jsonb(saved);
END $$;

GRANT EXECUTE ON FUNCTION public.ast_save_microorganism_mapping TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ast_save_observation(p_isolate_id UUID,p_antibiotic_id UUID,p_method TEXT,p_metric_value NUMERIC,p_metric_secondary_value NUMERIC,
 p_final_interpretation TEXT,p_override_reason TEXT,p_expected_revision BIGINT DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE iso public.ast_isolates%ROWTYPE; ab public.ast_antibiotics%ROWTYPE; grp public.ast_organism_groups%ROWTYPE; prior public.ast_observations%ROWTYPE; calc JSONB; auto_code TEXT; saved public.ast_observations%ROWTYPE; manual BOOLEAN;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_enter_results') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF p_final_interpretation NOT IN('S','I','R','SDD') THEN RAISE EXCEPTION 'Final interpretation must be S, I, R or SDD.' USING ERRCODE='22023'; END IF;
 SELECT * INTO iso FROM public.ast_isolates WHERE id=p_isolate_id AND growth_state='Positive' FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Positive isolate not found.' USING ERRCODE='23503'; END IF;
 SELECT * INTO ab FROM public.ast_antibiotics WHERE id=p_antibiotic_id AND is_active; IF NOT FOUND THEN RAISE EXCEPTION 'Active antibiotic not found.' USING ERRCODE='23503'; END IF;
 SELECT * INTO grp FROM public.ast_organism_groups WHERE id=iso.organism_group_id;
 calc:=public.ast_interpret_breakpoint(grp.code,ab.code,p_method,p_metric_value,p_metric_secondary_value,NULL); auto_code:=calc->>'automatic_interpretation'; manual:=auto_code IS NULL OR auto_code<>p_final_interpretation;
 IF manual AND btrim(COALESCE(p_override_reason,''))='' THEN RAISE EXCEPTION 'Manual interpretation or override requires an explicit reason.' USING ERRCODE='23514'; END IF;
 SELECT * INTO prior FROM public.ast_observations WHERE isolate_id=p_isolate_id AND antibiotic_id=p_antibiotic_id AND method=p_method FOR UPDATE;
 IF FOUND AND prior.row_version<>p_expected_revision THEN RAISE EXCEPTION 'AST observation changed. Reload before saving.' USING ERRCODE='PT409'; END IF;
 INSERT INTO public.ast_observations(isolate_id,antibiotic_id,antibiotic_code_snapshot,antibiotic_name_snapshot,method,metric_type,metric_value,metric_secondary_value,
  automatic_interpretation,final_interpretation,breakpoint_set_id,breakpoint_set_version_snapshot,breakpoint_rule_id,manual_override,override_reason,actor_id)
 VALUES(iso.id,ab.id,ab.code,ab.name,p_method,CASE WHEN p_method='Disk' THEN 'ZoneDiameterMm' ELSE 'MicConcentration' END,p_metric_value,p_metric_secondary_value,
  NULLIF(auto_code,''),p_final_interpretation,NULLIF(calc->>'breakpoint_set_id','')::UUID,calc->>'breakpoint_version',NULLIF(calc->>'rule_id','')::UUID,manual,p_override_reason,auth.uid())
 ON CONFLICT(isolate_id,antibiotic_id,method) DO UPDATE SET metric_type=EXCLUDED.metric_type,metric_value=EXCLUDED.metric_value,metric_secondary_value=EXCLUDED.metric_secondary_value,
  automatic_interpretation=EXCLUDED.automatic_interpretation,final_interpretation=EXCLUDED.final_interpretation,breakpoint_set_id=EXCLUDED.breakpoint_set_id,
  breakpoint_set_version_snapshot=EXCLUDED.breakpoint_set_version_snapshot,breakpoint_rule_id=EXCLUDED.breakpoint_rule_id,manual_override=EXCLUDED.manual_override,
  override_reason=EXCLUDED.override_reason,actor_id=auth.uid(),row_version=public.ast_observations.row_version+1,updated_at=now() RETURNING * INTO saved;
 INSERT INTO public.ast_observation_audit(observation_id,isolate_id,actor_id,action,before_state,after_state,reason)
 VALUES(saved.id,iso.id,auth.uid(),CASE WHEN prior.id IS NULL THEN 'AST_OBSERVATION_CREATED' WHEN manual THEN 'AST_INTERPRETATION_OVERRIDDEN' ELSE 'AST_OBSERVATION_UPDATED' END,
  CASE WHEN prior.id IS NULL THEN NULL ELSE to_jsonb(prior) END,to_jsonb(saved),p_override_reason);
 RETURN to_jsonb(saved)||jsonb_build_object('interpretation_message',calc->>'message','rule_notes',calc->>'notes');
END $$;

GRANT EXECUTE ON FUNCTION public.ast_save_observation TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.attach_report_artifact(
    p_report_id UUID,
    p_storage_path TEXT,
    p_sha256_hash VARCHAR(128)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    IF NOT (public.has_permission('can_sign_reports') OR public.has_permission('can_verify_results') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Access Denied: Missing permissions to attach report artifact.';
    END IF;

    UPDATE public.diagnostic_reports
    SET pdf_storage_path = p_storage_path,
        integrity_hash = p_sha256_hash,
        updated_at = NOW()
    WHERE id = p_report_id;

    RETURN jsonb_build_object('success', TRUE, 'report_id', p_report_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.attach_report_artifact TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.audit_patient_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),public.patient_actor_name(),'PATIENT_CREATED','Patient',NEW.id::TEXT,jsonb_build_object('uhid',NEW.uhid));
  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.audit_patient_created TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.authorize_my_report_pdf(p_report_id UUID, p_version INT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_patient_id UUID;
  v_report public.diagnostic_reports%ROWTYPE;
  v_artifact public.report_pdf_artifacts%ROWTYPE;
  v_order public.clinical_orders%ROWTYPE;
  v_group public.clinical_report_groups%ROWTYPE;
  v_raw_token TEXT;
  v_token_hash TEXT;
  v_expires_at TIMESTAMPTZ;
  v_download_url TEXT;
  v_filename TEXT;
  v_clean_title TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  SELECT patient_id INTO v_patient_id
  FROM public.patient_app_identities
  WHERE auth_user_id = v_uid AND status = 'LINKED';

  IF v_patient_id IS NULL THEN
    RAISE EXCEPTION 'Access denied: patient identity not linked.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_report
  FROM public.diagnostic_reports
  WHERE id = p_report_id
    AND version = p_version
    AND patient_id = v_patient_id
    AND status IN ('SignedOff', 'Amended');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Access denied or report not found.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_artifact
  FROM public.report_pdf_artifacts
  WHERE diagnostic_report_id = v_report.id
    AND report_version = v_report.version
        AND generation_status = 'Ready';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Report PDF artifact is not ready.' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_order FROM public.clinical_orders WHERE id = v_report.order_id;
  IF v_report.report_group_id IS NOT NULL THEN
    SELECT * INTO v_group FROM public.clinical_report_groups WHERE id = v_report.report_group_id;
  END IF;

  v_clean_title := regexp_replace(coalesce(v_group.title, 'Report'), '[^a-zA-Z0-9]+', '-', 'g');
  v_filename := 'Bimal-Pathology-' || v_order.order_number || '-' || v_clean_title || '-v' || v_report.version || '.pdf';

  -- Generate Short-Lived Android Delivery Token (15 minute TTL)
  v_raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_token_hash := encode(extensions.digest(convert_to(v_raw_token, 'UTF8'), 'sha256'), 'hex');
  v_expires_at := now() + interval '15 minutes';

  INSERT INTO public.patient_app_pdf_tokens (
    auth_user_id,
    patient_id,
    diagnostic_report_id,
    report_version,
    token_hash,
    created_at,
    expires_at
  ) VALUES (
    v_uid,
    v_patient_id,
    v_report.id,
    v_report.version,
    v_token_hash,
    now(),
    v_expires_at
  );

  v_download_url := 'https://dashboard.bimalpathology.com.np/api/patient-app/reports/' || v_raw_token || '/pdf?filename=' || v_filename;

  RETURN jsonb_build_object(
    'authorized', true,
    'report_id', v_report.id,
    'order_id', v_report.order_id,
    'order_number', v_order.order_number,
    'group_title', coalesce(v_group.title, 'Diagnostic Report'),
    'version', v_report.version,
    'sha256', v_artifact.pdf_sha256,
    'byte_size', v_artifact.byte_size,
    'delivery_url', v_download_url,
    'filename', v_filename,
    'expires_at', v_expires_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.authorize_my_report_pdf TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.authorize_order_report_delivery(p_token_hash TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE token public.order_report_delivery_tokens%ROWTYPE; payload JSONB;
BEGIN
 IF NOT public.is_report_artifact_worker() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO token FROM public.order_report_delivery_tokens WHERE token_hash=p_token_hash AND is_active AND revoked_at IS NULL AND expires_at>now() FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('authorized',false); END IF;
 UPDATE public.order_report_delivery_tokens SET access_count=access_count+1,last_accessed_at=now() WHERE id=token.id;
 SELECT jsonb_build_object('authorized',true,'order_id',token.order_id,'order_number',o.order_number,'reports',coalesce(jsonb_agg(jsonb_build_object('report_group_id',g.id,'group_key',g.group_key,'title',g.title,'state',g.lifecycle_state,'report_id',r.id,'version',r.version,'pdf_status',a.generation_status) ORDER BY g.display_order),'[]'::jsonb)) INTO payload
 FROM public.clinical_orders o JOIN public.order_report_delivery_entitlements e ON e.order_token_id=token.id JOIN public.clinical_report_groups g ON g.id=e.report_group_id
 LEFT JOIN LATERAL(SELECT dr.* FROM public.diagnostic_reports dr WHERE dr.report_group_id=g.id AND dr.status='SignedOff' ORDER BY dr.version DESC LIMIT 1) r ON true
 LEFT JOIN public.report_pdf_artifacts a ON a.diagnostic_report_id=r.id AND a.report_version=r.version WHERE o.id=token.order_id GROUP BY o.id;
 RETURN coalesce(payload,jsonb_build_object('authorized',false));
END $$;

GRANT EXECUTE ON FUNCTION public.authorize_order_report_delivery TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.authorize_order_report_pdf_artifact(p_token_hash TEXT,p_report_id UUID) RETURNS JSONB
LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT CASE WHEN NOT public.is_report_artifact_worker() THEN jsonb_build_object('authorized',false) ELSE coalesce((SELECT jsonb_build_object('authorized',true,'object_key',a.object_key,'sha256',a.pdf_sha256,'byte_size',a.byte_size,'report_id',r.id,'version',r.version) FROM public.order_report_delivery_tokens tok JOIN public.order_report_delivery_entitlements e ON e.order_token_id=tok.id JOIN public.diagnostic_reports r ON r.report_group_id=e.report_group_id AND r.id=p_report_id AND r.status='SignedOff' JOIN public.report_pdf_artifacts a ON a.diagnostic_report_id=r.id AND a.report_version=r.version AND a.generation_status='Ready' WHERE tok.token_hash=p_token_hash AND tok.is_active AND tok.revoked_at IS NULL AND tok.expires_at>now()),jsonb_build_object('authorized',false)) END
$$;

GRANT EXECUTE ON FUNCTION public.authorize_order_report_pdf_artifact TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.authorize_patient_app_pdf_artifact(p_token_hash TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_token public.patient_app_pdf_tokens%ROWTYPE;
  v_artifact public.report_pdf_artifacts%ROWTYPE;
  v_report public.diagnostic_reports%ROWTYPE;
BEGIN
  IF NOT public.is_report_artifact_worker() THEN
    RETURN jsonb_build_object('authorized', false);
  END IF;

  SELECT * INTO v_token
  FROM public.patient_app_pdf_tokens
  WHERE token_hash = p_token_hash
    AND consumed_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('authorized', false);
  END IF;

  SELECT * INTO v_report
  FROM public.diagnostic_reports
  WHERE id = v_token.diagnostic_report_id
    AND version = v_token.report_version
    AND status IN ('SignedOff', 'Amended');

  IF NOT FOUND THEN
    RETURN jsonb_build_object('authorized', false);
  END IF;

  SELECT * INTO v_artifact
  FROM public.report_pdf_artifacts
  WHERE diagnostic_report_id = v_token.diagnostic_report_id
    AND report_version = v_token.report_version
        AND generation_status = 'Ready';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('authorized', false);
  END IF;

  -- Mark token consumed
  UPDATE public.patient_app_pdf_tokens
  SET consumed_at = now()
  WHERE id = v_token.id;

  RETURN jsonb_build_object(
    'authorized', true,
    'object_key', v_artifact.object_key,
    'sha256', v_artifact.pdf_sha256,
    'byte_size', v_artifact.byte_size,
    'report_id', v_report.id,
    'version', v_report.version
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.authorize_patient_app_pdf_artifact TO authenticated, service_role;

CREATE FUNCTION public.authorize_report_pdf_artifact(p_token_hash VARCHAR)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.public_report_tokens%ROWTYPE;a public.report_pdf_artifacts%ROWTYPE;
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  SELECT * INTO t FROM public.public_report_tokens WHERE token_hash=p_token_hash AND is_active AND revoked_at IS NULL AND expires_at>NOW();
  IF NOT FOUND THEN RETURN jsonb_build_object('authorized',FALSE); END IF;
  SELECT artifact.* INTO a
  FROM public.report_pdf_artifacts artifact
  JOIN public.diagnostic_reports report ON report.id=artifact.diagnostic_report_id
  WHERE artifact.diagnostic_report_id=t.diagnostic_report_id
    AND artifact.report_version=report.version
    AND artifact.report_integrity_hash=report.integrity_hash
    AND encode(extensions.digest(report.clinical_snapshot_json::TEXT,'sha256'),'hex')=artifact.frozen_snapshot_sha256
    AND report.status IN('SignedOff','Amended')
    AND artifact.generation_status='Ready';
  IF NOT FOUND THEN RETURN jsonb_build_object('authorized',FALSE,'reason','ARTIFACT_NOT_READY'); END IF;
  RETURN jsonb_build_object('authorized',TRUE,'object_key',a.object_key,'sha256',a.pdf_sha256,'byte_size',a.byte_size,'report_id',a.diagnostic_report_id,'version',a.report_version);
END $$;

GRANT EXECUTE ON FUNCTION public.authorize_report_pdf_artifact TO authenticated, service_role;

CREATE FUNCTION public.bind_bpdc_lab_no() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  UPDATE public.lab_number_registry SET order_id=NEW.id,assigned_at=NOW() WHERE lab_no=NEW.order_number AND order_id IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'BPDC Lab No reservation is missing.' USING ERRCODE='23503'; END IF;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.bind_bpdc_lab_no TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.bootstrap_first_admin()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
    v_profile_count INT;
    v_email VARCHAR(255);
    v_caller_email VARCHAR(255);
    v_full_name VARCHAR(255);
    v_phone VARCHAR(50);
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required: Anonymous callers cannot bootstrap administrator.';
    END IF;

    SELECT email, raw_user_meta_data->>'full_name', raw_user_meta_data->>'phone'
    INTO v_caller_email, v_full_name, v_phone
    FROM auth.users
    WHERE id = v_caller_id;

    SELECT count(*) INTO v_profile_count FROM public.user_profiles;

    IF v_profile_count = 0 THEN
        -- First user gets Super Admin & Admin Role
        INSERT INTO public.user_profiles (
            id,
            email,
            full_name,
            phone,
            is_active,
            is_super_admin,
            created_at,
            updated_at
        ) VALUES (
            v_caller_id,
            COALESCE(v_caller_email, 'admin@bimalpathology.com'),
            COALESCE(v_full_name, 'System Administrator'),
            v_phone,
            TRUE,
            TRUE,
            NOW(),
            NOW()
        )
        ON CONFLICT (id) DO UPDATE
        SET is_super_admin = TRUE, is_active = TRUE, updated_at = NOW();

        INSERT INTO public.user_roles (user_id, role_id)
        VALUES (v_caller_id, '00000000-0000-0000-0000-000000000001')
        ON CONFLICT DO NOTHING;

        RETURN jsonb_build_object(
            'success', true,
            'bootstrapped', true,
            'is_super_admin', true,
            'message', 'Initial Super Administrator successfully bootstrapped.'
        );
    ELSE
        -- Ensure profile exists
        IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE id = v_caller_id) THEN
            INSERT INTO public.user_profiles (
                id,
                email,
                full_name,
                phone,
                is_active,
                is_super_admin,
                created_at,
                updated_at
            ) VALUES (
                v_caller_id,
                COALESCE(v_caller_email, 'staff@bimalpathology.com'),
                COALESCE(v_full_name, 'Staff Member'),
                v_phone,
                TRUE,
                FALSE,
                NOW(),
                NOW()
            )
            ON CONFLICT (id) DO NOTHING;

            INSERT INTO public.user_roles (user_id, role_id)
            VALUES (v_caller_id, '00000000-0000-0000-0000-000000000005')
            ON CONFLICT DO NOTHING;
        END IF;

        RETURN jsonb_build_object(
            'success', true,
            'bootstrapped', false,
            'is_super_admin', (SELECT is_super_admin FROM public.user_profiles WHERE id = v_caller_id),
            'message', 'User profile confirmed.'
        );
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.bootstrap_first_admin TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.build_single_credit_nepali_sms(
  p_order_id UUID,
  p_report_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_bill_id         UUID;
  v_paid_paisa      BIGINT := 0;
  v_amount_str      TEXT;
  v_test_count      INT := 0;
  v_first_test_name TEXT;
  v_alias           TEXT;
  v_msg             TEXT;
  -- Fixed-length portion of template excluding {TEST} and {AMOUNT}:
  -- "Bimal Pathology:  रिपोर्ट तयार भयो। रु  भुक्तानको लागि धन्यवाद।"
  -- = 63 UCS-2 code units (verified)
  v_fixed_len       CONSTANT INT := 63;
  v_avail_for_test  INT;
BEGIN
  -- Fetch cumulative paid amount (NOT net amount — only actual payment received)
  SELECT o.bill_id INTO v_bill_id FROM public.clinical_orders o WHERE o.id = p_order_id;
  IF v_bill_id IS NOT NULL THEN
    SELECT COALESCE(paid_amount_paisa, 0) INTO v_paid_paisa FROM public.bills WHERE id = v_bill_id;
  END IF;

  -- Payment guard: only positive paid amounts trigger the notification SMS
  IF v_paid_paisa <= 0 THEN
    RAISE EXCEPTION 'SMS_NO_PAYMENT: paid_amount_paisa is % — payment acknowledgement SMS must not be sent for unpaid or zero-paid orders.', v_paid_paisa
      USING ERRCODE = '23514';
  END IF;

  v_amount_str    := public.format_nepali_amount(v_paid_paisa);
  v_avail_for_test := 70 - v_fixed_len - length(v_amount_str);

  SELECT count(DISTINCT t.id), min(t.name)
  INTO v_test_count, v_first_test_name
  FROM public.clinical_order_items coi
  JOIN public.tests t ON t.id = coi.test_id
  WHERE coi.order_id = p_order_id AND coi.clinical_reporting_enabled = TRUE;

  -- 4-tier alias resolution
  IF v_test_count = 1 AND v_first_test_name IS NOT NULL THEN
    -- Tier 1: primary alias
    v_alias := public.get_sms_test_alias(v_first_test_name, greatest(1, v_avail_for_test));
    v_msg := 'Bimal Pathology: ' || v_alias || ' रिपोर्ट तयार भयो। रु ' || v_amount_str || ' भुक्तानको लागि धन्यवाद।';
    IF length(v_msg) <= 70 THEN RETURN v_msg; END IF;
  END IF;

  -- Tier 3: generic "Lab"
  v_msg := 'Bimal Pathology: Lab रिपोर्ट तयार भयो। रु ' || v_amount_str || ' भुक्तानको लागि धन्यवाद।';
  IF length(v_msg) <= 70 THEN RETURN v_msg; END IF;

  -- Tier 4: emergency "L"
  v_msg := 'Bimal Pathology: L रिपोर्ट तयार भयो। रु ' || v_amount_str || ' भुक्तानको लागि धन्यवाद।';
  IF length(v_msg) <= 70 THEN RETURN v_msg; END IF;

  -- Tier 5: reject — never multipart, never truncate
  RAISE EXCEPTION 'SMS_SINGLE_SEGMENT_LIMIT_EXCEEDED: message is % UCS-2 code units (max 70). Will not send multipart or truncated SMS.', length(v_msg)
    USING ERRCODE = '23514';
END;
$$;

GRANT EXECUTE ON FUNCTION public.build_single_credit_nepali_sms TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.calculation_dependency_blockers(p_order_item_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT public.is_active_user() THEN RAISE EXCEPTION 'Inactive or anonymous users cannot view calculation dependencies.' USING ERRCODE='42501';END IF;
 RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('parameter_code',p.code,'parameter_name',p.name,'formula_identifier',f.formula_identifier,'status',r.calculation_status,'error_code',r.error_code,'missing_dependencies',COALESCE(r.input_snapshot->'missing_dependencies','[]'::jsonb)) ORDER BY p.display_order)
 FROM public.clinical_calculation_formula_versions f JOIN public.parameters p ON p.id=f.output_parameter_id
 LEFT JOIN LATERAL(SELECT x.* FROM public.clinical_calculation_runs x WHERE x.order_item_id=p_order_item_id AND x.formula_version_id=f.id ORDER BY x.calculated_at DESC LIMIT 1) r ON TRUE
 WHERE f.scope_test_id=(SELECT test_id FROM public.clinical_order_items WHERE id=p_order_item_id) AND f.lifecycle_status='Approved' AND (r.id IS NULL OR r.calculation_status<>'Calculated')),'[]'::jsonb);
END $$;

GRANT EXECUTE ON FUNCTION public.calculation_dependency_blockers TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.capture_report_calculation_provenance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  INSERT INTO public.report_calculation_provenance(
    report_id,calculation_run_id,report_version,formula_snapshot,input_snapshot,
    calculated_raw_value,displayed_value,output_unit,calculation_status,provenance_hash)
  SELECT NEW.id,r.id,NEW.version,r.formula_snapshot,r.input_snapshot,r.calculated_raw_value,
         r.displayed_value,r.output_unit,r.calculation_status,
         encode(extensions.digest(convert_to(jsonb_build_object('report_id',NEW.id,'report_version',NEW.version,
           'formula',r.formula_snapshot,'inputs',r.input_snapshot,'raw',r.calculated_raw_value,
           'display',r.displayed_value,'unit',r.output_unit,'status',r.calculation_status)::TEXT,'UTF8'),'sha256'),'hex')
  FROM public.clinical_calculation_runs r
  JOIN public.clinical_order_items coi ON coi.id=r.order_item_id
  WHERE coi.order_id=NEW.order_id;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.capture_report_calculation_provenance TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_activate_rate(p_rate_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_rate_versions%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO r FROM public.catalogue_rate_versions WHERE id=p_rate_id FOR UPDATE; IF r.row_version<>p_expected_version THEN RAISE EXCEPTION 'Rate changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF r.price_paisa IS NULL THEN RAISE EXCEPTION 'Price not specified.' USING ERRCODE='23514'; END IF; UPDATE public.catalogue_rate_versions x SET status='Inactive',effective_to=COALESCE(x.effective_to,now()),row_version=x.row_version+1,updated_at=now() WHERE x.status='Active' AND x.id<>r.id AND ((r.test_id IS NOT NULL AND x.test_id=r.test_id) OR (r.panel_service_id IS NOT NULL AND x.panel_service_id=r.panel_service_id) OR (r.package_id IS NOT NULL AND x.package_id=r.package_id) OR (r.other_service_code IS NOT NULL AND x.other_service_code=r.other_service_code)); UPDATE public.catalogue_rate_versions SET status='Active',effective_from=COALESCE(effective_from,now()),effective_to=NULL,row_version=row_version+1,updated_at=now() WHERE id=r.id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_activate_rate TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_actor_name() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT COALESCE((SELECT full_name FROM public.user_profiles WHERE id=auth.uid()), 'Catalogue Administrator')
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_actor_name TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_adopt_standard_presets(
  p_test_ids UUID[],
  p_approval_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  actor_id UUID;
  actor_name TEXT;
  t RECORD;
  preset RECORD;
  p_param RECORD;
  adopted_count INT := 0;
  adopted_codes TEXT[] := ARRAY[]::TEXT[];
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  IF cardinality(p_test_ids) = 0 THEN
    RAISE EXCEPTION 'No tests selected for standard preset adoption.' USING ERRCODE='23514';
  END IF;

  FOR t IN SELECT * FROM public.tests WHERE id = ANY(p_test_ids) FOR UPDATE LOOP
    SELECT * INTO preset FROM public.catalogue_standard_presets WHERE test_code = t.code;

    -- Update Test to VALIDATED (Lab Approved) but keep INACTIVE until explicit separate activation
    UPDATE public.tests
    SET validation_status = 'VALIDATED',
        configuration_source = 'STANDARD_PRESET',
        clinical_configuration_status = 'Configured',
        lifecycle_status = 'Draft',
        is_active = FALSE,
        billing_enabled = FALSE,
        clinical_reporting_enabled = FALSE,
        method = COALESCE(preset.method, method),
        sample_type = COALESCE(preset.specimen, sample_type),
        container = COALESCE(preset.container, container),
        tat_hours = COALESCE(preset.tat_hours, tat_hours),
        updated_at = NOW()
    WHERE id = t.id;

    -- Insert Formal Clinical Approval Audit Record
    INSERT INTO public.catalogue_lab_approvals (
      test_id,
      approved_by,
      approved_by_name,
      approved_at,
      analyzer_model,
      reagent_manufacturer,
      method,
      reference_range_source,
      critical_limit_source,
      effective_from,
      approval_notes,
      approval_status,
      configuration_source
    ) VALUES (
      t.id,
      actor_id,
      actor_name,
      NOW(),
      NULL, -- Unresolved analyzer (intentionally NULL until physical device confirmed)
      NULL, -- Unresolved reagent (intentionally NULL until manufacturer confirmed)
      COALESCE(preset.method, t.method, 'Standard Clinical Method'),
      'Standard Clinical Presets Library v1.0',
      COALESCE(preset.critical_limits_policy, 'Standard Clinical Presets Policy'),
      CURRENT_DATE,
      COALESCE(p_approval_notes, 'Bulk adoption of Standard Clinical Presets. Laboratory responsibility assumed by authorized director.'),
      'APPROVED',
      'STANDARD_PRESET'
    );

    adopted_count := adopted_count + 1;
    adopted_codes := array_append(adopted_codes, t.code);
  END LOOP;

  RETURN jsonb_build_object(
    'success', TRUE,
    'adopted_count', adopted_count,
    'adopted_codes', adopted_codes,
    'validation_status', 'VALIDATED',
    'is_active', FALSE,
    'message', 'Standard presets adopted successfully. Tests are now VALIDATED and require separate explicit activation.'
  );
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_adopt_standard_presets TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_approve_calculation_formula(
 p_formula_id UUID,p_expected_identifier TEXT,p_expected_version INTEGER,p_rounding_scale SMALLINT,
 p_effective_from TIMESTAMPTZ,p_reason TEXT
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE d public.clinical_calculation_formula_versions%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO d FROM public.clinical_calculation_formula_versions WHERE id=p_formula_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Formula candidate not found.' USING ERRCODE='P0002'; END IF;
  IF d.formula_identifier<>p_expected_identifier OR d.formula_version<>p_expected_version THEN
    RAISE EXCEPTION 'Formula version changed. Reload latest.' USING ERRCODE='PT409';
  END IF;
  IF d.lifecycle_status<>'Candidate' OR p_rounding_scale IS NULL OR p_rounding_scale<0 OR p_rounding_scale>12
     OR p_effective_from IS NULL OR length(btrim(COALESCE(p_reason,'')))<5 THEN
    RAISE EXCEPTION 'Formula approval requires Candidate state, explicit rounding, effective date and reason.' USING ERRCODE='23514';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_inputs WHERE formula_version_id=d.id AND parameter_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Formula inputs are not mapped to catalogue parameter IDs.' USING ERRCODE='23514';
  END IF;
  UPDATE public.clinical_calculation_formula_versions SET lifecycle_status='Approved',rounding_scale=p_rounding_scale,
    rounding_mode='HalfAwayFromZero',effective_from=p_effective_from,approved_by=auth.uid(),approved_at=now(),approval_reason=btrim(p_reason)
  WHERE id=d.id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),public.catalogue_actor_name(),'CALCULATION_FORMULA_APPROVED','CalculationFormulaVersion',d.id::text,
    jsonb_build_object('identifier',d.formula_identifier,'version',d.formula_version,'rounding_scale',p_rounding_scale,
      'rounding_mode','HalfAwayFromZero','effective_from',p_effective_from,'reason',btrim(p_reason)));
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_approve_calculation_formula TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_approve_clinical_source_decision(
    p_decision_id UUID,
    p_expected_version BIGINT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.clinical_source_decisions%ROWTYPE; v_item public.clinical_source_items%ROWTYPE;
        v_min_age INT; v_max_age INT;
BEGIN
    PERFORM public.catalogue_require_manager();
    SELECT * INTO v FROM public.clinical_source_decisions WHERE id=p_decision_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Clinical decision not found.' USING ERRCODE='P0002'; END IF;
    IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Clinical decision changed. Reload latest.' USING ERRCODE='PT409'; END IF;
    IF v.status<>'Draft' THEN RAISE EXCEPTION 'Only a Draft decision may be approved.' USING ERRCODE='23514'; END IF;
    SELECT * INTO v_item FROM public.clinical_source_items WHERE id=v.source_item_id FOR UPDATE;

    IF v.action<>'RejectSource' THEN
      IF NULLIF(btrim(v.selected_policy->>'age_min_days'),'') IS NULL OR
         NULLIF(btrim(v.selected_policy->>'age_max_days'),'') IS NULL THEN
        RAISE EXCEPTION 'Clinical approval requires explicit non-null age bounds.' USING ERRCODE='23514';
      END IF;
      v_min_age:=(v.selected_policy->>'age_min_days')::INT;
      v_max_age:=(v.selected_policy->>'age_max_days')::INT;
      IF v_min_age<0 OR v_max_age<v_min_age THEN
        RAISE EXCEPTION 'Clinical approval requires valid ordered age bounds.' USING ERRCODE='23514';
      END IF;
      IF NULLIF(btrim(v.selected_policy->>'applicability_basis'),'') IS NULL OR
         NULLIF(btrim(v.selected_policy->>'method_or_analyzer_context'),'') IS NULL OR
         NOT (v.selected_policy ? 'critical_limits_reviewed') OR
         jsonb_typeof(v.selected_policy->'critical_limits_reviewed')<>'boolean' OR
         NULLIF(btrim(v.selected_policy->>'gender'),'') IS NULL OR
         NULLIF(btrim(v.selected_policy->>'unit'),'') IS NULL THEN
        RAISE EXCEPTION 'Clinical approval requires complete sex, applicability, method/analyzer, unit, and critical-limit review.' USING ERRCODE='23514';
      END IF;
      IF v_item.source_classification='AuthorizedApproximateReviewRequired'
         AND v.action NOT IN ('CorrectLaboratoryPolicy','RejectSource') THEN
        RAISE EXCEPTION 'Approximate source evidence requires a corrected laboratory policy or rejection.' USING ERRCODE='23514';
      END IF;
      IF v_item.source_classification IN ('AuthorizedContextDependent','AuthorizedSexSpecificAgeBoundsMissing','AuthorizedUnspecifiedAge')
         AND v.action NOT IN ('RestrictApplicability','CorrectLaboratoryPolicy','RetainOlderPolicy','RejectSource') THEN
        RAISE EXCEPTION 'Incomplete applicability cannot be accepted without restriction or correction.' USING ERRCODE='23514';
      END IF;
    END IF;

    UPDATE public.clinical_source_decisions
       SET status='Approved',approved_by=auth.uid(),approved_at=NOW(),row_version=row_version+1
     WHERE id=p_decision_id;
    UPDATE public.clinical_source_items
       SET review_state=CASE WHEN v.action='RejectSource' THEN 'Rejected' ELSE 'ApprovedForMaterialization' END,
           row_version=row_version+1
     WHERE id=v.source_item_id;
    UPDATE public.clinical_source_decisions
       SET status='Superseded',row_version=row_version+1
     WHERE source_item_id=v.source_item_id AND id<>p_decision_id AND status='Approved';
    INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
    VALUES(auth.uid(),public.catalogue_actor_name(),'CLINICAL_SOURCE_DECISION_APPROVED','ClinicalSourceDecision',p_decision_id::TEXT,
           jsonb_build_object('source_item_id',v.source_item_id,'action',v.action,'source_classification',v_item.source_classification));
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_approve_clinical_source_decision TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_archive_option_set(p_option_set_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE s public.catalogue_option_sets%ROWTYPE; BEGIN PERFORM public.catalogue_require_technical(); SELECT * INTO s FROM public.catalogue_option_sets WHERE id=p_option_set_id FOR UPDATE; IF s.row_version<>p_expected_version THEN RAISE EXCEPTION 'Option set changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.catalogue_option_sets SET lifecycle_status='Archived',archived_at=now(),archived_by=auth.uid(),row_version=row_version+1,updated_at=now() WHERE id=s.id; UPDATE public.catalogue_option_values SET is_active=FALSE,row_version=row_version+1,updated_at=now() WHERE option_set_id=s.id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_archive_option_set TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_archive_rate(p_rate_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_rate_versions%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO r FROM public.catalogue_rate_versions WHERE id=p_rate_id FOR UPDATE; IF r.row_version<>p_expected_version THEN RAISE EXCEPTION 'Rate changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF EXISTS(SELECT 1 FROM public.bill_panel_selections WHERE rate_version_id=r.id) THEN UPDATE public.catalogue_rate_versions SET status='Inactive',effective_to=COALESCE(effective_to,now()),row_version=row_version+1,updated_at=now() WHERE id=r.id; ELSE UPDATE public.catalogue_rate_versions SET status='Archived',effective_to=COALESCE(effective_to,now()),row_version=row_version+1,updated_at=now() WHERE id=r.id; END IF; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_archive_rate TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_booking_readiness(p_test_ids UUID[])
RETURNS TABLE(test_id UUID,approval_state TEXT,classification TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_create_bill') OR public.has_permission('can_manage_catalogue')) THEN
   RAISE EXCEPTION 'CATALOGUE_BOOKING_READINESS_ACCESS_DENIED' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT t.id,r.state::TEXT,public.catalogue_classification(t)
 FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id
 WHERE t.id=ANY(COALESCE(p_test_ids,ARRAY[]::UUID[]));
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_booking_readiness TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_bulk_activate(
  p_test_ids UUID[]
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  t_id UUID;
  readiness JSONB;
  activated_count INT := 0;
  failed_tests JSONB := '[]'::JSONB;
  actor_id UUID;
  actor_name TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  IF p_test_ids IS NULL OR cardinality(p_test_ids) = 0 THEN
    RAISE EXCEPTION 'No tests provided for bulk activation.' USING ERRCODE='22023';
  END IF;

  -- Validate readiness for all tests
  FOREACH t_id IN ARRAY p_test_ids LOOP
    readiness := public.catalogue_check_test_readiness(t_id);
    IF NOT (readiness->>'ready_for_activation')::BOOLEAN THEN
      failed_tests := failed_tests || jsonb_build_object(
        'test_id', t_id,
        'code', readiness->>'code',
        'blockers', readiness->'activation_blockers'
      );
    END IF;
  END LOOP;

  IF jsonb_array_length(failed_tests) > 0 THEN
    RAISE EXCEPTION 'Bulk activation blocked: % tests have activation blockers: %',
      jsonb_array_length(failed_tests), failed_tests::TEXT USING ERRCODE='23514';
  END IF;

  -- Apply activation
  FOREACH t_id IN ARRAY p_test_ids LOOP
    UPDATE public.tests
    SET lifecycle_status = 'Active',
        is_active = TRUE,
        billing_enabled = TRUE,
        clinical_reporting_enabled = TRUE,
        activated_at = NOW(),
        activated_by = actor_id,
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = t_id;

    activated_count := activated_count + 1;
  END LOOP;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id, actor_name, 'CATALOGUE_BULK_ACTIVATED', 'Test',
    'BULK_' || activated_count::TEXT,
    jsonb_build_object('count', activated_count),
    jsonb_build_object('test_ids', p_test_ids)
  );

  RETURN jsonb_build_object('activated_count', activated_count, 'test_ids', p_test_ids);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_bulk_activate TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_bulk_import_lab_data(
  p_items JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  item JSONB;
  t_code TEXT;
  t_id UUID;
  param_id UUID;
  updated_count INT := 0;
  errs TEXT[] := ARRAY[]::TEXT[];
  price_val BIGINT;
  actor_id UUID;
  actor_name TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('updated_count', 0, 'errors', ARRAY['EMPTY_IMPORT_DATA']);
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    t_code := upper(btrim(COALESCE(item->>'test_code', '')));
    IF t_code = '' THEN
      errs := array_append(errs, 'Row missing test_code');
      CONTINUE;
    END IF;

    SELECT id INTO t_id FROM public.tests WHERE upper(code) = t_code;
    IF t_id IS NULL THEN
      errs := array_append(errs, 'Test code not found: ' || t_code);
      CONTINUE;
    END IF;

    -- Calculate price in paisa if price_npr is provided
    IF item->>'price_npr' IS NOT NULL AND btrim(item->>'price_npr') <> '' THEN
      price_val := round((item->>'price_npr')::numeric * 100);
    ELSE
      price_val := NULL;
    END IF;

    -- Update test metadata in DRAFT state
    UPDATE public.tests
    SET method = COALESCE(NULLIF(btrim(item->>'method'), ''), method),
        sample_type = COALESCE(NULLIF(btrim(item->>'specimen'), ''), sample_type),
        container = COALESCE(NULLIF(btrim(item->>'container'), ''), container),
        tat_hours = COALESCE(NULLIF(btrim(item->>'tat'), '')::int, tat_hours),
        price_paisa = COALESCE(price_val, price_paisa),
        price_configured = CASE WHEN price_val IS NOT NULL THEN TRUE ELSE price_configured END,
        configuration_notes = COALESCE(NULLIF(btrim(item->>'approval_notes'), ''), configuration_notes),
        updated_at = NOW()
    WHERE id = t_id;

    -- If parameter reference ranges are supplied, insert/update them
    IF (item->>'male_range' IS NOT NULL AND btrim(item->>'male_range') <> '')
       OR (item->>'female_range' IS NOT NULL AND btrim(item->>'female_range') <> '')
       OR (item->>'unit' IS NOT NULL AND btrim(item->>'unit') <> '') THEN

      -- Update parameter unit
      UPDATE public.parameters
      SET unit = COALESCE(NULLIF(btrim(item->>'unit'), ''), unit)
      WHERE test_id = t_id;

      SELECT id INTO param_id FROM public.parameters WHERE test_id = t_id LIMIT 1;
      IF param_id IS NOT NULL AND (item->>'male_range' IS NOT NULL OR item->>'female_range' IS NOT NULL) THEN
        -- Insert/update draft reference range
        INSERT INTO public.reference_ranges (
          parameter_id, gender, age_min_days, age_max_days,
          normal_text, critical_low, critical_high, method, unit,
          is_active, is_approved, lifecycle_status, validation_state
        ) VALUES (
          param_id, 'All', 0, 43800,
          COALESCE(item->>'male_range', item->>'female_range'),
          NULLIF(btrim(item->>'critical_low'), '')::numeric,
          NULLIF(btrim(item->>'critical_high'), '')::numeric,
          btrim(item->>'method'), btrim(item->>'unit'),
          TRUE, FALSE, 'Draft', 'Unclassified'
        ) ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    updated_count := updated_count + 1;
  END LOOP;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id, actor_name, 'CATALOGUE_BULK_IMPORT_DATA', 'Test',
    'IMPORT_' || updated_count::TEXT,
    jsonb_build_object('count', updated_count),
    jsonb_build_object('updated_count', updated_count, 'errors', errs)
  );

  RETURN jsonb_build_object('updated_count', updated_count, 'errors', errs);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_bulk_import_lab_data TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_bulk_set_current_rates(p_changes JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE change JSONB; result JSONB; results JSONB:='[]'::JSONB; seen TEXT[]:=ARRAY[]::TEXT[]; key TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();
  IF jsonb_typeof(p_changes)<>'array' OR jsonb_array_length(p_changes)=0 OR jsonb_array_length(p_changes)>100 THEN RAISE EXCEPTION 'Provide between 1 and 100 reviewed rate changes.' USING ERRCODE='22023'; END IF;
  FOR change IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
    key:=(change->>'entity_type')||':'||(change->>'entity_id');
    IF key=ANY(seen) THEN RAISE EXCEPTION 'Duplicate entity in bulk rate review.' USING ERRCODE='22023'; END IF;
    seen:=array_append(seen,key);
    result:=public.catalogue_set_current_rate((change->>'entity_type')::public.catalogue_billable_entity_enum,(change->>'entity_id')::UUID,
      (change->>'price_paisa')::BIGINT,NULLIF(change->>'expected_rate_id','')::UUID,NULLIF(change->>'expected_rate_version','')::BIGINT,change->>'reason');
    results:=results||jsonb_build_array(result||jsonb_build_object('entity_type',change->>'entity_type','entity_id',change->>'entity_id'));
  END LOOP;
  RETURN jsonb_build_object('updated_count',jsonb_array_length(results),'changes',results);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_bulk_set_current_rates TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_bulk_submit_lab_approval(
  p_test_ids UUID[],
  p_analyzer_model TEXT,
  p_reagent_manufacturer TEXT,
  p_method TEXT,
  p_reference_range_source TEXT,
  p_critical_limit_source TEXT,
  p_effective_from DATE,
  p_approval_notes TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  t_id UUID;
  readiness JSONB;
  approved_count INT := 0;
  failed_tests JSONB := '[]'::JSONB;
  actor_id UUID;
  actor_name TEXT;
  new_version BIGINT;
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  IF p_test_ids IS NULL OR cardinality(p_test_ids) = 0 THEN
    RAISE EXCEPTION 'No tests provided for bulk approval.' USING ERRCODE='22023';
  END IF;

  -- First pass: Validate clinical readiness for ALL selected tests (fail closed)
  FOREACH t_id IN ARRAY p_test_ids LOOP
    readiness := public.catalogue_check_test_readiness(t_id);
    IF NOT (readiness->>'ready_for_approval')::BOOLEAN THEN
      failed_tests := failed_tests || jsonb_build_object(
        'test_id', t_id,
        'code', readiness->>'code',
        'missing', readiness->'missing_fields'
      );
    END IF;
  END LOOP;

  IF jsonb_array_length(failed_tests) > 0 THEN
    RAISE EXCEPTION 'Bulk approval blocked: % tests have missing clinical fields: %',
      jsonb_array_length(failed_tests), failed_tests::TEXT USING ERRCODE='23514';
  END IF;

  -- Second pass: Apply formal approval and transition to VALIDATED
  FOREACH t_id IN ARRAY p_test_ids LOOP
    SELECT COALESCE(MAX(version), 0) + 1 INTO new_version
    FROM public.catalogue_lab_approvals
    WHERE test_id = t_id;

    INSERT INTO public.catalogue_lab_approvals (
      test_id, approved_by, approved_by_name, approved_at,
      analyzer_model, reagent_manufacturer, method,
      reference_range_source, critical_limit_source,
      effective_from, version, approval_notes, approval_status
    ) VALUES (
      t_id, actor_id, actor_name, NOW(),
      btrim(p_analyzer_model), btrim(p_reagent_manufacturer), btrim(p_method),
      btrim(p_reference_range_source), btrim(p_critical_limit_source),
      COALESCE(p_effective_from, CURRENT_DATE), new_version, btrim(p_approval_notes), 'APPROVED'
    );

    UPDATE public.tests
    SET validation_status = 'VALIDATED',
        clinical_configuration_status = 'Configured',
        method = COALESCE(NULLIF(btrim(p_method), ''), method),
        configuration_notes = COALESCE(NULLIF(btrim(p_approval_notes), ''), configuration_notes),
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = t_id;

    approved_count := approved_count + 1;
  END LOOP;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id, actor_name, 'CATALOGUE_BULK_LAB_APPROVED', 'Test',
    'BULK_' || approved_count::TEXT,
    jsonb_build_object('count', approved_count),
    jsonb_build_object('test_ids', p_test_ids, 'approved_by', actor_name)
  );

  RETURN jsonb_build_object('approved_count', approved_count, 'test_ids', p_test_ids);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_bulk_submit_lab_approval TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_cbc_source_completeness()
RETURNS TABLE(parameter_code TEXT,mandatory BOOLEAN,v3_source_status TEXT,technical_decision_status TEXT,current_validated_policy BOOLEAN,blocker TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.catalogue_require_manager();
  RETURN QUERY
  WITH required(code) AS (VALUES ('HB'),('TLC'),('NEUT'),('LYMPH'),('EOSIN'),('MONO'),('BASO'),('RBC'),('PCV'),('MCV'),('MCH'),('MCHC'),('RDW'),('PLT')),
  v3 AS (
   SELECT target_parameter_code code,
          CASE WHEN bool_or(source_classification='AuthorizedApproximateReviewRequired') THEN 'Approximate'
               WHEN bool_or(source_classification='AuthorizedContextDependent') THEN 'ContextDependent'
               WHEN bool_or(source_classification='SourceVersionChanged') THEN 'SourceVersionChanged'
               WHEN bool_or(source_classification='AuthorizedSexSpecificAgeBoundsMissing') THEN 'AgeBoundsMissing'
               WHEN bool_or(source_classification='AuthorizedUnspecifiedAge') THEN 'AgeUnspecified'
               ELSE 'Supplied' END status,
          max(review_state) review_state
   FROM public.clinical_source_items s JOIN public.clinical_source_imports i ON i.id=s.import_id
   WHERE i.source_version='CBC-V3' AND target_test_code='CBC' GROUP BY target_parameter_code
  )
  SELECT r.code,TRUE,COALESCE(v3.status,'Missing'),COALESCE(v3.review_state,'PendingTechnicalReview'),
         EXISTS(SELECT 1 FROM public.tests t JOIN public.parameters p ON p.test_id=t.id
                JOIN public.reference_ranges rr ON rr.parameter_id=p.id
                WHERE t.code='CBC' AND p.code=r.code AND rr.lifecycle_status='Active' AND rr.is_active
                  AND rr.is_approved AND rr.validation_state='ClinicallyValidated'),
         CASE WHEN v3.code IS NULL THEN 'CBC_SOURCE_MISSING'
              WHEN v3.status='Approximate' THEN 'CBC_SOURCE_APPROXIMATE'
              WHEN v3.status IN ('ContextDependent','AgeBoundsMissing','AgeUnspecified') THEN 'CBC_APPLICABILITY_INCOMPLETE'
              WHEN v3.status='SourceVersionChanged' THEN 'CBC_SOURCE_CONFLICT'
              WHEN v3.review_state<>'ApprovedForMaterialization' THEN 'CBC_TECHNICAL_DECISION_REQUIRED'
              ELSE NULL END
  FROM required r LEFT JOIN v3 ON v3.code=r.code
  ORDER BY array_position(ARRAY['HB','TLC','NEUT','LYMPH','EOSIN','MONO','BASO','RBC','PCV','MCV','MCH','MCHC','RDW','PLT'],r.code);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_cbc_source_completeness TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_cbc_v4_completeness()
RETURNS TABLE(parameter_code TEXT,selected_source_candidate TEXT,age_coverage TEXT,sex_coverage TEXT,
 method_analyzer_status TEXT,formula_status TEXT,conflict_status TEXT,technical_decision_required TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.catalogue_require_manager();
  RETURN QUERY
  WITH required(code) AS (VALUES ('HB'),('TLC'),('NEUT'),('LYMPH'),('EOSIN'),('MONO'),('BASO'),('RBC'),('PCV'),('MCV'),('MCH'),('MCHC'),('RDW'),('PLT')),
  v4 AS (SELECT target_parameter_code code,string_agg(supplied_value||' '||coalesce(supplied_unit,''),'; ' ORDER BY source_key) candidate,
    bool_and(source_classification='AuthorizedExplicitApplicability') explicit_applicability,
    bool_or(source_classification='SourceVersionChanged') conflict
    FROM public.clinical_source_items s JOIN public.clinical_source_imports i ON i.id=s.import_id
    WHERE i.source_version='CBC-V4' AND target_test_code='CBC' GROUP BY target_parameter_code),
  formula AS (SELECT output_parameter_code code,string_agg(formula_identifier||' v'||formula_version||' '||lifecycle_status,', ') status
    FROM public.clinical_calculation_formula_versions WHERE formula_identifier LIKE 'CBC_%' GROUP BY output_parameter_code)
  SELECT r.code,coalesce(v4.candidate,'No V4 candidate'),
    CASE WHEN r.code='HB' THEN 'V4 intervals explicit; year/day materialization decision pending'
         WHEN v4.code IS NULL THEN 'Not supplied by V4' ELSE 'Age unspecified/incomplete' END,
    CASE WHEN r.code IN ('HB','PCV') THEN 'Sex-specific where supplied; pediatric Hb All'
         WHEN v4.code IS NULL THEN 'Not supplied by V4' ELSE 'Sex unspecified' END,
    'Technical method/analyzer applicability decision required',coalesce(formula.status,'Measured; no formula'),
    CASE WHEN v4.conflict THEN 'Source conflict requires selection' WHEN v4.code IS NULL THEN 'V1–V3 evidence retained' ELSE 'No changed numeric conflict identified in V4' END,
    CASE WHEN r.code='HB' THEN 'Select V4 policy; materialize non-overlapping age-day bounds; method/analyzer; critical-limit review'
         WHEN r.code IN ('MCV','MCH','MCHC') THEN 'Select source/applicability and Measured vs consistency-check mode; approve rounding if formula used'
         WHEN r.code IN ('RBC','RDW') THEN 'V4 missing: select/correct older source applicability'
         WHEN v4.conflict THEN 'Select source version; complete applicability; method/analyzer; critical-limit review'
         ELSE 'Complete applicability; method/analyzer; critical-limit review' END
  FROM required r LEFT JOIN v4 ON v4.code=r.code LEFT JOIN formula ON formula.code=r.code
  ORDER BY array_position(ARRAY['HB','TLC','NEUT','LYMPH','EOSIN','MONO','BASO','RBC','PCV','MCV','MCH','MCHC','RDW','PLT'],r.code);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_cbc_v4_completeness TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_check_test_readiness(p_test_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  missing TEXT[] := ARRAY[]::TEXT[];
  blockers TEXT[] := ARRAY[]::TEXT[];
  p RECORD;
  c RECORD;
  has_numeric BOOLEAN := FALSE;
  has_ranges BOOLEAN := FALSE;
  param_count INT := 0;
BEGIN
  SELECT * INTO v FROM public.tests WHERE id = p_test_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', FALSE, 'error', 'TEST_NOT_FOUND');
  END IF;

  -- 1. Basic Identity & Specimen
  IF btrim(COALESCE(v.code, '')) = '' THEN missing := array_append(missing, 'Test Code'); END IF;
  IF btrim(COALESCE(v.name, '')) = '' THEN missing := array_append(missing, 'Test Name'); END IF;
  IF v.reporting_type <> 'NoReporting' AND btrim(COALESCE(v.sample_type, '')) = '' THEN
    missing := array_append(missing, 'Specimen Type');
  END IF;
  IF v.reporting_type <> 'NoReporting' AND btrim(COALESCE(v.container, '')) = '' THEN
    missing := array_append(missing, 'Container');
  END IF;

  -- 2. Result-Type-Aware Parameter & Range Checks
  FOR p IN SELECT * FROM public.parameters WHERE test_id = v.id AND is_active LOOP
    param_count := param_count + 1;
    IF p.value_type = 'Numeric' THEN
      has_numeric := TRUE;
      IF btrim(COALESCE(p.unit, '')) = '' THEN
        missing := array_append(missing, 'Unit for numeric parameter: ' || p.code);
      END IF;
      -- Strict check: Numeric tests MUST have configured reference ranges to be ready for approval
      IF EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id = p.id AND r.is_active) THEN
        has_ranges := TRUE;
      ELSE
        missing := array_append(missing, 'Reference range for numeric parameter: ' || p.code);
      END IF;
    ELSIF p.value_type = 'Calculated' THEN
      IF btrim(COALESCE(p.formula, '')) = '' AND btrim(COALESCE(p.calculation_identifier, '')) = '' THEN
        missing := array_append(missing, 'Formula/Calculation Identifier for: ' || p.code);
      END IF;
      IF btrim(COALESCE(p.unit, '')) = '' THEN
        missing := array_append(missing, 'Unit for calculated parameter: ' || p.code);
      END IF;
    ELSIF p.value_type IN ('PositiveNegative', 'ReactiveNonReactive', 'DetectedNotDetected', 'Text') THEN
      -- Qualitative requires analytical method
      IF btrim(COALESCE(v.method, '')) = '' THEN
        missing := array_append(missing, 'Analytical Method for qualitative test');
      END IF;
    ELSIF p.value_type = 'CultureAST' THEN
      IF btrim(COALESCE(v.sample_type, '')) = '' THEN
        missing := array_append(missing, 'Specimen for Culture/AST');
      END IF;
    END IF;
  END LOOP;

  -- If not a panel and not NoReporting, ensure at least one parameter or method is defined
  IF v.test_kind <> 'Profile' AND v.reporting_type <> 'NoReporting' AND param_count = 0 THEN
    IF btrim(COALESCE(v.method, '')) = '' THEN
      missing := array_append(missing, 'Result structure or analytical method');
    END IF;
  END IF;

  -- 3. Panel Component Checks
  IF v.test_kind = 'Profile' OR v.test_type = 'Panel' THEN
    IF NOT EXISTS(SELECT 1 FROM public.catalogue_panel_components WHERE panel_test_id = v.id) THEN
      missing := array_append(missing, 'Panel Components (No child tests linked)');
    ELSE
      -- Check if child components are ready
      FOR c IN SELECT t.code, t.name, t.validation_status, t.is_active
               FROM public.catalogue_panel_components cpc
               JOIN public.tests t ON cpc.component_test_id = t.id
               WHERE cpc.panel_test_id = v.id LOOP
        IF c.validation_status <> 'VALIDATED' THEN
          blockers := array_append(blockers, 'Child test ' || c.code || ' is not validated');
        END IF;
        IF NOT c.is_active THEN
          blockers := array_append(blockers, 'Child test ' || c.code || ' is not active');
        END IF;
      END LOOP;
    END IF;
  END IF;

  -- Activation Blockers
  IF v.validation_status <> 'VALIDATED' THEN
    blockers := array_append(blockers, 'Test requires clinical validation and laboratory approval');
  END IF;
  IF cardinality(missing) > 0 THEN
    blockers := array_cat(blockers, missing);
  END IF;

  RETURN jsonb_build_object(
    'test_id', v.id,
    'code', v.code,
    'name', v.name,
    'test_kind', v.test_kind,
    'validation_status', v.validation_status,
    'is_active', v.is_active,
    'ready_for_approval', (cardinality(missing) = 0),
    'missing_fields', missing,
    'ready_for_activation', (cardinality(blockers) = 0),
    'activation_blockers', blockers,
    'has_pricing', (v.price_configured OR v.price_paisa > 0 OR v.allow_zero_price_billing),
    'has_method', (btrim(COALESCE(v.method, '')) <> ''),
    'has_ranges', has_ranges
  );
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_check_test_readiness TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_classification(p_test public.tests)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path=public,pg_temp AS $$
 SELECT CASE
   WHEN p_test.workflow_type IN
     ('MicrobiologyCulture','MicrobiologyMicroscopy','Cytology','Histopathology','Molecular') THEN 'SpecialistWorkflow'
   WHEN NOT p_test.workflow_supported AND p_test.workflow_type<>'NoClinicalReport' THEN 'SpecialistWorkflow'
   WHEN p_test.reporting_type='NoReporting' OR p_test.workflow_type='NoClinicalReport' THEN 'BillingOnly'
   WHEN p_test.reporting_type='OutsourceWithBimalReport' THEN 'OutsourceWithBimalReport'
   ELSE 'InHouse'
 END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_classification TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_clinical_missing_configuration(p_test_id UUID) RETURNS TEXT[]
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; missing TEXT[]:=ARRAY[]::TEXT[]; p RECORD;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO t FROM public.tests WHERE id=p_test_id;
  IF NOT FOUND THEN RETURN ARRAY['canonical identity']; END IF;
  IF NOT t.workflow_supported OR t.reporting_type='NoReporting' OR t.workflow_type IN ('MicrobiologyCulture','Cytology','Histopathology','Molecular','NoClinicalReport')
     OR t.clinical_configuration_status='Workflow Not Supported' THEN missing:=array_append(missing,'supported clinical workflow'); END IF;
  IF t.clinical_configuration_status='Requires Clinical Validation' THEN missing:=array_append(missing,'clinical validation approval'); END IF;
  IF btrim(COALESCE(t.sample_type,''))='' THEN missing:=array_append(missing,'specimen'); END IF;
  IF btrim(COALESCE(t.container,''))='' THEN missing:=array_append(missing,'container'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.parameters WHERE test_id=t.id AND lifecycle_status='Active' AND is_active) THEN missing:=array_append(missing,'at least one active parameter'); END IF;
  IF t.analyzer_configuration_required AND NOT EXISTS(
    SELECT 1 FROM public.test_analyzer_configurations c JOIN public.analyzers a ON a.id=c.analyzer_id
    WHERE c.test_id=t.id AND c.lifecycle_status='Active' AND c.is_clinically_approved
      AND c.validation_state='ClinicallyValidated' AND a.lifecycle_status='Active'
      AND c.effective_from<=CURRENT_DATE AND (c.effective_to IS NULL OR c.effective_to>=CURRENT_DATE)
  ) THEN missing:=array_append(missing,'active clinically validated analyzer configuration'); END IF;
  FOR p IN SELECT * FROM public.parameters WHERE test_id=t.id AND lifecycle_status='Active' AND is_active LOOP
    IF p.value_type IN ('Numeric','Calculated') AND btrim(COALESCE(p.unit,''))='' THEN missing:=array_append(missing,p.code||': unit'); END IF;
    IF p.clinical_configuration_status='Requires Clinical Validation' OR p.unit_validation_required OR p.range_validation_required OR p.method_validation_required THEN missing:=array_append(missing,p.code||': clinical validation'); END IF;
    IF p.value_type='Select' AND COALESCE(jsonb_array_length(p.options),0)=0 THEN missing:=array_append(missing,p.code||': select options'); END IF;
    IF p.value_type IN ('Numeric','Calculated') AND NOT EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id=p.id AND r.lifecycle_status='Active' AND r.is_active AND r.is_approved AND r.validation_state='ClinicallyValidated') THEN missing:=array_append(missing,p.code||': clinically validated reference-range policy'); END IF;
    IF p.value_type='Calculated' AND NOT EXISTS(SELECT 1 FROM public.catalogue_calculation_definitions d WHERE d.identifier=p.calculation_identifier AND d.parameter_code=p.code AND d.server_authoritative AND d.is_active) THEN missing:=array_append(missing,p.code||': approved server-authoritative calculation'); END IF;
  END LOOP;
  RETURN missing;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_clinical_missing_configuration TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_clone_test(p_test_id UUID,p_code TEXT,p_name TEXT) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE source public.tests%ROWTYPE; target UUID; p RECORD; new_p UUID;
BEGIN
 PERFORM public.catalogue_require_manager(); SELECT * INTO source FROM public.tests WHERE id=p_test_id FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'Source test not found.'; END IF;
 INSERT INTO public.tests(code,name,short_name,description,department,category,category_id,test_kind,reporting_type,outsource_lab_name,price_paisa,sample_type,container,sample_volume,method,tat_hours,display_order,is_active,lifecycle_status,configuration_notes,price_configured,clinical_configuration_status)
 VALUES(upper(btrim(p_code)),btrim(p_name),source.short_name,source.description,source.department,source.category,source.category_id,source.test_kind,source.reporting_type,source.outsource_lab_name,0,source.sample_type,source.container,source.sample_volume,source.method,source.tat_hours,source.display_order,FALSE,'Draft','Cloned configuration; clinical values and price require review.',FALSE,'Requires Clinical Validation') RETURNING id INTO target;
 FOR p IN SELECT * FROM public.parameters WHERE test_id=p_test_id AND lifecycle_status<>'Archived' ORDER BY display_order LOOP
  INSERT INTO public.parameters(test_id,code,name,value_type,unit,options,display_order,is_mandatory,is_active,lifecycle_status,decimal_precision,interpretation_config)
  VALUES(target,p.code,p.name,p.value_type,p.unit,p.options,p.display_order,p.is_mandatory,FALSE,'Draft',p.decimal_precision,p.interpretation_config) RETURNING id INTO new_p;
 END LOOP;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_TEST_CLONED','Test',target::TEXT,jsonb_build_object('source_id',p_test_id,'code',p_code)); RETURN target;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_clone_test TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_clone_test_easy(
  p_source_test_id UUID,
  p_new_code TEXT,
  p_new_name TEXT,
  p_new_price_paisa BIGINT DEFAULT 0
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  source public.tests%ROWTYPE;
  target_id UUID;
  p RECORD;
  new_p_id UUID;
  r RECORD;
  code_clean TEXT := upper(btrim(p_new_code));
  name_clean TEXT := btrim(p_new_name);
BEGIN
  PERFORM public.catalogue_require_manager();

  IF code_clean IS NULL OR code_clean = '' THEN
    RAISE EXCEPTION 'A unique new test code is required.' USING ERRCODE='22023';
  END IF;
  IF name_clean IS NULL OR name_clean = '' THEN
    RAISE EXCEPTION 'A test name is required.' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.tests WHERE code = code_clean) THEN
    RAISE EXCEPTION 'Test code % already exists. Please choose a unique code.', code_clean USING ERRCODE='23505';
  END IF;

  SELECT * INTO source FROM public.tests WHERE id = p_source_test_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Source test was not found.' USING ERRCODE='P0002';
  END IF;

  INSERT INTO public.tests (
    code, name, short_name, description, department, category, category_id,
    test_kind, reporting_type, outsource_lab_name, price_paisa, sample_type,
    container, sample_volume, method, tat_hours, display_order, is_active,
    lifecycle_status, configuration_notes, price_configured, clinical_configuration_status,
    billing_enabled, clinical_reporting_enabled, collection_required, workflow_type,
    allow_zero_price_billing, allow_manual_price, pricing_policy, search_aliases, row_version
  ) VALUES (
    code_clean, name_clean, source.short_name, source.description, source.department,
    source.category, source.category_id, source.test_kind, source.reporting_type,
    source.outsource_lab_name, COALESCE(p_new_price_paisa, source.price_paisa),
    source.sample_type, source.container, source.sample_volume, source.method,
    source.tat_hours, source.display_order, TRUE, 'Active',
    'Cloned from ' || source.code, (COALESCE(p_new_price_paisa, source.price_paisa) > 0),
    'Configured', TRUE, (source.reporting_type <> 'NoReporting'),
    (source.reporting_type <> 'NoReporting'), source.workflow_type,
    source.allow_zero_price_billing, source.allow_manual_price, source.pricing_policy,
    source.search_aliases, 1
  ) RETURNING id INTO target_id;

  -- Create initial rate version
  INSERT INTO public.catalogue_rate_versions (
    entity_type, test_id, ratelist_name, price_paisa, status, effective_from, row_version
  ) VALUES (
    'Test', target_id, 'Standard Patient Rate', COALESCE(p_new_price_paisa, source.price_paisa), 'Active', NOW(), 1
  );

  -- Copy parameters and their reference ranges
  FOR p IN SELECT * FROM public.parameters WHERE test_id = p_source_test_id AND lifecycle_status <> 'Archived' ORDER BY display_order LOOP
    INSERT INTO public.parameters (
      test_id, code, name, value_type, unit, options, formula, formula_dependencies,
      calculation_identifier, decimal_precision, interpretation_config, display_order,
      is_mandatory, is_active, lifecycle_status, clinical_configuration_status, row_version
    ) VALUES (
      target_id, p.code, p.name, p.value_type, p.unit, p.options, p.formula, p.formula_dependencies,
      p.calculation_identifier, p.decimal_precision, p.interpretation_config, p.display_order,
      p.is_mandatory, TRUE, 'Active', 'Configured', 1
    ) RETURNING id INTO new_p_id;

    -- Copy ranges for this parameter
    FOR r IN SELECT * FROM public.reference_ranges WHERE parameter_id = p.id AND lifecycle_status <> 'Archived' LOOP
      INSERT INTO public.reference_ranges (
        parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max,
        critical_low, critical_high, normal_text, reference_text, method, unit,
        is_active, is_approved, lifecycle_status, validation_state, row_version
      ) VALUES (
        new_p_id, r.gender, r.age_min_days, r.age_max_days, r.normal_min, r.normal_max,
        r.critical_low, r.critical_high, r.normal_text, r.reference_text, r.method, r.unit,
        r.is_active, TRUE, 'Active', 'ClinicallyValidated', 1
      );
    END LOOP;
  END LOOP;

  -- Create readiness record
  INSERT INTO public.catalogue_service_readiness (
    test_id, state, configuration_version, approved_by, approved_at, decision_reason
  ) VALUES (
    target_id, 'Approved', 1, auth.uid(), NOW(), 'Cloned from ' || source.code
  );

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, new_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_TEST_CLONED', 'Test', target_id::TEXT,
    jsonb_build_object('source_id', p_source_test_id, 'source_code', source.code, 'new_code', code_clean)
  );

  RETURN target_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_clone_test_easy TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_configuration_history(p_test_id UUID)
RETURNS TABLE(configuration_version BIGINT,category TEXT,status TEXT,actor_role TEXT,action_at TIMESTAMPTZ,reason TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 RETURN QUERY SELECT e.configuration_version,e.category,e.status::TEXT,e.actor_role,e.created_at,e.reason
 FROM public.catalogue_configuration_evidence e WHERE e.test_id=p_test_id
 ORDER BY e.configuration_version DESC,e.created_at DESC,e.id DESC LIMIT 100;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_configuration_history TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_create_rate_version(p_entity_type public.catalogue_billable_entity_enum,p_entity_id UUID,p_other_service_code TEXT,p_price_paisa BIGINT,p_effective_from TIMESTAMPTZ DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID; v_no INT; BEGIN PERFORM public.catalogue_require_manager(); IF p_price_paisa IS NOT NULL AND p_price_paisa<0 THEN RAISE EXCEPTION 'Price cannot be negative.' USING ERRCODE='23514'; END IF;
 SELECT COALESCE(max(version_number),0)+1 INTO v_no FROM public.catalogue_rate_versions r WHERE (p_entity_type='Test' AND r.test_id=p_entity_id) OR (p_entity_type='Panel' AND r.panel_service_id=p_entity_id) OR (p_entity_type='Package' AND r.package_id=p_entity_id) OR (p_entity_type='Other' AND r.other_service_code=p_other_service_code);
 INSERT INTO public.catalogue_rate_versions(entity_type,test_id,panel_service_id,package_id,other_service_code,version_number,price_paisa,effective_from,status,created_by) VALUES(p_entity_type,CASE WHEN p_entity_type='Test' THEN p_entity_id END,CASE WHEN p_entity_type='Panel' THEN p_entity_id END,CASE WHEN p_entity_type='Package' THEN p_entity_id END,CASE WHEN p_entity_type='Other' THEN upper(btrim(p_other_service_code)) END,v_no,p_price_paisa,p_effective_from,'Draft',auth.uid()) RETURNING id INTO v_id; RETURN v_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_create_rate_version TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_decide_readiness(p_test_id UUID,p_decision TEXT,p_reason TEXT,p_expected_version BIGINT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_service_readiness%ROWTYPE; t public.tests%ROWTYPE; checklist JSONB; next_version BIGINT; target public.catalogue_readiness_state_enum; old_state JSONB;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 IF p_decision NOT IN ('MarkReady','MarkReportable','NeedsConfiguration','Suspend','Reactivate','MarkNonReportable') THEN RAISE EXCEPTION 'CATALOGUE_DECISION_INVALID' USING ERRCODE='22023'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'A Technician decision reason is required.' USING ERRCODE='23514'; END IF;
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id FOR UPDATE;
 SELECT * INTO t FROM public.tests WHERE id=p_test_id FOR UPDATE;
 IF NOT FOUND OR r.test_id IS NULL THEN RAISE EXCEPTION 'CATALOGUE_SERVICE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF r.configuration_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 IF NOT t.is_active OR t.lifecycle_status<>'Active' THEN RAISE EXCEPTION 'Inactive or archived services cannot be made operational.' USING ERRCODE='23514'; END IF;
 old_state:=jsonb_build_object('state',r.state,'reporting_type',t.reporting_type,'clinical_reporting_enabled',t.clinical_reporting_enabled);
 checklist:=public.catalogue_service_readiness_checklist(p_test_id); next_version:=r.configuration_version+1;
 IF p_decision IN ('MarkReady','MarkReportable','Reactivate') THEN
   IF cardinality(ARRAY(SELECT jsonb_array_elements_text(checklist->'missing_requirements')))<>0 THEN RAISE EXCEPTION 'CATALOGUE_REPORTING_INVARIANT_FAILED: %',checklist->'missing_requirements' USING ERRCODE='23514'; END IF;
   IF t.reporting_type='NoReporting' THEN UPDATE public.tests SET reporting_type='InHouse',workflow_type=CASE WHEN workflow_type='NoClinicalReport' THEN 'Routine' ELSE workflow_type END,billing_enabled=TRUE,clinical_reporting_enabled=TRUE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
   ELSE UPDATE public.tests SET billing_enabled=TRUE,clinical_reporting_enabled=TRUE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now() WHERE id=p_test_id; END IF;
   target:='Approved';
 ELSIF p_decision='MarkNonReportable' THEN
   target:='Approved'; UPDATE public.tests SET reporting_type='NoReporting',workflow_type='NoClinicalReport',collection_required=FALSE,billing_enabled=TRUE,clinical_reporting_enabled=FALSE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 ELSIF p_decision='Suspend' THEN target:='Suspended'; UPDATE public.tests SET billing_enabled=FALSE,clinical_reporting_enabled=FALSE,row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 ELSE target:='NeedsConfiguration'; UPDATE public.tests SET billing_enabled=FALSE,clinical_reporting_enabled=FALSE,clinical_configuration_status='Requires Clinical Validation',row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 END IF;
 UPDATE public.catalogue_service_readiness SET state=target,configuration_version=next_version,
  approved_by=CASE WHEN target='Approved' THEN auth.uid() END,approved_at=CASE WHEN target='Approved' THEN now() END,
  suspended_by=CASE WHEN target='Suspended' THEN auth.uid() END,suspended_at=CASE WHEN target='Suspended' THEN now() END,
  decision_reason=btrim(p_reason),updated_at=now() WHERE test_id=p_test_id;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,previous_state,new_state,reason,actor_id,actor_role)
 VALUES(p_test_id,next_version,'Workflow',(CASE WHEN target='Approved' THEN 'Approved' ELSE 'Rejected' END)::public.catalogue_decision_status_enum,old_state,
  checklist||jsonb_build_object('decision',p_decision,'resulting_state',target),btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role());
 RETURN next_version;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_decide_readiness TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_delete_analyzer_mapping_easy(
  p_mapping_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.catalogue_require_manager();

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data
  )
  SELECT auth.uid(), public.catalogue_actor_name(), 'ANALYZER_MAPPING_DELETED', 'AnalyzerMapping', p_mapping_id::TEXT, to_jsonb(m)
  FROM public.analyzer_parameter_mappings m WHERE m.id = p_mapping_id;

  DELETE FROM public.analyzer_parameter_mappings WHERE id = p_mapping_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_analyzer_mapping_easy TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_delete_category(
    p_category_id UUID,
    p_expected_version BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_category public.test_categories%ROWTYPE;
BEGIN
    PERFORM public.catalogue_require_manager();
    SELECT * INTO v_category FROM public.test_categories
    WHERE id = p_category_id FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF p_expected_version IS NULL OR v_category.row_version <> p_expected_version THEN
        RAISE EXCEPTION 'Category changed. Refresh and try again.' USING ERRCODE = 'PT409';
    END IF;
    IF EXISTS (SELECT 1 FROM public.tests WHERE category_id = p_category_id) THEN
        RAISE EXCEPTION 'Referenced categories cannot be deleted. Move or archive their tests first.' USING ERRCODE = '23503';
    END IF;
    INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data)
    VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_CATEGORY_DELETED','TestCategory',p_category_id::TEXT,to_jsonb(v_category));
    DELETE FROM public.test_categories WHERE id = p_category_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_category TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_delete_or_archive_rate(p_rate_id UUID,p_expected_version BIGINT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_rate_versions%ROWTYPE; v_used BOOLEAN;
BEGIN
 PERFORM public.catalogue_require_manager();
 SELECT * INTO r FROM public.catalogue_rate_versions WHERE id=p_rate_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Rate not found.' USING ERRCODE='P0002'; END IF;
 IF r.row_version<>p_expected_version THEN RAISE EXCEPTION 'Rate changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.bill_panel_selections WHERE rate_version_id=r.id) INTO v_used;
 IF NOT v_used AND r.status='Draft' THEN
  DELETE FROM public.catalogue_rate_versions WHERE id=r.id;
  RETURN 'Deleted';
 END IF;
 UPDATE public.catalogue_rate_versions
 SET status=(CASE WHEN v_used THEN 'Inactive' ELSE 'Archived' END)::public.catalogue_rate_status_enum,
  effective_to=COALESCE(effective_to,now()),row_version=row_version+1,updated_at=now()
 WHERE id=r.id;
 RETURN CASE WHEN v_used THEN 'ArchivedUsedRate' ELSE 'Archived' END;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_or_archive_rate TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_delete_package(p_package_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.health_packages%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.health_packages WHERE id=p_package_id FOR UPDATE; IF NOT FOUND THEN RETURN; END IF; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Package changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF EXISTS(SELECT 1 FROM public.bill_package_selections WHERE package_id=p_package_id) THEN RAISE EXCEPTION 'Billed packages cannot be deleted. Archive this package.' USING ERRCODE='23503'; END IF; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PACKAGE_DELETED','HealthPackage',p_package_id::TEXT,to_jsonb(v)); DELETE FROM public.health_packages WHERE id=p_package_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_package TO authenticated, service_role;

CREATE FUNCTION public.catalogue_delete_panel(p_panel_id UUID,p_expected_version BIGINT) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; referenced BOOLEAN;
BEGIN
 PERFORM public.catalogue_require_manager(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Panel not found.' USING ERRCODE='P0002'; END IF; IF p.row_version<>p_expected_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.bill_panel_selections WHERE panel_id=p_panel_id) INTO referenced;
 IF referenced THEN PERFORM public.catalogue_set_panel_lifecycle(p_panel_id,'Archived',p_expected_version); RETURN 'Archived'; END IF;
 DELETE FROM public.catalogue_panel_components WHERE panel_id=p_panel_id; DELETE FROM public.catalogue_panel_ratelist_links WHERE panel_id=p_panel_id;
 DELETE FROM public.catalogue_panel_identity_resolution WHERE panel_id=p_panel_id; DELETE FROM public.catalogue_panel_services WHERE panel_id=p_panel_id; DELETE FROM public.catalogue_panels WHERE id=p_panel_id; RETURN 'Deleted';
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_panel TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_delete_parameter(p_parameter_id UUID,p_expected_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.parameters%ROWTYPE;
BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.parameters WHERE id=p_parameter_id FOR UPDATE; IF NOT FOUND THEN RETURN; END IF; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Parameter changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 IF EXISTS(SELECT 1 FROM public.test_results WHERE parameter_id=p_parameter_id) THEN RAISE EXCEPTION 'Referenced parameters cannot be deleted. Archive this parameter.' USING ERRCODE='23503'; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PARAMETER_DELETED','Parameter',p_parameter_id::TEXT,to_jsonb(v)); DELETE FROM public.parameters WHERE id=p_parameter_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_parameter TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_delete_parameter_guarded(
  p_parameter_id UUID,
  p_expected_version BIGINT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.parameters%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();

  SELECT * INTO v FROM public.parameters WHERE id = p_parameter_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  IF v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'This parameter was updated by another user. Reload before deleting.' USING ERRCODE='PT409';
  END IF;

  IF EXISTS (SELECT 1 FROM public.test_results WHERE parameter_id = p_parameter_id)
     OR EXISTS (SELECT 1 FROM public.catalogue_panel_components WHERE component_parameter_id = p_parameter_id)
  THEN
    RAISE EXCEPTION 'Referenced parameters cannot be deleted permanently. Archive this parameter instead.' USING ERRCODE='23503';
  END IF;

  DELETE FROM public.reference_ranges WHERE parameter_id = p_parameter_id;
  DELETE FROM public.analyzer_parameter_mappings WHERE parameter_id = p_parameter_id;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_PARAMETER_DELETED_PERMANENTLY', 'Parameter', p_parameter_id::TEXT, to_jsonb(v)
  );

  DELETE FROM public.parameters WHERE id = p_parameter_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_parameter_guarded TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_delete_range(p_range_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.reference_ranges%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.reference_ranges WHERE id=p_range_id FOR UPDATE; IF NOT FOUND THEN RETURN; END IF; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Reference range changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF EXISTS(SELECT 1 FROM public.test_results WHERE parameter_id=v.parameter_id) THEN RAISE EXCEPTION 'A historically used parameter range cannot be hard deleted. Archive it.' USING ERRCODE='23503'; END IF; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_RANGE_DELETED','ReferenceRange',p_range_id::TEXT,to_jsonb(v)); DELETE FROM public.reference_ranges WHERE id=p_range_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_range TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_delete_range_guarded(
  p_range_id UUID,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.reference_ranges%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();

  SELECT * INTO v FROM public.reference_ranges WHERE id = p_range_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  IF p_expected_version IS NOT NULL AND v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'This range was updated by another user. Reload before deleting.' USING ERRCODE='PT409';
  END IF;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_RANGE_DELETED', 'ReferenceRange', p_range_id::TEXT, to_jsonb(v)
  );

  DELETE FROM public.reference_ranges WHERE id = p_range_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_range_guarded TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_delete_test(p_test_id UUID,p_expected_version BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.tests%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF EXISTS(SELECT 1 FROM public.bill_items WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.clinical_order_items WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.test_results r JOIN public.parameters p ON p.id=r.parameter_id WHERE p.test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.health_package_components WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.catalogue_profile_components WHERE profile_test_id=p_test_id OR component_test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.catalogue_panel_components WHERE component_test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.bill_package_components WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.bill_panel_components WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.catalogue_configuration_evidence WHERE test_id=p_test_id)
  THEN RAISE EXCEPTION 'Referenced tests or reviewed configurations cannot be deleted. Archive this test.' USING ERRCODE='23503'; END IF;
  DELETE FROM public.catalogue_rate_versions WHERE test_id=p_test_id;
  DELETE FROM public.catalogue_service_readiness WHERE test_id=p_test_id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data)
  VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_TEST_DELETED','Test',p_test_id::TEXT,to_jsonb(v));
  DELETE FROM public.tests WHERE id=p_test_id;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_test TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_delete_test_guarded(
  p_test_id UUID,
  p_expected_version BIGINT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();

  SELECT * INTO v FROM public.tests WHERE id = p_test_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  IF v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'This test was updated by another user. Reload before deleting.' USING ERRCODE='PT409';
  END IF;

  -- Strict reference check: if used anywhere historically, deny hard delete
  IF EXISTS (SELECT 1 FROM public.bill_items WHERE test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.clinical_order_items WHERE test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.test_results r JOIN public.parameters p ON p.id = r.parameter_id WHERE p.test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.health_package_components WHERE test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.catalogue_profile_components WHERE profile_test_id = p_test_id OR component_test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.catalogue_panel_components WHERE component_test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.bill_package_components WHERE test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.bill_panel_components WHERE test_id = p_test_id)
  THEN
    RAISE EXCEPTION 'Referenced tests cannot be deleted permanently. Archive this test instead to preserve audit lineage.' USING ERRCODE='23503';
  END IF;

  -- Safe hard deletion of child records for unused test
  DELETE FROM public.test_aliases WHERE test_id = p_test_id;
  DELETE FROM public.reference_ranges WHERE parameter_id IN (SELECT id FROM public.parameters WHERE test_id = p_test_id);
  DELETE FROM public.analyzer_parameter_mappings WHERE test_id = p_test_id;
  DELETE FROM public.parameters WHERE test_id = p_test_id;
  DELETE FROM public.catalogue_rate_versions WHERE test_id = p_test_id;
  DELETE FROM public.catalogue_service_readiness WHERE test_id = p_test_id;
  DELETE FROM public.catalogue_test_approval_events WHERE test_id = p_test_id;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_TEST_DELETED_PERMANENTLY', 'Test', p_test_id::TEXT, to_jsonb(v)
  );

  DELETE FROM public.tests WHERE id = p_test_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_delete_test_guarded TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_expand_package(p_package_id UUID) RETURNS TABLE(package_id UUID,package_code TEXT,package_name TEXT,package_price_paisa BIGINT,test_id UUID,test_code TEXT,test_name TEXT,display_order INT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.health_packages p WHERE p.id=p_package_id AND p.lifecycle_status='Active') THEN RAISE EXCEPTION 'Package is unavailable.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM public.health_package_components c JOIN public.tests t ON t.id=c.test_id WHERE c.package_id=p_package_id AND (t.lifecycle_status<>'Active' OR NOT t.is_active OR NOT t.billing_enabled)) THEN RAISE EXCEPTION 'Package contains a disabled component.' USING ERRCODE='23514'; END IF;
 RETURN QUERY SELECT p.id,p.code::TEXT,p.name::TEXT,p.price_paisa,t.id,t.code::TEXT,t.name::TEXT,c.display_order FROM public.health_packages p JOIN public.health_package_components c ON c.package_id=p.id JOIN public.tests t ON t.id=c.test_id WHERE p.id=p_package_id AND p.lifecycle_status='Active' AND t.lifecycle_status='Active' AND t.is_active AND t.billing_enabled ORDER BY c.display_order;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_expand_package TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_expand_profile(p_profile_test_id UUID)
RETURNS TABLE(component_test_id UUID,component_parameter_id UUID,component_role TEXT,display_order INT,is_required BOOLEAN)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
 SELECT c.component_test_id,c.component_parameter_id,c.component_role,c.display_order,c.is_required
 FROM public.catalogue_profile_components c JOIN public.tests p ON p.id=c.profile_test_id
 WHERE c.profile_test_id=p_profile_test_id AND p.test_kind='Profile' ORDER BY c.display_order
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_expand_profile TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_get_governance_summary()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  res JSONB;
BEGIN
  SELECT json_build_object(
    'total_tests', (SELECT count(*)::int FROM public.tests),
    'requires_validation_tests', (SELECT count(*)::int FROM public.tests WHERE validation_status = 'REQUIRES_VALIDATION'),
    'ready_for_approval_tests', (
      SELECT count(*)::int
      FROM public.tests t
      WHERE t.validation_status = 'REQUIRES_VALIDATION'
        AND (public.catalogue_check_test_readiness(t.id)->>'ready_for_approval')::boolean = TRUE
    ),
    'validated_tests', (SELECT count(*)::int FROM public.tests WHERE validation_status = 'VALIDATED'),
    'active_tests', (SELECT count(*)::int FROM public.tests WHERE is_active = TRUE),
    'inactive_tests', (SELECT count(*)::int FROM public.tests WHERE is_active = FALSE),
    'standard_presets_available', (SELECT count(*)::int FROM public.catalogue_standard_presets),
    'standard_presets_adopted', (SELECT count(*)::int FROM public.tests WHERE configuration_source = 'STANDARD_PRESET' AND validation_status = 'VALIDATED'),
    'lab_custom_configurations', (SELECT count(*)::int FROM public.tests WHERE configuration_source = 'LAB_CUSTOM'),
    'missing_analyzer', (
      SELECT count(*)::int FROM public.tests t
      WHERE t.reporting_type <> 'NoReporting'
        AND NOT EXISTS (SELECT 1 FROM public.catalogue_lab_approvals a WHERE a.test_id = t.id AND a.approval_status = 'APPROVED' AND a.analyzer_model IS NOT NULL AND btrim(a.analyzer_model) <> '')
    ),
    'missing_reagent', (
      SELECT count(*)::int FROM public.tests t
      WHERE t.reporting_type <> 'NoReporting'
        AND NOT EXISTS (SELECT 1 FROM public.catalogue_lab_approvals a WHERE a.test_id = t.id AND a.approval_status = 'APPROVED' AND a.reagent_manufacturer IS NOT NULL AND btrim(a.reagent_manufacturer) <> '')
    ),
    'critical_limits_populated', (SELECT count(*)::int FROM public.catalogue_standard_presets WHERE jsonb_array_length(critical_limits) > 0),
    'critical_limits_requiring_policy', (SELECT count(*)::int FROM public.catalogue_standard_presets WHERE jsonb_array_length(critical_limits) = 0),
    'missing_configuration_tests', (SELECT count(*)::int FROM public.tests WHERE btrim(COALESCE(sample_type, '')) = '' OR btrim(COALESCE(container, '')) = ''),
    'missing_pricing_tests', (SELECT count(*)::int FROM public.tests WHERE (price_paisa IS NULL OR price_paisa = 0) AND NOT allow_zero_price_billing),
    'missing_method_tests', (SELECT count(*)::int FROM public.tests WHERE btrim(COALESCE(method, '')) = '' AND reporting_type <> 'NoReporting'),
    'missing_range_tests', (SELECT count(*)::int FROM public.tests t WHERE t.reporting_type <> 'NoReporting' AND NOT EXISTS(
      SELECT 1 FROM public.parameters p JOIN public.reference_ranges r ON r.parameter_id = p.id WHERE p.test_id = t.id AND r.is_active
    )),
    'rejected_or_correction_tests', (SELECT count(*)::int FROM public.catalogue_lab_approvals WHERE approval_status = 'REVOKED')
  ) INTO res;

  RETURN res;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_get_governance_summary TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_get_test_history(p_test_id UUID)
RETURNS TABLE (
  id UUID,
  "timestamp" TIMESTAMPTZ,
  user_name TEXT,
  action TEXT,
  entity_type TEXT,
  old_data JSONB,
  new_data JSONB
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.catalogue_require_manager();

  RETURN QUERY
  SELECT a.id, a.timestamp, a.user_name, a.action, a.entity_type, a.old_data, a.new_data
  FROM public.audit_logs a
  WHERE (a.entity_id = p_test_id::TEXT AND a.entity_type = 'Test')
     OR (a.entity_type = 'Parameter' AND a.entity_id IN (SELECT p.id::TEXT FROM public.parameters p WHERE p.test_id = p_test_id))
     OR (a.entity_type = 'ReferenceRange' AND a.entity_id IN (SELECT r.id::TEXT FROM public.reference_ranges r JOIN public.parameters p ON p.id = r.parameter_id WHERE p.test_id = p_test_id))
  ORDER BY a.timestamp DESC
  LIMIT 100;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_get_test_history TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_invalidate_test(
  p_test_id UUID,
  p_reason TEXT DEFAULT NULL,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;
  IF p_expected_version IS NOT NULL AND v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  UPDATE public.tests
  SET validation_status = 'REQUIRES_VALIDATION',
      clinical_configuration_status = 'Requires Clinical Validation',
      is_active = FALSE,
      lifecycle_status = 'Draft',
      billing_enabled = FALSE,
      clinical_reporting_enabled = FALSE,
      configuration_notes = COALESCE(NULLIF(btrim(p_reason), ''), configuration_notes),
      row_version = row_version + 1,
      updated_at = NOW()
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    'CATALOGUE_TEST_INVALIDATED',
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object('id', p_test_id, 'validation_status', 'REQUIRES_VALIDATION', 'is_active', FALSE);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_invalidate_test TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_master_acceptance_summary()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
DECLARE result JSONB;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Service-role acceptance authority required.' USING ERRCODE='42501';
  END IF;
  SELECT jsonb_build_object(
    'tests',count(*),
    'profiles',count(*) FILTER(WHERE test_kind='Profile'),
    'unique_codes',count(*)=count(DISTINCT upper(code)),
    'draft_operational',count(*) FILTER(WHERE lifecycle_status='Draft' AND (is_active OR billing_enabled OR clinical_reporting_enabled)),
    'reporting_without_structure',count(*) FILTER(WHERE clinical_reporting_enabled AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=tests.id AND p.is_active AND p.lifecycle_status='Active')),
    'specialist_generic_reporting',count(*) FILTER(WHERE reporting_model IN('MicrobiologyWorkflow','CytologyWorkflow','MolecularWorkflow','StructuredNested') AND workflow_supported AND clinical_reporting_enabled),
    'reporting_models',(SELECT jsonb_object_agg(reporting_model,n) FROM(SELECT reporting_model::TEXT,count(*) n FROM public.tests GROUP BY reporting_model)s),
    'departments',(SELECT jsonb_object_agg(department,n) FROM(SELECT department,count(*) n FROM public.tests GROUP BY department)s),
    'alias_checks',jsonb_build_object(
      'TLC',COALESCE((SELECT search_aliases @> ARRAY['wbc','tc'] FROM public.tests WHERE code='TLC'),FALSE),
      'PCV',COALESCE((SELECT search_aliases @> ARRAY['hct','hematocrit'] FROM public.tests WHERE code='PCV'),FALSE),
      'CK_MB',COALESCE((SELECT search_aliases @> ARRAY['ck-mb','cpk-mb'] FROM public.tests WHERE code='CK_MB'),FALSE),
      'KFT',COALESCE((SELECT search_aliases @> ARRAY['rft'] FROM public.tests WHERE code='KFT'),FALSE),
      'LIPID_PROFILE',COALESCE((SELECT search_aliases @> ARRAY['lipid'] FROM public.tests WHERE code='LIPID_PROFILE'),FALSE)
    ),
    'required_profiles',(SELECT jsonb_object_agg(code,present) FROM(SELECT x.code,EXISTS(SELECT 1 FROM public.tests t WHERE t.code=x.code AND t.test_kind='Profile')present FROM unnest(ARRAY['ABS_DLC','RBC_INDICES','PLATELET_INDICES','IRON_PROFILE','COAG_PROFILE','DENGUE_PANEL','HAV_PANEL'])x(code))s),
    'profile_components',(SELECT count(*) FROM public.catalogue_profile_components),
    'invalid_profile_components',(SELECT count(*) FROM public.catalogue_profile_components c LEFT JOIN public.tests p ON p.id=c.profile_test_id LEFT JOIN public.tests ct ON ct.id=c.component_test_id LEFT JOIN public.parameters cp ON cp.id=c.component_parameter_id WHERE p.id IS NULL OR (c.component_test_id IS NOT NULL AND ct.id IS NULL) OR (c.component_parameter_id IS NOT NULL AND cp.id IS NULL)),
    'duplicate_profile_order',(SELECT count(*) FROM(SELECT profile_test_id,display_order FROM public.catalogue_profile_components GROUP BY 1,2 HAVING count(*)>1)d)
  ) INTO result FROM public.tests;
  RETURN result;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_master_acceptance_summary TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_materialize_clinical_source_decision(
    p_decision_id UUID,
    p_expected_version BIGINT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_decision public.clinical_source_decisions%ROWTYPE; v_item public.clinical_source_items%ROWTYPE;
        v_parameter UUID; v_range UUID; v_policy JSONB;
BEGIN
    PERFORM public.catalogue_require_manager();
    SELECT * INTO v_decision FROM public.clinical_source_decisions WHERE id=p_decision_id FOR UPDATE;
    IF NOT FOUND OR v_decision.status<>'Approved' OR v_decision.action='RejectSource' THEN
        RAISE EXCEPTION 'Only an approved non-rejected decision may be materialized.' USING ERRCODE='23514';
    END IF;
    IF v_decision.row_version<>p_expected_version THEN RAISE EXCEPTION 'Clinical decision changed. Reload latest.' USING ERRCODE='PT409'; END IF;
    IF v_decision.materialized_range_id IS NOT NULL THEN RETURN v_decision.materialized_range_id; END IF;
    SELECT * INTO v_item FROM public.clinical_source_items WHERE id=v_decision.source_item_id;
    SELECT p.id INTO v_parameter FROM public.parameters p JOIN public.tests t ON t.id=p.test_id
     WHERE t.code=v_item.target_test_code AND p.code=v_item.target_parameter_code;
    IF v_parameter IS NULL THEN RAISE EXCEPTION 'The approved source decision has no unique existing target parameter.' USING ERRCODE='23514'; END IF;
    v_policy:=v_decision.selected_policy;
    IF NOT (v_policy ? 'normal_min' OR v_policy ? 'normal_max' OR NULLIF(btrim(v_policy->>'normal_text'),'') IS NOT NULL) THEN
        RAISE EXCEPTION 'Approved policy has no reportable interval/threshold/text.' USING ERRCODE='23514';
    END IF;
    INSERT INTO public.reference_ranges(
        parameter_id,gender,age_min_days,age_max_days,normal_min,normal_max,critical_low,critical_high,
        normal_text,reference_text,method,unit,is_active,is_approved,lifecycle_status,approved_by,approved_at,
        validation_state,validation_source,source_decision_id,supplied_value_snapshot,supplied_unit_snapshot,
        normalized_source_snapshot,policy_version)
    VALUES(
        v_parameter,v_policy->>'gender',(v_policy->>'age_min_days')::INT,(v_policy->>'age_max_days')::INT,
        NULLIF(v_policy->>'normal_min','')::NUMERIC,NULLIF(v_policy->>'normal_max','')::NUMERIC,
        NULLIF(v_policy->>'critical_low','')::NUMERIC,NULLIF(v_policy->>'critical_high','')::NUMERIC,
        NULLIF(btrim(v_policy->>'normal_text'),''),NULLIF(btrim(v_policy->>'reference_text'),''),
        NULLIF(btrim(v_policy->>'method'),''),v_policy->>'unit',FALSE,TRUE,'Draft',
        v_decision.approved_by,v_decision.approved_at,'ClinicallyValidated',
        'Bimal Pathology operator-authorized clinical dataset; source '||(SELECT source_version FROM public.clinical_source_imports WHERE id=v_item.import_id),
        p_decision_id,v_item.supplied_value,v_item.supplied_unit,v_item.normalized_representation,v_decision.decision_version)
    RETURNING id INTO v_range;
    UPDATE public.clinical_source_decisions SET materialized_range_id=v_range,row_version=row_version+1 WHERE id=p_decision_id;
    INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
    VALUES(auth.uid(),public.catalogue_actor_name(),'CLINICAL_SOURCE_RANGE_MATERIALIZED','ReferenceRange',v_range::TEXT,
           jsonb_build_object('decision_id',p_decision_id,'source_item_id',v_item.id,'lifecycle_status','Draft'));
    RETURN v_range;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_materialize_clinical_source_decision TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_panel_service_components(p_service_id UUID)
RETURNS TABLE(panel_service_id UUID,panel_id UUID,test_id UUID,test_code TEXT,test_name TEXT,display_order INT,readiness public.catalogue_result_readiness_enum)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_create_bill') OR public.has_permission('can_manage_catalogue')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY WITH owners AS (
  SELECT ps.id service_id,ps.panel_id,COALESCE(pc.component_test_id,owner.id) owner_id,min(pc.display_order) ord
  FROM public.catalogue_panel_services ps JOIN public.catalogue_panel_components pc ON pc.panel_id=ps.panel_id
  LEFT JOIN public.parameters prm ON prm.id=pc.component_parameter_id LEFT JOIN public.tests owner ON owner.id=prm.test_id
  WHERE ps.id=p_service_id GROUP BY ps.id,ps.panel_id,COALESCE(pc.component_test_id,owner.id)
 ) SELECT o.service_id,o.panel_id,t.id,t.code::TEXT,t.name::TEXT,o.ord,public.catalogue_test_result_readiness(t.id)
 FROM owners o JOIN public.tests t ON t.id=o.owner_id ORDER BY o.ord;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_panel_service_components TO authenticated, service_role;

CREATE FUNCTION public.catalogue_price_master() RETURNS TABLE(item JSONB) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_active_user() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY WITH entities AS (
  SELECT 'Test'::TEXT type,t.id,t.code::TEXT,t.name::TEXT,c.name::TEXT category,t.lifecycle_status::TEXT status FROM public.tests t LEFT JOIN public.test_categories c ON c.id=t.category_id
  UNION ALL SELECT 'Panel',ps.id,ps.code,ps.name,c.name,ps.lifecycle_status::TEXT FROM public.catalogue_panel_services ps LEFT JOIN public.test_categories c ON c.id=ps.category_id
  UNION ALL SELECT 'Package',p.id,p.code::TEXT,p.name::TEXT,'Packages',p.lifecycle_status::TEXT FROM public.health_packages p
 ), rates AS (SELECT r.*,row_number() OVER(PARTITION BY entity_type,test_id,panel_service_id,package_id,other_service_code ORDER BY version_number DESC) rn FROM public.catalogue_rate_versions r)
 SELECT jsonb_build_object('entity_type',e.type,'entity_id',e.id,'code',e.code,'name',e.name,'category',e.category,'entity_status',e.status,
  'rate_id',r.id,'version_number',r.version_number,'price_paisa',r.price_paisa,'effective_from',r.effective_from,'rate_status',r.status,'row_version',r.row_version)
 FROM entities e LEFT JOIN rates r ON r.rn=1 AND ((e.type='Test' AND r.test_id=e.id) OR(e.type='Panel' AND r.panel_service_id=e.id) OR(e.type='Package' AND r.package_id=e.id)) ORDER BY e.type,e.name;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_price_master TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_rate_history(p_entity_type public.catalogue_billable_entity_enum,p_entity_id UUID,p_other_service_code TEXT DEFAULT NULL)
RETURNS TABLE(item JSONB) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM public.catalogue_require_manager();
 RETURN QUERY SELECT jsonb_build_object('id',r.id,'version_number',r.version_number,'price_paisa',r.price_paisa,
  'effective_from',r.effective_from,'effective_to',r.effective_to,'status',r.status,'row_version',r.row_version,
  'used_by_bill_count',(SELECT count(*) FROM public.bill_panel_selections b WHERE b.rate_version_id=r.id))
 FROM public.catalogue_rate_versions r
 WHERE (p_entity_type='Test' AND r.test_id=p_entity_id) OR (p_entity_type='Panel' AND r.panel_service_id=p_entity_id)
  OR (p_entity_type='Package' AND r.package_id=p_entity_id) OR (p_entity_type='Other' AND r.other_service_code=upper(btrim(p_other_service_code)))
 ORDER BY r.version_number DESC;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_rate_history TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_readiness_actor_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT COALESCE(string_agg(DISTINCT r.name, ', ' ORDER BY r.name), 'Authenticated user')
  FROM public.user_profiles up
  LEFT JOIN public.user_roles ur ON ur.user_id=up.id
  LEFT JOIN public.roles r ON r.id=ur.role_id
  WHERE up.id=auth.uid() AND up.is_active;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_readiness_actor_role TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_readiness_inventory(p_state TEXT DEFAULT NULL,p_query TEXT DEFAULT NULL)
RETURNS SETOF JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE row RECORD; checklist JSONB; term TEXT:=lower(btrim(COALESCE(p_query,'')));
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 FOR row IN
   SELECT t.id,r.state,r.configuration_version,r.decision_reason
   FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id
   WHERE t.lifecycle_status<>'Archived'
     AND (p_state IS NULL OR p_state='' OR r.state::TEXT=p_state)
     AND (term='' OR lower(t.code) LIKE '%'||term||'%' OR lower(t.name) LIKE '%'||term||'%')
   ORDER BY t.is_active DESC,t.display_order,t.code,t.id LIMIT 500
 LOOP
   checklist:=public.catalogue_service_readiness_checklist(row.id);
   RETURN NEXT checklist||jsonb_build_object('service_kind','Test','approval_state',row.state,
     'configuration_version',row.configuration_version,'decision_reason',row.decision_reason);
 END LOOP;
 FOR row IN
   SELECT p.id,p.code,p.name,p.lifecycle_status,p.price_paisa,count(c.test_id) component_count
   FROM public.health_packages p LEFT JOIN public.health_package_components c ON c.package_id=p.id
   WHERE p.lifecycle_status<>'Archived' AND (term='' OR lower(p.code) LIKE '%'||term||'%' OR lower(p.name) LIKE '%'||term||'%')
   GROUP BY p.id,p.code,p.name,p.lifecycle_status,p.price_paisa ORDER BY p.code LIMIT 500
 LOOP
   RETURN NEXT jsonb_build_object('service_kind','Package','test_id',row.id,'code',row.code,'name',row.name,
     'classification','CommercialPackage','approval_state',CASE WHEN row.lifecycle_status='Active' THEN 'Approved' ELSE 'Draft' END,
     'clinical_reporting_enabled',FALSE,'parameter_count',row.component_count,
     'missing_requirements',CASE WHEN row.component_count=0 THEN jsonb_build_array('Package requires components') ELSE '[]'::JSONB END);
 END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_readiness_inventory TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_record_clinical_source_decision(
    p_source_item_id UUID,
    p_action TEXT,
    p_selected_policy JSONB,
    p_reason TEXT,
    p_expected_item_version BIGINT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_item public.clinical_source_items%ROWTYPE; v_id UUID; v_version INTEGER;
BEGIN
    PERFORM public.catalogue_require_manager();
    IF p_action NOT IN ('AcceptSource','RetainOlderPolicy','CorrectLaboratoryPolicy','RestrictApplicability','RejectSource') THEN
        RAISE EXCEPTION 'Unsupported clinical source decision.' USING ERRCODE='23514';
    END IF;
    IF length(btrim(COALESCE(p_reason,''))) < 5 THEN
        RAISE EXCEPTION 'A technical decision reason is required.' USING ERRCODE='23514';
    END IF;
    SELECT * INTO v_item FROM public.clinical_source_items WHERE id=p_source_item_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Clinical source item not found.' USING ERRCODE='P0002'; END IF;
    IF v_item.row_version <> p_expected_item_version THEN
        RAISE EXCEPTION 'Clinical source item changed. Reload latest.' USING ERRCODE='PT409';
    END IF;
    SELECT COALESCE(max(decision_version),0)+1 INTO v_version
      FROM public.clinical_source_decisions WHERE source_item_id=p_source_item_id;
    INSERT INTO public.clinical_source_decisions(source_item_id,decision_version,action,selected_policy,reason,reviewer_id)
    VALUES(p_source_item_id,v_version,p_action,COALESCE(p_selected_policy,'{}'::JSONB),btrim(p_reason),auth.uid())
    RETURNING id INTO v_id;
    UPDATE public.clinical_source_items
       SET review_state=CASE WHEN p_action='RejectSource' THEN 'DecisionRecorded' ELSE 'DecisionRecorded' END,
           row_version=row_version+1
     WHERE id=p_source_item_id;
    INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
    VALUES(auth.uid(),public.catalogue_actor_name(),'CLINICAL_SOURCE_DECISION_RECORDED','ClinicalSourceItem',p_source_item_id::TEXT,
           jsonb_build_object('decision_id',v_id,'decision_version',v_version,'action',p_action,'reason',btrim(p_reason)));
    RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_record_clinical_source_decision TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_record_configuration_review(
 p_test_id UUID,p_category TEXT,p_reason TEXT,p_source_metadata JSONB,p_expected_version BIGINT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_service_readiness%ROWTYPE; next_version BIGINT; previous JSONB;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 IF p_category NOT IN ('Identity','Specimen','ParameterStructure','ReferenceRanges','Calculations','CriticalLimits','MethodAnalyzer','SourceConflicts','Pricing','Workflow')
   THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_CATEGORY_INVALID' USING ERRCODE='22023'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'A review reason is required.' USING ERRCODE='23514'; END IF;
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'CATALOGUE_SERVICE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF r.configuration_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 SELECT new_state INTO previous FROM public.catalogue_configuration_evidence WHERE test_id=p_test_id AND category=p_category ORDER BY configuration_version DESC,created_at DESC LIMIT 1;
 next_version:=r.configuration_version+1;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,previous_state,new_state,source_metadata,reason,actor_id,actor_role)
 VALUES(p_test_id,next_version,p_category,'Reviewed',previous,jsonb_build_object('reviewed',TRUE),COALESCE(p_source_metadata,'{}'),btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role());
 UPDATE public.catalogue_service_readiness SET state='NeedsConfiguration',configuration_version=next_version,
   submitted_by=NULL,submitted_at=NULL,approved_by=NULL,approved_at=NULL,decision_reason=btrim(p_reason),updated_at=now()
 WHERE test_id=p_test_id;
 RETURN next_version;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_record_configuration_review TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_remove_panel_component(p_panel_id UUID,p_display_order INT,p_expected_panel_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; old_components JSONB;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Panel not found.' USING ERRCODE='P0002'; END IF;
  IF p.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF EXISTS(SELECT 1 FROM public.bill_panel_selections WHERE panel_id=p_panel_id) THEN RAISE EXCEPTION 'Historically billed panel composition cannot be changed; archive it and create a new definition.' USING ERRCODE='23503'; END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.display_order),'[]') INTO old_components FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id;
  DELETE FROM public.catalogue_panel_components WHERE panel_id=p_panel_id AND display_order=p_display_order;
  UPDATE public.catalogue_panels SET row_version=row_version+1,updated_at=now() WHERE id=p_panel_id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PANEL_MEMBER_REMOVED','Panel',p_panel_id::TEXT,old_components,(SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.display_order),'[]') FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id));
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_remove_panel_component TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_reorder_panel_components(p_panel_id UUID,p_component_ids UUID[],p_expected_panel_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; old_components JSONB;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Panel not found.' USING ERRCODE='P0002'; END IF;
  IF p.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF cardinality(p_component_ids)<>(SELECT count(*) FROM public.catalogue_panel_components WHERE panel_id=p_panel_id)
    OR EXISTS(SELECT 1 FROM unnest(p_component_ids) id LEFT JOIN public.catalogue_panel_components c ON c.panel_id=p_panel_id AND COALESCE(c.component_test_id,c.component_parameter_id)=id WHERE c.panel_id IS NULL)
  THEN RAISE EXCEPTION 'Complete canonical component order is required.' USING ERRCODE='23514'; END IF;
  SELECT jsonb_agg(to_jsonb(c) ORDER BY c.display_order) INTO old_components FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id;
  UPDATE public.catalogue_panel_components SET display_order=display_order+10000 WHERE panel_id=p_panel_id;
  UPDATE public.catalogue_panel_components c SET display_order=x.ord FROM unnest(p_component_ids) WITH ORDINALITY x(id,ord) WHERE c.panel_id=p_panel_id AND COALESCE(c.component_test_id,c.component_parameter_id)=x.id;
  UPDATE public.catalogue_panels SET row_version=row_version+1,updated_at=now() WHERE id=p_panel_id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PANEL_REORDERED','Panel',p_panel_id::TEXT,old_components,(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.display_order) FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id));
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_reorder_panel_components TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_reorder_parameters_easy(
  p_test_id UUID,
  p_parameter_ids UUID[]
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  i INT;
  param_id UUID;
BEGIN
  PERFORM public.catalogue_require_manager();

  FOR i IN 1..cardinality(p_parameter_ids) LOOP
    param_id := p_parameter_ids[i];
    UPDATE public.parameters
    SET display_order = i, updated_at = NOW()
    WHERE id = param_id AND test_id = p_test_id;
  END LOOP;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, new_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_PARAMETERS_REORDERED', 'Test', p_test_id::TEXT,
    jsonb_build_object('ordered_ids', p_parameter_ids)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_reorder_parameters_easy TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_replace_ranges(p_parameter_ids UUID[],p_ranges JSONB) RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE item JSONB; inserted_count INT:=0; parameter_uuid UUID; min_age INT; max_age INT;
BEGIN PERFORM public.catalogue_require_manager(); PERFORM 1 FROM public.parameters WHERE id=ANY(p_parameter_ids) FOR UPDATE;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_ranges,'[]'))x WHERE NOT ((x->>'parameter_id')::UUID=ANY(p_parameter_ids))) THEN RAISE EXCEPTION 'Range payload contains an unexpected parameter.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_ranges,'[]'))x WHERE COALESCE((x->>'is_approved')::BOOLEAN,FALSE) AND COALESCE(x->>'validation_state','Unclassified')<>'ClinicallyValidated') THEN RAISE EXCEPTION 'Approval requires an explicit ClinicallyValidated provenance state.' USING ERRCODE='23514'; END IF;
 UPDATE public.reference_ranges SET lifecycle_status='Archived',is_active=FALSE,archived_at=NOW(),archived_by=auth.uid(),row_version=row_version+1,updated_at=NOW() WHERE parameter_id=ANY(p_parameter_ids) AND lifecycle_status<>'Archived';
 FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(p_ranges,'[]')) LOOP parameter_uuid:=(item->>'parameter_id')::UUID;min_age:=COALESCE((item->>'age_min_days')::INT,0);max_age:=COALESCE((item->>'age_max_days')::INT,43800);IF min_age>max_age THEN RAISE EXCEPTION 'Minimum age cannot exceed maximum age.' USING ERRCODE='23514';END IF;
  IF EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id=parameter_uuid AND r.lifecycle_status='Active' AND r.gender=COALESCE(item->>'gender','All') AND int4range(r.age_min_days,r.age_max_days,'[]')&&int4range(min_age,max_age,'[]') AND COALESCE(r.method,'')=COALESCE(item->>'method','')) THEN RAISE EXCEPTION 'Overlapping active reference ranges.' USING ERRCODE='23505';END IF;
  INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_min,normal_max,critical_low,critical_high,normal_text,reference_text,method,unit,is_active,is_approved,lifecycle_status,approved_by,approved_at,validation_state,validation_source) VALUES(parameter_uuid,COALESCE(item->>'gender','All'),min_age,max_age,(item->>'normal_min')::NUMERIC,(item->>'normal_max')::NUMERIC,(item->>'critical_low')::NUMERIC,(item->>'critical_high')::NUMERIC,NULLIF(btrim(item->>'normal_text'),''),NULLIF(btrim(item->>'reference_text'),''),NULLIF(btrim(item->>'method'),''),NULLIF(btrim(item->>'unit'),''),TRUE,COALESCE((item->>'is_approved')::BOOLEAN,FALSE),'Active',CASE WHEN COALESCE((item->>'is_approved')::BOOLEAN,FALSE) THEN auth.uid() END,CASE WHEN COALESCE((item->>'is_approved')::BOOLEAN,FALSE) THEN NOW() END,COALESCE((item->>'validation_state')::public.reference_range_validation_state_enum,'Unclassified'),NULLIF(btrim(item->>'validation_source'),''));inserted_count:=inserted_count+1;
 END LOOP; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_RANGES_REPLACED','ParameterSet',array_to_string(p_parameter_ids,','),jsonb_build_object('count',inserted_count));RETURN inserted_count;END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_replace_ranges TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_require_manager() RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT (
    public.has_permission('can_manage_catalogue') OR public.is_super_admin()
  ) THEN
    RAISE EXCEPTION 'Catalogue management requires administrative authorization.' USING ERRCODE='42501';
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_require_manager TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_require_readiness_staff()
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_permission('can_configure_catalogue_technical') OR public.has_permission('can_manage_catalogue')) THEN
    RAISE EXCEPTION 'CATALOGUE_READINESS_ACCESS_DENIED' USING ERRCODE='42501';
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_require_readiness_staff TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_require_technical() RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT (
    public.has_permission('can_configure_catalogue_technical') OR public.is_super_admin()
  ) THEN
    RAISE EXCEPTION 'Catalogue technical configuration requires administrative authorization.' USING ERRCODE='42501';
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_require_technical TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_revert_to_proposed(
  p_test_id UUID,
  p_reason TEXT DEFAULT NULL,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  actor_id UUID;
  actor_name TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  SELECT * INTO v FROM public.tests WHERE id = p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;

  IF p_expected_version IS NOT NULL AND v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  -- Mark active approvals as superseded/revoked
  UPDATE public.catalogue_lab_approvals
  SET approval_status = 'REVOKED'
  WHERE test_id = p_test_id AND approval_status = 'APPROVED';

  UPDATE public.tests
  SET validation_status = 'REQUIRES_VALIDATION',
    clinical_configuration_status = 'Requires Clinical Validation',
    is_active = FALSE,
    lifecycle_status = 'Draft',
    billing_enabled = FALSE,
    clinical_reporting_enabled = FALSE,
    configuration_notes = COALESCE(NULLIF(btrim(p_reason), ''), configuration_notes),
    row_version = row_version + 1,
    updated_at = NOW()
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id,
    actor_name,
    'CATALOGUE_TEST_REVERTED_TO_PROPOSED',
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object('id', p_test_id, 'validation_status', 'REQUIRES_VALIDATION');
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_revert_to_proposed TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_analyzer(p_analyzer JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE a public.analyzers%ROWTYPE; result_id UUID; old_row JSONB;
BEGIN
  PERFORM public.catalogue_require_manager();
  IF btrim(COALESCE(p_analyzer->>'code',''))='' OR btrim(COALESCE(p_analyzer->>'name',''))='' THEN RAISE EXCEPTION 'Analyzer code and name are required.' USING ERRCODE='22023'; END IF;
  IF NULLIF(p_analyzer->>'id','') IS NOT NULL THEN
    SELECT * INTO a FROM public.analyzers WHERE id=(p_analyzer->>'id')::UUID FOR UPDATE;
    IF NOT FOUND OR a.row_version<>p_expected_version THEN RAISE EXCEPTION 'Analyzer changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; old_row:=to_jsonb(a);result_id:=a.id;
    UPDATE public.analyzers SET code=upper(btrim(p_analyzer->>'code')),name=btrim(p_analyzer->>'name'),manufacturer=NULLIF(btrim(p_analyzer->>'manufacturer'),''),model=NULLIF(btrim(p_analyzer->>'model'),''),serial_number=NULLIF(btrim(p_analyzer->>'serial_number'),''),laboratory_location=NULLIF(btrim(p_analyzer->>'laboratory_location'),''),lifecycle_status=COALESCE((p_analyzer->>'lifecycle_status')::public.analyzer_lifecycle_enum,lifecycle_status),row_version=row_version+1,updated_at=NOW() WHERE id=result_id;
  ELSE INSERT INTO public.analyzers(code,name,manufacturer,model,serial_number,laboratory_location) VALUES(upper(btrim(p_analyzer->>'code')),btrim(p_analyzer->>'name'),NULLIF(btrim(p_analyzer->>'manufacturer'),''),NULLIF(btrim(p_analyzer->>'model'),''),NULLIF(btrim(p_analyzer->>'serial_number'),''),NULLIF(btrim(p_analyzer->>'laboratory_location'),'')) RETURNING id INTO result_id; END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'ANALYZER_SAVED','Analyzer',result_id::TEXT,old_row,(SELECT to_jsonb(x) FROM public.analyzers x WHERE x.id=result_id)); RETURN result_id;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_analyzer TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_analyzer_mapping_easy(
  p_mapping JSONB
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_id UUID := NULLIF(p_mapping->>'id', '')::UUID;
  v_analyzer_id UUID := (p_mapping->>'analyzer_id')::UUID;
  v_channel_code VARCHAR(50) := upper(btrim(p_mapping->>'channel_code'));
  v_channel_name VARCHAR(255) := btrim(p_mapping->>'channel_name');
  v_test_id UUID := NULLIF(p_mapping->>'test_id', '')::UUID;
  v_param_id UUID := NULLIF(p_mapping->>'parameter_id', '')::UUID;
  v_measurement_type VARCHAR(50) := COALESCE(NULLIF(p_mapping->>'measurement_type', ''), 'DIRECT_MEASURED');
  v_method VARCHAR(255) := COALESCE(NULLIF(btrim(p_mapping->>'analytical_method'), ''), 'Automated');
  v_unit VARCHAR(50) := NULLIF(btrim(p_mapping->>'unit'), '');
  v_differential_type VARCHAR(50) := COALESCE(NULLIF(p_mapping->>'differential_type', ''), 'Not Applicable');
  v_result_id UUID;
BEGIN
  PERFORM public.catalogue_require_manager();

  IF v_analyzer_id IS NULL OR v_channel_code IS NULL OR v_channel_name IS NULL THEN
    RAISE EXCEPTION 'Analyzer, Channel Code, and Channel Name are required.' USING ERRCODE='22023';
  END IF;

  IF v_id IS NOT NULL THEN
    UPDATE public.analyzer_parameter_mappings
    SET analyzer_id = v_analyzer_id,
        channel_code = v_channel_code,
        channel_name = v_channel_name,
        test_id = v_test_id,
        parameter_id = v_param_id,
        measurement_type = v_measurement_type,
        analytical_method = v_method,
        unit = v_unit,
        differential_type = v_differential_type,
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = v_id
    RETURNING id INTO v_result_id;
  ELSE
    INSERT INTO public.analyzer_parameter_mappings (
      analyzer_id, channel_code, channel_name, test_id, parameter_id,
      measurement_type, analytical_method, unit, differential_type, row_version
    ) VALUES (
      v_analyzer_id, v_channel_code, v_channel_name, v_test_id, v_param_id,
      v_measurement_type, v_method, v_unit, v_differential_type, 1
    )
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
      channel_name = EXCLUDED.channel_name,
      test_id = EXCLUDED.test_id,
      parameter_id = EXCLUDED.parameter_id,
      measurement_type = EXCLUDED.measurement_type,
      analytical_method = EXCLUDED.analytical_method,
      unit = EXCLUDED.unit,
      differential_type = EXCLUDED.differential_type,
      row_version = public.analyzer_parameter_mappings.row_version + 1,
      updated_at = NOW()
    RETURNING id INTO v_result_id;
  END IF;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, new_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'ANALYZER_MAPPING_SAVED', 'AnalyzerMapping', v_result_id::TEXT, p_mapping
  );

  RETURN v_result_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_analyzer_mapping_easy TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_category(p_category JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result_id UUID; v public.test_categories%ROWTYPE; old_row JSONB; BEGIN PERFORM public.catalogue_require_manager();
 IF p_category ? 'id' AND NULLIF(p_category->>'id','') IS NOT NULL THEN SELECT * INTO v FROM public.test_categories WHERE id=(p_category->>'id')::UUID FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Category no longer exists.' USING ERRCODE='P0002'; END IF; IF p_expected_version IS NULL OR v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Category changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; old_row:=to_jsonb(v); UPDATE public.test_categories SET code=upper(btrim(p_category->>'code')),name=btrim(p_category->>'name'),description=NULLIF(btrim(p_category->>'description'),''),display_order=COALESCE((p_category->>'display_order')::INT,0),row_version=row_version+1,updated_at=NOW() WHERE id=v.id RETURNING id INTO result_id;
 ELSE INSERT INTO public.test_categories(code,name,description,display_order,lifecycle_status) VALUES(upper(btrim(p_category->>'code')),btrim(p_category->>'name'),NULLIF(btrim(p_category->>'description'),''),COALESCE((p_category->>'display_order')::INT,0),'Draft') RETURNING id INTO result_id; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_CATEGORY_SAVED','TestCategory',result_id::TEXT,old_row,(SELECT to_jsonb(c) FROM public.test_categories c WHERE c.id=result_id)); RETURN result_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_category TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_option_set(p_payload JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID:=NULLIF(p_payload->>'id','')::UUID; v_old JSONB; BEGIN PERFORM public.catalogue_require_technical();
 IF v_id IS NULL THEN INSERT INTO public.catalogue_option_sets(code,name) VALUES(upper(btrim(p_payload->>'code')),btrim(p_payload->>'name')) RETURNING id INTO v_id;
 ELSE SELECT to_jsonb(s) INTO v_old FROM public.catalogue_option_sets s WHERE id=v_id FOR UPDATE; IF (v_old->>'row_version')::BIGINT<>p_expected_version THEN RAISE EXCEPTION 'Option set changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.catalogue_option_sets SET code=upper(btrim(p_payload->>'code')),name=btrim(p_payload->>'name'),row_version=row_version+1,updated_at=now() WHERE id=v_id; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_OPTION_SET_SAVED','CatalogueOptionSet',v_id::TEXT,v_old,(SELECT to_jsonb(s) FROM public.catalogue_option_sets s WHERE s.id=v_id)); RETURN v_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_option_set TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_option_value(p_payload JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID:=NULLIF(p_payload->>'id','')::UUID; v_old JSONB; BEGIN PERFORM public.catalogue_require_technical();
 IF v_id IS NULL THEN INSERT INTO public.catalogue_option_values(option_set_id,value_code,label,display_order) VALUES((p_payload->>'option_set_id')::UUID,upper(btrim(p_payload->>'value_code')),btrim(p_payload->>'label'),(p_payload->>'display_order')::INT) RETURNING id INTO v_id;
 ELSE SELECT to_jsonb(v) INTO v_old FROM public.catalogue_option_values v WHERE id=v_id FOR UPDATE; IF (v_old->>'row_version')::BIGINT<>p_expected_version THEN RAISE EXCEPTION 'Option changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.catalogue_option_values SET value_code=upper(btrim(p_payload->>'value_code')),label=btrim(p_payload->>'label'),display_order=(p_payload->>'display_order')::INT,is_active=COALESCE((p_payload->>'is_active')::BOOLEAN,is_active),row_version=row_version+1,updated_at=now() WHERE id=v_id; END IF; RETURN v_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_option_value TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_package(
    p_package JSONB,
    p_components UUID[],
    p_expected_version BIGINT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_existing public.health_packages%ROWTYPE;
    v_old JSONB;
    v_result_id UUID;
    v_component UUID;
    v_position INT := 0;
    v_components UUID[] := COALESCE(p_components, ARRAY[]::UUID[]);
    v_pricing_policy public.catalogue_pricing_policy_enum;
    v_search_aliases TEXT[];
    v_price_paisa BIGINT;
    v_code TEXT;
    v_name TEXT;
BEGIN
    PERFORM public.catalogue_require_manager();

    IF COALESCE(jsonb_typeof(p_package), 'null') <> 'object' THEN
        RAISE EXCEPTION 'Package configuration must be a JSON object.' USING ERRCODE = '22023';
    END IF;
    IF p_package ? 'search_aliases'
       AND jsonb_typeof(p_package->'search_aliases') <> 'array' THEN
        RAISE EXCEPTION 'Package search aliases must be an array.' USING ERRCODE = '22023';
    END IF;

    v_code := upper(btrim(COALESCE(p_package->>'code', '')));
    v_name := btrim(COALESCE(p_package->>'name', ''));
    v_price_paisa := COALESCE(NULLIF(p_package->>'price_paisa', '')::BIGINT, 0);
    v_pricing_policy := COALESCE(
        NULLIF(p_package->>'pricing_policy', '')::public.catalogue_pricing_policy_enum,
        'Fixed'::public.catalogue_pricing_policy_enum
    );

    IF v_code = '' OR v_name = '' THEN
        RAISE EXCEPTION 'Package code and name are required.' USING ERRCODE = '22023';
    END IF;
    IF v_price_paisa < 0 THEN
        RAISE EXCEPTION 'Package price cannot be negative.' USING ERRCODE = '23514';
    END IF;
    IF cardinality(v_components) <> (
        SELECT count(DISTINCT component_id)::INT
        FROM unnest(v_components) AS component_id
    ) THEN
        RAISE EXCEPTION 'Package components must be unique.' USING ERRCODE = '23505';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM unnest(v_components) AS requested(test_id)
        LEFT JOIN public.tests t ON t.id = requested.test_id
        WHERE t.id IS NULL OR t.lifecycle_status <> 'Active' OR NOT t.is_active
    ) THEN
        RAISE EXCEPTION 'Packages may contain only active canonical tests/profiles.' USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(array_agg(alias_value ORDER BY alias_value), ARRAY[]::TEXT[])
    INTO v_search_aliases
    FROM (
        SELECT DISTINCT lower(btrim(alias_text)) AS alias_value
        FROM jsonb_array_elements_text(
            CASE
                WHEN jsonb_typeof(p_package->'search_aliases') = 'array'
                    THEN p_package->'search_aliases'
                ELSE '[]'::JSONB
            END
        ) AS aliases(alias_text)
        WHERE btrim(alias_text) <> ''
    ) normalized_aliases;

    IF NULLIF(p_package->>'id', '') IS NOT NULL THEN
        SELECT * INTO v_existing
        FROM public.health_packages
        WHERE id = (p_package->>'id')::UUID
        FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Package no longer exists.' USING ERRCODE = 'P0002';
        END IF;
        IF p_expected_version IS NULL OR v_existing.row_version <> p_expected_version THEN
            RAISE EXCEPTION 'Package changed. Refresh and try again.' USING ERRCODE = 'PT409';
        END IF;

        v_old := to_jsonb(v_existing);
        UPDATE public.health_packages
        SET code = v_code,
            name = v_name,
            description = NULLIF(btrim(p_package->>'description'), ''),
            price_paisa = v_price_paisa,
            pricing_policy = v_pricing_policy,
            search_aliases = v_search_aliases,
            row_version = row_version + 1,
            updated_at = NOW()
        WHERE id = v_existing.id
        RETURNING id INTO v_result_id;

        DELETE FROM public.health_package_components
        WHERE package_id = v_result_id;
    ELSE
        INSERT INTO public.health_packages(
            code, name, description, price_paisa, pricing_policy,
            search_aliases, lifecycle_status
        ) VALUES (
            v_code, v_name, NULLIF(btrim(p_package->>'description'), ''),
            v_price_paisa, v_pricing_policy, v_search_aliases, 'Draft'
        )
        RETURNING id INTO v_result_id;
    END IF;

    FOREACH v_component IN ARRAY v_components LOOP
        v_position := v_position + 1;
        INSERT INTO public.health_package_components(package_id, test_id, display_order)
        VALUES (v_result_id, v_component, v_position);
    END LOOP;

    INSERT INTO public.audit_logs(
        user_id, user_name, action, entity_type, entity_id, old_data, new_data
    ) VALUES (
        auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_PACKAGE_SAVED',
        'HealthPackage', v_result_id::TEXT, v_old,
        jsonb_build_object(
            'package', (SELECT to_jsonb(p) FROM public.health_packages p WHERE p.id = v_result_id),
            'components', to_jsonb(v_components)
        )
    );

    RETURN v_result_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_package TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_panel(p_payload JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID:=NULLIF(p_payload->>'id','')::UUID; p public.catalogue_panels%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager();
 IF v_id IS NULL THEN INSERT INTO public.catalogue_panels(code,name,category_id,reporting_type,workflow_supported,clinical_reporting_enabled,lifecycle_status,display_order) VALUES(upper(btrim(p_payload->>'code')),btrim(p_payload->>'name'),(p_payload->>'category_id')::UUID,COALESCE((p_payload->>'reporting_type')::public.reporting_type_enum,'InHouse'),COALESCE((p_payload->>'workflow_supported')::BOOLEAN,TRUE),FALSE,'Draft',COALESCE((p_payload->>'display_order')::INT,0)) RETURNING id INTO v_id;
 ELSE SELECT * INTO p FROM public.catalogue_panels WHERE id=v_id FOR UPDATE; IF p.row_version<>p_expected_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.catalogue_panels SET name=btrim(p_payload->>'name'),category_id=(p_payload->>'category_id')::UUID,display_order=COALESCE((p_payload->>'display_order')::INT,display_order),row_version=row_version+1,updated_at=now() WHERE id=v_id; END IF; RETURN v_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_panel TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_panel_component(p_panel_id UUID,p_component_test_id UUID,p_component_parameter_id UUID,p_display_name TEXT,p_display_order INT,p_expected_panel_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; old_components JSONB;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Panel not found.' USING ERRCODE='P0002'; END IF;
  IF p.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF (p_component_test_id IS NOT NULL)::INT+(p_component_parameter_id IS NOT NULL)::INT<>1 THEN RAISE EXCEPTION 'Exactly one canonical component identity is required.' USING ERRCODE='23514'; END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.display_order),'[]') INTO old_components FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id;
  INSERT INTO public.catalogue_panel_components(panel_id,component_test_id,component_parameter_id,display_name,display_order)
  VALUES(p_panel_id,p_component_test_id,p_component_parameter_id,btrim(p_display_name),p_display_order)
  ON CONFLICT(panel_id,display_order) DO UPDATE SET component_test_id=EXCLUDED.component_test_id,component_parameter_id=EXCLUDED.component_parameter_id,display_name=EXCLUDED.display_name;
  UPDATE public.catalogue_panels SET row_version=row_version+1,updated_at=now() WHERE id=p_panel_id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PANEL_MEMBERSHIP_CHANGED','Panel',p_panel_id::TEXT,old_components,(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.display_order) FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id));
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_panel_component TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_parameter(p_parameter JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.parameters%ROWTYPE; result_id UUID; old_row JSONB; vt public.parameter_value_type_enum;
BEGIN
 PERFORM public.catalogue_require_manager(); vt:=(p_parameter->>'value_type')::public.parameter_value_type_enum;
 IF vt='Calculated' AND (NULLIF(btrim(p_parameter->>'calculation_identifier'),'') IS NULL OR NULLIF(btrim(p_parameter->>'formula'),'') IS NULL) THEN RAISE EXCEPTION 'Calculated parameters require an approved calculation identifier and formula.' USING ERRCODE='23514'; END IF;
 IF p_parameter ? 'id' AND NULLIF(p_parameter->>'id','') IS NOT NULL THEN
  SELECT * INTO v FROM public.parameters WHERE id=(p_parameter->>'id')::UUID FOR UPDATE; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Parameter changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; old_row:=to_jsonb(v);
  UPDATE public.parameters SET code=upper(btrim(p_parameter->>'code')),name=btrim(p_parameter->>'name'),value_type=vt,unit=NULLIF(btrim(p_parameter->>'unit'),''),options=p_parameter->'options',formula=NULLIF(btrim(p_parameter->>'formula'),''),formula_dependencies=ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_parameter->'formula_dependencies','[]'))),calculation_identifier=NULLIF(btrim(p_parameter->>'calculation_identifier'),''),decimal_precision=(p_parameter->>'decimal_precision')::SMALLINT,interpretation_config=p_parameter->'interpretation_config',display_order=COALESCE((p_parameter->>'display_order')::INT,0),is_mandatory=COALESCE((p_parameter->>'is_mandatory')::BOOLEAN,TRUE),row_version=row_version+1,updated_at=NOW() WHERE id=v.id RETURNING id INTO result_id;
 ELSE
  INSERT INTO public.parameters(test_id,code,name,value_type,unit,options,formula,formula_dependencies,calculation_identifier,decimal_precision,interpretation_config,display_order,is_mandatory,is_active,lifecycle_status)
  VALUES((p_parameter->>'test_id')::UUID,upper(btrim(p_parameter->>'code')),btrim(p_parameter->>'name'),vt,NULLIF(btrim(p_parameter->>'unit'),''),p_parameter->'options',NULLIF(btrim(p_parameter->>'formula'),''),ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_parameter->'formula_dependencies','[]'))),NULLIF(btrim(p_parameter->>'calculation_identifier'),''),(p_parameter->>'decimal_precision')::SMALLINT,p_parameter->'interpretation_config',COALESCE((p_parameter->>'display_order')::INT,0),COALESCE((p_parameter->>'is_mandatory')::BOOLEAN,TRUE),FALSE,'Draft') RETURNING id INTO result_id;
 END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),CASE WHEN old_row IS NULL THEN 'CATALOGUE_PARAMETER_CREATED' ELSE 'CATALOGUE_PARAMETER_UPDATED' END,'Parameter',result_id::TEXT,old_row,(SELECT to_jsonb(x) FROM public.parameters x WHERE x.id=result_id)); RETURN result_id;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_parameter TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_parameter_easy(
  p_parameter JSONB,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_id UUID := NULLIF(p_parameter->>'id', '')::UUID;
  v_test_id UUID := (p_parameter->>'test_id')::UUID;
  v_code TEXT := upper(btrim(p_parameter->>'code'));
  v_name TEXT := btrim(p_parameter->>'name');
  v_value_type TEXT := COALESCE(NULLIF(btrim(p_parameter->>'value_type'), ''), 'Text');
  v_unit TEXT := NULLIF(btrim(p_parameter->>'unit'), '');
  v_options JSONB := p_parameter->'options';
  v_formula TEXT := NULLIF(btrim(p_parameter->>'formula'), '');
  v_calc_id TEXT := NULLIF(btrim(p_parameter->>'calculation_identifier'), '');
  v_precision SMALLINT := COALESCE((p_parameter->>'decimal_precision')::SMALLINT, 2);
  v_display_order INT := COALESCE((p_parameter->>'display_order')::INT, 0);
  v_is_mandatory BOOLEAN := COALESCE((p_parameter->>'is_mandatory')::BOOLEAN, TRUE);
  v_is_active BOOLEAN := COALESCE((p_parameter->>'is_active')::BOOLEAN, TRUE);
  v_interp JSONB := p_parameter->'interpretation_config';
  v_existing public.parameters%ROWTYPE;
  v_result_id UUID;
  v_old_data JSONB;
BEGIN
  PERFORM public.catalogue_require_manager();

  IF v_code IS NULL OR v_code = '' THEN
    RAISE EXCEPTION 'Parameter code is required.' USING ERRCODE='22023';
  END IF;
  IF v_name IS NULL OR v_name = '' THEN
    RAISE EXCEPTION 'Parameter name is required.' USING ERRCODE='22023';
  END IF;

  IF v_value_type = 'Calculated' AND (v_formula IS NULL OR v_calc_id IS NULL) THEN
    RAISE EXCEPTION 'Calculated parameters require a calculation identifier and formula.' USING ERRCODE='23514';
  END IF;

  IF v_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.parameters WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Parameter was not found.' USING ERRCODE='P0002';
    END IF;
    IF p_expected_version IS NOT NULL AND v_existing.row_version <> p_expected_version THEN
      RAISE EXCEPTION 'This parameter was updated by another user. Reload before saving.' USING ERRCODE='PT409';
    END IF;

    v_old_data := to_jsonb(v_existing);

    UPDATE public.parameters
    SET code = v_code,
        name = v_name,
        value_type = v_value_type,
        unit = v_unit,
        options = v_options,
        formula = v_formula,
        calculation_identifier = v_calc_id,
        decimal_precision = v_precision,
        display_order = v_display_order,
        is_mandatory = v_is_mandatory,
        is_active = v_is_active,
        lifecycle_status = CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
        interpretation_config = v_interp,
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = v_id
    RETURNING id INTO v_result_id;
  ELSE
    INSERT INTO public.parameters (
      test_id, code, name, value_type, unit, options, formula,
      calculation_identifier, decimal_precision, display_order,
      is_mandatory, is_active, lifecycle_status, clinical_configuration_status,
      interpretation_config, row_version
    ) VALUES (
      v_test_id, v_code, v_name, v_value_type, v_unit, v_options, v_formula,
      v_calc_id, v_precision, v_display_order,
      v_is_mandatory, v_is_active,
      CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
      'Configured', v_interp, 1
    ) RETURNING id INTO v_result_id;
  END IF;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data, new_data
  ) VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    CASE WHEN v_old_data IS NULL THEN 'CATALOGUE_PARAMETER_CREATED' ELSE 'CATALOGUE_PARAMETER_UPDATED' END,
    'Parameter',
    v_result_id::TEXT,
    v_old_data,
    (SELECT to_jsonb(x) FROM public.parameters x WHERE x.id = v_result_id)
  );

  RETURN v_result_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_parameter_easy TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_range(p_range JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.reference_ranges%ROWTYPE; result_id UUID; old_row JSONB; min_age INT:=COALESCE((p_range->>'age_min_days')::INT,0); max_age INT:=COALESCE((p_range->>'age_max_days')::INT,43800);
BEGIN PERFORM public.catalogue_require_manager(); IF min_age>max_age THEN RAISE EXCEPTION 'Minimum age cannot exceed maximum age.' USING ERRCODE='23514'; END IF;
 IF COALESCE((p_range->>'is_approved')::BOOLEAN,FALSE) AND COALESCE(p_range->>'validation_state','Unclassified')<>'ClinicallyValidated' THEN RAISE EXCEPTION 'Approval requires an explicit ClinicallyValidated provenance state.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id=(p_range->>'parameter_id')::UUID AND r.id<>COALESCE((p_range->>'id')::UUID,'00000000-0000-0000-0000-000000000000'::UUID) AND r.lifecycle_status='Active' AND r.is_active AND r.gender=COALESCE(p_range->>'gender','All') AND int4range(r.age_min_days,r.age_max_days,'[]') && int4range(min_age,max_age,'[]') AND COALESCE(r.method,'')=COALESCE(p_range->>'method','')) THEN RAISE EXCEPTION 'Overlapping active reference range for the same sex and method.' USING ERRCODE='23505'; END IF;
 IF p_range ? 'id' AND NULLIF(p_range->>'id','') IS NOT NULL THEN SELECT * INTO v FROM public.reference_ranges WHERE id=(p_range->>'id')::UUID FOR UPDATE; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Reference range changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; old_row:=to_jsonb(v);
  UPDATE public.reference_ranges SET gender=COALESCE(p_range->>'gender','All'),age_min_days=min_age,age_max_days=max_age,normal_min=(p_range->>'normal_min')::NUMERIC,normal_max=(p_range->>'normal_max')::NUMERIC,critical_low=(p_range->>'critical_low')::NUMERIC,critical_high=(p_range->>'critical_high')::NUMERIC,normal_text=NULLIF(btrim(p_range->>'normal_text'),''),reference_text=NULLIF(btrim(p_range->>'reference_text'),''),method=NULLIF(btrim(p_range->>'method'),''),unit=NULLIF(btrim(p_range->>'unit'),''),validation_state=COALESCE((p_range->>'validation_state')::public.reference_range_validation_state_enum,'Unclassified'),validation_source=NULLIF(btrim(p_range->>'validation_source'),''),is_approved=COALESCE((p_range->>'is_approved')::BOOLEAN,FALSE),approved_by=CASE WHEN COALESCE((p_range->>'is_approved')::BOOLEAN,FALSE) THEN auth.uid() ELSE NULL END,approved_at=CASE WHEN COALESCE((p_range->>'is_approved')::BOOLEAN,FALSE) THEN NOW() ELSE NULL END,row_version=row_version+1,updated_at=NOW() WHERE id=v.id RETURNING id INTO result_id;
 ELSE INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_min,normal_max,critical_low,critical_high,normal_text,reference_text,method,unit,is_active,is_approved,lifecycle_status,validation_state,validation_source)
  VALUES((p_range->>'parameter_id')::UUID,COALESCE(p_range->>'gender','All'),min_age,max_age,(p_range->>'normal_min')::NUMERIC,(p_range->>'normal_max')::NUMERIC,(p_range->>'critical_low')::NUMERIC,(p_range->>'critical_high')::NUMERIC,NULLIF(btrim(p_range->>'normal_text'),''),NULLIF(btrim(p_range->>'reference_text'),''),NULLIF(btrim(p_range->>'method'),''),NULLIF(btrim(p_range->>'unit'),''),FALSE,FALSE,'Draft',COALESCE((p_range->>'validation_state')::public.reference_range_validation_state_enum,'Unclassified'),NULLIF(btrim(p_range->>'validation_source'),'')) RETURNING id INTO result_id; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),CASE WHEN old_row IS NULL THEN 'CATALOGUE_RANGE_CREATED' ELSE 'CATALOGUE_RANGE_UPDATED' END,'ReferenceRange',result_id::TEXT,old_row,(SELECT to_jsonb(x) FROM public.reference_ranges x WHERE x.id=result_id)); RETURN result_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_range TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_range_easy(
  p_range JSONB,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_id UUID := NULLIF(p_range->>'id', '')::UUID;
  v_param_id UUID := (p_range->>'parameter_id')::UUID;
  v_gender TEXT := COALESCE(NULLIF(btrim(p_range->>'gender'), ''), 'All');
  v_age_min INT := COALESCE((p_range->>'age_min_days')::INT, 0);
  v_age_max INT := COALESCE((p_range->>'age_max_days')::INT, 43800);
  v_normal_min NUMERIC := NULLIF(p_range->>'normal_min', '')::NUMERIC;
  v_normal_max NUMERIC := NULLIF(p_range->>'normal_max', '')::NUMERIC;
  v_crit_low NUMERIC := NULLIF(p_range->>'critical_low', '')::NUMERIC;
  v_crit_high NUMERIC := NULLIF(p_range->>'critical_high', '')::NUMERIC;
  v_normal_text TEXT := NULLIF(btrim(p_range->>'normal_text'), '');
  v_ref_text TEXT := NULLIF(btrim(p_range->>'reference_text'), '');
  v_method TEXT := NULLIF(btrim(p_range->>'method'), '');
  v_unit TEXT := NULLIF(btrim(p_range->>'unit'), '');
  v_is_active BOOLEAN := COALESCE((p_range->>'is_active')::BOOLEAN, TRUE);
  v_existing public.reference_ranges%ROWTYPE;
  v_result_id UUID;
  v_old_data JSONB;
BEGIN
  PERFORM public.catalogue_require_manager();

  IF v_param_id IS NULL THEN
    RAISE EXCEPTION 'Parameter ID is required.' USING ERRCODE='22023';
  END IF;

  IF v_age_min > v_age_max THEN
    RAISE EXCEPTION 'Minimum age cannot exceed maximum age.' USING ERRCODE='23514';
  END IF;

  IF v_normal_min IS NOT NULL AND v_normal_max IS NOT NULL AND v_normal_min > v_normal_max THEN
    RAISE EXCEPTION 'Normal minimum (%) cannot exceed normal maximum (%).', v_normal_min, v_normal_max USING ERRCODE='23514';
  END IF;

  IF v_crit_low IS NOT NULL AND v_crit_high IS NOT NULL AND v_crit_low > v_crit_high THEN
    RAISE EXCEPTION 'Critical low (%) cannot exceed critical high (%).', v_crit_low, v_crit_high USING ERRCODE='23514';
  END IF;

  IF v_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.reference_ranges WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Reference range was not found.' USING ERRCODE='P0002';
    END IF;
    IF p_expected_version IS NOT NULL AND v_existing.row_version <> p_expected_version THEN
      RAISE EXCEPTION 'This range was updated by another user. Reload before saving.' USING ERRCODE='PT409';
    END IF;

    v_old_data := to_jsonb(v_existing);

    UPDATE public.reference_ranges
    SET gender = v_gender,
        age_min_days = v_age_min,
        age_max_days = v_age_max,
        normal_min = v_normal_min,
        normal_max = v_normal_max,
        critical_low = v_crit_low,
        critical_high = v_crit_high,
        normal_text = v_normal_text,
        reference_text = v_ref_text,
        method = v_method,
        unit = v_unit,
        is_active = v_is_active,
        is_approved = TRUE,
        lifecycle_status = CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
        validation_state = 'ClinicallyValidated',
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = v_id
    RETURNING id INTO v_result_id;
  ELSE
    INSERT INTO public.reference_ranges (
      parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max,
      critical_low, critical_high, normal_text, reference_text, method, unit,
      is_active, is_approved, lifecycle_status, validation_state, row_version
    ) VALUES (
      v_param_id, v_gender, v_age_min, v_age_max, v_normal_min, v_normal_max,
      v_crit_low, v_crit_high, v_normal_text, v_ref_text, v_method, v_unit,
      v_is_active, TRUE,
      CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
      'ClinicallyValidated', 1
    ) RETURNING id INTO v_result_id;
  END IF;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data, new_data
  ) VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    CASE WHEN v_old_data IS NULL THEN 'CATALOGUE_RANGE_CREATED' ELSE 'CATALOGUE_RANGE_UPDATED' END,
    'ReferenceRange',
    v_result_id::TEXT,
    v_old_data,
    (SELECT to_jsonb(x) FROM public.reference_ranges x WHERE x.id = v_result_id)
  );

  RETURN v_result_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_range_easy TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_test(p_test JSONB,p_expected_version BIGINT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result JSONB; v_test_id UUID; is_new BOOLEAN:=NOT (p_test ? 'id') OR NULLIF(p_test->>'id','') IS NULL; report_kind public.reporting_type_enum;
BEGIN
 PERFORM public.catalogue_require_manager();
 result:=public.catalogue_save_test_conservative_00089(p_test,p_expected_version);
 v_test_id:=(result->>'id')::UUID;
 IF NOT is_new THEN RETURN result; END IF;
 report_kind:=(p_test->>'reporting_type')::public.reporting_type_enum;
 IF report_kind<>'NoReporting' THEN
   INSERT INTO public.parameters(test_id,code,name,value_type,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status)
   VALUES(v_test_id,'RESULT','Result','Text',1,TRUE,TRUE,'Active','Configured');
 END IF;
 UPDATE public.tests SET is_active=TRUE,lifecycle_status='Active',billing_enabled=TRUE,
   clinical_reporting_enabled=(report_kind<>'NoReporting'),
   collection_required=(report_kind<>'NoReporting' AND (btrim(COALESCE(sample_type,''))<>'' OR btrim(COALESCE(container,''))<>'')),
   workflow_type=CASE WHEN report_kind='NoReporting' THEN 'NoClinicalReport'::public.clinical_workflow_type_enum ELSE workflow_type END,
   clinical_configuration_status='Configured',
   activated_at=now(),activated_by=auth.uid(),row_version=row_version+1,updated_at=now() WHERE id=v_test_id;
 UPDATE public.catalogue_service_readiness SET state='Approved',configuration_version=configuration_version+1,
   approved_by=auth.uid(),approved_at=now(),decision_reason=CASE WHEN report_kind='NoReporting'
     THEN 'Created as an intentional Non-Reportable Service.' ELSE 'Created Ready & Reportable by default.' END,updated_at=now()
 WHERE catalogue_service_readiness.test_id=v_test_id;
 RETURN jsonb_build_object('id',v_test_id,'missing','[]'::JSONB,'operational_status',CASE WHEN report_kind='NoReporting' THEN 'Non-Reportable Service' ELSE 'Ready & Reportable' END);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_test TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_test_aliases_easy(
  p_test_id UUID,
  p_aliases TEXT[]
) RETURNS TEXT[]
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  cleaned TEXT[];
  item TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();

  SELECT COALESCE(array_agg(DISTINCT lower(btrim(x)) ORDER BY lower(btrim(x))), ARRAY[]::TEXT[])
  INTO cleaned
  FROM unnest(p_aliases) x
  WHERE btrim(x) <> '';

  DELETE FROM public.test_aliases WHERE test_id = p_test_id;

  FOREACH item IN ARRAY cleaned LOOP
    INSERT INTO public.test_aliases (test_id, alias_name)
    VALUES (p_test_id, item)
    ON CONFLICT (test_id, alias_name) DO NOTHING;
  END LOOP;

  UPDATE public.tests
  SET search_aliases = cleaned, row_version = row_version + 1, updated_at = NOW()
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, new_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_ALIASES_UPDATED', 'Test', p_test_id::TEXT,
    jsonb_build_object('aliases', cleaned)
  );

  RETURN cleaned;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_test_aliases_easy TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_test_analyzer_configuration(p_configuration JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE c public.test_analyzer_configurations%ROWTYPE; result_id UUID; old_row JSONB; approved BOOLEAN;
BEGIN
  PERFORM public.catalogue_require_manager(); approved:=COALESCE((p_configuration->>'is_clinically_approved')::BOOLEAN,FALSE);
  IF btrim(COALESCE(p_configuration->>'method',''))='' OR btrim(COALESCE(p_configuration->>'configuration_version',''))='' THEN RAISE EXCEPTION 'Method and configuration version are required.' USING ERRCODE='22023'; END IF;
  IF NULLIF(p_configuration->>'parameter_id','') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.parameters WHERE id=(p_configuration->>'parameter_id')::UUID AND test_id=(p_configuration->>'test_id')::UUID) THEN RAISE EXCEPTION 'Analyzer parameter must belong to the configured test.' USING ERRCODE='23503'; END IF;
  IF approved AND (COALESCE(p_configuration->>'validation_state','Unclassified')<>'ClinicallyValidated' OR btrim(COALESCE(p_configuration->>'validation_source',''))='') THEN RAISE EXCEPTION 'Clinical approval requires validated provenance.' USING ERRCODE='23514'; END IF;
  IF NULLIF(p_configuration->>'id','') IS NOT NULL THEN
    SELECT * INTO c FROM public.test_analyzer_configurations WHERE id=(p_configuration->>'id')::UUID FOR UPDATE;
    IF NOT FOUND OR c.row_version<>p_expected_version THEN RAISE EXCEPTION 'Analyzer configuration changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; old_row:=to_jsonb(c);result_id:=c.id;
    UPDATE public.test_analyzer_configurations SET test_id=(p_configuration->>'test_id')::UUID,parameter_id=NULLIF(p_configuration->>'parameter_id','')::UUID,analyzer_id=(p_configuration->>'analyzer_id')::UUID,method=btrim(p_configuration->>'method'),assay_identifier=NULLIF(btrim(p_configuration->>'assay_identifier'),''),configuration_version=btrim(p_configuration->>'configuration_version'),effective_from=COALESCE((p_configuration->>'effective_from')::DATE,CURRENT_DATE),effective_to=NULLIF(p_configuration->>'effective_to','')::DATE,validation_state=COALESCE((p_configuration->>'validation_state')::public.reference_range_validation_state_enum,'Unclassified'),validation_source=NULLIF(btrim(p_configuration->>'validation_source'),''),is_clinically_approved=approved,approved_by=CASE WHEN approved THEN auth.uid() END,approved_at=CASE WHEN approved THEN NOW() END,lifecycle_status=COALESCE((p_configuration->>'lifecycle_status')::public.analyzer_lifecycle_enum,lifecycle_status),row_version=row_version+1,updated_at=NOW() WHERE id=result_id;
  ELSE INSERT INTO public.test_analyzer_configurations(test_id,parameter_id,analyzer_id,method,assay_identifier,configuration_version,effective_from,effective_to,validation_state,validation_source,is_clinically_approved,approved_by,approved_at,lifecycle_status) VALUES((p_configuration->>'test_id')::UUID,NULLIF(p_configuration->>'parameter_id','')::UUID,(p_configuration->>'analyzer_id')::UUID,btrim(p_configuration->>'method'),NULLIF(btrim(p_configuration->>'assay_identifier'),''),btrim(p_configuration->>'configuration_version'),COALESCE((p_configuration->>'effective_from')::DATE,CURRENT_DATE),NULLIF(p_configuration->>'effective_to','')::DATE,COALESCE((p_configuration->>'validation_state')::public.reference_range_validation_state_enum,'Unclassified'),NULLIF(btrim(p_configuration->>'validation_source'),''),approved,CASE WHEN approved THEN auth.uid() END,CASE WHEN approved THEN NOW() END,COALESCE((p_configuration->>'lifecycle_status')::public.analyzer_lifecycle_enum,'Draft')) RETURNING id INTO result_id; END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'TEST_ANALYZER_CONFIGURATION_SAVED','TestAnalyzerConfiguration',result_id::TEXT,old_row,(SELECT to_jsonb(x) FROM public.test_analyzer_configurations x WHERE x.id=result_id)); RETURN result_id;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_test_analyzer_configuration TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_test_easy(
  p_test JSONB,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_id UUID := NULLIF(p_test->>'id', '')::UUID;
  v_existing public.tests%ROWTYPE;
  v_code TEXT := upper(btrim(p_test->>'code'));
  v_name TEXT := btrim(p_test->>'name');
  v_short_name TEXT := NULLIF(btrim(p_test->>'short_name'), '');
  v_department TEXT := COALESCE(NULLIF(btrim(p_test->>'department'), ''), 'Clinical Pathology');
  v_category TEXT := COALESCE(NULLIF(btrim(p_test->>'category'), ''), 'General');
  v_category_id UUID := NULLIF(p_test->>'category_id', '')::UUID;
  v_test_kind public.catalogue_test_kind_enum := COALESCE((p_test->>'test_kind')::public.catalogue_test_kind_enum, 'Individual');
  v_reporting_type public.reporting_type_enum := COALESCE((p_test->>'reporting_type')::public.reporting_type_enum, 'InHouse');
  v_outsource_lab TEXT := NULLIF(btrim(p_test->>'outsource_lab_name'), '');
  v_sample_type TEXT := COALESCE(NULLIF(btrim(p_test->>'sample_type'), ''), 'Blood');
  v_container TEXT := COALESCE(NULLIF(btrim(p_test->>'container'), ''), 'EDTA');
  v_sample_volume TEXT := NULLIF(btrim(p_test->>'sample_volume'), '');
  v_method TEXT := NULLIF(btrim(p_test->>'method'), '');
  v_tat_hours INT := COALESCE((p_test->>'tat_hours')::INT, 24);
  v_display_order INT := COALESCE((p_test->>'display_order')::INT, 0);
  v_description TEXT := NULLIF(btrim(p_test->>'description'), '');
  v_configuration_notes TEXT := NULLIF(btrim(p_test->>'configuration_notes'), '');
  v_is_active BOOLEAN := COALESCE((p_test->>'is_active')::BOOLEAN, TRUE);
  v_billing_enabled BOOLEAN := COALESCE((p_test->>'billing_enabled')::BOOLEAN, TRUE);
  v_allow_zero_price BOOLEAN := COALESCE((p_test->>'allow_zero_price_billing')::BOOLEAN, FALSE);
  v_allow_manual_price BOOLEAN := COALESCE((p_test->>'allow_manual_price')::BOOLEAN, FALSE);
  v_pricing_policy public.catalogue_pricing_policy_enum := COALESCE((p_test->>'pricing_policy')::public.catalogue_pricing_policy_enum, 'Fixed');
  v_price_paisa BIGINT := COALESCE((p_test->>'price_paisa')::BIGINT, 0);
  v_aliases TEXT[] := ARRAY(SELECT DISTINCT lower(btrim(x)) FROM jsonb_array_elements_text(COALESCE(p_test->'search_aliases', '[]'::JSONB)) x WHERE btrim(x) <> '');
  v_result_id UUID;
  v_old_data JSONB;
  alias_item TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();

  IF v_code IS NULL OR v_code = '' THEN
    RAISE EXCEPTION 'Test code is required.' USING ERRCODE='22023';
  END IF;
  IF v_name IS NULL OR v_name = '' THEN
    RAISE EXCEPTION 'Test name is required.' USING ERRCODE='22023';
  END IF;
  IF v_price_paisa < 0 THEN
    RAISE EXCEPTION 'Price cannot be negative.' USING ERRCODE='23514';
  END IF;

  IF v_id IS NOT NULL THEN
    -- Update existing test
    SELECT * INTO v_existing FROM public.tests WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
    END IF;
    IF p_expected_version IS NOT NULL AND v_existing.row_version <> p_expected_version THEN
      RAISE EXCEPTION 'This test was updated by another user. Reload before saving.' USING ERRCODE='PT409';
    END IF;

    -- Check duplicate code on other tests
    IF EXISTS (SELECT 1 FROM public.tests WHERE code = v_code AND id <> v_id) THEN
      RAISE EXCEPTION 'Test code % is already in use by another test.', v_code USING ERRCODE='23505';
    END IF;

    v_old_data := to_jsonb(v_existing);

    UPDATE public.tests
    SET code = v_code,
        name = v_name,
        short_name = v_short_name,
        department = v_department,
        category = v_category,
        category_id = v_category_id,
        test_kind = v_test_kind,
        reporting_type = v_reporting_type,
        outsource_lab_name = CASE WHEN v_reporting_type = 'OutsourceWithBimalReport' THEN v_outsource_lab ELSE NULL END,
        sample_type = v_sample_type,
        container = v_container,
        sample_volume = v_sample_volume,
        method = v_method,
        tat_hours = v_tat_hours,
        display_order = v_display_order,
        description = v_description,
        configuration_notes = v_configuration_notes,
        is_active = v_is_active,
        lifecycle_status = CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
        billing_enabled = v_billing_enabled,
        clinical_reporting_enabled = (v_reporting_type <> 'NoReporting'),
        collection_required = (v_reporting_type <> 'NoReporting'),
        workflow_type = CASE WHEN v_reporting_type = 'NoReporting' THEN 'NoClinicalReport'::public.clinical_workflow_type_enum ELSE workflow_type END,
        price_paisa = v_price_paisa,
        price_configured = (v_price_paisa > 0),
        allow_zero_price_billing = v_allow_zero_price,
        allow_manual_price = v_allow_manual_price,
        pricing_policy = v_pricing_policy,
        search_aliases = v_aliases,
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = v_id
    RETURNING id INTO v_result_id;

    -- If price changed or no active rate version exists, update catalogue_rate_versions
    IF v_existing.price_paisa IS DISTINCT FROM v_price_paisa OR NOT EXISTS (
      SELECT 1 FROM public.catalogue_rate_versions WHERE test_id = v_id AND status = 'Active' AND (effective_to IS NULL OR effective_to > now())
    ) THEN
      -- Inactivate current active rates
      UPDATE public.catalogue_rate_versions
      SET status = 'Inactive', effective_to = NOW(), updated_at = NOW(), row_version = row_version + 1
      WHERE test_id = v_id AND status = 'Active' AND (effective_to IS NULL OR effective_to > now());

      -- Insert new active rate version
      INSERT INTO public.catalogue_rate_versions (
        entity_type, test_id, ratelist_name, price_paisa, status, effective_from, row_version
      ) VALUES (
        'Test', v_id, 'Standard Patient Rate', v_price_paisa, 'Active', NOW(), 1
      );
    END IF;

  ELSE
    -- Insert new test
    IF EXISTS (SELECT 1 FROM public.tests WHERE code = v_code) THEN
      RAISE EXCEPTION 'Test code % already exists.', v_code USING ERRCODE='23505';
    END IF;

    INSERT INTO public.tests (
      code, name, short_name, department, category, category_id,
      test_kind, reporting_type, outsource_lab_name, sample_type, container,
      sample_volume, method, tat_hours, display_order, description,
      configuration_notes, is_active, lifecycle_status, billing_enabled,
      clinical_reporting_enabled, collection_required, workflow_type,
      price_paisa, price_configured, allow_zero_price_billing, allow_manual_price,
      pricing_policy, search_aliases, clinical_configuration_status, row_version
    ) VALUES (
      v_code, v_name, v_short_name, v_department, v_category, v_category_id,
      v_test_kind, v_reporting_type, CASE WHEN v_reporting_type = 'OutsourceWithBimalReport' THEN v_outsource_lab ELSE NULL END,
      v_sample_type, v_container, v_sample_volume, v_method, v_tat_hours, v_display_order,
      v_description, v_configuration_notes, v_is_active,
      CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
      v_billing_enabled, (v_reporting_type <> 'NoReporting'), (v_reporting_type <> 'NoReporting'),
      CASE WHEN v_reporting_type = 'NoReporting' THEN 'NoClinicalReport'::public.clinical_workflow_type_enum ELSE 'General'::public.clinical_workflow_type_enum END,
      v_price_paisa, (v_price_paisa > 0), v_allow_zero_price, v_allow_manual_price,
      v_pricing_policy, v_aliases, 'Configured', 1
    ) RETURNING id INTO v_result_id;

    -- Add default parameter for standalone reportable tests
    IF v_reporting_type <> 'NoReporting' THEN
      INSERT INTO public.parameters (
        test_id, code, name, value_type, display_order, is_mandatory, is_active, lifecycle_status, clinical_configuration_status, row_version
      ) VALUES (
        v_result_id, 'RESULT', 'Result', 'Text', 1, TRUE, TRUE, 'Active', 'Configured', 1
      ) ON CONFLICT DO NOTHING;
    END IF;

    -- Create initial rate version
    INSERT INTO public.catalogue_rate_versions (
      entity_type, test_id, ratelist_name, price_paisa, status, effective_from, row_version
    ) VALUES (
      'Test', v_result_id, 'Standard Patient Rate', v_price_paisa, 'Active', NOW(), 1
    );

    -- Create catalogue_service_readiness record
    INSERT INTO public.catalogue_service_readiness (
      test_id, state, configuration_version, approved_by, approved_at, decision_reason
    ) VALUES (
      v_result_id, 'Approved', 1, auth.uid(), NOW(), 'Created via Easy Test Catalogue Editor'
    ) ON CONFLICT (test_id) DO NOTHING;
  END IF;

  -- Sync test_aliases table
  DELETE FROM public.test_aliases WHERE test_id = v_result_id;
  FOREACH alias_item IN ARRAY v_aliases LOOP
    INSERT INTO public.test_aliases (test_id, alias_name)
    VALUES (v_result_id, alias_item)
    ON CONFLICT (test_id, alias_name) DO NOTHING;
  END LOOP;

  -- Audit log
  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data, new_data
  ) VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    CASE WHEN v_old_data IS NULL THEN 'CATALOGUE_TEST_CREATED' ELSE 'CATALOGUE_TEST_UPDATED' END,
    'Test',
    v_result_id::TEXT,
    v_old_data,
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = v_result_id)
  );

  RETURN (SELECT to_jsonb(t) FROM public.tests t WHERE t.id = v_result_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_save_test_easy TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_search_rate_list(
  p_query TEXT DEFAULT NULL,
  p_category_id UUID DEFAULT NULL,
  p_lifecycle public.catalogue_lifecycle_enum DEFAULT NULL,
  p_priced BOOLEAN DEFAULT NULL,
  p_entity_type public.catalogue_billable_entity_enum DEFAULT NULL,
  p_sort TEXT DEFAULT 'name',
  p_desc BOOLEAN DEFAULT FALSE,
  p_offset INT DEFAULT 0,
  p_limit INT DEFAULT 25
) RETURNS TABLE(item JSONB,total_count BIGINT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT (
    public.has_permission('can_manage_catalogue') OR public.has_permission('can_configure_catalogue_technical')
  ) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_sort NOT IN ('name','code','rate','updated_at') THEN RAISE EXCEPTION 'Invalid rate-list sort.' USING ERRCODE='22023'; END IF;

  RETURN QUERY
  WITH entities AS (
    SELECT 'Test'::public.catalogue_billable_entity_enum entity_type,t.id entity_id,t.code::TEXT,t.name::TEXT,
      t.category_id,c.name::TEXT category,t.lifecycle_status,t.updated_at,t.price_configured
    FROM public.tests t LEFT JOIN public.test_categories c ON c.id=t.category_id
    UNION ALL
    SELECT 'Panel',s.id,s.code,s.name,s.category_id,c.name,s.lifecycle_status,s.updated_at,
      EXISTS(SELECT 1 FROM public.catalogue_rate_versions rv WHERE rv.panel_service_id=s.id AND rv.status='Active' AND rv.price_paisa IS NOT NULL)
    FROM public.catalogue_panel_services s LEFT JOIN public.test_categories c ON c.id=s.category_id
    UNION ALL
    SELECT 'Package',p.id,p.code::TEXT,p.name::TEXT,NULL::UUID,'Packages',p.lifecycle_status,p.updated_at,
      EXISTS(SELECT 1 FROM public.catalogue_rate_versions rv WHERE rv.package_id=p.id AND rv.status='Active' AND rv.price_paisa IS NOT NULL)
    FROM public.health_packages p
  ), selected AS (
    SELECT e.*,r.id rate_id,r.price_paisa,r.version_number,r.row_version rate_row_version,r.effective_from,r.status rate_status,r.updated_at rate_updated_at
    FROM entities e LEFT JOIN LATERAL (
      SELECT rv.* FROM public.catalogue_rate_versions rv
      WHERE (e.entity_type='Test' AND rv.test_id=e.entity_id)
         OR (e.entity_type='Panel' AND rv.panel_service_id=e.entity_id)
         OR (e.entity_type='Package' AND rv.package_id=e.entity_id)
      ORDER BY (rv.status='Active') DESC,rv.version_number DESC LIMIT 1
    ) r ON TRUE
    WHERE (p_query IS NULL OR btrim(p_query)='' OR e.code ILIKE '%'||btrim(p_query)||'%' OR e.name ILIKE '%'||btrim(p_query)||'%')
      AND (p_category_id IS NULL OR e.category_id=p_category_id)
      AND (p_lifecycle IS NULL OR e.lifecycle_status=p_lifecycle)
      AND (p_priced IS NULL OR (r.status='Active' AND r.price_paisa IS NOT NULL)=p_priced)
      AND (p_entity_type IS NULL OR e.entity_type=p_entity_type)
  ), counted AS (SELECT s.*,count(*) OVER() AS matched_count FROM selected s)
  SELECT jsonb_build_object(
    'entity_type',x.entity_type,'entity_id',x.entity_id,'code',x.code,'name',x.name,'category_id',x.category_id,
    'category',x.category,'entity_status',x.lifecycle_status,'rate_id',x.rate_id,'price_paisa',x.price_paisa,
    'version_number',x.version_number,'rate_row_version',x.rate_row_version,'effective_from',x.effective_from,
    'rate_status',x.rate_status,'updated_at',COALESCE(x.rate_updated_at,x.updated_at)
  ),x.matched_count
  FROM counted x
  ORDER BY
    CASE WHEN p_sort='name' AND NOT p_desc THEN lower(x.name) END ASC,
    CASE WHEN p_sort='name' AND p_desc THEN lower(x.name) END DESC,
    CASE WHEN p_sort='code' AND NOT p_desc THEN lower(x.code) END ASC,
    CASE WHEN p_sort='code' AND p_desc THEN lower(x.code) END DESC,
    CASE WHEN p_sort='rate' AND NOT p_desc THEN x.price_paisa END ASC NULLS LAST,
    CASE WHEN p_sort='rate' AND p_desc THEN x.price_paisa END DESC NULLS LAST,
    CASE WHEN p_sort='updated_at' AND NOT p_desc THEN COALESCE(x.rate_updated_at,x.updated_at) END ASC,
    CASE WHEN p_sort='updated_at' AND p_desc THEN COALESCE(x.rate_updated_at,x.updated_at) END DESC,
    x.entity_id
  OFFSET greatest(COALESCE(p_offset,0),0) LIMIT greatest(1,least(COALESCE(p_limit,25),100));
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_search_rate_list TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_service_readiness_checklist(p_test_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; r public.catalogue_service_readiness%ROWTYPE; classification TEXT;
 missing TEXT[]:=ARRAY[]::TEXT[]; parameter_count INT:=0; calculation_ready BOOLEAN:=TRUE; method_ready BOOLEAN:=TRUE;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT * INTO t FROM public.tests WHERE id=p_test_id;
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'CATALOGUE_SERVICE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 classification:=public.catalogue_classification(t);
 SELECT count(*) INTO parameter_count FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active';
 IF btrim(COALESCE(t.code,''))='' OR btrim(COALESCE(t.name,''))='' OR t.category_id IS NULL THEN missing:=array_append(missing,'Canonical identity/category is incomplete'); END IF;
 IF NOT t.is_active OR t.lifecycle_status<>'Active' THEN missing:=array_append(missing,'Service lifecycle is not Active'); END IF;
 IF classification='SpecialistWorkflow' THEN missing:=array_append(missing,'Reporting workflow requires Technician configuration');
 ELSIF classification<>'BillingOnly' THEN
   IF t.reporting_type NOT IN ('InHouse','OutsourceWithBimalReport') THEN missing:=array_append(missing,'A report-producing reporting type is required'); END IF;
   IF t.collection_required AND (btrim(COALESCE(t.sample_type,''))='' OR btrim(COALESCE(t.container,''))='') THEN missing:=array_append(missing,'Required specimen/container configuration is missing'); END IF;
   IF parameter_count=0 AND t.reporting_model<>'NarrativeDocument' THEN missing:=array_append(missing,'Required result structure is missing'); END IF;
   IF EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND (btrim(COALESCE(p.name,''))='' OR btrim(COALESCE(p.code,''))='')) THEN missing:=array_append(missing,'An active result parameter has no identity'); END IF;
   IF EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN ('Select','Boolean') AND (p.option_set_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.catalogue_option_values ov WHERE ov.option_set_id=p.option_set_id AND ov.is_active))) THEN missing:=array_append(missing,'A qualitative result vocabulary is missing'); END IF;
   IF EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type='Calculated' AND (p.calculation_identifier IS NULL OR NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_versions f WHERE f.formula_identifier=p.calculation_identifier AND f.lifecycle_status='Approved' AND f.rounding_scale IS NOT NULL))) THEN calculation_ready:=FALSE; missing:=array_append(missing,'Approved calculation formula/rounding configuration is missing'); END IF;
   IF t.analyzer_configuration_required OR EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.method_validation_required) THEN
     method_ready:=EXISTS(SELECT 1 FROM public.test_analyzer_configurations c WHERE c.test_id=t.id AND c.lifecycle_status='Active' AND c.is_clinically_approved);
     IF NOT method_ready THEN missing:=array_append(missing,'Required analyzer/method configuration is missing'); END IF;
   END IF;
 END IF;
 RETURN jsonb_build_object('test_id',t.id,'code',t.code,'name',t.name,'classification',classification,
  'active',t.is_active AND t.lifecycle_status='Active','billable',t.billing_enabled,'reporting_type',t.reporting_type,
  'reporting_model',t.reporting_model,'workflow_type',t.workflow_type,'workflow_supported',t.workflow_supported,
  'clinical_reporting_enabled',t.clinical_reporting_enabled,'collection_required',t.collection_required,
  'specimen',t.sample_type,'container',t.container,'method',t.method,'test_row_version',t.row_version,
  'parameter_count',parameter_count,'calculation_ready',calculation_ready,'method_analyzer_ready',method_ready,
  'pricing_ready',TRUE,'missing_requirements',to_jsonb(missing),'ready_for_review',cardinality(missing)=0,
  'operational_status',CASE WHEN NOT t.is_active OR t.lifecycle_status<>'Active' THEN 'Inactive'
    WHEN r.state='Suspended' THEN 'Suspended' WHEN r.state='NeedsConfiguration' THEN 'Needs Attention'
    WHEN classification='BillingOnly' THEN 'Non-Reportable Service' WHEN t.clinical_reporting_enabled THEN 'Ready & Reportable'
    ELSE 'Needs Attention' END);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_service_readiness_checklist TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_set_category_lifecycle(p_category_id UUID,p_status public.catalogue_lifecycle_enum,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.test_categories%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.test_categories WHERE id=p_category_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Category no longer exists.' USING ERRCODE='P0002'; END IF; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Category changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF p_status='Archived' AND EXISTS(SELECT 1 FROM public.tests WHERE category_id=p_category_id AND lifecycle_status<>'Archived') THEN RAISE EXCEPTION 'Archive or move category tests first.' USING ERRCODE='23503'; END IF; UPDATE public.test_categories SET lifecycle_status=p_status,row_version=row_version+1,updated_at=NOW() WHERE id=p_category_id; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_CATEGORY_'||upper(p_status::TEXT),'TestCategory',p_category_id::TEXT,to_jsonb(v),(SELECT to_jsonb(c) FROM public.test_categories c WHERE c.id=p_category_id)); END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_set_category_lifecycle TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_set_current_rate(
  p_entity_type public.catalogue_billable_entity_enum,
  p_entity_id UUID,
  p_price_paisa BIGINT,
  p_expected_rate_id UUID DEFAULT NULL,
  p_expected_rate_version BIGINT DEFAULT NULL,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE current_rate public.catalogue_rate_versions%ROWTYPE; new_rate public.catalogue_rate_versions%ROWTYPE; next_version INT;
BEGIN
  PERFORM public.catalogue_require_manager();
  IF p_entity_type NOT IN ('Test','Panel','Package') OR p_entity_id IS NULL THEN RAISE EXCEPTION 'Unsupported catalogue rate entity.' USING ERRCODE='22023'; END IF;
  IF p_price_paisa IS NULL OR p_price_paisa<=0 THEN RAISE EXCEPTION 'A configured billing rate must be a positive integer number of paisa.' USING ERRCODE='23514'; END IF;
  IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Rate-change reason is required.' USING ERRCODE='23514'; END IF;

  IF p_entity_type='Test' THEN PERFORM 1 FROM public.tests WHERE id=p_entity_id FOR UPDATE;
  ELSIF p_entity_type='Panel' THEN PERFORM 1 FROM public.catalogue_panel_services WHERE id=p_entity_id FOR UPDATE;
  ELSE PERFORM 1 FROM public.health_packages WHERE id=p_entity_id FOR UPDATE; END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Catalogue entity not found.' USING ERRCODE='P0002'; END IF;

  SELECT * INTO current_rate FROM public.catalogue_rate_versions r
  WHERE (p_entity_type='Test' AND r.test_id=p_entity_id) OR (p_entity_type='Panel' AND r.panel_service_id=p_entity_id) OR (p_entity_type='Package' AND r.package_id=p_entity_id)
  ORDER BY (r.status='Active') DESC,r.version_number DESC LIMIT 1 FOR UPDATE;
  IF p_expected_rate_id IS DISTINCT FROM current_rate.id OR p_expected_rate_version IS DISTINCT FROM current_rate.row_version THEN
    RAISE EXCEPTION 'Rate changed. Refresh and review the latest value.' USING ERRCODE='PT409';
  END IF;
  IF current_rate.status='Active' AND current_rate.price_paisa=p_price_paisa THEN RAISE EXCEPTION 'New rate is unchanged.' USING ERRCODE='22023'; END IF;

  SELECT COALESCE(max(r.version_number),0)+1 INTO next_version FROM public.catalogue_rate_versions r
  WHERE (p_entity_type='Test' AND r.test_id=p_entity_id) OR (p_entity_type='Panel' AND r.panel_service_id=p_entity_id) OR (p_entity_type='Package' AND r.package_id=p_entity_id);
  UPDATE public.catalogue_rate_versions r SET status='Inactive',effective_to=COALESCE(effective_to,now()),row_version=row_version+1,updated_at=now()
  WHERE r.status='Active' AND ((p_entity_type='Test' AND r.test_id=p_entity_id) OR (p_entity_type='Panel' AND r.panel_service_id=p_entity_id) OR (p_entity_type='Package' AND r.package_id=p_entity_id));
  INSERT INTO public.catalogue_rate_versions(entity_type,test_id,panel_service_id,package_id,version_number,price_paisa,effective_from,status,created_by)
  VALUES(p_entity_type,CASE WHEN p_entity_type='Test' THEN p_entity_id END,CASE WHEN p_entity_type='Panel' THEN p_entity_id END,
    CASE WHEN p_entity_type='Package' THEN p_entity_id END,next_version,p_price_paisa,now(),'Active',auth.uid()) RETURNING * INTO new_rate;

  IF p_entity_type='Test' THEN UPDATE public.tests SET price_paisa=p_price_paisa,price_configured=TRUE,pricing_policy='Fixed',allow_manual_price=FALSE,allow_zero_price_billing=FALSE,row_version=row_version+1,updated_at=now() WHERE id=p_entity_id;
  ELSIF p_entity_type='Package' THEN UPDATE public.health_packages SET price_paisa=p_price_paisa,pricing_policy='Fixed',row_version=row_version+1,updated_at=now() WHERE id=p_entity_id;
  END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_RATE_CHANGED',p_entity_type::TEXT,p_entity_id::TEXT,
    jsonb_build_object('rate_id',current_rate.id,'version_number',current_rate.version_number,'price_paisa',current_rate.price_paisa,'status',current_rate.status),
    jsonb_build_object('rate_id',new_rate.id,'version_number',new_rate.version_number,'price_paisa',new_rate.price_paisa,'status',new_rate.status,'reason',btrim(p_reason)));
  RETURN jsonb_build_object('rate_id',new_rate.id,'version_number',new_rate.version_number,'price_paisa',new_rate.price_paisa,'rate_row_version',new_rate.row_version);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_set_current_rate TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_set_package_lifecycle(
    p_package_id UUID,
    p_status public.catalogue_lifecycle_enum,
    p_expected_version BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_package public.health_packages%ROWTYPE;
BEGIN
    PERFORM public.catalogue_require_manager();
    SELECT * INTO v_package
    FROM public.health_packages
    WHERE id=p_package_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Package no longer exists.' USING ERRCODE='P0002';
    END IF;
    IF p_expected_version IS NULL OR v_package.row_version<>p_expected_version THEN
        RAISE EXCEPTION 'Package changed. Refresh and try again.' USING ERRCODE='PT409';
    END IF;

    IF p_status='Active' THEN
        IF NOT EXISTS(
            SELECT 1 FROM public.health_package_components c
            WHERE c.package_id=p_package_id
        ) THEN
            RAISE EXCEPTION 'An active package requires at least one component.' USING ERRCODE='23514';
        END IF;
        IF EXISTS(
            SELECT 1
            FROM public.health_package_components c
            LEFT JOIN public.tests t ON t.id=c.test_id
            WHERE c.package_id=p_package_id
              AND (
                  t.id IS NULL
                  OR t.lifecycle_status<>'Active'
                  OR NOT t.is_active
                  OR NOT t.workflow_supported
                  OR t.clinical_configuration_status NOT IN ('Configured','Ready for Activation')
              )
        ) THEN
            RAISE EXCEPTION 'Every package component must be active, clinically configured, and workflow-supported.' USING ERRCODE='23514';
        END IF;
        IF v_package.pricing_policy='Fixed' AND v_package.price_paisa<=0 THEN
            RAISE EXCEPTION 'A fixed package requires a positive authoritative price.' USING ERRCODE='23514';
        END IF;
    END IF;

    UPDATE public.health_packages
    SET lifecycle_status=p_status,
        row_version=row_version+1,
        updated_at=NOW(),
        archived_at=CASE WHEN p_status='Archived' THEN NOW() ELSE NULL END,
        archived_by=CASE WHEN p_status='Archived' THEN auth.uid() ELSE NULL END
    WHERE id=p_package_id;

    INSERT INTO public.audit_logs(
        user_id,user_name,action,entity_type,entity_id,old_data,new_data
    ) VALUES (
        auth.uid(),public.catalogue_actor_name(),
        'CATALOGUE_PACKAGE_'||upper(p_status::TEXT),
        'HealthPackage',p_package_id::TEXT,to_jsonb(v_package),
        (SELECT to_jsonb(p) FROM public.health_packages p WHERE p.id=p_package_id)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_set_package_lifecycle TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_set_panel_lifecycle(p_panel_id UUID,p_status public.catalogue_lifecycle_enum,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE; IF p.row_version<>p_expected_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.catalogue_panels SET lifecycle_status=p_status,archived_at=CASE WHEN p_status='Archived' THEN now() END,archived_by=CASE WHEN p_status='Archived' THEN auth.uid() END,row_version=row_version+1,updated_at=now() WHERE id=p_panel_id; UPDATE public.catalogue_panel_services SET lifecycle_status=p_status,row_version=row_version+1,updated_at=now() WHERE panel_id=p_panel_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_set_panel_lifecycle TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_set_parameter_calculation_reporting_mode(
 p_parameter_id UUID,p_mode public.calculation_reporting_mode_enum,p_reason TEXT
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.parameters%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO p FROM public.parameters WHERE id=p_parameter_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Parameter not found.' USING ERRCODE='P0002'; END IF;
  IF length(btrim(COALESCE(p_reason,'')))<5 THEN RAISE EXCEPTION 'Reporting-mode reason is required.' USING ERRCODE='23514'; END IF;
  IF p_mode='Calculated' AND NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_versions d
      WHERE d.output_parameter_id=p.id AND d.calculation_mode='Result' AND d.lifecycle_status='Approved') THEN
    RAISE EXCEPTION 'Calculated reporting requires an approved Result formula version.' USING ERRCODE='23514';
  END IF;
  IF p_mode='MeasuredWithCalculatedConsistencyCheck' AND NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_versions d
      WHERE d.output_parameter_id=p.id AND d.calculation_mode='ConsistencyCheck' AND d.lifecycle_status='Approved') THEN
    RAISE EXCEPTION 'Consistency-check reporting requires an approved formula version.' USING ERRCODE='23514';
  END IF;
  UPDATE public.parameters SET calculation_reporting_mode=p_mode,row_version=row_version+1,updated_at=now() WHERE id=p.id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES(auth.uid(),public.catalogue_actor_name(),'PARAMETER_CALCULATION_REPORTING_MODE_CHANGED','Parameter',p.id::text,
    jsonb_build_object('mode',p.calculation_reporting_mode),jsonb_build_object('mode',p_mode,'reason',btrim(p_reason)));
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_set_parameter_calculation_reporting_mode TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_set_parameter_lifecycle(p_parameter_id UUID,p_status public.catalogue_lifecycle_enum,p_expected_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.parameters%ROWTYPE;
BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.parameters WHERE id=p_parameter_id FOR UPDATE; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Parameter changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 IF p_status='Active' AND v.value_type IN ('Numeric','Calculated') AND btrim(COALESCE(v.unit,''))='' THEN RAISE EXCEPTION 'Numeric/calculated parameters require a unit.' USING ERRCODE='23514'; END IF;
 UPDATE public.parameters SET lifecycle_status=p_status,is_active=(p_status='Active'),row_version=row_version+1,archived_at=CASE WHEN p_status='Archived' THEN NOW() ELSE NULL END,archived_by=CASE WHEN p_status='Archived' THEN auth.uid() ELSE NULL END,updated_at=NOW() WHERE id=p_parameter_id;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PARAMETER_'||upper(p_status::TEXT),'Parameter',p_parameter_id::TEXT,to_jsonb(v),(SELECT to_jsonb(x) FROM public.parameters x WHERE x.id=p_parameter_id)); END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_set_parameter_lifecycle TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_set_parameter_option_set(p_parameter_id UUID,p_option_set_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.parameters%ROWTYPE; BEGIN PERFORM public.catalogue_require_technical(); SELECT * INTO p FROM public.parameters WHERE id=p_parameter_id FOR UPDATE; IF p.row_version<>p_expected_version THEN RAISE EXCEPTION 'Parameter changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF p.value_type NOT IN ('Select','Boolean') THEN RAISE EXCEPTION 'Option sets apply only to Select or Boolean parameters.' USING ERRCODE='23514'; END IF; UPDATE public.parameters SET option_set_id=p_option_set_id,row_version=row_version+1,updated_at=now() WHERE id=p_parameter_id; END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_set_parameter_option_set TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_set_range_lifecycle(p_range_id UUID,p_status public.catalogue_lifecycle_enum,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.reference_ranges%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.reference_ranges WHERE id=p_range_id FOR UPDATE; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Reference range changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.reference_ranges SET lifecycle_status=p_status,is_active=(p_status='Active'),row_version=row_version+1,archived_at=CASE WHEN p_status='Archived' THEN NOW() ELSE NULL END,archived_by=CASE WHEN p_status='Archived' THEN auth.uid() ELSE NULL END,updated_at=NOW() WHERE id=p_range_id; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_RANGE_'||upper(p_status::TEXT),'ReferenceRange',p_range_id::TEXT,to_jsonb(v),(SELECT to_jsonb(x) FROM public.reference_ranges x WHERE x.id=p_range_id)); END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_set_range_lifecycle TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_set_test_lifecycle(
  p_test_id UUID,
  p_status public.catalogue_lifecycle_enum,
  p_expected_version BIGINT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;
  IF v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  UPDATE public.tests
  SET lifecycle_status = p_status,
      is_active = (p_status = 'Active'),
      billing_enabled = CASE WHEN p_status = 'Active' THEN TRUE ELSE billing_enabled END,
      clinical_reporting_enabled = CASE WHEN p_status = 'Active' AND reporting_type IN ('InHouse', 'OutsourceWithBimalReport') THEN TRUE ELSE clinical_reporting_enabled END,
      row_version = row_version + 1,
      updated_at = NOW(),
      archived_at = CASE WHEN p_status = 'Archived' THEN NOW() ELSE NULL END,
      archived_by = CASE WHEN p_status = 'Archived' THEN auth.uid() ELSE NULL END,
      activated_at = CASE WHEN p_status = 'Active' THEN NOW() ELSE activated_at END,
      activated_by = CASE WHEN p_status = 'Active' THEN auth.uid() ELSE activated_by END
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    'CATALOGUE_TEST_' || upper(p_status::TEXT),
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object('id', p_test_id, 'status', p_status, 'validation_status', v.validation_status);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_set_test_lifecycle TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_set_test_operational_gates(
  p_test_id UUID,p_billing_enabled BOOLEAN,p_clinical_reporting_enabled BOOLEAN,
  p_collection_required BOOLEAN,p_expected_version BIGINT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; missing TEXT[]; actor TEXT;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO t FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Test not found.' USING ERRCODE='P0002'; END IF;
  IF t.row_version<>p_expected_version THEN RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF p_billing_enabled AND t.lifecycle_status<>'Active' THEN RAISE EXCEPTION 'Billing requires an active catalogue identity.' USING ERRCODE='23514'; END IF;
  IF p_billing_enabled AND NOT (t.price_configured OR t.pricing_policy IN ('Negotiable','PricePending','Manual')) THEN RAISE EXCEPTION 'Billing requires a valid pricing policy.' USING ERRCODE='23514'; END IF;
  IF p_billing_enabled AND t.price_paisa=0 AND t.price_configured AND t.pricing_policy='Fixed' AND NOT t.allow_zero_price_billing THEN RAISE EXCEPTION 'Zero-price billing requires explicit authorization.' USING ERRCODE='23514'; END IF;
  IF p_clinical_reporting_enabled AND NOT p_collection_required THEN RAISE EXCEPTION 'Clinical reporting requires collection traceability.' USING ERRCODE='23514'; END IF;
  IF p_collection_required AND (btrim(COALESCE(t.sample_type,''))='' OR btrim(COALESCE(t.container,''))='') THEN RAISE EXCEPTION 'Collected services require specimen and container.' USING ERRCODE='23514'; END IF;
  IF p_clinical_reporting_enabled THEN missing:=public.catalogue_clinical_missing_configuration(p_test_id); IF cardinality(missing)>0 THEN RAISE EXCEPTION 'Clinical reporting cannot be enabled. Missing: %',array_to_string(missing,', ') USING ERRCODE='23514'; END IF; END IF;
  UPDATE public.tests SET billing_enabled=p_billing_enabled,clinical_reporting_enabled=p_clinical_reporting_enabled,
    collection_required=p_collection_required,row_version=row_version+1,updated_at=NOW() WHERE id=p_test_id;
  actor:=public.catalogue_actor_name();
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES(auth.uid(),actor,'CATALOGUE_OPERATIONAL_GATES_CHANGED','Test',p_test_id::TEXT,
    jsonb_build_object('billing_enabled',t.billing_enabled,'clinical_reporting_enabled',t.clinical_reporting_enabled,'collection_required',t.collection_required),
    jsonb_build_object('billing_enabled',p_billing_enabled,'clinical_reporting_enabled',p_clinical_reporting_enabled,'collection_required',p_collection_required));
  RETURN jsonb_build_object('id',p_test_id,'billing_enabled',p_billing_enabled,'clinical_reporting_enabled',p_clinical_reporting_enabled,'collection_required',p_collection_required);
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_set_test_operational_gates TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_start_template_copy(p_source_order INT,p_proposed_code TEXT,p_proposed_name TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE draft_id UUID; normalized_code TEXT:=upper(btrim(COALESCE(p_proposed_code,''))); normalized_name TEXT:=regexp_replace(lower(btrim(COALESCE(p_proposed_name,''))),'[^a-z0-9]+','','g');
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 IF normalized_code='' OR normalized_name='' THEN RAISE EXCEPTION 'A distinct code and name are required for a copied draft.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM public.tests WHERE upper(code)=normalized_code OR regexp_replace(lower(name),'[^a-z0-9]+','','g')=normalized_name OR normalized_code=ANY(SELECT upper(x) FROM unnest(COALESCE(search_aliases,ARRAY[]::TEXT[])) x)) THEN
   RAISE EXCEPTION 'CATALOGUE_TEMPLATE_DESTINATION_COLLISION' USING ERRCODE='23505';
 END IF;
 INSERT INTO public.catalogue_test_template_drafts(template_source_order,created_by,proposed_code,proposed_name,technical_configuration)
 VALUES(p_source_order,auth.uid(),normalized_code,btrim(p_proposed_name),public.catalogue_test_template_detail(p_source_order)) RETURNING id INTO draft_id;
 RETURN draft_id;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_start_template_copy TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_submit_for_review(p_test_id UUID,p_reason TEXT,p_expected_version BIGINT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_service_readiness%ROWTYPE; checklist JSONB; next_version BIGINT;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id FOR UPDATE;
 IF r.configuration_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 checklist:=public.catalogue_service_readiness_checklist(p_test_id);
 IF NOT COALESCE((checklist->>'ready_for_review')::BOOLEAN,FALSE) THEN
   RAISE EXCEPTION 'CATALOGUE_NOT_READY: %',checklist->'missing_requirements' USING ERRCODE='23514';
 END IF;
 next_version:=r.configuration_version+1;
 UPDATE public.catalogue_service_readiness SET state='ReadyForReview',configuration_version=next_version,
   submitted_by=auth.uid(),submitted_at=now(),decision_reason=NULLIF(btrim(p_reason),''),updated_at=now() WHERE test_id=p_test_id;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,new_state,reason,actor_id,actor_role)
 VALUES(p_test_id,next_version,'Workflow','Reviewed',checklist,COALESCE(NULLIF(btrim(p_reason),''),'Submitted for final review'),auth.uid(),public.catalogue_readiness_actor_role());
 RETURN next_version;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_submit_for_review TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_submit_lab_approval(
  p_test_id UUID,
  p_analyzer_model TEXT,
  p_reagent_manufacturer TEXT,
  p_method TEXT,
  p_reference_range_source TEXT,
  p_critical_limit_source TEXT,
  p_effective_from DATE,
  p_approval_notes TEXT,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  actor_id UUID;
  actor_name TEXT;
  new_version BIGINT;
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  SELECT * INTO v FROM public.tests WHERE id = p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;

  IF p_expected_version IS NOT NULL AND v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  -- Validate required approval metadata
  IF btrim(COALESCE(p_reference_range_source, '')) = '' AND v.test_kind IN ('Single', 'Component') AND v.reporting_type <> 'NoReporting' THEN
    RAISE EXCEPTION 'Laboratory approval requires a documented reference range source/clinical policy.' USING ERRCODE='23514';
  END IF;

  SELECT COALESCE(MAX(version), 0) + 1 INTO new_version
  FROM public.catalogue_lab_approvals
  WHERE test_id = p_test_id;

  -- Insert formal approval record
  INSERT INTO public.catalogue_lab_approvals (
    test_id, approved_by, approved_by_name, approved_at,
    analyzer_model, reagent_manufacturer, method,
    reference_range_source, critical_limit_source,
    effective_from, version, approval_notes, approval_status
  ) VALUES (
    p_test_id, actor_id, actor_name, NOW(),
    btrim(p_analyzer_model), btrim(p_reagent_manufacturer), COALESCE(btrim(p_method), v.method),
    btrim(p_reference_range_source), btrim(p_critical_limit_source),
    COALESCE(p_effective_from, CURRENT_DATE), new_version, btrim(p_approval_notes), 'APPROVED'
  );

  -- Update test validation state to VALIDATED
  UPDATE public.tests
  SET validation_status = 'VALIDATED',
      clinical_configuration_status = 'Configured',
      method = COALESCE(NULLIF(btrim(p_method), ''), method),
      configuration_notes = COALESCE(NULLIF(btrim(p_approval_notes), ''), configuration_notes),
      row_version = row_version + 1,
      updated_at = NOW()
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id,
    actor_name,
    'CATALOGUE_TEST_LAB_APPROVED',
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object(
    'id', p_test_id,
    'validation_status', 'VALIDATED',
    'approval_version', new_version,
    'approved_by_name', actor_name
  );
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_submit_lab_approval TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_submit_pending_configuration(
  p_test_id UUID,
  p_analyzer_model TEXT DEFAULT NULL,
  p_reagent_manufacturer TEXT DEFAULT NULL,
  p_method TEXT DEFAULT NULL,
  p_unit TEXT DEFAULT NULL,
  p_normal_min NUMERIC DEFAULT NULL,
  p_normal_max NUMERIC DEFAULT NULL,
  p_critical_low NUMERIC DEFAULT NULL,
  p_critical_high NUMERIC DEFAULT NULL,
  p_normal_text TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  v_param public.parameters%ROWTYPE;
  actor_id UUID;
  actor_name TEXT;
  can_approve BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE='42501';
  END IF;

  IF NOT (
    public.has_permission('can_enter_results') OR
    public.has_permission('can_verify_results') OR
    public.has_permission('can_manage_catalogue') OR
    public.has_permission('can_configure_catalogue_technical')
  ) THEN
    RAISE EXCEPTION 'Permission denied to configure laboratory test parameters.' USING ERRCODE='42501';
  END IF;

  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();
  can_approve := public.has_permission('can_manage_catalogue');

  SELECT * INTO v FROM public.tests WHERE id = p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;

  -- Update test method, configuration_notes, and configuration_status
  UPDATE public.tests
  SET method = COALESCE(NULLIF(btrim(p_method), ''), method),
      configuration_status = CASE WHEN can_approve THEN 'CONFIGURED' ELSE 'PENDING_APPROVAL' END,
      configuration_notes = COALESCE(NULLIF(btrim(p_notes), ''), configuration_notes),
      updated_at = NOW()
  WHERE id = p_test_id;

  -- If parameter exists, update unit and draft range
  FOR v_param IN SELECT * FROM public.parameters WHERE test_id = p_test_id AND is_active LOOP
    IF p_unit IS NOT NULL AND btrim(p_unit) <> '' THEN
      UPDATE public.parameters SET unit = p_unit, updated_at = NOW() WHERE id = v_param.id;
    END IF;

    -- Add or update draft unapproved reference range
    IF p_normal_min IS NOT NULL OR p_normal_max IS NOT NULL OR p_normal_text IS NOT NULL THEN
      INSERT INTO public.reference_ranges (
        parameter_id,
        gender,
        age_min_days,
        age_max_days,
        normal_min,
        normal_max,
        critical_low,
        critical_high,
        normal_text,
        unit,
        method,
        is_active,
        is_approved
      ) VALUES (
        v_param.id,
        'All',
        0,
        43800,
        p_normal_min,
        p_normal_max,
        p_critical_low,
        p_critical_high,
        p_normal_text,
        COALESCE(p_unit, v_param.unit),
        COALESCE(p_method, v.method),
        TRUE,
        can_approve
      );
    END IF;
  END LOOP;

  -- Audit log
  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id,
    actor_name,
    'CATALOGUE_PENDING_CONFIG_SUBMIT',
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object(
    'test_id', p_test_id,
    'configuration_status', CASE WHEN can_approve THEN 'CONFIGURED' ELSE 'PENDING_APPROVAL' END,
    'validation_status', v.validation_status,
    'message', CASE WHEN can_approve THEN 'Configuration saved.' ELSE 'Configuration saved as PENDING_APPROVAL awaiting formal lab sign-off.' END
  );
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_submit_pending_configuration TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_technical_save_range(
 p_range JSONB,p_expected_version BIGINT,p_reason TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.reference_ranges%ROWTYPE; result_id UUID; test_uuid UUID; old_row JSONB; forbidden TEXT;
 min_age INT:=COALESCE((p_range->>'age_min_days')::INT,0); max_age INT:=COALESCE((p_range->>'age_max_days')::INT,43800);
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT key INTO forbidden FROM jsonb_object_keys(COALESCE(p_range,'{}')) key WHERE key NOT IN
  ('id','parameter_id','gender','age_min_days','age_max_days','normal_min','normal_max','critical_low','critical_high','normal_text','reference_text','method','unit','effective_from','effective_to') LIMIT 1;
 IF forbidden IS NOT NULL THEN RAISE EXCEPTION 'PROTECTED_REFERENCE_RANGE_FIELD: %',forbidden USING ERRCODE='42501'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Technical change reason is required.' USING ERRCODE='23514'; END IF;
 SELECT p.test_id INTO test_uuid FROM public.parameters p WHERE p.id=(p_range->>'parameter_id')::UUID AND p.lifecycle_status='Active';
 IF test_uuid IS NULL THEN RAISE EXCEPTION 'CATALOGUE_PARAMETER_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF EXISTS(SELECT 1 FROM public.reference_ranges x WHERE x.parameter_id=(p_range->>'parameter_id')::UUID
   AND x.id<>COALESCE(NULLIF(p_range->>'id','')::UUID,'00000000-0000-0000-0000-000000000000'::UUID)
   AND x.lifecycle_status='Active' AND x.is_active AND x.gender=COALESCE(p_range->>'gender','All')
   AND int4range(x.age_min_days,x.age_max_days,'[]')&&int4range(min_age,max_age,'[]')
   AND COALESCE(x.method,'')=COALESCE(NULLIF(btrim(p_range->>'method'),''),'')) THEN
   RAISE EXCEPTION 'Overlapping active reference range for the same sex and method.' USING ERRCODE='23505';
 END IF;
 IF NULLIF(p_range->>'id','') IS NOT NULL THEN
   SELECT * INTO r FROM public.reference_ranges WHERE id=(p_range->>'id')::UUID FOR UPDATE;
   IF NOT FOUND OR r.parameter_id<>(p_range->>'parameter_id')::UUID THEN RAISE EXCEPTION 'REFERENCE_RANGE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
   IF r.row_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
   old_row:=to_jsonb(r);
   UPDATE public.reference_ranges SET gender=COALESCE(p_range->>'gender','All'),age_min_days=min_age,age_max_days=max_age,
    normal_min=(p_range->>'normal_min')::NUMERIC,normal_max=(p_range->>'normal_max')::NUMERIC,critical_low=(p_range->>'critical_low')::NUMERIC,critical_high=(p_range->>'critical_high')::NUMERIC,
    normal_text=NULLIF(btrim(p_range->>'normal_text'),''),reference_text=NULLIF(btrim(p_range->>'reference_text'),''),method=NULLIF(btrim(p_range->>'method'),''),unit=NULLIF(btrim(p_range->>'unit'),''),
    effective_from=COALESCE((p_range->>'effective_from')::DATE,effective_from),effective_to=NULLIF(p_range->>'effective_to','')::DATE,
    is_approved=FALSE,approved_by=NULL,approved_at=NULL,validation_state='Unclassified',validation_source='Technician configuration; final approval required',row_version=row_version+1,updated_at=now()
   WHERE id=r.id RETURNING id INTO result_id;
 ELSE
   INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_min,normal_max,critical_low,critical_high,normal_text,reference_text,method,unit,is_active,is_approved,lifecycle_status,validation_state,validation_source,effective_from,effective_to)
   VALUES((p_range->>'parameter_id')::UUID,COALESCE(p_range->>'gender','All'),min_age,max_age,(p_range->>'normal_min')::NUMERIC,(p_range->>'normal_max')::NUMERIC,(p_range->>'critical_low')::NUMERIC,(p_range->>'critical_high')::NUMERIC,NULLIF(btrim(p_range->>'normal_text'),''),NULLIF(btrim(p_range->>'reference_text'),''),NULLIF(btrim(p_range->>'method'),''),NULLIF(btrim(p_range->>'unit'),''),TRUE,FALSE,'Active','Unclassified','Technician configuration; final approval required',COALESCE((p_range->>'effective_from')::DATE,CURRENT_DATE),NULLIF(p_range->>'effective_to','')::DATE) RETURNING id INTO result_id;
 END IF;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,previous_state,new_state,reason,actor_id,actor_role)
 SELECT test_uuid,cr.configuration_version+1,'ReferenceRanges','Configured',old_row,
   jsonb_build_object('range_id',result_id,'approval','Final Super Admin approval required'),btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role()
 FROM public.catalogue_service_readiness cr WHERE cr.test_id=test_uuid;
 UPDATE public.catalogue_service_readiness SET state='NeedsConfiguration',configuration_version=configuration_version+1,submitted_by=NULL,submitted_at=NULL,approved_by=NULL,approved_at=NULL,decision_reason=btrim(p_reason),updated_at=now() WHERE test_id=test_uuid;
 RETURN result_id;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_technical_save_range TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_technical_update_parameter(
 p_parameter_id UUID,p_patch JSONB,p_expected_version BIGINT,p_reason TEXT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.parameters%ROWTYPE; next_version BIGINT; forbidden TEXT;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT key INTO forbidden FROM jsonb_object_keys(COALESCE(p_patch,'{}')) key
 WHERE key NOT IN ('unit','display_order','is_mandatory','range_validation_required','method_validation_required') LIMIT 1;
 IF forbidden IS NOT NULL THEN RAISE EXCEPTION 'PROTECTED_PARAMETER_FIELD: %',forbidden USING ERRCODE='42501'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Technical change reason is required.' USING ERRCODE='23514'; END IF;
 SELECT * INTO p FROM public.parameters WHERE id=p_parameter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'CATALOGUE_PARAMETER_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF p.row_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 UPDATE public.parameters SET
   unit=CASE WHEN p_patch?'unit' THEN NULLIF(btrim(p_patch->>'unit'),'') ELSE unit END,
   display_order=CASE WHEN p_patch?'display_order' THEN (p_patch->>'display_order')::INT ELSE display_order END,
   is_mandatory=CASE WHEN p_patch?'is_mandatory' THEN (p_patch->>'is_mandatory')::BOOLEAN ELSE is_mandatory END,
   range_validation_required=CASE WHEN p_patch?'range_validation_required' THEN (p_patch->>'range_validation_required')::BOOLEAN ELSE range_validation_required END,
   method_validation_required=CASE WHEN p_patch?'method_validation_required' THEN (p_patch->>'method_validation_required')::BOOLEAN ELSE method_validation_required END,
   row_version=row_version+1,updated_at=now() WHERE id=p_parameter_id RETURNING row_version INTO next_version;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,previous_state,new_state,reason,actor_id,actor_role)
 SELECT p.test_id,r.configuration_version+1,'ParameterStructure','Configured',to_jsonb(p),p_patch,btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role()
 FROM public.catalogue_service_readiness r WHERE r.test_id=p.test_id;
 UPDATE public.catalogue_service_readiness SET state='NeedsConfiguration',configuration_version=configuration_version+1,
   submitted_by=NULL,submitted_at=NULL,approved_by=NULL,approved_at=NULL,decision_reason=btrim(p_reason),updated_at=now() WHERE test_id=p.test_id;
 RETURN next_version;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_technical_update_parameter TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_technical_update_test(
 p_test_id UUID,p_patch JSONB,p_expected_version BIGINT,p_reason TEXT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; next_version BIGINT; forbidden TEXT;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT key INTO forbidden FROM jsonb_object_keys(COALESCE(p_patch,'{}')) key
 WHERE key NOT IN ('sample_type','container','collection_required','method','configuration_notes') LIMIT 1;
 IF forbidden IS NOT NULL THEN RAISE EXCEPTION 'PROTECTED_CATALOGUE_FIELD: %',forbidden USING ERRCODE='42501'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Technical change reason is required.' USING ERRCODE='23514'; END IF;
 SELECT * INTO t FROM public.tests WHERE id=p_test_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'CATALOGUE_SERVICE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF t.row_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 UPDATE public.tests SET
   sample_type=CASE WHEN p_patch?'sample_type' THEN COALESCE(p_patch->>'sample_type','') ELSE sample_type END,
   container=CASE WHEN p_patch?'container' THEN COALESCE(p_patch->>'container','') ELSE container END,
   collection_required=CASE WHEN p_patch?'collection_required' THEN (p_patch->>'collection_required')::BOOLEAN ELSE collection_required END,
   method=CASE WHEN p_patch?'method' THEN NULLIF(btrim(p_patch->>'method'),'') ELSE method END,
   configuration_notes=CASE WHEN p_patch?'configuration_notes' THEN NULLIF(btrim(p_patch->>'configuration_notes'),'') ELSE configuration_notes END,
   row_version=row_version+1,updated_at=now() WHERE id=p_test_id RETURNING row_version INTO next_version;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,previous_state,new_state,reason,actor_id,actor_role)
 SELECT p_test_id,r.configuration_version+1,'Specimen','Configured',
   jsonb_build_object('sample_type',t.sample_type,'container',t.container,'collection_required',t.collection_required,'method',t.method),
   p_patch,btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role()
 FROM public.catalogue_service_readiness r WHERE r.test_id=p_test_id;
 UPDATE public.catalogue_service_readiness SET state='NeedsConfiguration',configuration_version=configuration_version+1,
   submitted_by=NULL,submitted_at=NULL,approved_by=NULL,approved_at=NULL,decision_reason=btrim(p_reason),updated_at=now() WHERE test_id=p_test_id;
 RETURN next_version;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_technical_update_test TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_test_missing_configuration(p_test_id UUID) RETURNS TEXT[]
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; missing TEXT[]:=ARRAY[]::TEXT[]; p RECORD;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO t FROM public.tests WHERE id=p_test_id;
  IF NOT FOUND THEN RETURN ARRAY['canonical identity']; END IF;
  IF btrim(COALESCE(t.code,''))='' THEN missing:=array_append(missing,'unique code'); END IF;
  IF btrim(COALESCE(t.name,''))='' THEN missing:=array_append(missing,'canonical name'); END IF;
  IF t.category_id IS NULL THEN missing:=array_append(missing,'category'); END IF;
  IF t.reporting_type IS NULL THEN missing:=array_append(missing,'reporting tier'); END IF;
  IF NOT t.workflow_supported OR t.clinical_configuration_status='Workflow Not Supported' THEN missing:=array_append(missing,'supported clinical workflow'); END IF;
  IF t.clinical_configuration_status='Requires Clinical Validation' THEN missing:=array_append(missing,'clinical validation approval'); END IF;
  IF NOT t.price_configured AND t.pricing_policy NOT IN ('PricePending','Manual') AND NOT t.allow_zero_price_billing THEN missing:=array_append(missing,'configured production price'); END IF;
  IF t.price_paisa=0 AND t.price_configured AND NOT t.allow_zero_price_billing THEN missing:=array_append(missing,'zero-price billing authorization'); END IF;
  IF t.reporting_type<>'NoReporting' AND btrim(COALESCE(t.sample_type,''))='' THEN missing:=array_append(missing,'specimen'); END IF;
  IF t.reporting_type<>'NoReporting' AND NOT EXISTS(SELECT 1 FROM public.parameters WHERE test_id=t.id AND lifecycle_status='Active' AND is_active) THEN missing:=array_append(missing,'at least one active parameter'); END IF;
  FOR p IN SELECT * FROM public.parameters WHERE test_id=t.id AND lifecycle_status='Active' AND is_active LOOP
    IF p.value_type IN ('Numeric','Calculated') AND btrim(COALESCE(p.unit,''))='' THEN missing:=array_append(missing,p.code||': unit'); END IF;
    IF p.clinical_configuration_status='Requires Clinical Validation' OR p.unit_validation_required OR p.range_validation_required OR p.method_validation_required THEN missing:=array_append(missing,p.code||': clinical validation'); END IF;
    IF p.value_type='Select' AND COALESCE(jsonb_array_length(p.options),0)=0 THEN missing:=array_append(missing,p.code||': select options'); END IF;
    IF p.value_type='Calculated' AND (btrim(COALESCE(p.calculation_identifier,''))='' OR btrim(COALESCE(p.formula,''))='' OR NOT EXISTS(SELECT 1 FROM public.catalogue_calculation_definitions d WHERE d.identifier=p.calculation_identifier AND d.parameter_code=p.code AND d.server_authoritative AND d.is_active)) THEN missing:=array_append(missing,p.code||': approved server-authoritative calculation configuration'); END IF;
    IF p.value_type IN ('Numeric','Calculated') AND NOT EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id=p.id AND r.lifecycle_status='Active' AND r.is_active AND r.is_approved AND r.validation_state='ClinicallyValidated') THEN missing:=array_append(missing,p.code||': clinically validated reference-range policy'); END IF;
  END LOOP;
  IF t.billing_enabled AND NOT (t.price_configured OR t.pricing_policy IN ('Negotiable','PricePending','Manual')) THEN missing:=array_append(missing,'valid billing price policy'); END IF;
  IF t.billing_enabled AND t.price_paisa=0 AND t.price_configured AND t.pricing_policy='Fixed' AND NOT t.allow_zero_price_billing THEN missing:=array_append(missing,'zero-price billing authorization'); END IF;
  IF t.collection_required AND btrim(COALESCE(t.sample_type,''))='' THEN missing:=array_append(missing,'specimen'); END IF;
  IF t.collection_required AND btrim(COALESCE(t.container,''))='' THEN missing:=array_append(missing,'container'); END IF;
  IF t.clinical_reporting_enabled THEN missing:=missing||public.catalogue_clinical_missing_configuration(t.id); END IF;
  RETURN missing;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_test_missing_configuration TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_test_operational_label(p_test_id UUID)
RETURNS TEXT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  t public.tests%ROWTYPE;
  r public.catalogue_service_readiness%ROWTYPE;
BEGIN
  SELECT * INTO t FROM public.tests WHERE id=p_test_id;
  IF NOT FOUND THEN RETURN 'Unknown'; END IF;
  SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id;

  IF t.validation_status = 'REQUIRES_VALIDATION' THEN
    RETURN 'Requires Validation';
  END IF;
  IF NOT t.is_active OR t.lifecycle_status = 'Archived' THEN
    RETURN 'Inactive';
  END IF;
  IF r.state = 'Suspended' THEN
    RETURN 'Suspended';
  END IF;
  IF r.state = 'NeedsConfiguration' THEN
    RETURN 'Needs Attention';
  END IF;
  IF t.reporting_type = 'NoReporting' OR t.workflow_type = 'NoClinicalReport' THEN
    RETURN 'Non-Reportable Service';
  END IF;
  IF public.catalogue_test_result_readiness(t.id) = 'Ready' THEN
    RETURN 'Ready & Reportable';
  ELSE
    RETURN 'Needs Attention';
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_test_operational_label TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_test_result_readiness(p_test_id UUID)
RETURNS public.catalogue_result_readiness_enum LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT CASE WHEN t.lifecycle_status='Archived' OR NOT t.is_active THEN 'Inactive'
  WHEN r.state IN('Suspended','NeedsConfiguration') THEN 'Incomplete'
  WHEN t.reporting_type='NoReporting' OR t.workflow_type='NoClinicalReport' THEN 'NoReporting'
  WHEN NOT t.workflow_supported THEN 'SpecialistWorkflow'
  WHEN NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active') THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND (btrim(COALESCE(p.name,''))='' OR btrim(COALESCE(p.code,''))='')) THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN('Select','Boolean') AND (p.option_set_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.catalogue_option_values ov WHERE ov.option_set_id=p.option_set_id AND ov.is_active))) THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type='Calculated' AND NOT EXISTS(
    SELECT 1 FROM public.clinical_calculation_formula_versions f
    WHERE f.formula_identifier=p.calculation_identifier
      AND f.output_parameter_id=p.id
      AND f.scope_test_id=t.id
      AND f.lifecycle_status='Approved'
      AND f.rounding_scale IS NOT NULL
      AND f.rounding_mode IS NOT NULL
      AND NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_inputs i WHERE i.formula_version_id=f.id AND (i.source_identifier IS NULL OR (i.source_type IN('SAME_TEST_PARAMETER','SAME_ORDER_CANONICAL_PARAMETER') AND i.parameter_id IS NULL)))
  )) THEN 'Incomplete'
  ELSE 'Ready' END::public.catalogue_result_readiness_enum
 FROM public.tests t LEFT JOIN public.catalogue_service_readiness r ON r.test_id=t.id WHERE t.id=p_test_id
$$;

GRANT EXECUTE ON FUNCTION public.catalogue_test_result_readiness TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_test_template_detail(p_source_order INT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result JSONB;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_active_user() THEN RAISE EXCEPTION 'TEST_TEMPLATE_ACCESS_DENIED' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object(
   'source_order',ct.source_order,'name',ct.supplied_name,
   'basic',jsonb_build_object('test_name',t.name,'code',t.code,'category',tc.name,'test_type',d.test_type,'short_name',d.short_name),
   'parameters',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',p.name,'unit',p.unit,'result_type',p.value_type,'display_order',p.display_order) ORDER BY p.display_order,p.id) FROM public.parameters p WHERE p.test_id=t.id AND p.is_active),'[]'::JSONB),
   'reference_ranges',COALESCE((SELECT jsonb_agg(jsonb_build_object('parameter',p.name,'sex',r.gender,'age_min_days',r.age_min_days,'age_max_days',r.age_max_days,'normal_min',r.normal_min,'normal_max',r.normal_max,'normal_text',r.normal_text,'critical_low',r.critical_low,'critical_high',r.critical_high,'method',NULLIF(r.method,'')) ORDER BY p.display_order,r.gender,r.age_min_days) FROM public.parameters p JOIN public.reference_ranges r ON r.parameter_id=p.id WHERE p.test_id=t.id AND p.is_active AND r.lifecycle_status='Active'),'[]'::JSONB),
   'workflow',jsonb_build_object('specimen',t.sample_type,'container',t.container,'reporting_model',t.reporting_model,'reporting_type',t.reporting_type,'collection_required',t.collection_required),
   'notes',jsonb_build_object('interpretation',t.interpretation_template,'technical_notes',NULL)
 ) INTO result
 FROM public.catalogue_test_templates ct
 JOIN public.catalogue_test_database_entries d ON d.source_order=ct.test_database_source_order
 JOIN public.tests t ON t.id=ct.configuration_test_id
 JOIN public.test_categories tc ON tc.id=d.category_id
 WHERE ct.source_order=p_source_order;
 IF result IS NULL THEN RAISE EXCEPTION 'TEST_TEMPLATE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 RETURN result;
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_test_template_detail TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_update_test_price(p_test_id UUID,p_price_paisa BIGINT,p_acknowledge_zero_price BOOLEAN DEFAULT FALSE) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old_price BIGINT; BEGIN PERFORM public.catalogue_require_manager(); IF p_price_paisa<0 THEN RAISE EXCEPTION 'Price cannot be negative.' USING ERRCODE='23514'; END IF; IF p_price_paisa=0 AND NOT p_acknowledge_zero_price THEN RAISE EXCEPTION 'Explicit acknowledgement is required to configure a genuine zero price.' USING ERRCODE='23514'; END IF; SELECT price_paisa INTO old_price FROM public.tests WHERE id=p_test_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Test no longer exists.'; END IF; UPDATE public.tests SET price_paisa=p_price_paisa,price_configured=TRUE,allow_zero_price_billing=(p_price_paisa=0 AND p_acknowledge_zero_price),row_version=row_version+1,updated_at=NOW() WHERE id=p_test_id; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PRICE_UPDATED','Test',p_test_id::TEXT,jsonb_build_object('price_paisa',old_price),jsonb_build_object('price_paisa',p_price_paisa,'zero_price_acknowledged',p_acknowledge_zero_price)); END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_update_test_price TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_validate_test(
  p_test_id UUID,
  p_notes TEXT DEFAULT NULL,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  missing TEXT[];
  p RECORD;
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;
  IF p_expected_version IS NOT NULL AND v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  -- Verify basic clinical prerequisites
  IF btrim(COALESCE(v.sample_type, '')) = '' AND v.reporting_type <> 'NoReporting' THEN
    RAISE EXCEPTION 'Clinical validation requires a valid specimen type.' USING ERRCODE='23514';
  END IF;

  -- For calculated parameters, verify calculation definition exists
  FOR p IN SELECT * FROM public.parameters WHERE test_id = v.id AND is_active LOOP
    IF p.value_type = 'Calculated' AND (btrim(COALESCE(p.calculation_identifier, '')) = '' OR btrim(COALESCE(p.formula, '')) = '') THEN
      RAISE EXCEPTION 'Parameter % is marked Calculated but lacks formula or calculation identifier.', p.code USING ERRCODE='23514';
    END IF;
  END LOOP;

  UPDATE public.tests
  SET validation_status = 'VALIDATED',
      clinical_configuration_status = 'Configured',
      configuration_notes = COALESCE(NULLIF(btrim(p_notes), ''), configuration_notes),
      row_version = row_version + 1,
      updated_at = NOW()
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    'CATALOGUE_TEST_CLINICALLY_VALIDATED',
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object('id', p_test_id, 'validation_status', 'VALIDATED');
END $$;

GRANT EXECUTE ON FUNCTION public.catalogue_validate_test TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.check_order_report_readiness(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_reportable_count INT := 0;
    v_verified_count INT := 0;
    v_unverified_items JSONB := '[]'::JSONB;
    v_unack_critical_count INT := 0;
    v_unack_critical_items JSONB := '[]'::JSONB;
    v_is_ready BOOLEAN := FALSE;
    v_item RECORD;
    v_res RECORD;
BEGIN
    FOR v_item IN (
        SELECT coi.id, coi.test_name, coi.department, coi.reporting_type, coi.status, t.code AS test_code
        FROM public.clinical_order_items coi
        JOIN public.tests t ON coi.test_id = t.id
        WHERE coi.order_id = p_order_id
          AND coi.reporting_type IN ('InHouse', 'OutsourceWithBimalReport')
    ) LOOP
        v_reportable_count := v_reportable_count + 1;

        IF v_item.status IN ('Verified', 'SignedOff') THEN
            v_verified_count := v_verified_count + 1;
        ELSE
            v_unverified_items := v_unverified_items || jsonb_build_object(
                'order_item_id', v_item.id,
                'test_name', v_item.test_name,
                'department', v_item.department,
                'status', v_item.status
            );
        END IF;
    END LOOP;

    -- Check critical panic values
    FOR v_res IN (
        SELECT tr.id, tr.parameter_name, tr.display_value, tr.unit, tr.flag, tr.critical_acknowledged, coi.test_name
        FROM public.test_results tr
        JOIN public.clinical_order_items coi ON tr.order_item_id = coi.id
        WHERE coi.order_id = p_order_id
          AND (tr.is_critical = TRUE OR tr.flag IN ('CriticalLow', 'CriticalHigh'))
          AND tr.critical_acknowledged = FALSE
    ) LOOP
        v_unack_critical_count := v_unack_critical_count + 1;
        v_unack_critical_items := v_unack_critical_items || jsonb_build_object(
            'result_id', v_res.id,
            'test_name', v_res.test_name,
            'parameter_name', v_res.parameter_name,
            'display_value', v_res.display_value,
            'flag', v_res.flag
        );
    END LOOP;

    v_is_ready := (
        v_reportable_count > 0 AND
        v_verified_count = v_reportable_count AND
        v_unack_critical_count = 0
    );

    RETURN jsonb_build_object(
        'is_ready', v_is_ready,
        'reportable_count', v_reportable_count,
        'verified_count', v_verified_count,
        'unverified_count', jsonb_array_length(v_unverified_items),
        'unverified_items', v_unverified_items,
        'unvalidated_count', 0,
        'unvalidated_items', '[]'::JSONB,
        'unacknowledged_critical_count', v_unack_critical_count,
        'unacknowledged_critical_items', v_unack_critical_items
    );
END $$;

GRANT EXECUTE ON FUNCTION public.check_order_report_readiness TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.check_report_group_readiness(p_report_group_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE total_count INT; unverified INT; collection_blocked INT; critical_blocked INT; calculation_blocked INT; state TEXT;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_enter_results') OR public.has_permission('can_verify_results') OR public.has_permission('can_sign_reports')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.clinical_report_groups WHERE id=p_report_group_id) THEN RAISE EXCEPTION 'Report group not found.' USING ERRCODE='P0002'; END IF;
 SELECT count(*),count(*) FILTER(WHERE oi.status NOT IN ('Verified','SignedOff') OR (oi.execution_route='OUTSOURCE' AND oi.outsource_state NOT IN ('Verified','Signed'))),
 count(*) FILTER(WHERE oi.collection_required AND (s.id IS NULL OR s.status<>'Received')),
 count(*) FILTER(WHERE EXISTS(SELECT 1 FROM public.test_results tr WHERE tr.order_item_id=oi.id AND tr.is_critical AND tr.critical_acknowledged_at IS NULL)),
 count(*) FILTER(WHERE EXISTS(SELECT 1 FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id WHERE tr.order_item_id=oi.id AND p.value_type='Calculated' AND (tr.display_value IS NULL OR tr.display_value IN ('','Calculation Error'))))
 INTO total_count,unverified,collection_blocked,critical_blocked,calculation_blocked
 FROM public.clinical_report_group_items gi JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id LEFT JOIN public.samples s ON s.id=oi.sample_id
 WHERE gi.report_group_id=p_report_group_id AND oi.reporting_type IN ('InHouse', 'OutsourceWithBimalReport');
 state:=CASE WHEN unverified+collection_blocked+critical_blocked+calculation_blocked=0 AND total_count>0 THEN 'ReadyToSign' WHEN unverified<total_count THEN 'InProgress' ELSE 'Pending' END;
 UPDATE public.clinical_report_groups SET lifecycle_state=CASE WHEN lifecycle_state IN ('Signed','Amended') THEN lifecycle_state ELSE state END,updated_at=now(),row_version=row_version+1 WHERE id=p_report_group_id;
 RETURN jsonb_build_object('is_ready',total_count>0 AND unverified+collection_blocked+critical_blocked+calculation_blocked=0,'total_count',total_count,'unverified_count',unverified,'collection_blocked_count',collection_blocked,'unacknowledged_critical_count',critical_blocked,'calculation_blocked_count',calculation_blocked,'state',state);
END $$;

GRANT EXECUTE ON FUNCTION public.check_report_group_readiness TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.claim_next_sms_gateway_item(p_worker_id UUID,p_lease_seconds INT DEFAULT 300)
RETURNS TABLE(id UUID,sms_type VARCHAR,recipient_phone VARCHAR,message_body TEXT,retry_count INT,max_attempts INT,idempotency_key VARCHAR,lease_owner UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF p_worker_id IS NULL OR p_lease_seconds NOT BETWEEN 60 AND 900 THEN RAISE EXCEPTION 'Valid worker and lease are required.' USING ERRCODE='22023'; END IF;
 RETURN QUERY WITH candidate AS (
   SELECT q.id FROM public.sms_queue_items q
   WHERE q.status IN ('Pending','Failed') AND q.scheduled_at<=NOW() AND q.retry_count<q.max_attempts
   ORDER BY q.scheduled_at,q.created_at,q.id FOR UPDATE SKIP LOCKED LIMIT 1
 ) UPDATE public.sms_queue_items q SET status='Processing',lease_owner=p_worker_id,
   lease_expires_at=NOW()+make_interval(secs=>p_lease_seconds),provider_call_started_at=NULL,
   error_message=NULL,error_classification=NULL,updated_at=NOW()
 FROM candidate c WHERE q.id=c.id
 RETURNING q.id,q.sms_type,q.recipient_phone,q.message_body,q.retry_count,q.max_attempts,q.idempotency_key,q.lease_owner;
END;$$;

GRANT EXECUTE ON FUNCTION public.claim_next_sms_gateway_item TO authenticated, service_role;

CREATE FUNCTION public.claim_report_pdf_artifact(p_lease_seconds INT DEFAULT 300)
RETURNS TABLE(artifact_id UUID,report_id UUID,report_version INT,report_integrity_hash VARCHAR,
  snapshot_sha256 CHAR(64),snapshot JSONB,artifact_created_at TIMESTAMPTZ,lease_owner UUID,public_url TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE owner UUID:=gen_random_uuid();
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_lease_seconds<60 OR p_lease_seconds>900 THEN RAISE EXCEPTION 'Invalid artifact lease.' USING ERRCODE='22023'; END IF;
  RETURN QUERY WITH candidate AS (
    SELECT a.id FROM public.report_pdf_artifacts a WHERE
      (a.generation_status IN('Pending','GenerationFailed','UploadFailed') OR
       (a.generation_status='Generating' AND a.lease_expires_at<=NOW())) AND a.attempt_count<5
      AND public.report_artifact_public_url(a.diagnostic_report_id) IS NOT NULL
    ORDER BY a.created_at,a.diagnostic_report_id,a.id LIMIT 1 FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.report_pdf_artifacts a SET generation_status='Generating',attempt_count=attempt_count+1,
      lease_owner=owner,lease_expires_at=NOW()+make_interval(secs=>p_lease_seconds),failure_code=NULL,updated_at=NOW()
    FROM candidate c WHERE a.id=c.id RETURNING a.*
  ) SELECT c.id,r.id,r.version,r.integrity_hash,c.frozen_snapshot_sha256,r.clinical_snapshot_json,c.created_at,owner,
      public.report_artifact_public_url(r.id)
    FROM claimed c JOIN public.diagnostic_reports r ON r.id=c.diagnostic_report_id
    WHERE r.status IN('SignedOff','Amended') AND r.version=c.report_version
      AND r.integrity_hash=c.report_integrity_hash
      AND encode(extensions.digest(r.clinical_snapshot_json::TEXT,'sha256'),'hex')=c.frozen_snapshot_sha256;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_report_pdf_artifact TO authenticated, service_role;

CREATE FUNCTION public.claim_report_pdf_artifact_v2(p_lease_seconds INT DEFAULT 300)
RETURNS TABLE(artifact_id UUID,report_id UUID,report_number VARCHAR,report_version INT,report_integrity_hash VARCHAR,
  snapshot_sha256 CHAR(64),snapshot JSONB,artifact_created_at TIMESTAMPTZ,lease_owner UUID,public_url TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE owner UUID:=gen_random_uuid();
BEGIN
  IF NOT public.is_report_artifact_worker() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_lease_seconds<60 OR p_lease_seconds>900 THEN RAISE EXCEPTION 'Invalid artifact lease.' USING ERRCODE='22023'; END IF;
  RETURN QUERY WITH candidate AS (
    SELECT a.id FROM public.report_pdf_artifacts a WHERE
      (a.generation_status IN('Pending','GenerationFailed','UploadFailed') OR
       (a.generation_status='Generating' AND a.lease_expires_at<=NOW())) AND a.attempt_count<5
      AND public.report_artifact_public_url(a.diagnostic_report_id) IS NOT NULL
    ORDER BY a.created_at,a.diagnostic_report_id,a.id LIMIT 1 FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.report_pdf_artifacts a SET generation_status='Generating',attempt_count=attempt_count+1,
      lease_owner=owner,lease_expires_at=NOW()+make_interval(secs=>p_lease_seconds),failure_code=NULL,updated_at=NOW()
    FROM candidate c WHERE a.id=c.id RETURNING a.*
  ) SELECT c.id,r.id,r.report_number,r.version,r.integrity_hash,c.frozen_snapshot_sha256,
      r.clinical_snapshot_json,c.created_at,owner,public.report_artifact_public_url(r.id)
    FROM claimed c JOIN public.diagnostic_reports r ON r.id=c.diagnostic_report_id
    WHERE r.status IN('SignedOff','Amended') AND r.version=c.report_version
      AND r.integrity_hash=c.report_integrity_hash
      AND encode(extensions.digest(r.clinical_snapshot_json::TEXT,'sha256'),'hex')=c.frozen_snapshot_sha256;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_report_pdf_artifact_v2 TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.claim_sms_batch(p_batch_size INT DEFAULT 10)
RETURNS TABLE (
    id UUID,
    sms_type VARCHAR,
    recipient_phone VARCHAR,
    recipient_name VARCHAR,
    message_body TEXT,
    retry_count INT,
    max_attempts INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH claimed AS (
        SELECT s.id
        FROM public.sms_queue_items s
        WHERE s.status = 'Pending'
          AND s.scheduled_at <= NOW()
          AND s.retry_count < s.max_attempts
        ORDER BY s.scheduled_at ASC
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.sms_queue_items q
    SET status = 'Processing',
        updated_at = NOW()
    FROM claimed c
    WHERE q.id = c.id
    RETURNING q.id, q.sms_type, q.recipient_phone, q.recipient_name, q.message_body, q.retry_count, q.max_attempts;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_sms_batch TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.claim_sms_gateway_item(p_sms_id UUID)
RETURNS TABLE (
    id UUID,
    sms_type VARCHAR,
    recipient_phone VARCHAR,
    message_body TEXT,
    retry_count INT,
    max_attempts INT,
    idempotency_key VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_sms_id IS NULL THEN
        RAISE EXCEPTION 'An explicit SMS queue UUID is required.' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH claimed AS (
        SELECT q.id
        FROM public.sms_queue_items q
        WHERE q.id = p_sms_id
          AND q.status = 'Pending'
          AND q.scheduled_at <= NOW()
          AND q.retry_count < q.max_attempts
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.sms_queue_items q
       SET status = 'Processing',
           updated_at = NOW()
      FROM claimed c
     WHERE q.id = c.id
    RETURNING q.id, q.sms_type, q.recipient_phone, q.message_body,
              q.retry_count, q.max_attempts, q.idempotency_key;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_sms_gateway_item TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.claim_sms_gateway_v2_batch(
  p_instance_id UUID,p_worker_id UUID,p_lease_seconds INT DEFAULT 300,p_batch_size INT DEFAULT 1)
RETURNS TABLE(id UUID,sms_type VARCHAR,recipient_phone VARCHAR,message_body TEXT,retry_count INT,max_attempts INT,idempotency_key VARCHAR,lease_owner UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  IF NOT EXISTS(SELECT 1 FROM public.sms_gateway_instances WHERE instance_id=p_instance_id AND claiming_enabled) THEN
    RAISE EXCEPTION 'Gateway v2 claiming is disabled.' USING ERRCODE='55000';
  END IF;
  IF p_worker_id IS NULL OR p_lease_seconds NOT BETWEEN 60 AND 900 OR p_batch_size NOT BETWEEN 1 AND 10 THEN
    RAISE EXCEPTION 'Invalid claim bounds.' USING ERRCODE='22023';
  END IF;
  RETURN QUERY WITH candidates AS (
    SELECT q.id FROM public.sms_queue_items q WHERE q.status IN('Pending','Failed') AND q.scheduled_at<=now() AND q.retry_count<q.max_attempts
    ORDER BY q.scheduled_at,q.created_at,q.id FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  ), claimed AS (
    UPDATE public.sms_queue_items q SET status='Processing',lease_owner=p_worker_id,lease_instance_id=p_instance_id,
      lease_expires_at=now()+make_interval(secs=>p_lease_seconds),provider_call_started_at=NULL,error_message=NULL,error_classification=NULL,updated_at=now()
    FROM candidates c WHERE q.id=c.id RETURNING q.*
  ) SELECT q.id,q.sms_type,q.recipient_phone,q.message_body,q.retry_count,q.max_attempts,q.idempotency_key,q.lease_owner FROM claimed q;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_sms_gateway_v2_batch TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.clinical_result_collection_readiness(p_order_item_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  item public.clinical_order_items%ROWTYPE;
  sample public.samples%ROWTYPE;
  ready BOOLEAN := FALSE;
  reason TEXT;
BEGIN
  SELECT * INTO item FROM public.clinical_order_items WHERE id=p_order_item_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ready',FALSE,'code','RESULT_ITEM_NOT_FOUND');
  END IF;
  IF NOT item.clinical_reporting_enabled THEN
    RETURN jsonb_build_object('ready',FALSE,'code','RESULT_REPORTING_DISABLED');
  END IF;
  IF NOT item.collection_required THEN
    RETURN jsonb_build_object('ready',TRUE,'code','RESULT_COLLECTION_NOT_REQUIRED');
  END IF;
  IF item.sample_id IS NULL THEN
    RETURN jsonb_build_object('ready',FALSE,'code','RESULT_COLLECTION_NOT_READY','reason','SAMPLE_MISSING');
  END IF;

  SELECT * INTO sample FROM public.samples WHERE id=item.sample_id;
  IF NOT FOUND OR sample.order_id<>item.order_id THEN reason:='SAMPLE_ORDER_MISMATCH';
  ELSIF sample.status IN ('Pending','Rejected','Recollected') THEN reason:='SAMPLE_'||upper(sample.status::TEXT);
  ELSIF sample.status NOT IN ('Collected','Received','Processing','Completed') THEN reason:='SAMPLE_STATE_INVALID';
  ELSIF sample.collected_at IS NULL THEN reason:='COLLECTION_TIMESTAMP_MISSING';
  ELSIF sample.collected_by IS NULL OR NULLIF(btrim(COALESCE(sample.collected_by_name,'')),'') IS NULL
        OR NOT EXISTS(SELECT 1 FROM public.user_profiles u WHERE u.id=sample.collected_by) THEN
    reason:='COLLECTOR_IDENTITY_INVALID';
  ELSE ready:=TRUE;
  END IF;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'ready',ready,
    'code',CASE WHEN ready THEN 'RESULT_COLLECTION_READY' ELSE 'RESULT_COLLECTION_NOT_READY' END,
    'reason',reason,
    'sample_id',sample.id,
    'sample_status',sample.status,
    'result_revision',item.result_revision
  ));
END $$;

GRANT EXECUTE ON FUNCTION public.clinical_result_collection_readiness TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.complete_report_pdf_artifact(p_artifact_id UUID,p_lease_owner UUID,p_ready BOOLEAN,
  p_pdf_sha256 TEXT DEFAULT NULL,p_byte_size BIGINT DEFAULT NULL,p_generator_name TEXT DEFAULT NULL,
  p_generator_version TEXT DEFAULT NULL,p_failure_code TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE a public.report_pdf_artifacts%ROWTYPE; key TEXT; next_status public.report_artifact_status_enum;
BEGIN
  IF NOT public.is_report_artifact_worker() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  SELECT * INTO a FROM public.report_pdf_artifacts WHERE id=p_artifact_id FOR UPDATE;
  IF NOT FOUND OR a.generation_status<>'Generating' OR a.lease_owner IS DISTINCT FROM p_lease_owner OR a.lease_expires_at<=NOW() THEN
    RAISE EXCEPTION 'Artifact lease is not owned by this attempt.' USING ERRCODE='55000';
  END IF;
  IF p_ready THEN
    IF p_pdf_sha256 !~ '^[0-9a-f]{64}$' OR p_byte_size IS NULL OR p_byte_size<=0 THEN RAISE EXCEPTION 'Invalid PDF evidence.' USING ERRCODE='22023'; END IF;
    key:=format('reports/%s/%s/v%s/%s.pdf',extract(year from a.created_at AT TIME ZONE 'UTC')::INT,a.diagnostic_report_id,a.report_version,p_pdf_sha256);
    next_status:='Ready';
    UPDATE public.report_pdf_artifacts SET generation_status=next_status,object_key=key,pdf_sha256=p_pdf_sha256,
      byte_size=p_byte_size,mime_type='application/pdf',generator_name=p_generator_name,generator_version=p_generator_version,
      generated_at=NOW(),lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW() WHERE id=a.id;
  ELSE
    next_status:=(CASE WHEN p_failure_code='R2_UPLOAD_FAILED' THEN 'UploadFailed' ELSE 'GenerationFailed' END)::public.report_artifact_status_enum;
    UPDATE public.report_pdf_artifacts SET generation_status=next_status,failure_code=left(p_failure_code,100),
      lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW() WHERE id=a.id;
  END IF;
  RETURN jsonb_build_object('status',next_status,'object_key',key);
END $$;

GRANT EXECUTE ON FUNCTION public.complete_report_pdf_artifact TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.complete_report_pdf_artifact_v2(p_artifact_id UUID,p_lease_owner UUID,p_ready BOOLEAN,p_pdf_sha256 TEXT DEFAULT NULL,p_byte_size BIGINT DEFAULT NULL,p_generator_name TEXT DEFAULT NULL,p_generator_version TEXT DEFAULT NULL,p_failure_code TEXT DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result JSONB; artifact public.report_pdf_artifacts%ROWTYPE; intent public.report_pdf_delivery_intents%ROWTYPE; report public.diagnostic_reports%ROWTYPE; patient public.patients%ROWTYPE; ordering public.clinical_orders%ROWTYPE; sms_id UUID; phone TEXT; generation_id UUID; v_sms_body TEXT;
BEGIN
 IF NOT public.is_report_artifact_worker() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 result:=public.complete_report_pdf_artifact(p_artifact_id,p_lease_owner,p_ready,p_pdf_sha256,p_byte_size,p_generator_name,p_generator_version,p_failure_code); IF NOT p_ready THEN RETURN result; END IF;
 SELECT * INTO artifact FROM public.report_pdf_artifacts WHERE id=p_artifact_id; SELECT * INTO intent FROM public.report_pdf_delivery_intents WHERE diagnostic_report_id=artifact.diagnostic_report_id AND status='AwaitingArtifact' FOR UPDATE;
 IF NOT FOUND THEN RETURN result||jsonb_build_object('sms_queued',false); END IF;
 SELECT * INTO report FROM public.diagnostic_reports WHERE id=artifact.diagnostic_report_id; SELECT * INTO patient FROM public.patients WHERE id=report.patient_id; SELECT * INTO ordering FROM public.clinical_orders WHERE id=report.order_id;
 IF intent.order_token_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.order_report_notification_generations WHERE order_id=report.order_id AND generation=1) THEN UPDATE public.report_pdf_delivery_intents SET status='Skipped',queued_at=now() WHERE diagnostic_report_id=report.id; RETURN result||jsonb_build_object('sms_queued',false,'sms_status','Order already notified'); END IF;
 phone:=regexp_replace(coalesce(patient.mobile,''),'[^0-9]','','g'); IF phone LIKE '977%' AND length(phone)=13 THEN phone:=substring(phone FROM 4); END IF;
 IF phone !~ '^(97|98)[0-9]{8}$' THEN UPDATE public.report_pdf_delivery_intents SET status='Skipped',queued_at=now() WHERE diagnostic_report_id=report.id; RETURN result||jsonb_build_object('sms_queued',false,'sms_status','SMS skipped: invalid or missing Nepal mobile'); END IF;
 v_sms_body := public.build_single_credit_nepali_sms(report.order_id, report.id);
 INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id) VALUES('ReportReady',phone,patient.full_name,v_sms_body,'Pending',CASE WHEN intent.order_token_id IS NULL THEN 'REPORT_READY:'||report.id||':'||report.version ELSE 'ORDER_REPORT_READY:'||report.order_id||':1' END,report.id) ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
 IF intent.order_token_id IS NOT NULL THEN INSERT INTO public.order_report_notification_generations(order_id,generation,reason,requested_by,sms_queue_item_id) VALUES(report.order_id,1,'First finalized PDF milestone',coalesce(report.signed_by_personnel_id,report.performed_by_personnel_id),sms_id) ON CONFLICT(order_id,generation) DO NOTHING RETURNING id INTO generation_id; END IF;
  UPDATE public.report_pdf_delivery_intents SET status=CASE WHEN sms_id IS NULL THEN 'Skipped' ELSE 'Queued' END,queued_sms_id=sms_id,queued_at=now() WHERE diagnostic_report_id=report.id;
  RETURN result||jsonb_build_object('sms_queued',sms_id IS NOT NULL);
END $$;

GRANT EXECUTE ON FUNCTION public.complete_report_pdf_artifact_v2 TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.complete_sms_gateway_item(
 p_sms_id UUID,p_worker_id UUID,p_accepted BOOLEAN,p_provider_msg_id TEXT DEFAULT NULL,
 p_provider_response JSONB DEFAULT NULL,p_provider_response_code TEXT DEFAULT NULL,
 p_error_msg TEXT DEFAULT NULL,p_error_classification TEXT DEFAULT NULL,p_retryable BOOLEAN DEFAULT FALSE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q public.sms_queue_items%ROWTYPE; attempts INT; next_status TEXT;
BEGIN
 SELECT * INTO q FROM public.sms_queue_items WHERE id=p_sms_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'SMS queue item not found.' USING ERRCODE='P0002'; END IF;
 IF q.status='Sent' THEN RETURN jsonb_build_object('success',true,'status','Sent','already_completed',true); END IF;
 IF q.status<>'Processing' OR q.lease_owner IS DISTINCT FROM p_worker_id THEN RAISE EXCEPTION 'SMS lease ownership conflict.' USING ERRCODE='40001'; END IF;
 IF q.provider_call_started_at IS NULL THEN RAISE EXCEPTION 'Provider call was not marked as started.' USING ERRCODE='55000'; END IF;
 IF p_accepted THEN
   UPDATE public.sms_queue_items SET status='Sent',sent_at=NOW(),final_state_at=NOW(),delivery_attempt_count=delivery_attempt_count+1,provider_message_id=p_provider_msg_id,
    provider_response_json=p_provider_response,provider_response_code=p_provider_response_code,error_message=NULL,error_classification=NULL,
    lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW() WHERE id=p_sms_id;
   INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data) VALUES('SMS_SENT','SmsQueueItem',p_sms_id::TEXT,jsonb_build_object('provider_message_id',p_provider_msg_id));
   RETURN jsonb_build_object('success',true,'status','Sent');
 END IF;
 attempts:=q.retry_count+1;
 next_status:=CASE WHEN NOT p_retryable OR attempts>=q.max_attempts THEN 'DeadLetter' ELSE 'Failed' END;
 UPDATE public.sms_queue_items SET status=next_status,retry_count=attempts,delivery_attempt_count=delivery_attempt_count+1,
   scheduled_at=CASE WHEN next_status='Failed' THEN NOW()+make_interval(secs=>CASE attempts WHEN 1 THEN 120 WHEN 2 THEN 600 WHEN 3 THEN 1800 ELSE 3600 END) ELSE scheduled_at END,
   provider_response_json=p_provider_response,provider_response_code=p_provider_response_code,
   error_message=left(COALESCE(p_error_msg,'Delivery failed'),500),error_classification=COALESCE(p_error_classification,CASE WHEN p_retryable THEN 'RetryableProviderFailure' ELSE 'PermanentProviderFailure' END),
   final_state_at=CASE WHEN next_status='DeadLetter' THEN NOW() ELSE NULL END,lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW() WHERE id=p_sms_id;
 INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data) VALUES('SMS_FAILED','SmsQueueItem',p_sms_id::TEXT,jsonb_build_object('attempt',attempts,'status',next_status,'classification',p_error_classification));
 RETURN jsonb_build_object('success',true,'status',next_status,'attempt',attempts);
END;$$;

GRANT EXECUTE ON FUNCTION public.complete_sms_gateway_item TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.complete_sms_gateway_v2_item(
  p_instance_id UUID,p_sms_id UUID,p_worker_id UUID,p_accepted BOOLEAN,p_provider_msg_id TEXT DEFAULT NULL,
  p_provider_response JSONB DEFAULT NULL,p_provider_response_code TEXT DEFAULT NULL,p_error_msg TEXT DEFAULT NULL,
  p_error_classification TEXT DEFAULT NULL,p_retryable BOOLEAN DEFAULT FALSE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q public.sms_queue_items%ROWTYPE;attempts INT;next_status TEXT;
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  SELECT * INTO q FROM public.sms_queue_items WHERE id=p_sms_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SMS queue item not found.' USING ERRCODE='P0002'; END IF;
  IF q.status='Sent' THEN RETURN jsonb_build_object('success',true,'status','Sent','already_completed',true); END IF;
  IF q.status<>'Processing' OR q.lease_owner IS DISTINCT FROM p_worker_id OR q.lease_instance_id IS DISTINCT FROM p_instance_id THEN
    RAISE EXCEPTION 'SMS lease ownership conflict.' USING ERRCODE='40001'; END IF;
  IF q.provider_call_started_at IS NULL THEN RAISE EXCEPTION 'Provider call was not marked as started.' USING ERRCODE='55000'; END IF;
  IF p_accepted THEN
    UPDATE public.sms_queue_items SET status='Sent',sent_at=now(),final_state_at=now(),delivery_attempt_count=delivery_attempt_count+1,
      provider_message_id=p_provider_msg_id,provider_response_json=p_provider_response,provider_response_code=p_provider_response_code,
      error_message=NULL,error_classification=NULL,lease_owner=NULL,lease_instance_id=NULL,lease_expires_at=NULL,updated_at=now() WHERE id=p_sms_id;
    INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data) VALUES('SMS_SENT','SmsQueueItem',p_sms_id::TEXT,jsonb_build_object('provider_message_id',p_provider_msg_id,'gateway_instance_id',p_instance_id));
    RETURN jsonb_build_object('success',true,'status','Sent');
  END IF;
  attempts:=q.retry_count+1;
  next_status:=CASE WHEN NOT p_retryable OR attempts>=q.max_attempts THEN 'DeadLetter' ELSE 'Failed' END;
  UPDATE public.sms_queue_items SET status=next_status,retry_count=attempts,delivery_attempt_count=delivery_attempt_count+1,
    scheduled_at=CASE WHEN next_status='Failed' THEN now()+make_interval(secs=>CASE attempts WHEN 1 THEN 120 WHEN 2 THEN 600 WHEN 3 THEN 1800 ELSE 3600 END) ELSE scheduled_at END,
    provider_response_json=p_provider_response,provider_response_code=p_provider_response_code,error_message=left(COALESCE(p_error_msg,'Delivery failed'),500),
    error_classification=COALESCE(p_error_classification,CASE WHEN p_retryable THEN 'RetryableProviderFailure' ELSE 'PermanentProviderFailure' END),
    final_state_at=CASE WHEN next_status='DeadLetter' THEN now() ELSE NULL END,lease_owner=NULL,lease_instance_id=NULL,lease_expires_at=NULL,updated_at=now() WHERE id=p_sms_id;
  INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data) VALUES('SMS_FAILED','SmsQueueItem',p_sms_id::TEXT,
    jsonb_build_object('attempt',attempts,'status',next_status,'classification',p_error_classification,'gateway_instance_id',p_instance_id));
  RETURN jsonb_build_object('success',true,'status',next_status,'attempt',attempts);
END $$;

GRANT EXECUTE ON FUNCTION public.complete_sms_gateway_v2_item TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.configure_reference_laboratory(p_payload JSONB,p_expected_version BIGINT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.reference_laboratories%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_outsource_tracking') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF nullif(p_payload->>'id','') IS NULL THEN
  INSERT INTO public.reference_laboratories(code,name,external_code,contact_details,tat_hours,is_active,created_by)
  VALUES(upper(btrim(p_payload->>'code')),btrim(p_payload->>'name'),nullif(btrim(p_payload->>'external_code'),''),nullif(btrim(p_payload->>'contact_details'),''),(p_payload->>'tat_hours')::int,coalesce((p_payload->>'is_active')::boolean,true),auth.uid()) RETURNING * INTO r;
 ELSE
  UPDATE public.reference_laboratories SET code=upper(btrim(p_payload->>'code')),name=btrim(p_payload->>'name'),external_code=nullif(btrim(p_payload->>'external_code'),''),contact_details=nullif(btrim(p_payload->>'contact_details'),''),tat_hours=(p_payload->>'tat_hours')::int,is_active=coalesce((p_payload->>'is_active')::boolean,is_active),row_version=row_version+1,updated_at=now()
  WHERE id=(p_payload->>'id')::uuid AND row_version=p_expected_version RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reference laboratory changed. Refresh and retry.' USING ERRCODE='PT409'; END IF;
 END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'REFERENCE_LAB_CONFIGURED','ReferenceLaboratory',r.id::text,to_jsonb(r)-'contact_details');
 RETURN jsonb_build_object('id',r.id,'row_version',r.row_version);
END $$;

GRANT EXECUTE ON FUNCTION public.configure_reference_laboratory TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_patient(p_patient_data JSONB)
RETURNS public.patients LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp AS $$
DECLARE
  v_patient public.patients%ROWTYPE;
  v_mobile TEXT := public.patient_normalize_mobile(p_patient_data->>'mobile');
  v_name TEXT := public.patient_clean_text(p_patient_data->>'full_name');
  v_address TEXT := public.patient_clean_text(p_patient_data->>'address');
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF NOT public.has_permission('can_edit_patient') THEN RAISE EXCEPTION 'Not authorized to create patients.' USING ERRCODE = '42501'; END IF;
  IF v_name = '' OR v_address = '' THEN RAISE EXCEPTION 'Patient name and address are required.' USING ERRCODE = '22023'; END IF;
  IF COALESCE((p_patient_data->>'gender'), '') NOT IN ('Male','Female','Other') THEN RAISE EXCEPTION 'Invalid patient gender.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_years','')::INT NOT BETWEEN 0 AND 120 AND NULLIF(p_patient_data->>'age_years','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age years must be from 0 to 120.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_months','')::INT NOT BETWEEN 0 AND 11 AND NULLIF(p_patient_data->>'age_months','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age months must be from 0 to 11.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_days','')::INT NOT BETWEEN 0 AND 31 AND NULLIF(p_patient_data->>'age_days','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age days must be from 0 to 31.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_months','')::INT NOT BETWEEN 0 AND 11 AND NULLIF(p_patient_data->>'age_months','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age months must be from 0 to 11.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_days','')::INT NOT BETWEEN 0 AND 31 AND NULLIF(p_patient_data->>'age_days','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age days must be from 0 to 31.' USING ERRCODE = '22023'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('patient-mobile:' || v_mobile, 0));
  IF EXISTS (SELECT 1 FROM public.patients WHERE mobile = v_mobile) THEN RAISE EXCEPTION 'A patient with this mobile number already exists. Open the existing patient; patients are never auto-merged.' USING ERRCODE = '23505'; END IF;

  INSERT INTO public.patients(uhid,mobile,title,full_name,gender,dob,age_years,age_months,age_days,address,email,identification_no,created_at)
  VALUES(public.allocate_patient_uhid(v_mobile,v_now),v_mobile,NULLIF(public.patient_clean_text(p_patient_data->>'title'),''),v_name,p_patient_data->>'gender',NULLIF(p_patient_data->>'dob','')::DATE,NULLIF(p_patient_data->>'age_years','')::INT,NULLIF(p_patient_data->>'age_months','')::INT,NULLIF(p_patient_data->>'age_days','')::INT,v_address,NULLIF(public.patient_clean_text(p_patient_data->>'email'),''),NULLIF(public.patient_clean_text(p_patient_data->>'identification_no'),''),v_now)
  RETURNING * INTO v_patient;

  RETURN v_patient;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_patient TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_patient_bill_and_order(p_patient_data JSONB,p_bill_data JSONB,p_items_data JSONB[],p_payment_data JSONB,p_idempotency_key TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
DECLARE v_caller UUID:=auth.uid();v_key TEXT:=btrim(COALESCE(p_idempotency_key,''));v_hash TEXT;v_existing public.billing_idempotency_requests%ROWTYPE;v_response JSONB;v_payment public.payment_transactions%ROWTYPE;v_bill public.bills%ROWTYPE;v_patient public.patients%ROWTYPE;v_phone TEXT;v_lab_no TEXT;v_message TEXT;v_sms_id UUID;v_sms_status TEXT:='No payment notification required';
BEGIN
 IF v_caller IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';END IF;
 IF v_key='' OR length(v_key)>200 THEN RAISE EXCEPTION 'A valid billing request key is required.' USING ERRCODE='22023';END IF;
 IF COALESCE((p_bill_data->>'paid_amount_paisa')::BIGINT,0)>0 AND p_payment_data IS NULL THEN RAISE EXCEPTION 'Payment details are required when an amount is received.' USING ERRCODE='22023';END IF;
 IF COALESCE((p_bill_data->>'paid_amount_paisa')::BIGINT,0)>0 AND COALESCE(p_payment_data->>'payment_mode','')<>'Cash' AND public.patient_clean_text(p_payment_data->>'transaction_reference')='' THEN RAISE EXCEPTION 'Transaction reference is required for non-cash payments.' USING ERRCODE='22023';END IF;
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('patient',p_patient_data,'bill',p_bill_data,'items',to_jsonb(p_items_data),'payment',p_payment_data)::TEXT,'UTF8'),'sha256'),'hex');
 INSERT INTO public.billing_idempotency_requests(caller_id,idempotency_key,request_hash)VALUES(v_caller,v_key,v_hash)ON CONFLICT(caller_id,idempotency_key)DO NOTHING;
 SELECT * INTO v_existing FROM public.billing_idempotency_requests WHERE caller_id=v_caller AND idempotency_key=v_key FOR UPDATE;
 IF v_existing.request_hash<>v_hash THEN RAISE EXCEPTION 'Billing request key was already used for different data.' USING ERRCODE='22023';END IF;
 IF v_existing.response_json IS NOT NULL THEN RETURN v_existing.response_json||jsonb_build_object('idempotency_replay',TRUE);END IF;
 v_response:=public.create_patient_bill_and_order(p_patient_data,p_bill_data,p_items_data,p_payment_data);
 SELECT * INTO v_bill FROM public.bills WHERE id=(v_response->>'bill_id')::UUID;
 SELECT * INTO v_payment FROM public.payment_transactions WHERE bill_id=v_bill.id ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN
  SELECT * INTO v_patient FROM public.patients WHERE id=v_bill.patient_id;
  v_phone:=regexp_replace(COALESCE(v_patient.mobile,''),'[^0-9]','','g');IF v_phone LIKE '977%' AND length(v_phone)=13 THEN v_phone:=substring(v_phone FROM 4);END IF;
  v_lab_no:=COALESCE(NULLIF(v_response->>'order_number',''),v_response->>'bill_number');
  BEGIN
   IF v_phone~'^(97|98)[0-9]{8}$' THEN
    v_message:='Bimal Pathology: Payment of NPR '||(v_payment.amount_paisa/100)::TEXT||'.'||lpad((v_payment.amount_paisa%100)::TEXT,2,'0')||' received for Lab No: '||v_lab_no||'. Thank you.';
    INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,bill_id)VALUES('BillRegistration',v_phone,v_patient.full_name,v_message,'Pending','PAYMENT_CONFIRMATION:'||v_payment.id::TEXT,v_bill.id)ON CONFLICT(idempotency_key)DO NOTHING RETURNING id INTO v_sms_id;
    v_sms_status:=CASE WHEN v_sms_id IS NULL THEN 'Payment notification already queued' ELSE 'Payment notification queued' END;
   ELSE v_sms_status:='SMS skipped: invalid or missing Nepal mobile';END IF;
  EXCEPTION WHEN OTHERS THEN v_sms_status:='Payment committed; notification unavailable';INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)VALUES(v_caller,public.patient_actor_name(),'PAYMENT_SMS_QUEUE_FAILED','PaymentTransaction',v_payment.id::TEXT,jsonb_build_object('bill_id',v_bill.id));END;
 END IF;
 v_response:=v_response||jsonb_build_object('sms_queued',v_sms_id IS NOT NULL,'sms_status',v_sms_status);
 UPDATE public.billing_idempotency_requests SET response_json=v_response,completed_at=NOW()WHERE caller_id=v_caller AND idempotency_key=v_key;
 RETURN v_response||jsonb_build_object('idempotency_replay',FALSE);
END;$$;

GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_patient_bill_order_mixed_catalogue(p_patient_data JSONB,p_bill_data JSONB,p_items_data JSONB[],p_payment_data JSONB,p_idempotency_key TEXT,p_packages JSONB DEFAULT '[]',p_panel_service_id UUID DEFAULT NULL,p_expected_panel_version BIGINT DEFAULT NULL,p_agreed_panel_price_paisa BIGINT DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE svc public.catalogue_panel_services%ROWTYPE; pnl public.catalogue_panels%ROWTYPE; response JSONB; bill_uuid UUID; selection_uuid UUID; component_snapshot JSONB; component_ids UUID[]; temporary_manual UUID[]:=ARRAY[]::uuid[]; temporary_zero UUID[]:=ARRAY[]::uuid[];
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF p_panel_service_id IS NULL THEN RETURN public.create_patient_bill_order_with_packages(p_patient_data,p_bill_data,p_items_data,p_payment_data,p_idempotency_key,p_packages); END IF;
 SELECT * INTO svc FROM public.catalogue_panel_services WHERE id=p_panel_service_id AND lifecycle_status='Active' FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'Panel service is inactive or missing.' USING ERRCODE='23503'; END IF;
 SELECT * INTO pnl FROM public.catalogue_panels WHERE id=svc.panel_id AND lifecycle_status='Active' FOR SHARE; IF NOT FOUND OR pnl.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; END IF;
 IF coalesce(p_agreed_panel_price_paisa,0)<=0 THEN RAISE EXCEPTION 'A positive bundled panel rate is required.' USING ERRCODE='23514'; END IF;
 SELECT jsonb_agg(jsonb_build_object('test_id',c.test_id,'test_code',c.test_code,'test_name',c.test_name,'display_order',c.display_order) ORDER BY c.display_order),array_agg(c.test_id ORDER BY c.test_id) INTO component_snapshot,component_ids FROM public.catalogue_panel_service_components(svc.id)c;
 IF component_ids IS NULL OR EXISTS(SELECT 1 FROM unnest(component_ids)x(id) WHERE NOT EXISTS(SELECT 1 FROM unnest(p_items_data)i WHERE (i->>'test_id')::uuid=x.id)) THEN RAISE EXCEPTION 'Panel component traceability is incomplete.' USING ERRCODE='23514'; END IF;
 PERFORM 1 FROM public.tests WHERE id=ANY(component_ids) ORDER BY id FOR UPDATE; SELECT coalesce(array_agg(id),ARRAY[]::uuid[]) INTO temporary_manual FROM public.tests WHERE id=ANY(component_ids) AND NOT allow_manual_price; SELECT coalesce(array_agg(id),ARRAY[]::uuid[]) INTO temporary_zero FROM public.tests WHERE id=ANY(component_ids) AND NOT allow_zero_price_billing;
 UPDATE public.tests SET allow_manual_price=true WHERE id=ANY(temporary_manual); UPDATE public.tests SET allow_zero_price_billing=true WHERE id=ANY(temporary_zero);
 response:=public.create_patient_bill_order_with_packages(p_patient_data,p_bill_data,p_items_data,p_payment_data,p_idempotency_key,p_packages); bill_uuid:=(response->>'bill_id')::uuid;
 UPDATE public.tests SET allow_manual_price=false WHERE id=ANY(temporary_manual); UPDATE public.tests SET allow_zero_price_billing=false WHERE id=ANY(temporary_zero);
 INSERT INTO public.bill_panel_selections(bill_id,panel_service_id,panel_id,service_code_snapshot,panel_name_snapshot,panel_price_paisa,rate_version_id,component_snapshot)
 SELECT bill_uuid,svc.id,pnl.id,svc.code,pnl.name,p_agreed_panel_price_paisa,r.id,component_snapshot FROM public.catalogue_rate_versions r WHERE r.panel_service_id=svc.id AND r.status='Active' ORDER BY r.effective_from DESC LIMIT 1 ON CONFLICT(bill_id,panel_service_id) DO NOTHING RETURNING id INTO selection_uuid;
 IF selection_uuid IS NULL THEN SELECT id INTO selection_uuid FROM public.bill_panel_selections WHERE bill_id=bill_uuid AND panel_service_id=svc.id; END IF;
 INSERT INTO public.bill_panel_components(bill_panel_selection_id,bill_item_id,test_id,display_order) SELECT selection_uuid,bi.id,bi.test_id,(x->>'display_order')::int FROM jsonb_array_elements(component_snapshot)x JOIN public.bill_items bi ON bi.bill_id=bill_uuid AND bi.test_id=(x->>'test_id')::uuid ON CONFLICT DO NOTHING;
 RETURN response||jsonb_build_object('panel_selection_id',selection_uuid,'panel_service_id',svc.id);
END $$;

GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_mixed_catalogue TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_packages(
    p_patient_data JSONB,
    p_bill_data JSONB,
    p_items_data JSONB[],
    p_payment_data JSONB,
    p_idempotency_key TEXT,
    p_packages JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE 
    response JSONB; 
    bill_uuid UUID; 
    pkg JSONB; 
    component UUID; 
    selection_uuid UUID; 
    expected_ids UUID[]; 
    supplied_ids UUID[] := ARRAY(SELECT DISTINCT (x->>'test_id')::UUID FROM unnest(p_items_data) x); 
    package_seen UUID[] := ARRAY[]::UUID[]; 
    manual_ids UUID[] := ARRAY[]::UUID[]; 
    package_row public.health_packages%ROWTYPE; 
    agreed_price BIGINT; 
    component_sum BIGINT;
BEGIN
    -- 1. Permission Verification
    IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN 
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; 
    END IF;

    -- 2. Duplicate Item Check
    IF cardinality(p_items_data) <> cardinality(supplied_ids) THEN 
        RAISE EXCEPTION 'A canonical service may be selected only once.' USING ERRCODE='23505'; 
    END IF;

    -- 3. Active & Billing Enabled Check
    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        LEFT JOIN public.tests t ON t.id = (i->>'test_id')::UUID 
        WHERE t.id IS NULL OR t.lifecycle_status <> 'Active' OR NOT t.is_active OR NOT t.billing_enabled
    ) THEN 
        RAISE EXCEPTION 'Only active, billing-enabled catalogue services may be billed.' USING ERRCODE='23514'; 
    END IF;

    -- 4. Valid Rate Verification
    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        WHERE (i->>'unit_price_paisa') IS NULL OR (i->>'unit_price_paisa')::BIGINT < 0
    ) THEN 
        RAISE EXCEPTION 'Every item requires a valid agreed rate.' USING ERRCODE='23514'; 
    END IF;

    -- 5. Zero-Price Billing Policy Check
    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        JOIN public.tests t ON t.id = (i->>'test_id')::UUID 
        WHERE (i->>'unit_price_paisa')::BIGINT = 0 
          AND (NOT t.allow_zero_price_billing OR NOT COALESCE((i->>'zero_price_acknowledged')::BOOLEAN, FALSE))
    ) THEN 
        RAISE EXCEPTION 'Zero-price billing requires explicit catalogue authorization and acknowledgement.' USING ERRCODE='23514'; 
    END IF;

    -- 6. Health Package Bundles Verification
    FOR pkg IN SELECT value FROM jsonb_array_elements(COALESCE(p_packages, '[]')) LOOP
        SELECT * INTO package_row FROM public.health_packages WHERE id = (pkg->>'package_id')::UUID AND lifecycle_status = 'Active' FOR SHARE; 
        IF NOT FOUND THEN 
            RAISE EXCEPTION 'Only active packages may be billed.' USING ERRCODE='23514'; 
        END IF;

        SELECT array_agg(c.test_id ORDER BY c.display_order) INTO expected_ids 
        FROM public.health_package_components c 
        JOIN public.tests t ON t.id = c.test_id 
        WHERE c.package_id = package_row.id AND t.lifecycle_status = 'Active' AND t.is_active AND t.billing_enabled;

        IF expected_ids IS NULL OR expected_ids <> ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids') x) THEN 
            RAISE EXCEPTION 'Package definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; 
        END IF;

        agreed_price := (pkg->>'agreed_price_paisa')::BIGINT; 
        IF agreed_price <= 0 THEN 
            RAISE EXCEPTION 'A package requires a positive agreed price.' USING ERRCODE='23514'; 
        END IF;

        FOREACH component IN ARRAY expected_ids LOOP 
            IF component = ANY(package_seen) OR NOT component = ANY(supplied_ids) THEN 
                RAISE EXCEPTION 'Package components are duplicated or missing.' USING ERRCODE='23514'; 
            END IF; 
            package_seen := array_append(package_seen, component); 
        END LOOP;

        SELECT COALESCE(sum((i->>'unit_price_paisa')::BIGINT), 0) INTO component_sum 
        FROM unnest(p_items_data) i 
        WHERE (i->>'test_id')::UUID = ANY(expected_ids); 
        
        IF component_sum <> agreed_price THEN 
            RAISE EXCEPTION 'Package component prices must equal the agreed package price.' USING ERRCODE='23514'; 
        END IF;
    END LOOP;

    -- 7. Lock Selected Tests and Allow Manual Override During Atomic Insert
    PERFORM 1 FROM public.tests t WHERE t.id = ANY(supplied_ids) ORDER BY t.id FOR UPDATE;
    SELECT COALESCE(array_agg(id ORDER BY id), ARRAY[]::UUID[]) INTO manual_ids FROM public.tests WHERE id = ANY(supplied_ids) AND NOT allow_manual_price;
    UPDATE public.tests SET allow_manual_price = TRUE WHERE id = ANY(manual_ids);

    -- 8. Core Billing and Clinical Order Creation
    response := public.create_patient_bill_and_order(p_patient_data, p_bill_data, p_items_data, p_payment_data, p_idempotency_key); 
    bill_uuid := (response->>'bill_id')::UUID;

    UPDATE public.bill_items bi SET catalogue_price_paisa_snapshot = t.price_paisa FROM public.tests t WHERE bi.bill_id = bill_uuid AND bi.test_id = t.id;
    UPDATE public.tests SET allow_manual_price = FALSE WHERE id = ANY(manual_ids);

    -- 9. Record Package Selections and Components
    FOR pkg IN SELECT value FROM jsonb_array_elements(COALESCE(p_packages, '[]')) LOOP
        INSERT INTO public.bill_package_selections(bill_id, package_id, package_code_snapshot, package_name_snapshot, package_price_paisa, catalogue_package_price_paisa)
        SELECT bill_uuid, p.id, p.code, p.name, (pkg->>'agreed_price_paisa')::BIGINT, p.price_paisa 
        FROM public.health_packages p 
        WHERE p.id = (pkg->>'package_id')::UUID
        ON CONFLICT(bill_id, package_id) DO NOTHING RETURNING id INTO selection_uuid;

        IF selection_uuid IS NOT NULL THEN 
            INSERT INTO public.bill_package_components(bill_package_selection_id, bill_item_id, test_id) 
            SELECT selection_uuid, bi.id, bi.test_id 
            FROM public.bill_items bi 
            WHERE bi.bill_id = bill_uuid AND bi.test_id = ANY(ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids') x)); 
        END IF;
    END LOOP;

    RETURN response || jsonb_build_object('packages_recorded', jsonb_array_length(COALESCE(p_packages, '[]')));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_packages TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_panel_service(
  p_patient_data JSONB,
  p_bill_data JSONB,
  p_payment_data JSONB,
  p_idempotency_key TEXT,
  p_panel_service_id UUID,
  p_expected_panel_version BIGINT,
  p_agreed_panel_price_paisa BIGINT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  svc public.catalogue_panel_services%ROWTYPE;
  rate public.catalogue_rate_versions%ROWTYPE;
  items JSONB[];
  response JSONB;
  bill_uuid UUID;
  selection_uuid UUID;
  component_snapshot JSONB;
  component_ids UUID[];
  manual_ids UUID[]:=ARRAY[]::UUID[];
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_agreed_panel_price_paisa IS NULL OR p_agreed_panel_price_paisa<=0 THEN RAISE EXCEPTION 'A panel requires a positive agreed price.' USING ERRCODE='23514'; END IF;
  SELECT * INTO svc FROM public.catalogue_panel_services WHERE id=p_panel_service_id AND lifecycle_status='Active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Panel service is inactive or missing.' USING ERRCODE='23503'; END IF;
  IF svc.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; END IF;
  SELECT * INTO rate FROM public.catalogue_rate_versions WHERE panel_service_id=svc.id AND status='Active' AND price_paisa IS NOT NULL AND COALESCE(effective_from,now())<=now() AND(effective_to IS NULL OR effective_to>now()) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'A panel catalogue default must be active before billing.' USING ERRCODE='23514'; END IF;
  
  SELECT array_agg(jsonb_build_object('test_id',c.test_id,'unit_price_paisa',CASE WHEN c.display_order=x.min_ord THEN p_agreed_panel_price_paisa ELSE 0 END,'manual_price_paisa',CASE WHEN c.display_order=x.min_ord THEN p_agreed_panel_price_paisa ELSE 0 END,'discount_paisa',0,'zero_price_acknowledged',TRUE) ORDER BY c.display_order),
    jsonb_agg(jsonb_build_object('test_id',c.test_id,'test_code',c.test_code,'test_name',c.test_name,'display_order',c.display_order) ORDER BY c.display_order),array_agg(c.test_id ORDER BY c.test_id)
  INTO items,component_snapshot,component_ids FROM public.catalogue_panel_service_components(svc.id)c CROSS JOIN(SELECT min(display_order)min_ord FROM public.catalogue_panel_service_components(svc.id))x;
  IF items IS NULL THEN RAISE EXCEPTION 'Panel has no canonical component tests.' USING ERRCODE='23514'; END IF;
  PERFORM 1 FROM public.tests WHERE id=ANY(component_ids) ORDER BY id FOR UPDATE;
  SELECT COALESCE(array_agg(id ORDER BY id),ARRAY[]::UUID[]) INTO manual_ids FROM public.tests WHERE id=ANY(component_ids) AND NOT allow_manual_price;
  UPDATE public.tests SET allow_manual_price=TRUE WHERE id=ANY(manual_ids);
  response:=public.create_patient_bill_and_order(p_patient_data,p_bill_data,items,p_payment_data,p_idempotency_key); bill_uuid:=(response->>'bill_id')::UUID;
  UPDATE public.bill_items bi SET catalogue_price_paisa_snapshot=t.price_paisa FROM public.tests t WHERE bi.bill_id=bill_uuid AND bi.test_id=t.id;
  UPDATE public.tests SET allow_manual_price=FALSE WHERE id=ANY(manual_ids);
  INSERT INTO public.bill_panel_selections(bill_id,panel_service_id,panel_id,service_code_snapshot,panel_name_snapshot,panel_price_paisa,catalogue_panel_price_paisa,rate_version_id,component_snapshot)
  VALUES(bill_uuid,svc.id,svc.panel_id,svc.code,svc.name,p_agreed_panel_price_paisa,rate.price_paisa,rate.id,component_snapshot)
  ON CONFLICT(bill_id,panel_service_id) DO NOTHING RETURNING id INTO selection_uuid;
  IF selection_uuid IS NULL THEN
    SELECT id INTO selection_uuid FROM public.bill_panel_selections WHERE bill_id=bill_uuid AND panel_service_id=svc.id;
  ELSE
    INSERT INTO public.bill_panel_components(bill_panel_selection_id,bill_item_id,test_id,display_order)
    SELECT selection_uuid,bi.id,bi.test_id,(x->>'display_order')::INT
    FROM jsonb_array_elements(component_snapshot)x
    JOIN public.bill_items bi ON bi.bill_id=bill_uuid AND bi.test_id=(x->>'test_id')::UUID;
  END IF;
  RETURN response||jsonb_build_object('panel_selection_id',selection_uuid,'panel_service_id',svc.id,'panel_code',svc.code,'components_recorded',cardinality(items));
END $$;

GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_panel_service TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_public_report_token(
  p_report_id UUID,p_token_hash VARCHAR(128),p_expiry_days INT DEFAULT 30,p_public_url_base TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE report public.diagnostic_reports%ROWTYPE; existing public.public_report_tokens%ROWTYPE;
  patient public.patients%ROWTYPE; ordering public.clinical_orders%ROWTYPE;
  token_id UUID; v_expires_at TIMESTAMPTZ; raw_token TEXT; delivery_host TEXT;
  phone TEXT; sms_id UUID; v_sms_body TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE='42501'; END IF;
  IF NOT(public.has_permission('can_sign_reports') OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;
  SELECT * INTO report FROM public.diagnostic_reports WHERE id=p_report_id FOR UPDATE;
  IF NOT FOUND OR report.status NOT IN('SignedOff','Amended') THEN
    RAISE EXCEPTION 'A signed or amended report is required.' USING ERRCODE='22023';
  END IF;
  UPDATE public.public_report_tokens token SET is_active=FALSE,updated_at=NOW()
    WHERE token.diagnostic_report_id=p_report_id AND token.is_active
      AND (token.revoked_at IS NOT NULL OR token.expires_at<=NOW());
  SELECT * INTO existing FROM public.public_report_tokens
    WHERE diagnostic_report_id=p_report_id AND is_active AND revoked_at IS NULL AND expires_at>NOW()
    ORDER BY created_at LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('success',TRUE,'token_id',existing.id,'expires_at',existing.expires_at,
      'report_number',report.report_number,'sms_queued',FALSE,'sms_status','Existing report link retained',
      'idempotency_replay',TRUE);
  END IF;
  raw_token:=substring(p_public_url_base FROM '/r/([A-Za-z0-9_-]+)$');
  delivery_host:=substring(p_public_url_base FROM '^https://(lis|dashboard)[.]bimalpathology[.]com[.]np/r/');
  IF delivery_host IS NULL OR raw_token IS NULL OR length(raw_token) NOT BETWEEN 32 AND 256
     OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
     OR encode(extensions.digest(convert_to(raw_token,'UTF8'),'sha256'),'hex')<>p_token_hash THEN
    RAISE EXCEPTION 'A valid approved production report token is required.' USING ERRCODE='22023';
  END IF;
  v_expires_at:=NOW()+(greatest(1,least(COALESCE(p_expiry_days,30),90))||' days')::INTERVAL;
  INSERT INTO public.public_report_tokens(diagnostic_report_id,token_hash,expires_at,created_by,is_active)
    VALUES(p_report_id,p_token_hash,v_expires_at,auth.uid(),TRUE) RETURNING id INTO token_id;
  INSERT INTO public.report_secure_link_presentations(report_token_id,public_url)
    VALUES(token_id,p_public_url_base);
  IF delivery_host='dashboard' THEN
    INSERT INTO public.report_pdf_delivery_intents(diagnostic_report_id,report_token_id,public_url)
      VALUES(p_report_id,token_id,p_public_url_base);
  ELSE
    SELECT * INTO patient FROM public.patients WHERE id=report.patient_id;
    SELECT * INTO ordering FROM public.clinical_orders WHERE id=report.order_id;
    phone:=regexp_replace(COALESCE(patient.mobile,''),'[^0-9]','','g');
    IF phone LIKE '977%' AND length(phone)=13 THEN phone:=substring(phone FROM 4); END IF;
    IF phone~'^(97|98)[0-9]{8}$' THEN
      v_sms_body := public.build_single_credit_nepali_sms(report.order_id, report.id);
      INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id)
      VALUES('ReportReady',phone,patient.full_name,
        v_sms_body,
        'Pending','REPORT_READY:'||report.id::TEXT||':'||report.version::TEXT,report.id)
      ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
    END IF;
  END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
    VALUES(auth.uid(),'Authorized Signatory','PUBLIC_REPORT_TOKEN_CREATED','DiagnosticReport',report.report_number,
      jsonb_build_object('report_id',p_report_id,'token_id',token_id,'expires_at',v_expires_at,
        'delivery_host',delivery_host||'.bimalpathology.com.np',
        'delivery_state',CASE WHEN delivery_host='dashboard' THEN 'AwaitingArtifact' ELSE 'LegacyImmediate' END));
  RETURN jsonb_build_object('success',TRUE,'token_id',token_id,'expires_at',v_expires_at,
    'report_number',report.report_number,'sms_queued',sms_id IS NOT NULL,
    'sms_status',CASE WHEN delivery_host='dashboard' THEN 'Awaiting authoritative PDF'
      WHEN sms_id IS NOT NULL THEN 'Report notification queued' ELSE 'SMS skipped: invalid or missing Nepal mobile' END,
    'idempotency_replay',FALSE);
END $$;

GRANT EXECUTE ON FUNCTION public.create_public_report_token TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.delete_unused_patient(p_patient_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_patient public.patients%ROWTYPE; v_has_history BOOLEAN;
BEGIN
  IF NOT public.has_permission('can_edit_patient') THEN RAISE EXCEPTION 'Not authorized to delete patients.' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_patient FROM public.patients WHERE id=p_patient_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found.' USING ERRCODE='P0002'; END IF;
  SELECT EXISTS(SELECT 1 FROM public.bills WHERE patient_id=p_patient_id) OR EXISTS(SELECT 1 FROM public.clinical_orders WHERE patient_id=p_patient_id) OR EXISTS(SELECT 1 FROM public.samples WHERE patient_id=p_patient_id) OR EXISTS(SELECT 1 FROM public.diagnostic_reports WHERE patient_id=p_patient_id) OR EXISTS(SELECT 1 FROM public.outsource_samples WHERE patient_id=p_patient_id) INTO v_has_history;
  IF v_has_history THEN RAISE EXCEPTION 'This patient has transactional history and cannot be deleted. Archive the patient instead.' USING ERRCODE='23503'; END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data) VALUES(auth.uid(),public.patient_actor_name(),'PATIENT_HARD_DELETED','Patient',p_patient_id::TEXT,jsonb_build_object('uhid',v_patient.uhid));
  DELETE FROM public.patients WHERE id=p_patient_id;
  RETURN jsonb_build_object('deleted',TRUE,'patient_id',p_patient_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_unused_patient TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.derive_order_reporting_state(p_order_id UUID) RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT CASE WHEN count(*)=0 THEN 'Pending' WHEN bool_and(lifecycle_state IN ('Signed','Amended')) THEN 'Fully Reported' WHEN bool_or(lifecycle_state IN ('Signed','Amended')) THEN 'Partially Reported' WHEN bool_or(lifecycle_state IN ('InProgress','ReadyToSign')) THEN 'In Progress' ELSE 'Pending' END FROM public.clinical_report_groups WHERE order_id=p_order_id
$$;

GRANT EXECUTE ON FUNCTION public.derive_order_reporting_state TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.diagnose_report_notification_rollback(
    p_report_id UUID,
    p_actor_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_raw_token TEXT;
    v_token_hash TEXT;
    v_result JSONB;
BEGIN
    IF auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'Service role required.' USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE id = p_actor_id) THEN
        RAISE EXCEPTION 'Diagnostic actor does not exist.' USING ERRCODE = '22023';
    END IF;

    -- Reproduce the original authenticated caller context without retaining it
    -- beyond this request transaction.
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', p_actor_id, 'role', 'authenticated')::TEXT,
        TRUE
    );

    v_raw_token := encode(extensions.gen_random_bytes(32), 'hex');
    v_token_hash := encode(
        extensions.digest(convert_to(v_raw_token, 'UTF8'), 'sha256'),
        'hex'
    );

    BEGIN
        v_result := public.create_public_report_token(
            p_report_id,
            v_token_hash,
            30,
            'https://lis.bimalpathology.com.np/r/' || v_raw_token
        );

        RAISE EXCEPTION 'BPSG_DIAGNOSTIC_ROLLBACK'
            USING ERRCODE = 'P0001', DETAIL = v_result::TEXT;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'BPSG_DIAGNOSTIC_ROLLBACK' THEN
            RETURN jsonb_build_object(
                'branch_succeeded', TRUE,
                'rolled_back', TRUE
            );
        END IF;

        RETURN jsonb_build_object(
            'branch_succeeded', FALSE,
            'rolled_back', TRUE,
            'sqlstate', SQLSTATE,
            'error', left(SQLERRM, 500)
        );
    END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.diagnose_report_notification_rollback TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.enforce_critical_acknowledgement_authority()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_was_acknowledged BOOLEAN := FALSE;
    v_material_change BOOLEAN := FALSE;
    v_not_before TIMESTAMPTZ := '-infinity'::TIMESTAMPTZ;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_was_acknowledged := COALESCE(OLD.critical_acknowledged, FALSE);
        v_not_before := COALESCE(OLD.updated_at, '-infinity'::TIMESTAMPTZ);
        v_material_change :=
            NEW.numeric_value IS DISTINCT FROM OLD.numeric_value
            OR NEW.text_value IS DISTINCT FROM OLD.text_value
            OR NEW.display_value IS DISTINCT FROM OLD.display_value
            OR NEW.flag IS DISTINCT FROM OLD.flag
            OR NEW.is_critical IS DISTINCT FROM OLD.is_critical
            OR NEW.unit IS DISTINCT FROM OLD.unit
            OR NEW.normal_range_text IS DISTINCT FROM OLD.normal_range_text
            OR NEW.normal_min IS DISTINCT FROM OLD.normal_min
            OR NEW.normal_max IS DISTINCT FROM OLD.normal_max
            OR NEW.critical_low IS DISTINCT FROM OLD.critical_low
            OR NEW.critical_high IS DISTINCT FROM OLD.critical_high;

        IF NOT COALESCE(NEW.is_critical, FALSE)
           AND NEW.flag NOT IN ('CriticalLow', 'CriticalHigh') THEN
            NEW.critical_acknowledged := FALSE;
            NEW.critical_acknowledged_by := NULL;
            NEW.critical_acknowledged_at := NULL;
            RETURN NEW;
        END IF;

        IF v_was_acknowledged
           AND COALESCE(NEW.critical_acknowledged, FALSE)
           AND NOT v_material_change THEN
            NEW.critical_acknowledged_by := OLD.critical_acknowledged_by;
            NEW.critical_acknowledged_at := OLD.critical_acknowledged_at;
            RETURN NEW;
        END IF;
    END IF;

    IF COALESCE(NEW.critical_acknowledged, FALSE)
       AND (COALESCE(NEW.is_critical, FALSE)
            OR NEW.flag IN ('CriticalLow', 'CriticalHigh')) THEN
        IF NOT public.has_permission('can_acknowledge_critical') THEN
            RAISE EXCEPTION 'Critical acknowledgement permission is required.'
                USING ERRCODE = '42501';
        END IF;
        IF NEW.critical_acknowledged_by IS DISTINCT FROM auth.uid()
           OR NEW.critical_acknowledged_at IS NULL THEN
            RAISE EXCEPTION 'Critical acknowledgement actor metadata is invalid.'
                USING ERRCODE = '23514';
        END IF;
        IF NOT EXISTS (
            SELECT 1
            FROM public.audit_logs a
            WHERE a.action = 'CRITICAL_VALUE_ACKNOWLEDGED'
              AND a.entity_type = 'ClinicalOrderItem'
              AND a.entity_id = NEW.order_item_id::TEXT
              AND a.user_id = auth.uid()
              AND a.timestamp >= v_not_before
              AND a.timestamp <= clock_timestamp()
        ) THEN
            RAISE EXCEPTION 'Document the critical notification before saving its acknowledgement.'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.enforce_critical_acknowledgement_authority TO authenticated, service_role;

CREATE FUNCTION public.enforce_report_pdf_artifact_immutability()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'Report PDF artifacts are append-only.' USING ERRCODE='55000';
  END IF;
  IF OLD.generation_status='Ready' THEN
    IF NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION 'Ready report PDF artifacts are immutable.' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.diagnostic_report_id IS DISTINCT FROM OLD.diagnostic_report_id
     OR NEW.report_version IS DISTINCT FROM OLD.report_version
     OR NEW.report_integrity_hash IS DISTINCT FROM OLD.report_integrity_hash
     OR NEW.frozen_snapshot_sha256 IS DISTINCT FROM OLD.frozen_snapshot_sha256
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Signed report artifact identity is immutable.' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.enforce_report_pdf_artifact_immutability TO authenticated, service_role;

CREATE FUNCTION public.enqueue_missing_report_pdf_artifacts(p_limit INT DEFAULT 25)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE inserted_count INT;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'Invalid backfill limit.' USING ERRCODE='22023'; END IF;
  WITH candidates AS (
    SELECT r.* FROM public.diagnostic_reports r
    WHERE r.status IN('SignedOff','Amended') AND public.report_artifact_public_url(r.id) IS NOT NULL
      AND NOT EXISTS(SELECT 1 FROM public.report_pdf_artifacts a WHERE a.diagnostic_report_id=r.id AND a.report_version=r.version)
    ORDER BY r.signed_at,r.id LIMIT p_limit
  ) INSERT INTO public.report_pdf_artifacts(diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256)
    SELECT id,version,integrity_hash,encode(extensions.digest(clinical_snapshot_json::TEXT,'sha256'),'hex') FROM candidates
    ON CONFLICT(diagnostic_report_id,report_version) DO NOTHING;
  GET DIAGNOSTICS inserted_count=ROW_COUNT;
  RETURN inserted_count;
END $$;

GRANT EXECUTE ON FUNCTION public.enqueue_missing_report_pdf_artifacts TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ensure_bill_collection_traceability(p_bill_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE b public.bills%ROWTYPE; o public.clinical_orders%ROWTYPE; x RECORD; s_id UUID; key TEXT; sample_map JSONB:='{}'; actor_name TEXT; created_samples INT:=0; created_items INT:=0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  SELECT * INTO b FROM public.bills WHERE id=p_bill_id FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'Bill not found.' USING ERRCODE='P0002'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.bill_items bi JOIN public.tests t ON t.id=bi.test_id WHERE bi.bill_id=b.id AND (t.collection_required OR t.reporting_type IN ('InHouse','OutsourceWithBimalReport'))) THEN RETURN jsonb_build_object('order_id',NULL,'order_number',NULL,'samples_created',0,'items_created',0); END IF;
  SELECT * INTO o FROM public.clinical_orders WHERE bill_id=b.id ORDER BY created_at LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN INSERT INTO public.clinical_orders(order_number,bill_id,patient_id,order_date_ad,order_date_bs,status) VALUES('ALLOCATE-BPDC',b.id,b.patient_id,CURRENT_DATE,to_char(CURRENT_DATE,'YYYY-MM-DD'),'Registered') RETURNING * INTO o; END IF;
  SELECT COALESCE(full_name,'Billing Staff') INTO actor_name FROM public.user_profiles WHERE id=auth.uid();
  FOR x IN SELECT bi.id bill_item_id,t.* FROM public.bill_items bi JOIN public.tests t ON t.id=bi.test_id WHERE bi.bill_id=b.id AND (t.collection_required OR t.reporting_type IN ('InHouse','OutsourceWithBimalReport')) ORDER BY bi.created_at LOOP
    SELECT sample_id INTO s_id FROM public.clinical_order_items WHERE bill_item_id=x.bill_item_id;
    IF s_id IS NULL THEN
      key:=COALESCE(NULLIF(btrim(x.sample_type),''),'Blood')||'::'||COALESCE(NULLIF(btrim(x.container),''),'EDTA');
      IF sample_map ? key THEN s_id:=(sample_map->>key)::UUID; ELSE
        SELECT id INTO s_id FROM public.samples WHERE order_id=o.id AND specimen_type=COALESCE(NULLIF(btrim(x.sample_type),''),'Blood') AND container_type=COALESCE(NULLIF(btrim(x.container),''),'EDTA') ORDER BY created_at LIMIT 1;
        IF s_id IS NULL THEN INSERT INTO public.samples(barcode,order_id,patient_id,specimen_type,container_type,status) VALUES('SMP-'||to_char(CURRENT_DATE,'YYYY')||'-'||lpad(nextval('sample_seq')::TEXT,5,'0'),o.id,b.patient_id,COALESCE(NULLIF(btrim(x.sample_type),''),'Blood'),COALESCE(NULLIF(btrim(x.container),''),'EDTA'),'Pending') RETURNING id INTO s_id; created_samples:=created_samples+1; END IF;
        sample_map:=jsonb_set(sample_map,ARRAY[key],to_jsonb(s_id::TEXT));
      END IF;
      INSERT INTO public.clinical_order_items(order_id,bill_item_id,test_id,test_name,department,reporting_type,outsource_lab_name,specimen_type,container_type,status,sample_id,workflow_type,clinical_reporting_enabled,collection_required)
      VALUES(o.id,x.bill_item_id,x.id,x.name,x.department,x.reporting_type,x.outsource_lab_name,COALESCE(NULLIF(btrim(x.sample_type),''),'Blood'),COALESCE(NULLIF(btrim(x.container),''),'EDTA'),'Pending',s_id,x.workflow_type,TRUE,COALESCE(x.collection_required,TRUE)); created_items:=created_items+1;
    ELSE UPDATE public.clinical_order_items SET workflow_type=x.workflow_type,clinical_reporting_enabled=TRUE,collection_required=COALESCE(x.collection_required,TRUE) WHERE bill_item_id=x.bill_item_id; END IF;
  END LOOP;
  INSERT INTO public.sample_lifecycle_events(sample_id,from_status,to_status,reason,performed_by,performed_by_name,timestamp)
  SELECT s.id,s.status,s.status,'Sample accession created during bill finalization',auth.uid(),COALESCE(actor_name,'Billing Staff'),s.created_at FROM public.samples s WHERE s.order_id=o.id AND NOT EXISTS(SELECT 1 FROM public.sample_lifecycle_events e WHERE e.sample_id=s.id);
  RETURN jsonb_build_object('order_id',o.id,'order_number',o.order_number,'samples_created',created_samples,'items_created',created_items);
END $$;

GRANT EXECUTE ON FUNCTION public.ensure_bill_collection_traceability TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ensure_catalogue_test_readiness()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp AS $$
DECLARE v_state public.catalogue_readiness_state_enum;
BEGIN
  v_state:=CASE
    WHEN NEW.lifecycle_status='Archived' OR NOT NEW.is_active THEN 'Draft'::public.catalogue_readiness_state_enum
    WHEN NEW.reporting_type='NoReporting' OR NEW.workflow_type='NoClinicalReport' THEN 'Approved'::public.catalogue_readiness_state_enum
    WHEN NOT NEW.workflow_supported THEN 'NeedsConfiguration'::public.catalogue_readiness_state_enum
    ELSE 'Approved'::public.catalogue_readiness_state_enum
  END;
  INSERT INTO public.catalogue_service_readiness(test_id,state,decision_reason,approved_at)
  VALUES(NEW.id,v_state,
    CASE WHEN v_state='Approved' THEN 'Ready by default; Lab Technician exception control applies.'
         WHEN v_state='NeedsConfiguration' THEN 'Reporting workflow is not currently supported.'
         ELSE 'Inactive catalogue item.' END,
    CASE WHEN v_state='Approved' THEN now() END)
  ON CONFLICT(test_id) DO NOTHING;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.ensure_catalogue_test_readiness TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.evaluate_governed_formula(p_formula_key TEXT,p_inputs JSONB)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=public,pg_temp AS $$
DECLARE a NUMERIC;b NUMERIC;c NUMERIC;sex_factor NUMERIC;kappa NUMERIC;alpha NUMERIC;result NUMERIC;
BEGIN
 IF jsonb_typeof(p_inputs)<>'object' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_INVALID_INPUT'; END IF;
 CASE p_formula_key
  WHEN 'CBC_MCV' THEN a:=NULLIF(p_inputs->>'HCT','')::NUMERIC;b:=NULLIF(p_inputs->>'RBC','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a*10/b;
  WHEN 'CBC_MCH' THEN a:=NULLIF(p_inputs->>'HB','')::NUMERIC;b:=NULLIF(p_inputs->>'RBC','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a*10/b;
  WHEN 'CBC_MCHC' THEN a:=NULLIF(p_inputs->>'HB','')::NUMERIC;b:=NULLIF(p_inputs->>'HCT','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a*100/b;
  WHEN 'ABS_ANC' THEN result:=(NULLIF(p_inputs->>'TLC','')::NUMERIC)*(NULLIF(p_inputs->>'NEUT','')::NUMERIC)/100;
  WHEN 'ABS_ALC' THEN result:=(NULLIF(p_inputs->>'TLC','')::NUMERIC)*(NULLIF(p_inputs->>'LYMPH','')::NUMERIC)/100;
  WHEN 'ABS_AEC' THEN result:=(NULLIF(p_inputs->>'TLC','')::NUMERIC)*(NULLIF(p_inputs->>'EOS','')::NUMERIC)/100;
  WHEN 'ABS_AMC' THEN result:=(NULLIF(p_inputs->>'TLC','')::NUMERIC)*(NULLIF(p_inputs->>'MONO','')::NUMERIC)/100;
  WHEN 'ABS_ABC' THEN result:=(NULLIF(p_inputs->>'TLC','')::NUMERIC)*(NULLIF(p_inputs->>'BASO','')::NUMERIC)/100;
  WHEN 'CBC_ANC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'NEUT','')::NUMERIC)/100;
  WHEN 'CBC_ALC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'LYMPH','')::NUMERIC)/100;
  WHEN 'CBC_AEC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'EOS','')::NUMERIC)/100;
  WHEN 'CBC_AMC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'MONO','')::NUMERIC)/100;
  WHEN 'CBC_ABC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'BASO','')::NUMERIC)/100;
  WHEN 'CBC_NLR' THEN a:=NULLIF(p_inputs->>'NEUT','')::NUMERIC;b:=NULLIF(p_inputs->>'LYMPH','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a/b;
  WHEN 'BILIRUBIN_INDIRECT' THEN a:=NULLIF(p_inputs->>'TOTAL','')::NUMERIC;b:=NULLIF(p_inputs->>'DIRECT','')::NUMERIC;IF b>a THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_DIRECT_BILIRUBIN_EXCEEDS_TOTAL';END IF;result:=a-b;
  WHEN 'GLOBULIN' THEN result:=NULLIF(p_inputs->>'TOTAL_PROTEIN','')::NUMERIC-NULLIF(p_inputs->>'ALBUMIN','')::NUMERIC;
  WHEN 'AG_RATIO' THEN a:=NULLIF(p_inputs->>'ALBUMIN','')::NUMERIC;b:=NULLIF(p_inputs->>'GLOBULIN','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a/b;
  WHEN 'VLDL' THEN result:=NULLIF(p_inputs->>'TRIGLYCERIDES','')::NUMERIC/5;
  WHEN 'CHOL_HDL_RATIO' THEN a:=NULLIF(p_inputs->>'CHOLESTEROL','')::NUMERIC;b:=NULLIF(p_inputs->>'HDL','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a/b;
  WHEN 'NON_HDL' THEN result:=NULLIF(p_inputs->>'CHOLESTEROL','')::NUMERIC-NULLIF(p_inputs->>'HDL','')::NUMERIC;
  WHEN 'INR' THEN a:=NULLIF(p_inputs->>'PATIENT_PT','')::NUMERIC;b:=NULLIF(p_inputs->>'MEAN_NORMAL_PT','')::NUMERIC;c:=NULLIF(p_inputs->>'ISI','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=power(a/b,c);
  WHEN 'EGFR_CKD_EPI_2021' THEN
    a:=NULLIF(p_inputs->>'CREATININE','')::NUMERIC;b:=NULLIF(p_inputs->>'AGE_YEARS','')::NUMERIC;sex_factor:=NULLIF(p_inputs->>'SEX_FEMALE','')::NUMERIC;
    IF sex_factor NOT IN(0,1) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_UNSUPPORTED_DEMOGRAPHIC';END IF;
    kappa:=CASE WHEN sex_factor=1 THEN 0.7 ELSE 0.9 END;alpha:=CASE WHEN sex_factor=1 THEN -0.241 ELSE -0.302 END;
    result:=142*power(least(a/kappa,1),alpha)*power(greatest(a/kappa,1),-1.200)*power(0.9938,b)*CASE WHEN sex_factor=1 THEN 1.012 ELSE 1 END;
  ELSE RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_FORMULA_NOT_IMPLEMENTED';
 END CASE;
 IF result IS NULL THEN RAISE EXCEPTION USING ERRCODE='22004',MESSAGE='CALCULATION_NULL_INPUT';END IF;
 IF abs(result)>1e30 THEN RAISE EXCEPTION USING ERRCODE='22003',MESSAGE='CALCULATION_OVERFLOW';END IF;
 RETURN result;
EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_INVALID_INPUT';
END $$;

GRANT EXECUTE ON FUNCTION public.evaluate_governed_formula TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.finalize_hmis_report(p_report_id uuid,p_snapshot jsonb,p_revision_reason text DEFAULT NULL) RETURNS public.hmis_monthly_report_versions LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
DECLARE r public.hmis_monthly_reports; v public.hmis_monthly_report_versions; n int; h text;
BEGIN
 IF NOT public.has_permission('can_finalize_hmis_reports') THEN RAISE EXCEPTION 'HMIS finalize permission required' USING ERRCODE='42501'; END IF;
 SELECT * INTO r FROM public.hmis_monthly_reports WHERE id=p_report_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'HMIS report not found'; END IF;
 IF r.current_version>0 AND nullif(trim(p_revision_reason),'') IS NULL THEN RAISE EXCEPTION 'Revision reason required'; END IF;
 IF p_snapshot::text ~* '"(patientName|patientMobile|patientUhid|patientAddress|mobile|uhid|resultValues|clinicalSnapshot)"\s*:' THEN RAISE EXCEPTION 'Patient-identifiable or clinical-detail keys are forbidden in HMIS snapshots'; END IF;
 n:=r.current_version+1; h:=encode(extensions.digest(convert_to(p_snapshot::text,'UTF8'),'sha256'),'hex');
 IF COALESCE(p_snapshot#>>'{identities,prepared,id}','')='' THEN RAISE EXCEPTION 'Prepared By must be selected explicitly'; END IF;
 INSERT INTO public.hmis_monthly_report_versions(report_id,version,snapshot_json,sha256,generated_by,finalized_by,parent_version,revision_reason) VALUES(p_report_id,n,p_snapshot,h,auth.uid(),auth.uid(),CASE WHEN n>1 THEN n-1 ELSE NULL END,p_revision_reason) RETURNING * INTO v;
 UPDATE public.hmis_monthly_reports SET status='Finalized',current_version=n,finalized_by=auth.uid(),finalized_at=v.finalized_at,updated_at=now() WHERE id=p_report_id;
 RETURN v;
END $$;

GRANT EXECUTE ON FUNCTION public.finalize_hmis_report TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.format_nepali_amount(p_paisa BIGINT)
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public, pg_temp
IMMUTABLE
AS $$
DECLARE
  v_rupees BIGINT;
  v_rem BIGINT;
BEGIN
  IF p_paisa IS NULL OR p_paisa <= 0 THEN RETURN '०'; END IF;
  v_rupees := p_paisa / 100;
  v_rem := p_paisa % 100;
  IF v_rem = 0 THEN
    RETURN public.format_nepali_digits(v_rupees::TEXT);
  ELSIF v_rem % 10 = 0 THEN
    RETURN public.format_nepali_digits(v_rupees::TEXT) || '.' || public.format_nepali_digits((v_rem / 10)::TEXT);
  ELSE
    RETURN public.format_nepali_digits(v_rupees::TEXT) || '.' || public.format_nepali_digits(lpad(v_rem::TEXT, 2, '0'));
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.format_nepali_amount TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.format_nepali_digits(p_val TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public, pg_temp
IMMUTABLE
AS $$
BEGIN
  IF p_val IS NULL THEN RETURN ''; END IF;
  RETURN translate(p_val, '0123456789', '०१२३४५६७८९');
END;
$$;

GRANT EXECUTE ON FUNCTION public.format_nepali_digits TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.freeze_order_item_execution_route() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE;
BEGIN
 SELECT * INTO t FROM public.tests WHERE id=NEW.test_id;
 NEW.execution_route:=t.execution_route;
 NEW.reference_laboratory_id:=t.default_reference_laboratory_id;
 NEW.outsource_state:=CASE WHEN t.execution_route='OUTSOURCE' THEN 'AwaitingDispatch'::public.outsource_item_state_enum ELSE NULL END;
 RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.freeze_order_item_execution_route TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.freeze_report_group_execution_route() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 SELECT execution_route,reference_laboratory_id INTO NEW.execution_route,NEW.frozen_reference_laboratory_id
 FROM public.clinical_order_items WHERE id=NEW.order_item_id;
 RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.freeze_report_group_execution_route TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.freeze_sample_requirement_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN NEW.specimen_requirement_key:=coalesce(nullif(NEW.specimen_requirement_key,''),upper(regexp_replace(trim(coalesce(NEW.specimen_type,'UNSPECIFIED'))||'|'||trim(coalesce(NEW.container_type,'UNSPECIFIED')),'[^A-Za-z0-9]+','_','g'))); RETURN NEW; END $$;

GRANT EXECUTE ON FUNCTION public.freeze_sample_requirement_identity TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.freeze_test_delivery_configuration() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.report_group_key IS NULL OR NEW.report_group_key='' THEN NEW.report_group_key:='general_laboratory'; END IF;
 IF NEW.report_group_title IS NULL OR NEW.report_group_title='' THEN NEW.report_group_title:='General Laboratory'; END IF;
 IF NEW.report_section IS NULL OR NEW.report_section='' THEN NEW.report_section:=coalesce(nullif(NEW.department,''),nullif(NEW.category,''),'Laboratory'); END IF;
 NEW.specimen_requirement_key:=CASE WHEN NOT coalesce(NEW.collection_required,NEW.requires_sample_tracking,false) THEN 'NO_SAMPLE' ELSE upper(regexp_replace(trim(coalesce(NEW.sample_type,'UNSPECIFIED'))||'|'||trim(coalesce(NEW.container,'UNSPECIFIED')),'[^A-Za-z0-9]+','_','g')) END;
 RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.freeze_test_delivery_configuration TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_active_pt_inr_config()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_config jsonb;
BEGIN
    SELECT row_to_json(c.*)::jsonb INTO v_config
    FROM public.pt_inr_reagent_configs c
    WHERE c.is_active = TRUE
      AND (c.effective_to IS NULL OR c.effective_to > NOW())
    ORDER BY c.effective_from DESC, c.created_at DESC
    LIMIT 1;

    RETURN v_config;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_active_pt_inr_config TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_catalogue_panel_components(p_panel_test_id UUID)
RETURNS TABLE(
  component_test_id UUID,
  component_code TEXT,
  component_name TEXT,
  component_unit TEXT,
  component_specimen TEXT,
  component_role TEXT,
  display_order INT,
  is_required BOOLEAN
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT 
    t.id AS component_test_id,
    t.code::TEXT AS component_code,
    t.name::TEXT AS component_name,
    COALESCE(t.unit, '')::TEXT AS component_unit,
    COALESCE(t.sample_type, 'Specimen')::TEXT AS component_specimen,
    COALESCE(cpc.component_role, 'Measured')::TEXT AS component_role,
    cpc.display_order,
    COALESCE(cpc.is_required, TRUE) AS is_required
  FROM public.catalogue_panel_components cpc
  JOIN public.tests t ON t.id = cpc.component_test_id
  WHERE cpc.panel_test_id = p_panel_test_id
  ORDER BY cpc.display_order ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_catalogue_panel_components TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_dashboard_collection_summary()
RETURNS TABLE (
    today_collection_paisa BIGINT,
    month_collection_paisa BIGINT,
    total_collection_paisa BIGINT,
    today_count INT,
    month_count INT,
    total_count INT,
    month_label TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today_start TIMESTAMPTZ;
    v_month_start TIMESTAMPTZ;
    v_month_name TEXT;
BEGIN
    IF NOT public.has_permission('can_view_financials') THEN
        RAISE EXCEPTION 'Access Denied: User lacks can_view_financials permission' USING ERRCODE = '42501';
    END IF;
    v_today_start := date_trunc('day', now() AT TIME ZONE 'Asia/Kathmandu') AT TIME ZONE 'Asia/Kathmandu';
    v_month_start := date_trunc('month', now() AT TIME ZONE 'Asia/Kathmandu') AT TIME ZONE 'Asia/Kathmandu';
    v_month_name := to_char(now() AT TIME ZONE 'Asia/Kathmandu', 'FMMonth YYYY');
    RETURN QUERY
    SELECT
        COALESCE(sum(CASE WHEN pt.created_at >= v_today_start THEN pt.amount_paisa ELSE 0 END), 0)::BIGINT,
        COALESCE(sum(CASE WHEN pt.created_at >= v_month_start THEN pt.amount_paisa ELSE 0 END), 0)::BIGINT,
        COALESCE(sum(pt.amount_paisa), 0)::BIGINT,
        COALESCE(count(CASE WHEN pt.created_at >= v_today_start THEN 1 END), 0)::INT,
        COALESCE(count(CASE WHEN pt.created_at >= v_month_start THEN 1 END), 0)::INT,
        COALESCE(count(*), 0)::INT,
        v_month_name
    FROM public.payment_transactions pt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_dashboard_collection_summary TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_dashboard_operational_summary()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today_date DATE := (now() AT TIME ZONE 'Asia/Kathmandu')::date;
    v_departments JSONB;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.has_permission('can_view_financials') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('dept', department, 'count', item_count)
               ORDER BY department), '[]'::jsonb)
      INTO v_departments
      FROM (
        SELECT COALESCE(NULLIF(btrim(department), ''), 'Unassigned') AS department,
               count(*)::INT AS item_count
          FROM public.clinical_order_items
         WHERE status IN ('Pending', 'SampleCollected', 'SampleReceived', 'ResultDrafted')
         GROUP BY 1
      ) workload;

    RETURN jsonb_build_object(
        'today_patients', (SELECT count(*) FROM public.patients WHERE (created_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'today_invoices', (SELECT count(*) FROM public.bills WHERE (created_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'today_collection_paisa', (SELECT COALESCE(sum(amount_paisa), 0) FROM public.payment_transactions WHERE (created_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'outstanding_due_paisa', (SELECT COALESCE(sum(due_amount_paisa), 0) FROM public.bills WHERE due_amount_paisa > 0),
        'pending_samples', (SELECT count(*) FROM public.samples WHERE status = 'Pending'),
        'received_samples', (SELECT count(*) FROM public.samples WHERE status = 'Received'),
        'rejected_samples', (SELECT count(*) FROM public.samples WHERE status = 'Rejected'),
        'pending_results', (SELECT count(*) FROM public.clinical_order_items WHERE status IN ('SampleReceived', 'ResultDrafted')),
        'awaiting_verification', (
            SELECT count(DISTINCT coi.id)
            FROM public.clinical_order_items coi
            WHERE coi.status NOT IN ('Verified', 'SignedOff')
              AND EXISTS (
                SELECT 1
                FROM public.test_results tr
                WHERE tr.order_item_id = coi.id
                  AND tr.status = 'SubmittedForVerification'
              )
        ),
        'signed_reports', (SELECT count(*) FROM public.diagnostic_reports WHERE status = 'SignedOff' AND signed_at IS NOT NULL AND (signed_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'signed_reports_today', (SELECT count(*) FROM public.diagnostic_reports WHERE status = 'SignedOff' AND signed_at IS NOT NULL AND (signed_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'total_signed_reports', (SELECT count(*) FROM public.diagnostic_reports WHERE status = 'SignedOff'),
        'critical_unacknowledged', (SELECT count(*) FROM public.test_results WHERE is_critical = TRUE AND critical_acknowledged = FALSE),
        'department_workload', v_departments
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_dashboard_operational_summary TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_my_patient_profile() RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_identity public.patient_app_identities%ROWTYPE;
  v_patient_name TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_identity
  FROM public.patient_app_identities
  WHERE auth_user_id = v_uid;

  IF NOT FOUND THEN
    RETURN public.sync_my_patient_identity();
  END IF;

  IF v_identity.status = 'LINKED' AND v_identity.patient_id IS NOT NULL THEN
    SELECT full_name INTO v_patient_name
    FROM public.patients
    WHERE id = v_identity.patient_id;
  END IF;

  RETURN jsonb_build_object(
    'identity_id', v_identity.id,
    'auth_user_id', v_uid,
    'mobile', v_identity.phone,
    'status', v_identity.status,
    'match_count', v_identity.match_count,
    'patient_id', CASE WHEN v_identity.status = 'LINKED' THEN v_identity.patient_id ELSE NULL END,
    'linked_patient_name', v_patient_name,
    'linked_at', v_identity.linked_at,
    'last_synced_at', v_identity.last_synced_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_patient_profile TO authenticated, service_role;

CREATE FUNCTION public.get_report_pdf_delivery_acceptance_candidate()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE candidate RECORD; public_url TEXT;
BEGIN
  IF NOT public.is_report_artifact_worker() THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;
  SELECT a.*,r.report_number INTO candidate
  FROM public.report_pdf_artifacts a
  JOIN public.diagnostic_reports r ON r.id=a.diagnostic_report_id
  WHERE a.generation_status='Ready' AND r.status IN('SignedOff','Amended')
    AND a.report_version=r.version AND a.report_integrity_hash=r.integrity_hash
    AND encode(extensions.digest(r.clinical_snapshot_json::TEXT,'sha256'),'hex')=a.frozen_snapshot_sha256
  ORDER BY a.generated_at DESC,a.id DESC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('available',FALSE); END IF;
  public_url:=public.report_artifact_public_url(candidate.diagnostic_report_id);
  IF public_url IS NULL THEN RETURN jsonb_build_object('available',FALSE); END IF;
  RETURN jsonb_build_object('available',TRUE,'public_url',public_url,
    'report_number',candidate.report_number,'report_version',candidate.report_version,
    'pdf_sha256',candidate.pdf_sha256,'byte_size',candidate.byte_size);
END $$;

GRANT EXECUTE ON FUNCTION public.get_report_pdf_delivery_acceptance_candidate TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_report_secure_link_status(p_report_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report public.diagnostic_reports%ROWTYPE;
    v_token public.public_report_tokens%ROWTYPE;
    v_url TEXT;
    v_raw_token TEXT;
    v_state TEXT := 'Missing';
    v_first_token_at TIMESTAMPTZ;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT (public.has_permission('can_print_reports') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_report
    FROM public.diagnostic_reports
    WHERE id = p_report_id;

    IF NOT FOUND OR v_report.status NOT IN ('SignedOff', 'Amended') THEN
        RAISE EXCEPTION 'A signed or amended report is required.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_token
    FROM public.public_report_tokens
    WHERE diagnostic_report_id = p_report_id
    ORDER BY
      CASE WHEN is_active AND revoked_at IS NULL AND expires_at > NOW() THEN 0
           WHEN revoked_at IS NOT NULL THEN 1
           WHEN expires_at <= NOW() THEN 2 ELSE 3 END,
      created_at DESC
    LIMIT 1;

    IF FOUND THEN
        IF v_token.revoked_at IS NOT NULL THEN
            v_state := 'Revoked';
        ELSIF v_token.expires_at <= NOW() OR NOT v_token.is_active THEN
            v_state := 'Expired';
        ELSE
            SELECT p.public_url INTO v_url
            FROM public.report_secure_link_presentations p
            WHERE p.report_token_id = v_token.id;

            IF v_url IS NULL THEN
                SELECT substring(s.message_body FROM '(https://lis[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+)')
                  INTO v_url
                FROM public.sms_queue_items s
                WHERE s.diagnostic_report_id = p_report_id
                  AND s.sms_type = 'ReportReady'
                  AND s.idempotency_key = 'REPORT_READY:' || p_report_id::TEXT || ':' || v_report.version::TEXT
                ORDER BY s.created_at DESC
                LIMIT 1;
            END IF;

            v_raw_token := substring(v_url FROM '/r/([A-Za-z0-9_-]+)$');
            IF v_raw_token IS NOT NULL
               AND length(v_raw_token) BETWEEN 32 AND 256
               AND encode(extensions.digest(convert_to(v_raw_token, 'UTF8'), 'sha256'), 'hex') = v_token.token_hash THEN
                v_state := 'Active';
            ELSE
                v_url := NULL;
                v_state := 'ActiveUnrecoverable';
            END IF;
        END IF;
    END IF;

    SELECT MIN(created_at) INTO v_first_token_at FROM public.public_report_tokens;

    RETURN jsonb_build_object(
      'report_id', v_report.id,
      'report_version', v_report.version,
      'state', v_state,
      'has_valid_token', v_state IN ('Active', 'ActiveUnrecoverable'),
      'qr_available', v_state = 'Active',
      'public_url', v_url,
      'expires_at', CASE WHEN FOUND THEN v_token.expires_at ELSE NULL END,
      'signed_before_first_token', CASE WHEN v_first_token_at IS NULL THEN NULL ELSE v_report.signed_at < v_first_token_at END
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_report_secure_link_status TO authenticated, anon, service_role;

CREATE FUNCTION public.get_sms_delivery_status(p_limit INT DEFAULT 200)
RETURNS TABLE(id UUID,event_type TEXT,lab_no TEXT,mobile TEXT,status TEXT,provider_status TEXT,provider_message_id TEXT,retry_count INT,manual_retry_count INT,estimated_segments INT,created_at TIMESTAMPTZ,sent_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_users') OR public.is_super_admin()) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT q.id,
  CASE q.sms_type WHEN 'BillRegistration' THEN 'Payment Confirmation' WHEN 'ReportReady' THEN 'Report Ready' ELSE 'Transactional SMS' END::TEXT,
  COALESCE(o.order_number,ro.order_number,b.bill_number)::TEXT,q.recipient_phone::TEXT,q.status::TEXT,
  left(COALESCE(q.error_message,CASE WHEN q.status='Sent' THEN 'Accepted' ELSE q.error_classification END,q.status),500)::TEXT,
  q.provider_message_id::TEXT,q.delivery_attempt_count,q.manual_retry_count,
  CASE WHEN q.message_body~'^[\u0000-\u007F]*$' THEN CASE WHEN length(q.message_body)<=160 THEN 1 ELSE ceil(length(q.message_body)::NUMERIC/153)::INT END ELSE CASE WHEN length(q.message_body)<=70 THEN 1 ELSE ceil(length(q.message_body)::NUMERIC/67)::INT END END,
  q.created_at,q.sent_at
 FROM public.sms_queue_items q LEFT JOIN public.bills b ON b.id=q.bill_id LEFT JOIN public.clinical_orders o ON o.bill_id=q.bill_id
 LEFT JOIN public.diagnostic_reports r ON r.id=q.diagnostic_report_id LEFT JOIN public.clinical_orders ro ON ro.id=r.order_id
 ORDER BY q.created_at DESC LIMIT greatest(1,least(COALESCE(p_limit,200),500));
END;$$;

GRANT EXECUTE ON FUNCTION public.get_sms_delivery_status TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_sms_gateway_v2_health()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE counts JSONB;instances JSONB;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_users') OR public.is_super_admin()) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('pending_count',count(*) FILTER(WHERE status='Pending'),'failed_count',count(*) FILTER(WHERE status='Failed'),
    'deadletter_count',count(*) FILTER(WHERE status='DeadLetter'),'stale_processing_count',count(*) FILTER(WHERE status='Processing' AND lease_expires_at<=now()),
    'oldest_pending_at',min(created_at) FILTER(WHERE status='Pending')) INTO counts FROM public.sms_queue_items;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('instance_id',instance_id,'hostname',hostname,'gateway_version',gateway_version,'provider_name',provider_name,
    'service_started_at',service_started_at,'last_heartbeat_at',last_heartbeat_at,'last_successful_queue_access_at',last_successful_queue_access_at,
    'last_provider_success_at',last_provider_success_at,'provider_health',provider_health,'safe_last_error_code',safe_last_error_code,
    'active_job_count',active_job_count,'claiming_enabled',claiming_enabled,'is_enabled',is_enabled,
    'online',last_heartbeat_at>=now()-interval '2 minutes') ORDER BY created_at),'[]'::JSONB) INTO instances FROM public.sms_gateway_instances;
  RETURN jsonb_build_object('instances',instances,'queue',counts,'server_time',now());
END $$;

GRANT EXECUTE ON FUNCTION public.get_sms_gateway_v2_health TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_sms_test_alias(p_name TEXT, p_max_len INT DEFAULT 10)
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public, pg_temp
IMMUTABLE
AS $$
DECLARE
  v_norm TEXT := lower(trim(coalesce(p_name, '')));
BEGIN
  -- Approved primary aliases per lab specification
  IF v_norm ~ 'complete\s+blood\s+count|^cbc\b'         THEN RETURN 'CBC';  END IF;
  IF v_norm ~ 'lipid\s+profile|^lipid\b'                THEN RETURN 'LP';   END IF;
  IF v_norm ~ 'liver\s+function\s+test|^lft\b'          THEN RETURN 'LFT';  END IF;
  IF v_norm ~ 'kidney\s+function|renal\s+function|^kft\b|^rft\b' THEN RETURN 'KFT'; END IF;
  IF v_norm ~ 'thyroid\s+profile|thyroid\s+function|^tft\b|^thyroid\b' THEN RETURN 'TFT'; END IF;
  IF v_norm ~ 'urine\s+routine|urine\s+r/?e|^urine\b'   THEN RETURN 'UR';   END IF;
  IF v_norm ~ 'vitamin\s+d\b|25-oh|vit\s*d'             THEN RETURN 'VD';   END IF;
  IF v_norm ~ 'vitamin\s+b12\b|vit\s*b12|\bb12\b'       THEN RETURN 'B12';  END IF;
  IF v_norm ~ 'd-dimer'                                  THEN RETURN 'DD';   END IF;
  IF v_norm ~ 'ferritin'                                 THEN RETURN 'FER';  END IF;
  IF v_norm ~ 'hba1c|glycated\s+hemoglobin'             THEN RETURN 'A1c';  END IF;

  -- Short ASCII passthrough
  IF length(trim(p_name)) <= p_max_len AND p_name ~ '^[A-Za-z0-9+ -]+$' THEN
    RETURN trim(p_name);
  END IF;

  RETURN 'Lab';
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sms_test_alias TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_technician_operational_summary()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today_date DATE := (now() AT TIME ZONE 'Asia/Kathmandu')::date;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT public.has_permission('can_view_dashboard') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'today_patients', (SELECT count(*) FROM public.patients WHERE (created_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'today_orders', (SELECT count(*) FROM public.clinical_orders WHERE (created_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'samples_pending', (SELECT count(*) FROM public.samples WHERE status = 'Pending'),
        'samples_received', (SELECT count(*) FROM public.samples WHERE status = 'Received'),
        'samples_rejected', (SELECT count(*) FROM public.samples WHERE status = 'Rejected'),
        'worklist_pending', (SELECT count(*) FROM public.clinical_order_items WHERE status IN ('SampleReceived', 'ResultDrafted')),
        'result_entry_pending', (SELECT count(*) FROM public.clinical_order_items WHERE status = 'SampleReceived'),
        'awaiting_verification', (
            SELECT count(DISTINCT coi.id)
            FROM public.clinical_order_items coi
            WHERE coi.status NOT IN ('Verified', 'SignedOff')
              AND EXISTS (
                SELECT 1
                FROM public.test_results tr
                WHERE tr.order_item_id = coi.id
                  AND tr.status = 'SubmittedForVerification'
              )
        ),
        'specialist_microbiology_pending', (SELECT count(*) FROM public.clinical_order_items oi JOIN public.tests t ON t.id = oi.test_id WHERE t.code = 'PUS_CULTURE_AND_SENSITIVITY' AND oi.status NOT IN ('Verified', 'SignedOff')),
        'signed_reports_today', (SELECT count(*) FROM public.diagnostic_reports WHERE status = 'SignedOff' AND signed_at IS NOT NULL AND (signed_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'critical_unacknowledged', (SELECT count(*) FROM public.test_results WHERE is_critical AND NOT critical_acknowledged),
        'department_workload', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object('department', x.department, 'count', x.count) ORDER BY x.department), '[]'::JSONB)
              FROM (
                SELECT COALESCE(NULLIF(btrim(department), ''), 'Unassigned') AS department, count(*) AS count
                  FROM public.clinical_order_items
                 WHERE status IN ('Pending', 'SampleCollected', 'SampleReceived', 'ResultDrafted', 'Verified')
                 GROUP BY 1
              ) x
        ),
        'recent_orders', (
            SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::JSONB)
              FROM (
                SELECT o.id, o.order_number, o.status, o.created_at, p.uhid, p.full_name, p.age_years, p.gender
                  FROM public.clinical_orders o
                  JOIN public.patients p ON p.id = o.patient_id
                 ORDER BY o.created_at DESC LIMIT 8
              ) x
        ),
        'critical_items', (
            SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
              FROM (
                SELECT tr.id, tr.parameter_name, tr.display_value, tr.flag
                  FROM public.test_results tr
                 WHERE tr.is_critical AND NOT tr.critical_acknowledged
                 ORDER BY tr.created_at DESC LIMIT 5
              ) x
        )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_technician_operational_summary TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_clinical_result_write() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM public.clinical_order_items
    WHERE id = NEW.order_item_id
      AND reporting_type IN ('InHouse', 'OutsourceWithBimalReport')
  ) THEN
    RAISE EXCEPTION 'Clinical reporting is not supported for billing-only items.' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.guard_clinical_result_write TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_clinical_source_item_update()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
    IF (to_jsonb(NEW) - ARRAY['review_state','row_version'])
       IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['review_state','row_version']) THEN
        RAISE EXCEPTION 'Imported clinical source content is immutable.' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.guard_clinical_source_item_update TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_diagnostic_report_personnel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.reporting_personnel
        WHERE id = NEW.performed_by_personnel_id AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Performed-by reporting personnel must be active.';
    END IF;

    IF NEW.signed_by_personnel_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.reporting_personnel
        WHERE id = NEW.signed_by_personnel_id
          AND is_active = TRUE
          AND can_sign_reports = TRUE
    ) THEN
        RAISE EXCEPTION 'Authorizing reporting personnel must be active and eligible to sign.';
    END IF;

    RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.guard_diagnostic_report_personnel TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_formula_version_rewrite()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF OLD.lifecycle_status='Approved' OR EXISTS(
    SELECT 1 FROM public.clinical_calculation_runs WHERE formula_version_id=OLD.id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='CALCULATION_FORMULA_VERSION_IMMUTABLE';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.guard_formula_version_rewrite TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_immutable_calculation_evidence()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='CALCULATION_EVIDENCE_IMMUTABLE';
END $$;

GRANT EXECUTE ON FUNCTION public.guard_immutable_calculation_evidence TO authenticated, service_role;

CREATE FUNCTION public.guard_lab_number_registry() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'BPDC Lab No reservations are permanent.' USING ERRCODE='55000'; END IF;
  IF OLD.lab_no<>NEW.lab_no OR OLD.reserved_at<>NEW.reserved_at OR OLD.order_id IS NOT NULL
     OR NEW.order_id IS NULL OR NEW.assigned_at IS NULL THEN
    RAISE EXCEPTION 'BPDC Lab No registry is append-only.' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.guard_lab_number_registry TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_outsource_sample_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Billing RPC callers have can_create_bill; operational transitions require
    -- can_manage_outsource_tracking. Service-role maintenance has auth.uid null
    -- and is allowed only because it bypasses RLS and invokes trusted code.
    IF auth.uid() IS NOT NULL THEN
        IF TG_OP = 'INSERT'
           AND NOT public.has_permission('can_create_bill')
           AND NOT public.has_permission('can_manage_outsource_tracking') THEN
            RAISE EXCEPTION 'Access denied for outsource tracking creation.';
        ELSIF TG_OP = 'UPDATE'
           AND NOT public.has_permission('can_manage_outsource_tracking') THEN
            RAISE EXCEPTION 'Access denied for outsource tracking mutation.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.guard_outsource_sample_write TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_payment_immutability()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'Committed payment transactions are immutable; use an explicit reversal workflow when available.' USING ERRCODE='55000';
END;
$$;

GRANT EXECUTE ON FUNCTION public.guard_payment_immutability TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_sms_queue_item()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  NEW.recipient_phone:=public.normalize_nepal_sms_mobile(NEW.recipient_phone);
  IF NEW.idempotency_key IS NULL OR btrim(NEW.idempotency_key)='' THEN
    RAISE EXCEPTION 'SMS idempotency key is required.' USING ERRCODE='22023';
  END IF;
  IF NEW.status='Sent' AND NEW.sent_at IS NULL THEN NEW.sent_at:=NOW(); END IF;
  IF NEW.status IN ('Sent','DeadLetter') THEN NEW.final_state_at:=COALESCE(NEW.final_state_at,NOW()); END IF;
  NEW.updated_at:=NOW();
  RETURN NEW;
END;$$;

GRANT EXECUTE ON FUNCTION public.guard_sms_queue_item TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_first BOOLEAN;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('bimal:first-admin-bootstrap'));
    SELECT NOT EXISTS (SELECT 1 FROM public.user_profiles) INTO v_is_first;

    INSERT INTO public.user_profiles(
        id, email, full_name, phone, is_active, is_super_admin, created_at, updated_at
    ) VALUES (
        NEW.id,
        COALESCE(NEW.email, 'staff@bimalpathology.com'),
        COALESCE(NULLIF(btrim(NEW.raw_user_meta_data->>'full_name'), ''), 'Pending Staff Account'),
        NULLIF(btrim(NEW.raw_user_meta_data->>'phone'), ''),
        v_is_first,
        v_is_first,
        now(), now()
    )
    ON CONFLICT (id) DO NOTHING;

    IF v_is_first THEN
        INSERT INTO public.user_roles(user_id, role_id)
        VALUES (NEW.id, '00000000-0000-0000-0000-000000000001')
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.handle_new_auth_user TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.has_permission(p_permission_key VARCHAR) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
DECLARE direct_value BOOLEAN;
BEGIN
  IF NOT public.is_active_user() THEN RETURN FALSE; END IF;
  IF public.is_super_admin() THEN RETURN TRUE; END IF;
  SELECT is_granted INTO direct_value FROM public.user_direct_permissions WHERE user_id=auth.uid() AND permission_key=p_permission_key;
  IF direct_value IS NOT NULL THEN RETURN direct_value; END IF;
  RETURN EXISTS(
    SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
    JOIN public.role_permissions rp ON rp.role_id=r.id
    WHERE ur.user_id=auth.uid() AND r.code='lab_technician' AND rp.permission_key=p_permission_key
  );
END $$;

GRANT EXECUTE ON FUNCTION public.has_permission TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.heartbeat_sms_gateway_v2(
  p_instance_id UUID,p_hostname TEXT,p_gateway_version TEXT,p_provider_name TEXT,p_service_started_at TIMESTAMPTZ,
  p_last_successful_queue_access_at TIMESTAMPTZ,p_last_provider_success_at TIMESTAMPTZ,p_provider_health TEXT,
  p_safe_last_error_code TEXT,p_active_job_count INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  IF p_provider_health NOT IN ('Unknown','Healthy','Degraded','Unavailable','ConfigurationError') OR p_active_job_count<0 OR
     length(COALESCE(p_safe_last_error_code,''))>100 THEN RAISE EXCEPTION 'Invalid safe heartbeat payload.' USING ERRCODE='22023'; END IF;
  UPDATE public.sms_gateway_instances SET hostname=btrim(p_hostname),gateway_version=btrim(p_gateway_version),provider_name=btrim(p_provider_name),
    service_started_at=p_service_started_at,last_heartbeat_at=now(),last_successful_queue_access_at=p_last_successful_queue_access_at,
    last_provider_success_at=p_last_provider_success_at,provider_health=p_provider_health,safe_last_error_code=NULLIF(btrim(p_safe_last_error_code),''),
    active_job_count=p_active_job_count,updated_at=now() WHERE instance_id=p_instance_id;
  RETURN jsonb_build_object('success',true,'server_time',now());
END $$;

GRANT EXECUTE ON FUNCTION public.heartbeat_sms_gateway_v2 TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.hmis_auto_summary(p_month date) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
 WITH bounds AS (SELECT date_trunc('month',p_month)::date s,(date_trunc('month',p_month)+interval '1 month')::date e),
 registered AS (SELECT p.id,p.gender,COALESCE(p.dob,(p.created_at AT TIME ZONE 'Asia/Kathmandu')::date-make_interval(years=>COALESCE(p.age_years,0),months=>COALESCE(p.age_months,0),days=>COALESCE(p.age_days,0))) dob FROM patients p,bounds b WHERE p.created_at>=b.s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND p.created_at<b.e::timestamp AT TIME ZONE 'Asia/Kathmandu'),
 age_counts AS (SELECT CASE WHEN age<1 THEN '<1 Year' WHEN age<5 THEN '1–4 Years' WHEN age<10 THEN '5–9 Years' WHEN age<15 THEN '10–14 Years' WHEN age<20 THEN '15–19 Years' WHEN age<30 THEN '20–29 Years' WHEN age<60 THEN '30–59 Years' WHEN age<70 THEN '60–69 Years' ELSE '70+ Years' END grp,gender,count(*) n FROM (SELECT gender,extract(year FROM age((SELECT s FROM bounds),dob))::int age FROM registered) x GROUP BY 1,2),
 ages AS (SELECT COALESCE(jsonb_object_agg(grp,counts),'{}') value FROM (SELECT grp,jsonb_build_object('Female',sum(n) FILTER(WHERE gender='Female'),'Male',sum(n) FILTER(WHERE gender='Male')) counts FROM age_counts GROUP BY grp)y),
 metrics AS (SELECT
 (SELECT count(*) FROM registered) registered_patients,
 (SELECT count(*) FROM bills,bounds WHERE created_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND created_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu') bills_visits,
 (SELECT count(*) FROM clinical_order_items,bounds WHERE created_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND created_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu') investigations,
 (SELECT count(*) FROM clinical_order_items,bounds WHERE updated_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND updated_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu' AND status IN('Verified','SignedOff')) completed_tests,
 (SELECT count(*) FROM clinical_order_items,bounds WHERE created_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND created_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu' AND reporting_type='OutsourceWithBimalReport') outsource_count,
 (SELECT count(*) FROM diagnostic_reports,bounds WHERE created_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND created_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu') report_count,
 (SELECT count(*) FROM samples,bounds WHERE created_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND created_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu') sample_count)
 SELECT jsonb_build_object('registeredPatients',registered_patients,'totalBillsVisits',bills_visits,'totalInvestigations',investigations,'completedTests',completed_tests,'outsourceCount',outsource_count,'reportCount',report_count,'sampleCount',sample_count,'newClientsByAgeSex',ages.value)
 FROM metrics,ages WHERE public.has_permission('can_view_hmis_reports');
$$;

GRANT EXECUTE ON FUNCTION public.hmis_auto_summary TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.hmis_identity_options() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT COALESCE(jsonb_agg(x ORDER BY x->>'name'),'[]'::jsonb) FROM (
  SELECT jsonb_build_object('source','ReportingPersonnel','id',rp.id,'name',rp.full_name,'designation',concat_ws(', ',rp.professional_type::text,nullif(rp.qualification,'')),'signatureUrl',rp.signature_url) x FROM reporting_personnel rp WHERE rp.is_active
  UNION ALL
  SELECT jsonb_build_object('source','Staff','id',up.id,'name',up.full_name,'designation',COALESCE((SELECT string_agg(r.name,', ' ORDER BY r.name) FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=up.id),'Staff'),'signatureUrl',NULL) FROM user_profiles up WHERE up.is_active
 ) options WHERE public.has_permission('can_view_hmis_reports');
$$;

GRANT EXECUTE ON FUNCTION public.hmis_identity_options TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_active_user()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT auth.uid() IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM public.user_profiles up
           WHERE up.id = auth.uid()
             AND up.is_active = TRUE
       )
$$;

GRANT EXECUTE ON FUNCTION public.is_active_user TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_report_artifact_worker()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT auth.role()='authenticated' AND auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.report_artifact_worker_identities w
    WHERE w.auth_user_id=auth.uid() AND w.is_enabled
  )
$$;

GRANT EXECUTE ON FUNCTION public.is_report_artifact_worker TO authenticated, service_role;

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

GRANT EXECUTE ON FUNCTION public.is_super_admin TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.link_outsource_tracker_to_order_item() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.execution_route='OUTSOURCE' THEN
  UPDATE public.outsource_samples SET order_item_id=NEW.id
  WHERE bill_item_id=NEW.bill_item_id AND order_item_id IS NULL;
 END IF;
 RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.link_outsource_tracker_to_order_item TO authenticated, service_role;

CREATE FUNCTION public.list_laboratory_worklist_departments()
RETURNS TABLE(department TEXT)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
  SELECT DISTINCT coi.department
  FROM public.clinical_order_items coi
  WHERE coi.clinical_reporting_enabled = true
    AND coi.reporting_type IN ('InHouse','OutsourceWithBimalReport')
    AND NULLIF(btrim(coi.department),'') IS NOT NULL
  ORDER BY coi.department;
$$;

GRANT EXECUTE ON FUNCTION public.list_laboratory_worklist_departments TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.list_my_report_groups(p_order_id UUID) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_patient_id UUID;
  v_groups JSONB;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT patient_id INTO v_patient_id
  FROM public.patient_app_identities
  WHERE auth_user_id = v_uid AND status = 'LINKED';

  IF v_patient_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.clinical_orders WHERE id = p_order_id AND patient_id = v_patient_id
  ) THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'report_group_id', g.id,
      'group_key', g.group_key,
      'title', g.title,
      'clinical_section', g.clinical_section,
      'status', CASE WHEN art.generation_status = 'Ready' THEN 'Ready' ELSE 'Pending' END,
      'report_id', CASE WHEN art.generation_status = 'Ready' THEN rep.id ELSE NULL END,
      'version', CASE WHEN art.generation_status = 'Ready' THEN rep.version ELSE NULL END,
      'signed_at', CASE WHEN art.generation_status = 'Ready' THEN rep.signed_at ELSE NULL END,
      'is_amendment', CASE WHEN art.generation_status = 'Ready' THEN (rep.status = 'Amended') ELSE false END,
      'pdf_sha256', CASE WHEN art.generation_status = 'Ready' THEN art.pdf_sha256 ELSE NULL END,
      'byte_size', CASE WHEN art.generation_status = 'Ready' THEN art.byte_size ELSE NULL END
    ) ORDER BY g.created_at
  ), '[]'::jsonb)
  INTO v_groups
  FROM public.clinical_report_groups g
  LEFT JOIN LATERAL (
    SELECT dr.id, dr.version, dr.status, dr.signed_at
    FROM public.diagnostic_reports dr
    WHERE dr.report_group_id = g.id
      AND dr.status IN ('SignedOff', 'Amended')
    ORDER BY dr.version DESC
    LIMIT 1
  ) rep ON true
  LEFT JOIN LATERAL (
    SELECT a.generation_status, a.pdf_sha256, a.byte_size
    FROM public.report_pdf_artifacts a
    WHERE a.diagnostic_report_id = rep.id
            AND a.generation_status = 'Ready'
    LIMIT 1
  ) art ON true
  WHERE g.order_id = p_order_id;

  RETURN v_groups;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_my_report_groups TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.list_my_report_orders(p_limit INT DEFAULT 50, p_offset INT DEFAULT 0) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_patient_id UUID;
  v_orders JSONB;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT patient_id INTO v_patient_id
  FROM public.patient_app_identities
  WHERE auth_user_id = v_uid AND status = 'LINKED';

  IF v_patient_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  p_limit := least(greatest(coalesce(p_limit, 50), 1), 100);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT coalesce(jsonb_agg(x.row_data), '[]'::jsonb)
  INTO v_orders
  FROM (
    SELECT
      jsonb_build_object(
        'order_id', o.id,
        'order_number', o.order_number,
        'order_date_ad', o.order_date_ad,
        'order_date_bs', o.order_date_bs,
        'created_at', o.created_at,
        'total_groups', coalesce(grp.total_groups, 0),
        'ready_groups', coalesce(grp.ready_groups, 0),
        'overall_status', CASE
          WHEN coalesce(grp.total_groups, 0) = 0 THEN 'Pending'
          WHEN grp.ready_groups = grp.total_groups THEN 'Ready'
          WHEN grp.ready_groups > 0 THEN 'Partially Ready'
          ELSE 'Pending'
        END
      ) AS row_data
    FROM public.clinical_orders o
    LEFT JOIN LATERAL (
      SELECT
        count(g.id)::int AS total_groups,
        count(g.id) FILTER (
          WHERE EXISTS (
            SELECT 1 FROM public.diagnostic_reports dr
            JOIN public.report_pdf_artifacts a ON a.diagnostic_report_id = dr.id
            WHERE dr.report_group_id = g.id
              AND dr.status IN ('SignedOff', 'Amended')
                            AND a.generation_status = 'Ready'
          )
        )::int AS ready_groups
      FROM public.clinical_report_groups g
      WHERE g.order_id = o.id
    ) grp ON true
    WHERE o.patient_id = v_patient_id
    ORDER BY o.order_date_ad DESC, o.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) x;

  RETURN v_orders;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_my_report_orders TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.lock_diagnostic_report_lineage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.order_id::TEXT, 0));
    RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.lock_diagnostic_report_lineage TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.mark_sms_gateway_v2_provider_call_started(p_instance_id UUID,p_sms_id UUID,p_worker_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  UPDATE public.sms_queue_items SET provider_call_started_at=now(),updated_at=now()
  WHERE id=p_sms_id AND status='Processing' AND lease_instance_id=p_instance_id AND lease_owner=p_worker_id
    AND lease_expires_at>now() AND provider_call_started_at IS NULL;
  RETURN FOUND;
END $$;

GRANT EXECUTE ON FUNCTION public.mark_sms_gateway_v2_provider_call_started TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.mark_sms_provider_call_started(p_sms_id UUID,p_worker_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 UPDATE public.sms_queue_items SET provider_call_started_at=NOW(),updated_at=NOW()
 WHERE id=p_sms_id AND status='Processing' AND lease_owner=p_worker_id AND lease_expires_at>NOW() AND provider_call_started_at IS NULL;
 RETURN FOUND;
END;$$;

GRANT EXECUTE ON FUNCTION public.mark_sms_provider_call_started TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.materialize_report_group_item() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; g UUID; actor UUID:=coalesce(auth.uid(),(SELECT created_by FROM public.bills b JOIN public.clinical_orders o ON o.bill_id=b.id WHERE o.id=NEW.order_id));
BEGIN
  SELECT * INTO t FROM public.tests WHERE id=NEW.test_id;
  IF NOT FOUND OR NEW.reporting_type = 'NoReporting' THEN RETURN NEW; END IF;
  INSERT INTO public.clinical_report_groups(order_id,group_key,title,clinical_section,display_order,configuration_version,created_by)
  VALUES(NEW.order_id,COALESCE(NULLIF(t.report_group_key,''),'general_laboratory'),COALESCE(NULLIF(t.report_group_title,''),'General Laboratory'),COALESCE(NULLIF(t.report_section,''),'Laboratory'),COALESCE(t.report_group_sort_order,500),COALESCE(t.row_version,1),actor)
  ON CONFLICT(order_id,group_key) DO UPDATE SET display_order=least(clinical_report_groups.display_order,excluded.display_order)
  RETURNING id INTO g;
  INSERT INTO public.clinical_report_group_items(report_group_id,order_item_id,frozen_test_code,frozen_test_name,display_order,created_by)
  VALUES(g,NEW.id,COALESCE(t.code,NEW.test_name),NEW.test_name,coalesce(t.display_order,0),actor) ON CONFLICT(order_item_id) DO NOTHING;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
  VALUES(actor,public.catalogue_actor_name(),'REPORT_GROUP_ITEM_FROZEN','ClinicalReportGroup',g::text,jsonb_build_object('order_item_id',NEW.id,'group_key',COALESCE(t.report_group_key,'general_laboratory'),'test_code',t.code));
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.materialize_report_group_item TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.normalize_clinical_calculation_input(
  p_value NUMERIC,p_supplied_unit TEXT,p_canonical_unit TEXT
) RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=public,pg_temp AS $$
DECLARE supplied TEXT:=lower(regexp_replace(p_supplied_unit,'[[:space:]]','','g'));
        canonical TEXT:=lower(regexp_replace(p_canonical_unit,'[[:space:]]','','g'));
BEGIN
  IF p_value::TEXT IN ('Infinity','-Infinity','NaN') THEN
    RAISE EXCEPTION USING ERRCODE='22003',MESSAGE='CALCULATION_INVALID_INPUT';
  END IF;
  IF supplied=canonical THEN RETURN p_value; END IF;
  IF canonical='10^9/l' AND supplied IN ('×10³/mm³','x10^3/mm3','10^3/mm3','thousand/mm3') THEN RETURN p_value; END IF;
  IF canonical='10^9/l' AND supplied IN ('/cumm','/mm³','/mm3') THEN RETURN p_value/1000; END IF;
  IF canonical='10^12/l' AND supplied IN ('million/mm³','million/mm3','10^6/mm3') THEN RETURN p_value; END IF;
  IF canonical='10^12/l' AND supplied='million/cumm' THEN RETURN p_value; END IF;
  IF canonical='g/dl' AND supplied='gm/dl' THEN RETURN p_value; END IF;
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_UNIT_MISMATCH',
    DETAIL=jsonb_build_object('supplied_unit',p_supplied_unit,'required_unit',p_canonical_unit)::TEXT;
END $$;

GRANT EXECUTE ON FUNCTION public.normalize_clinical_calculation_input TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.normalize_nepal_mobile(p_mobile TEXT) RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public, pg_temp IMMUTABLE STRICT AS $$
DECLARE
  clean_digits TEXT;
BEGIN
  IF p_mobile IS NULL THEN
    RETURN NULL;
  END IF;

  clean_digits := regexp_replace(p_mobile, '[^0-9]', '', 'g');

  IF length(clean_digits) = 13 AND clean_digits LIKE '977%' THEN
    clean_digits := substring(clean_digits FROM 4);
  ELSIF length(clean_digits) = 14 AND clean_digits LIKE '0977%' THEN
    clean_digits := substring(clean_digits FROM 5);
  ELSIF length(clean_digits) = 11 AND clean_digits LIKE '0%' THEN
    clean_digits := substring(clean_digits FROM 2);
  END IF;

  IF length(clean_digits) = 10 AND (clean_digits LIKE '98%' OR clean_digits LIKE '97%') THEN
    RETURN clean_digits;
  END IF;

  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.normalize_nepal_mobile TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.normalize_nepal_sms_mobile(p_mobile TEXT)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE SET search_path=public,pg_temp AS $$
DECLARE v TEXT:=regexp_replace(btrim(COALESCE(p_mobile,'')),'[[:space:]()+-]','','g');
BEGIN
  IF v LIKE '977%' AND length(v)=13 THEN v:=substring(v FROM 4); END IF;
  IF v !~ '^(97|98)[0-9]{8}$' THEN
    RAISE EXCEPTION 'A valid Nepal mobile number is required.' USING ERRCODE='22023';
  END IF;
  RETURN v;
END;$$;

GRANT EXECUTE ON FUNCTION public.normalize_nepal_sms_mobile TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.notify_updated_order_reports(p_order_id UUID,p_expected_generation INTEGER,p_reason TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE current_generation INT; token public.order_report_delivery_tokens%ROWTYPE; report public.diagnostic_reports%ROWTYPE; patient public.patients%ROWTYPE; ordering public.clinical_orders%ROWTYPE; phone TEXT; sms_id UUID; next_generation INT; v_sms_body TEXT;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_sign_reports') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF btrim(coalesce(p_reason,''))='' THEN RAISE EXCEPTION 'Notification reason is required.' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_order_id::text,91));
 SELECT coalesce(max(generation),0) INTO current_generation FROM public.order_report_notification_generations WHERE order_id=p_order_id;
 IF current_generation<>p_expected_generation THEN RAISE EXCEPTION 'Notification state changed. Refresh and retry.' USING ERRCODE='PT409'; END IF;
 SELECT * INTO token FROM public.order_report_delivery_tokens WHERE order_id=p_order_id AND is_active AND revoked_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order delivery entitlement is unavailable.' USING ERRCODE='23514'; END IF;
 SELECT dr.* INTO report FROM public.diagnostic_reports dr WHERE dr.order_id=p_order_id AND dr.report_group_id IS NOT NULL AND dr.status='SignedOff' ORDER BY dr.signed_at DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'No finalized report is available.' USING ERRCODE='23514'; END IF;
 SELECT * INTO patient FROM public.patients WHERE id=report.patient_id; SELECT * INTO ordering FROM public.clinical_orders WHERE id=p_order_id;
 phone:=regexp_replace(coalesce(patient.mobile,''),'[^0-9]','','g'); IF phone LIKE '977%' AND length(phone)=13 THEN phone:=substring(phone FROM 4); END IF; IF phone !~ '^(97|98)[0-9]{8}$' THEN RAISE EXCEPTION 'Patient has no valid Nepal mobile.' USING ERRCODE='23514'; END IF;
 next_generation:=current_generation+1;
 v_sms_body := public.build_single_credit_nepali_sms(p_order_id, report.id);
 INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id) SELECT 'ReportReady',phone,patient.full_name,v_sms_body,'Pending','ORDER_REPORT_READY:'||p_order_id||':'||next_generation,report.id FROM public.report_pdf_delivery_intents i WHERE i.order_token_id=token.id ORDER BY i.queued_at NULLS LAST LIMIT 1 ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
 IF sms_id IS NULL THEN SELECT sms_queue_item_id INTO sms_id FROM public.order_report_notification_generations WHERE order_id=p_order_id AND generation=next_generation; END IF;
 INSERT INTO public.order_report_notification_generations(order_id,generation,reason,requested_by,sms_queue_item_id) VALUES(p_order_id,next_generation,btrim(p_reason),auth.uid(),sms_id) ON CONFLICT(order_id,generation) DO NOTHING;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'ORDER_REPORT_UPDATED_NOTIFICATION','ClinicalOrder',p_order_id::text,jsonb_build_object('generation',next_generation,'reason',btrim(p_reason)));
 RETURN jsonb_build_object('success',true,'generation',next_generation,'sms_queue_item_id',sms_id);
END $$;

GRANT EXECUTE ON FUNCTION public.notify_updated_order_reports TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.patient_actor_name()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE((SELECT full_name FROM public.user_profiles WHERE id = auth.uid()), 'Authenticated user')
$$;

GRANT EXECUTE ON FUNCTION public.patient_actor_name TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.patient_clean_text(p_value TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp AS $$
  SELECT regexp_replace(btrim(COALESCE(p_value, '')), '[[:space:]]+', ' ', 'g')
$$;

GRANT EXECUTE ON FUNCTION public.patient_clean_text TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.patient_normalize_mobile(p_mobile TEXT)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE SET search_path = public, pg_temp AS $$
DECLARE v_mobile TEXT := regexp_replace(COALESCE(p_mobile, ''), '[^0-9]', '', 'g');
BEGIN
  IF v_mobile LIKE '977%' AND length(v_mobile) = 13 THEN v_mobile := substring(v_mobile FROM 4); END IF;
  IF v_mobile LIKE '0%' AND length(v_mobile) = 11 THEN v_mobile := substring(v_mobile FROM 2); END IF;
  IF v_mobile !~ '^(97|98)[0-9]{8}$' THEN
    RAISE EXCEPTION 'Please enter a valid 10-digit Nepal mobile number starting with 98 or 97.' USING ERRCODE = '22023';
  END IF;
  RETURN v_mobile;
END;
$$;

GRANT EXECUTE ON FUNCTION public.patient_normalize_mobile TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.prevent_archived_patient_transaction()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=NEW.patient_id AND is_active) THEN
    RAISE EXCEPTION 'Archived patients must be restored before creating a new transaction.' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.prevent_archived_patient_transaction TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.prevent_catalogue_evidence_mutation()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'CATALOGUE_APPROVAL_EVIDENCE_IS_IMMUTABLE' USING ERRCODE='23514'; END $$;

GRANT EXECUTE ON FUNCTION public.prevent_catalogue_evidence_mutation TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.prevent_hmis_version_mutation() RETURNS trigger LANGUAGE plpgsql
SET search_path = public, pg_temp AS $$ BEGIN RAISE EXCEPTION 'Finalized HMIS versions are immutable'; END $$;

GRANT EXECUTE ON FUNCTION public.prevent_hmis_version_mutation TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.prevent_patient_uhid_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.uhid !~ '^[0-9]{10}$' THEN
        RAISE EXCEPTION 'New patient UHID must contain exactly 10 numeric digits.' USING ERRCODE = '22023';
    ELSIF TG_OP = 'UPDATE' AND NEW.uhid IS DISTINCT FROM OLD.uhid THEN
        RAISE EXCEPTION 'Patient UHID is immutable.' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.prevent_patient_uhid_change TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.provision_historical_report_secure_link(
    p_report_id UUID,
    p_token_hash VARCHAR(128),
    p_public_url TEXT,
    p_expiry_days INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report public.diagnostic_reports%ROWTYPE;
    v_existing public.public_report_tokens%ROWTYPE;
    v_token_id UUID;
    v_expires_at TIMESTAMPTZ;
    v_raw_token TEXT;
    v_existing_url TEXT;
    v_existing_raw TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT (public.has_permission('can_print_reports') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_report
    FROM public.diagnostic_reports
    WHERE id = p_report_id
    FOR UPDATE;

    IF NOT FOUND OR v_report.status NOT IN ('SignedOff', 'Amended') THEN
        RAISE EXCEPTION 'A signed or amended report is required.' USING ERRCODE = '22023';
    END IF;

    v_raw_token := substring(p_public_url FROM '^https://lis[.]bimalpathology[.]com[.]np/r/([A-Za-z0-9_-]+)$');
    IF v_raw_token IS NULL OR length(v_raw_token) NOT BETWEEN 32 AND 256
       OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
       OR encode(extensions.digest(convert_to(v_raw_token, 'UTF8'), 'sha256'), 'hex') <> p_token_hash THEN
        RAISE EXCEPTION 'A valid secure report token is required.' USING ERRCODE = '22023';
    END IF;

    UPDATE public.public_report_tokens
       SET is_active = FALSE, updated_at = NOW()
     WHERE diagnostic_report_id = p_report_id
       AND is_active = TRUE
       AND (revoked_at IS NOT NULL OR expires_at <= NOW());

    SELECT * INTO v_existing
    FROM public.public_report_tokens
    WHERE diagnostic_report_id = p_report_id
      AND is_active = TRUE AND revoked_at IS NULL AND expires_at > NOW()
    ORDER BY created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
        SELECT p.public_url INTO v_existing_url
        FROM public.report_secure_link_presentations p
        WHERE p.report_token_id = v_existing.id;

        IF v_existing_url IS NULL THEN
            SELECT substring(s.message_body FROM '(https://lis[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+)')
              INTO v_existing_url
            FROM public.sms_queue_items s
            WHERE s.diagnostic_report_id = p_report_id
              AND s.sms_type = 'ReportReady'
              AND s.idempotency_key = 'REPORT_READY:' || p_report_id::TEXT || ':' || v_report.version::TEXT
            ORDER BY s.created_at DESC
            LIMIT 1;
        END IF;
        v_existing_raw := substring(v_existing_url FROM '/r/([A-Za-z0-9_-]+)$');

        IF v_existing_raw IS NOT NULL
           AND encode(extensions.digest(convert_to(v_existing_raw, 'UTF8'), 'sha256'), 'hex') = v_existing.token_hash THEN
            RETURN jsonb_build_object('success', TRUE, 'created', FALSE, 'reused', TRUE,
              'report_id', v_report.id, 'report_version', v_report.version,
              'public_url', v_existing_url, 'expires_at', v_existing.expires_at,
              'sms_queued', FALSE);
        END IF;

        -- An unrecoverable one-way token cannot produce a QR. Replacement is
        -- explicit user action and is recorded; no notification is generated.
        UPDATE public.public_report_tokens
           SET is_active = FALSE, revoked_at = COALESCE(revoked_at, NOW()), updated_at = NOW()
         WHERE id = v_existing.id;
    END IF;

    v_expires_at := NOW() + (GREATEST(1, LEAST(COALESCE(p_expiry_days, 30), 90)) || ' days')::INTERVAL;
    INSERT INTO public.public_report_tokens(
      diagnostic_report_id, token_hash, expires_at, created_by, is_active
    ) VALUES (
      p_report_id, p_token_hash, v_expires_at, auth.uid(), TRUE
    ) RETURNING id INTO v_token_id;

    INSERT INTO public.report_secure_link_presentations(report_token_id, public_url)
    VALUES(v_token_id, p_public_url);

    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES(auth.uid(), 'Authorized Reporting User', 'HISTORICAL_REPORT_LINK_PROVISIONED',
      'DiagnosticReport', v_report.report_number,
      jsonb_build_object('report_id', v_report.id, 'report_version', v_report.version,
        'token_id', v_token_id, 'expires_at', v_expires_at));

    -- Intentionally no sms_queue_items write: link provisioning is not a
    -- ReportReady notification and never resends historical SMS.
    RETURN jsonb_build_object('success', TRUE, 'created', TRUE, 'reused', FALSE,
      'report_id', v_report.id, 'report_version', v_report.version,
      'public_url', p_public_url, 'expires_at', v_expires_at,
      'sms_queued', FALSE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.provision_historical_report_secure_link TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.queue_bill_sms(p_bill_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_bill RECORD;
    v_order RECORD;
    v_clean_phone VARCHAR(20);
    v_idempotency_key VARCHAR(255);
    v_msg TEXT;
    v_sms_id UUID;
    v_net_rupees TEXT;
    v_paid_rupees TEXT;
    v_due_rupees TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT * INTO v_bill FROM public.bills WHERE id = p_bill_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bill record % not found.', p_bill_id;
    END IF;

    SELECT * INTO v_order FROM public.clinical_orders WHERE bill_id = p_bill_id LIMIT 1;

    -- Clean phone number
    v_clean_phone := REGEXP_REPLACE(TRIM(v_bill.patient_mobile_snapshot), '[^0-9]', '', 'g');
    IF v_clean_phone LIKE '977%' AND LENGTH(v_clean_phone) > 10 THEN
        v_clean_phone := SUBSTRING(v_clean_phone FROM 4);
    END IF;

    IF LENGTH(v_clean_phone) < 10 OR (v_clean_phone NOT LIKE '98%' AND v_clean_phone NOT LIKE '97%') THEN
        -- Invalid Nepal mobile: log and skip without throwing (SMS must not break clinical billing)
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid mobile number format: ' || v_clean_phone);
    END IF;

    v_net_rupees := TRIM(TO_CHAR(v_bill.net_amount_paisa / 100.0, '999999990.00'));
    v_paid_rupees := TRIM(TO_CHAR(v_bill.paid_amount_paisa / 100.0, '999999990.00'));
    v_due_rupees := TRIM(TO_CHAR(v_bill.due_amount_paisa / 100.0, '999999990.00'));

    v_idempotency_key := 'BILL_CREATED:' || p_bill_id::TEXT;

    v_msg := 'Dear ' || v_bill.patient_name_snapshot || ', your booking ' || COALESCE(v_order.order_number, v_bill.bill_number) || ' at Bimal Pathology is confirmed. Bill: NPR ' || v_net_rupees || ', Paid: NPR ' || v_paid_rupees || ', Due: NPR ' || v_due_rupees || '. Ph: 056-593288';

    INSERT INTO public.sms_queue_items (
        sms_type,
        recipient_phone,
        recipient_name,
        message_body,
        status,
        idempotency_key,
        bill_id
    ) VALUES (
        'BillRegistration',
        v_clean_phone,
        v_bill.patient_name_snapshot,
        v_msg,
        'Pending',
        v_idempotency_key,
        p_bill_id
    )
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING id INTO v_sms_id;

    -- Audit log
    INSERT INTO public.audit_logs (
        user_id,
        user_name,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        auth.uid(),
        'Front Desk / System',
        'SMS_QUEUED',
        'Bill',
        v_bill.bill_number,
        jsonb_build_object('sms_type', 'BillRegistration', 'recipient_phone', v_clean_phone, 'bill_id', p_bill_id)
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'sms_id', v_sms_id,
        'idempotency_key', v_idempotency_key,
        'recipient_phone', v_clean_phone
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.queue_bill_sms TO authenticated, service_role;

CREATE FUNCTION public.queue_signed_report_artifact()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF NEW.status IN('SignedOff','Amended') THEN
    INSERT INTO public.report_pdf_artifacts(diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256)
    VALUES(NEW.id,NEW.version,NEW.integrity_hash,encode(extensions.digest(NEW.clinical_snapshot_json::TEXT,'sha256'),'hex'))
    ON CONFLICT(diagnostic_report_id,report_version) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.queue_signed_report_artifact TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.receive_bill_payment(
  p_bill_id UUID,
  p_amount_paisa BIGINT,
  p_payment_mode public.payment_mode_enum,
  p_transaction_reference TEXT,
  p_remarks TEXT,
  p_idempotency_key TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_key TEXT := btrim(COALESCE(p_idempotency_key,''));
  v_hash TEXT;
  v_existing public.payment_idempotency_requests%ROWTYPE;
  v_bill public.bills%ROWTYPE;
  v_payment public.payment_transactions%ROWTYPE;
  v_patient public.patients%ROWTYPE;
  v_lab_no TEXT;
  v_phone TEXT;
  v_message TEXT;
  v_sms_id UUID;
  v_sms_status TEXT := 'Payment committed; notification unavailable';
  v_new_paid BIGINT;
  v_new_due BIGINT;
  v_new_status public.payment_status_enum;
  v_response JSONB;
BEGIN
  IF v_caller IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF v_key='' OR length(v_key)>200 THEN RAISE EXCEPTION 'A valid payment request key is required.' USING ERRCODE='22023'; END IF;
  IF p_amount_paisa IS NULL OR p_amount_paisa<=0 THEN RAISE EXCEPTION 'Payment amount must be greater than zero.' USING ERRCODE='22023'; END IF;
  IF p_payment_mode IS NULL THEN RAISE EXCEPTION 'Payment method is required.' USING ERRCODE='22023'; END IF;
  IF p_payment_mode <> 'Cash' AND public.patient_clean_text(p_transaction_reference)='' THEN RAISE EXCEPTION 'Transaction reference is required for non-cash payments.' USING ERRCODE='22023'; END IF;
  IF length(COALESCE(p_transaction_reference,''))>100 THEN RAISE EXCEPTION 'Transaction reference is too long.' USING ERRCODE='22023'; END IF;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('bill_id',p_bill_id,'amount_paisa',p_amount_paisa,'payment_mode',p_payment_mode,'transaction_reference',NULLIF(public.patient_clean_text(p_transaction_reference),''),'remarks',NULLIF(public.patient_clean_text(p_remarks),''))::TEXT,'UTF8'),'sha256'),'hex');
  INSERT INTO public.payment_idempotency_requests(caller_id,idempotency_key,request_hash) VALUES(v_caller,v_key,v_hash) ON CONFLICT DO NOTHING;
  SELECT * INTO v_existing FROM public.payment_idempotency_requests WHERE caller_id=v_caller AND idempotency_key=v_key FOR UPDATE;
  IF v_existing.request_hash<>v_hash THEN RAISE EXCEPTION 'Payment request key was already used for different data.' USING ERRCODE='22023'; END IF;
  IF v_existing.response_json IS NOT NULL THEN RETURN v_existing.response_json||jsonb_build_object('idempotency_replay',TRUE); END IF;

  SELECT * INTO v_bill FROM public.bills WHERE id=p_bill_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Bill not found.' USING ERRCODE='P0002'; END IF;
  IF v_bill.due_amount_paisa<=0 OR v_bill.payment_status='Paid' THEN RAISE EXCEPTION 'This bill has no outstanding balance.' USING ERRCODE='22023'; END IF;
  IF p_amount_paisa>v_bill.due_amount_paisa THEN RAISE EXCEPTION 'Payment cannot exceed the outstanding balance of % paisa.',v_bill.due_amount_paisa USING ERRCODE='22023'; END IF;

  INSERT INTO public.payment_transactions(bill_id,receipt_number,amount_paisa,payment_mode,transaction_reference,remarks,received_by,received_by_name)
  VALUES(v_bill.id,'RCP-'||TO_CHAR(NOW() AT TIME ZONE 'Asia/Kathmandu','YYYY')||'-'||LPAD(NEXTVAL('receipt_seq')::TEXT,6,'0'),p_amount_paisa,p_payment_mode,NULLIF(public.patient_clean_text(p_transaction_reference),''),NULLIF(public.patient_clean_text(p_remarks),''),v_caller,public.patient_actor_name()) RETURNING * INTO v_payment;

  v_new_paid:=v_bill.paid_amount_paisa+p_amount_paisa;
  v_new_due:=v_bill.net_amount_paisa-v_new_paid;
  v_new_status:=CASE WHEN v_new_due=0 THEN 'Paid'::public.payment_status_enum ELSE 'Partial'::public.payment_status_enum END;
  UPDATE public.bills SET paid_amount_paisa=v_new_paid,due_amount_paisa=v_new_due,payment_status=v_new_status,updated_at=NOW() WHERE id=v_bill.id;

  SELECT * INTO v_patient FROM public.patients WHERE id=v_bill.patient_id;
  SELECT order_number INTO v_lab_no FROM public.clinical_orders WHERE bill_id=v_bill.id ORDER BY created_at,id LIMIT 1;
  v_lab_no:=COALESCE(v_lab_no,v_bill.bill_number);
  v_phone:=regexp_replace(COALESCE(v_patient.mobile,''),'[^0-9]','','g');
  IF v_phone LIKE '977%' AND length(v_phone)=13 THEN v_phone:=substring(v_phone FROM 4); END IF;
  BEGIN
    IF v_phone~'^(97|98)[0-9]{8}$' THEN
      v_message:='Bimal Pathology: Payment of NPR '||(p_amount_paisa/100)::TEXT||'.'||lpad((p_amount_paisa%100)::TEXT,2,'0')||' received for Lab No: '||v_lab_no||'. Thank you.';
      INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,bill_id)
      VALUES('BillRegistration',v_phone,v_patient.full_name,v_message,'Pending','PAYMENT_CONFIRMATION:'||v_payment.id::TEXT,v_bill.id)
      ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO v_sms_id;
      v_sms_status:=CASE WHEN v_sms_id IS NULL THEN 'Payment notification already queued' ELSE 'Payment notification queued' END;
    ELSE v_sms_status:='SMS skipped: invalid or missing Nepal mobile'; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_sms_status:='Payment committed; notification unavailable';
    INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(v_caller,public.patient_actor_name(),'PAYMENT_SMS_QUEUE_FAILED','PaymentTransaction',v_payment.id::TEXT,jsonb_build_object('bill_id',v_bill.id));
  END;

  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
  VALUES(v_caller,public.patient_actor_name(),'PAYMENT_RECEIVED','PaymentTransaction',v_payment.id::TEXT,jsonb_build_object('bill_id',v_bill.id,'amount_paisa',p_amount_paisa,'payment_mode',p_payment_mode,'new_status',v_new_status));
  v_response:=jsonb_build_object('payment_id',v_payment.id,'receipt_number',v_payment.receipt_number,'bill_id',v_bill.id,'bill_number',v_bill.bill_number,'lab_no',v_lab_no,'amount_paisa',p_amount_paisa,'paid_amount_paisa',v_new_paid,'due_amount_paisa',v_new_due,'payment_status',v_new_status,'sms_queued',v_sms_id IS NOT NULL,'sms_status',v_sms_status);
  UPDATE public.payment_idempotency_requests SET response_json=v_response,completed_at=NOW() WHERE caller_id=v_caller AND idempotency_key=v_key;
  RETURN v_response||jsonb_build_object('idempotency_replay',FALSE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.receive_bill_payment TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.recompute_order_item_calculated_results(p_order_item_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN RETURN; END $$;

GRANT EXECUTE ON FUNCTION public.recompute_order_item_calculated_results TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.record_critical_value_acknowledgement(
    p_order_item_id UUID,
    p_notification_method TEXT,
    p_notified_person TEXT,
    p_comment TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_item public.clinical_order_items%ROWTYPE;
    v_user_name TEXT;
BEGIN
    IF NOT public.has_permission('can_acknowledge_critical') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF NULLIF(btrim(p_notified_person), '') IS NULL THEN
        RAISE EXCEPTION 'The notified clinician or ward staff is required.' USING ERRCODE = '22023';
    END IF;
    IF p_notification_method NOT IN (
        'Direct Phone Call', 'In-Person Verbal Alert',
        'Hospital Intercom', 'Official WhatsApp / SMS'
    ) THEN
        RAISE EXCEPTION 'A supported notification method is required.' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_item FROM public.clinical_order_items
    WHERE id = p_order_item_id FOR UPDATE;
    IF NOT FOUND OR v_item.status = 'SignedOff' THEN
        RAISE EXCEPTION 'This result can no longer be modified.' USING ERRCODE = '55000';
    END IF;
    SELECT COALESCE(full_name, 'Lab Staff') INTO v_user_name
    FROM public.user_profiles WHERE id = auth.uid();
    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(), v_user_name, 'CRITICAL_VALUE_ACKNOWLEDGED',
        'ClinicalOrderItem', p_order_item_id::TEXT,
        jsonb_strip_nulls(jsonb_build_object(
            'notification_method', p_notification_method,
            'notified_person', left(btrim(p_notified_person), 255),
            'comment', NULLIF(left(btrim(COALESCE(p_comment, '')), 1000), '')
        ))
    );
    RETURN jsonb_build_object('success', TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_critical_value_acknowledgement TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.record_hmis_submission(p_report_id uuid,p_submission_date date,p_submitted_to text,p_method text,p_reference text DEFAULT NULL,p_remarks text DEFAULT NULL,p_attachment_path text DEFAULT NULL) RETURNS public.hmis_submission_events LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.hmis_monthly_reports; e public.hmis_submission_events;
BEGIN
 IF NOT public.has_permission('can_finalize_hmis_reports') THEN RAISE EXCEPTION 'HMIS finalize permission required' USING ERRCODE='42501'; END IF;
 SELECT * INTO r FROM public.hmis_monthly_reports WHERE id=p_report_id FOR UPDATE; IF r.current_version=0 THEN RAISE EXCEPTION 'Finalize before submission'; END IF;
 INSERT INTO public.hmis_submission_events(report_id,report_version,submission_date,submitted_to,method,reference_receipt_no,remarks,attachment_path,recorded_by) VALUES(r.id,r.current_version,p_submission_date,p_submitted_to,p_method,p_reference,p_remarks,p_attachment_path,auth.uid()) RETURNING * INTO e;
 UPDATE public.hmis_monthly_reports SET status='Submitted',submitted_at=now(),updated_at=now() WHERE id=r.id; RETURN e;
END $$;

GRANT EXECUTE ON FUNCTION public.record_hmis_submission TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.recover_stale_sms_gateway_items(p_stale_after_seconds INT DEFAULT 300)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE recovered INT:=0; quarantined INT:=0;
BEGIN
 IF p_stale_after_seconds NOT BETWEEN 60 AND 3600 THEN RAISE EXCEPTION 'Stale threshold must be between 60 and 3600 seconds.' USING ERRCODE='22023'; END IF;
 WITH stale AS (SELECT id,provider_call_started_at FROM public.sms_queue_items WHERE status='Processing' AND COALESCE(lease_expires_at,updated_at+make_interval(secs=>p_stale_after_seconds))<=NOW() FOR UPDATE SKIP LOCKED), changed AS (
 UPDATE public.sms_queue_items q SET status=CASE WHEN s.provider_call_started_at IS NULL THEN 'Pending' ELSE 'DeadLetter' END,
   retry_count=CASE WHEN s.provider_call_started_at IS NULL THEN q.retry_count ELSE LEAST(q.retry_count+1,q.max_attempts) END,
   scheduled_at=CASE WHEN s.provider_call_started_at IS NULL THEN NOW() ELSE q.scheduled_at END,
   error_classification=CASE WHEN s.provider_call_started_at IS NULL THEN 'LeaseExpiredBeforeProviderCall' ELSE 'ProviderOutcomeUnknown' END,
   error_message=CASE WHEN s.provider_call_started_at IS NULL THEN 'Gateway lease expired before provider call; safely returned to queue.' ELSE 'Gateway stopped after provider call began; automatic resend blocked because provider outcome is unknown.' END,
   final_state_at=CASE WHEN s.provider_call_started_at IS NULL THEN NULL ELSE NOW() END,lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW()
 FROM stale s WHERE q.id=s.id RETURNING q.status)
 SELECT count(*) FILTER(WHERE status='Pending'),count(*) FILTER(WHERE status='DeadLetter') INTO recovered,quarantined FROM changed;
 RETURN jsonb_build_object('success',true,'recovered',recovered,'deadlettered',quarantined);
END;$$;

GRANT EXECUTE ON FUNCTION public.recover_stale_sms_gateway_items TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.recover_stale_sms_gateway_v2_items(p_instance_id UUID,p_stale_after_seconds INT DEFAULT 300)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE recovered INT:=0;quarantined INT:=0;
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  IF NOT EXISTS(SELECT 1 FROM public.sms_gateway_instances WHERE instance_id=p_instance_id AND claiming_enabled) THEN
    RAISE EXCEPTION 'Gateway v2 claiming is disabled.' USING ERRCODE='55000';
  END IF;
  IF p_stale_after_seconds NOT BETWEEN 60 AND 3600 THEN RAISE EXCEPTION 'Stale threshold must be between 60 and 3600 seconds.' USING ERRCODE='22023'; END IF;
  WITH stale AS (SELECT id,provider_call_started_at FROM public.sms_queue_items WHERE status='Processing' AND
    COALESCE(lease_expires_at,updated_at+make_interval(secs=>p_stale_after_seconds))<=now() FOR UPDATE SKIP LOCKED), changed AS (
    UPDATE public.sms_queue_items q SET status=CASE WHEN s.provider_call_started_at IS NULL THEN 'Pending' ELSE 'DeadLetter' END,
      retry_count=CASE WHEN s.provider_call_started_at IS NULL THEN q.retry_count ELSE LEAST(q.retry_count+1,q.max_attempts) END,
      scheduled_at=CASE WHEN s.provider_call_started_at IS NULL THEN now() ELSE q.scheduled_at END,
      error_classification=CASE WHEN s.provider_call_started_at IS NULL THEN 'LeaseExpiredBeforeProviderCall' ELSE 'ProviderOutcomeUnknown' END,
      error_message=CASE WHEN s.provider_call_started_at IS NULL THEN 'Gateway lease expired before provider call; safely returned to queue.' ELSE 'Gateway stopped after provider call began; automatic resend blocked because provider outcome is unknown.' END,
      final_state_at=CASE WHEN s.provider_call_started_at IS NULL THEN NULL ELSE now() END,lease_owner=NULL,lease_instance_id=NULL,lease_expires_at=NULL,updated_at=now()
    FROM stale s WHERE q.id=s.id RETURNING q.status)
  SELECT count(*) FILTER(WHERE status='Pending'),count(*) FILTER(WHERE status='DeadLetter') INTO recovered,quarantined FROM changed;
  RETURN jsonb_build_object('success',true,'recovered',recovered,'deadlettered',quarantined);
END $$;

GRANT EXECUTE ON FUNCTION public.recover_stale_sms_gateway_v2_items TO authenticated, service_role;

CREATE FUNCTION public.register_report_artifact_worker(p_auth_user_id UUID,p_worker_name TEXT,p_confirmation TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF NOT public.is_super_admin() OR p_confirmation<>'REGISTER_REPORT_ARTIFACT_WORKER' THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_auth_user_id) THEN
    RAISE EXCEPTION 'Auth identity not found.' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM public.user_profiles WHERE id=p_auth_user_id AND is_active)
     OR EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=p_auth_user_id)
     OR EXISTS(SELECT 1 FROM public.user_direct_permissions WHERE user_id=p_auth_user_id) THEN
    RAISE EXCEPTION 'Worker identity must not have LIS staff access.' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.report_artifact_worker_identities(auth_user_id,worker_name,created_by)
  VALUES(p_auth_user_id,p_worker_name,auth.uid());
END $$;

GRANT EXECUTE ON FUNCTION public.register_report_artifact_worker TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.register_sms_gateway_v2_instance(
  p_instance_id UUID,p_auth_user_id UUID,p_hostname TEXT,p_gateway_version TEXT,p_provider_name TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_instance_id IS NULL OR p_auth_user_id IS NULL THEN RAISE EXCEPTION 'Instance and Auth user are required.' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_auth_user_id) THEN RAISE EXCEPTION 'Gateway Auth user does not exist.' USING ERRCODE='P0002'; END IF;
  IF EXISTS(SELECT 1 FROM public.user_profiles WHERE id=p_auth_user_id AND is_active) THEN
    RAISE EXCEPTION 'Gateway Auth user must not be an active LIS staff user.' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.sms_gateway_instances(instance_id,auth_user_id,hostname,gateway_version,provider_name)
  VALUES(p_instance_id,p_auth_user_id,btrim(p_hostname),btrim(p_gateway_version),btrim(p_provider_name))
  ON CONFLICT(instance_id) DO UPDATE SET auth_user_id=EXCLUDED.auth_user_id,hostname=EXCLUDED.hostname,
    gateway_version=EXCLUDED.gateway_version,provider_name=EXCLUDED.provider_name,updated_at=now();
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),'SMS_GATEWAY_V2_REGISTERED','SmsGatewayInstance',p_instance_id::TEXT,
    jsonb_build_object('auth_user_id',p_auth_user_id,'hostname',btrim(p_hostname),'version',btrim(p_gateway_version),'provider',btrim(p_provider_name)));
  RETURN jsonb_build_object('success',true,'instance_id',p_instance_id,'claiming_enabled',false);
END $$;

GRANT EXECUTE ON FUNCTION public.register_sms_gateway_v2_instance TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reject_catalogue_master_evidence_mutation() RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN RAISE EXCEPTION 'Catalogue master source evidence is immutable.' USING ERRCODE='55000'; END $$;

GRANT EXECUTE ON FUNCTION public.reject_catalogue_master_evidence_mutation TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reject_clinical_source_evidence_mutation()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
    RAISE EXCEPTION 'Clinical source evidence is immutable; import a successor source version.'
      USING ERRCODE='55000';
END $$;

GRANT EXECUTE ON FUNCTION public.reject_clinical_source_evidence_mutation TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reject_sms_gateway_v2_local_validation(
  p_instance_id UUID, p_sms_id UUID, p_worker_id UUID, p_error_code TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE changed INT;
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  IF p_error_code NOT IN (
    'INVALID_NEPAL_MOBILE',
    'EMPTY_MESSAGE',
    'SEGMENT_LIMIT_EXCEEDED',
    'SMS_SINGLE_SEGMENT_LIMIT_EXCEEDED',
    'SMS_URL_BLOCKED'
  ) THEN
    RAISE EXCEPTION 'Unsupported local validation code.' USING ERRCODE='22023';
  END IF;
  UPDATE public.sms_queue_items SET status='DeadLetter',retry_count=LEAST(retry_count+1,max_attempts),
    error_message=p_error_code,error_classification='PermanentGatewayValidationFailure',final_state_at=now(),
    lease_owner=NULL,lease_instance_id=NULL,lease_expires_at=NULL,updated_at=now()
  WHERE id=p_sms_id AND status='Processing' AND lease_owner=p_worker_id AND lease_instance_id=p_instance_id
    AND lease_expires_at>now() AND provider_call_started_at IS NULL;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>1 THEN RAISE EXCEPTION 'SMS lease was lost or provider call already started.' USING ERRCODE='40001'; END IF;
  INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data)
  VALUES('SMS_FAILED','SmsQueueItem',p_sms_id::TEXT,
    jsonb_build_object('status','DeadLetter','classification','PermanentGatewayValidationFailure',
      'error_code',p_error_code,'gateway_instance_id',p_instance_id));
  RETURN TRUE;
END $$;

GRANT EXECUTE ON FUNCTION public.reject_sms_gateway_v2_local_validation TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.replace_role_permission_matrix(p_matrix JSONB) RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  entry JSONB;
  role_row public.roles%ROWTYPE;
  seen UUID[] := ARRAY[]::UUID[];
  supplied TEXT[];
  admin_allowed CONSTANT TEXT[] := ARRAY[
    'can_view_dashboard',
    'can_create_bill',
    'can_edit_patient',
    'can_collect_sample',
    'can_receive_sample',
    'can_reject_sample',
    'can_enter_results',
    'can_verify_results',
    'can_acknowledge_critical',
    'can_sign_reports',
    'can_amend_reports',
    'can_print_reports',
    'can_manage_catalogue',
    'can_configure_catalogue_technical',
    'can_manage_ast_breakpoints',
    'can_manage_referring_doctors',
    'can_manage_personnel',
    'can_view_financials',
    'can_manage_users',
    'can_manage_roles',
    'can_view_audit_logs',
    'can_manage_outsource_tracking',
    'can_view_hmis_reports',
    'can_edit_hmis_reports',
    'can_finalize_hmis_reports'
  ];
  technician_allowed CONSTANT TEXT[] := ARRAY[
    'can_view_dashboard',
    'can_create_bill',
    'can_edit_patient',
    'can_collect_sample',
    'can_receive_sample',
    'can_reject_sample',
    'can_enter_results',
    'can_verify_results',
    'can_acknowledge_critical',
    'can_sign_reports',
    'can_amend_reports',
    'can_print_reports',
    'can_manage_outsource_tracking'
  ];
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_roles') OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;

  IF jsonb_typeof(COALESCE(p_matrix, '[]')) <> 'array' THEN
    RAISE EXCEPTION 'Role permission matrix must be an array.' USING ERRCODE='22023';
  END IF;

  FOR entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_matrix, '[]')) LOOP
    SELECT * INTO role_row FROM public.roles WHERE id = (entry->>'role_id')::UUID FOR UPDATE;
    IF NOT FOUND OR role_row.code NOT IN ('admin', 'lab_technician') THEN
      RAISE EXCEPTION 'Only active Administrator and Lab Technician roles may be submitted.' USING ERRCODE='22023';
    END IF;

    IF role_row.id = ANY(seen) THEN
      RAISE EXCEPTION 'A role may occur only once.' USING ERRCODE='23505';
    END IF;

    IF jsonb_typeof(COALESCE(entry->'permissions', '[]')) <> 'array' THEN
      RAISE EXCEPTION 'Permissions must be an array.' USING ERRCODE='22023';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT p ORDER BY p), ARRAY[]::TEXT[])
    INTO supplied
    FROM jsonb_array_elements_text(COALESCE(entry->'permissions', '[]')) p;

    IF role_row.code = 'admin' AND supplied <> ARRAY(SELECT p FROM unnest(admin_allowed) p ORDER BY p) THEN
      RAISE EXCEPTION 'Administrator must retain the complete operational and governance permission set.' USING ERRCODE='23514';
    END IF;

    IF role_row.code = 'lab_technician' AND supplied <> ARRAY(SELECT p FROM unnest(technician_allowed) p ORDER BY p) THEN
      RAISE EXCEPTION 'Lab Technician must retain the complete operational pathology permission set (13 operational permissions).' USING ERRCODE='23514';
    END IF;

    seen := array_append(seen, role_row.id);
  END LOOP;

  FOR entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_matrix, '[]')) LOOP
    DELETE FROM public.role_permissions WHERE role_id = (entry->>'role_id')::UUID;
    INSERT INTO public.role_permissions (role_id, permission_key)
    SELECT (entry->>'role_id')::UUID, p
    FROM jsonb_array_elements_text(entry->'permissions') p;

    INSERT INTO public.audit_logs (user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
      auth.uid(),
      public.catalogue_actor_name(),
      'ROLE_PERMISSIONS_REPLACED',
      'Role',
      entry->>'role_id',
      jsonb_build_object('permissions', entry->'permissions')
    );
  END LOOP;

  RETURN cardinality(seen);
END $$;

GRANT EXECUTE ON FUNCTION public.replace_role_permission_matrix TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.report_artifact_public_url(p_report_id UUID) RETURNS TEXT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE url TEXT;
BEGIN
 SELECT intent.public_url INTO url FROM public.report_pdf_delivery_intents intent JOIN public.order_report_delivery_tokens token ON token.id=intent.order_token_id
 WHERE intent.diagnostic_report_id=p_report_id AND token.is_active AND token.revoked_at IS NULL AND token.expires_at>now()
 AND intent.public_url~'^https://dashboard[.]bimalpathology[.]com[.]np/o/[A-Za-z0-9_-]+$' AND length(substring(intent.public_url FROM '/o/([A-Za-z0-9_-]+)$')) BETWEEN 32 AND 256
 AND encode(extensions.digest(convert_to(substring(intent.public_url FROM '/o/([A-Za-z0-9_-]+)$'),'UTF8'),'sha256'),'hex')=token.token_hash LIMIT 1;
 IF url IS NOT NULL THEN RETURN url; END IF;
 SELECT candidate.public_url INTO url FROM public.public_report_tokens token CROSS JOIN LATERAL(
   SELECT presentation.public_url,0 priority FROM public.report_secure_link_presentations presentation WHERE presentation.report_token_id=token.id
   UNION ALL SELECT substring(message.message_body FROM '(https://(lis|dashboard)[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+)'),1 FROM public.sms_queue_items message JOIN public.diagnostic_reports report ON report.id=message.diagnostic_report_id WHERE message.diagnostic_report_id=p_report_id AND message.sms_type='ReportReady' AND message.idempotency_key='REPORT_READY:'||p_report_id::text||':'||report.version::text
 )candidate WHERE token.diagnostic_report_id=p_report_id AND token.is_active AND token.revoked_at IS NULL AND token.expires_at>now() AND candidate.public_url~'^https://(lis|dashboard)[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+$' AND length(substring(candidate.public_url FROM '/r/([A-Za-z0-9_-]+)$')) BETWEEN 32 AND 256 AND encode(extensions.digest(convert_to(substring(candidate.public_url FROM '/r/([A-Za-z0-9_-]+)$'),'UTF8'),'sha256'),'hex')=token.token_hash ORDER BY candidate.priority,token.created_at DESC LIMIT 1;
 RETURN url;
END $$;

GRANT EXECUTE ON FUNCTION public.report_artifact_public_url TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.require_outsource_tracking_permission()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_outsource_tracking') THEN
        RAISE EXCEPTION 'Access denied: can_manage_outsource_tracking permission required.';
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.require_outsource_tracking_permission TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.resolve_public_report_by_token(p_token_hash VARCHAR(128))
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_token public.public_report_tokens%ROWTYPE;
    v_report public.diagnostic_reports%ROWTYPE;
BEGIN
    IF p_token_hash IS NULL OR btrim(p_token_hash) = '' THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Token is required.');
    END IF;
    SELECT * INTO v_token FROM public.public_report_tokens WHERE token_hash = btrim(p_token_hash) FOR UPDATE;
    IF NOT FOUND OR v_token.is_active IS NOT TRUE OR v_token.revoked_at IS NOT NULL OR v_token.expires_at < NOW() THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Invalid or expired report link.');
    END IF;
    SELECT * INTO v_report FROM public.diagnostic_reports WHERE id = v_token.diagnostic_report_id;
    IF NOT FOUND OR v_report.status NOT IN ('SignedOff', 'Amended') THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Report is not available.');
    END IF;
    UPDATE public.public_report_tokens SET access_count = access_count + 1, last_accessed_at = NOW()
    WHERE id = v_token.id;
    INSERT INTO public.audit_logs(action, entity_type, entity_id, new_data)
    VALUES ('PUBLIC_REPORT_VIEWED', 'DiagnosticReport', v_report.report_number,
        jsonb_build_object('token_id', v_token.id, 'report_id', v_report.id,
            'version', v_report.version, 'access_count', v_token.access_count + 1));
    RETURN jsonb_build_object(
        'valid', TRUE, 'report_number', v_report.report_number, 'version', v_report.version,
        'is_amendment', v_report.is_amendment, 'amendment_reason', v_report.amendment_reason,
        'signed_at', v_report.signed_at, 'integrity_hash', v_report.integrity_hash,
        'snapshot', v_report.clinical_snapshot_json
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_public_report_by_token TO authenticated, anon, service_role;

CREATE OR REPLACE FUNCTION public.retry_sms_delivery(p_sms_id UUID,p_reason TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q public.sms_queue_items%ROWTYPE; reason TEXT:=btrim(COALESCE(p_reason,''));
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_users') OR public.is_super_admin()) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF length(reason) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'A retry reason is required.' USING ERRCODE='22023'; END IF;
 SELECT * INTO q FROM public.sms_queue_items WHERE id=p_sms_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'SMS queue item not found.' USING ERRCODE='P0002'; END IF;
 IF q.status='Sent' THEN RAISE EXCEPTION 'Sent SMS cannot be retried.' USING ERRCODE='55000'; END IF;
 IF q.status NOT IN ('Failed','DeadLetter') THEN RAISE EXCEPTION 'Only Failed or DeadLetter SMS may be retried.' USING ERRCODE='55000'; END IF;
 UPDATE public.sms_queue_items SET status='Pending',retry_count=0,scheduled_at=NOW(),final_state_at=NULL,error_classification='ManualRetry',
  manual_retry_count=manual_retry_count+1,last_manual_retry_at=NOW(),last_manual_retry_by=auth.uid(),lease_owner=NULL,lease_expires_at=NULL,provider_call_started_at=NULL,updated_at=NOW() WHERE id=p_sms_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,new_data) VALUES(auth.uid(),'SMS_MANUAL_RETRY','SmsQueueItem',p_sms_id::TEXT,jsonb_build_object('reason',reason,'previous_status',q.status,'manual_retry_count',q.manual_retry_count+1));
 RETURN jsonb_build_object('success',true,'status','Pending','id',p_sms_id);
END;$$;

GRANT EXECUTE ON FUNCTION public.retry_sms_delivery TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.revoke_public_report_token(
    p_token_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_tok RECORD;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    IF NOT (public.has_permission('can_sign_reports') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Access Denied: Missing permissions to revoke public report tokens.';
    END IF;

    SELECT * INTO v_tok FROM public.public_report_tokens WHERE id = p_token_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Token % not found.', p_token_id;
    END IF;

    UPDATE public.public_report_tokens
    SET is_active = FALSE,
        revoked_at = NOW(),
        updated_at = NOW()
    WHERE id = p_token_id;

    INSERT INTO public.audit_logs (
        user_id,
        user_name,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        auth.uid(),
        'Authorized Staff',
        'PUBLIC_REPORT_TOKEN_REVOKED',
        'PublicReportToken',
        p_token_id::TEXT,
        jsonb_build_object('token_id', p_token_id, 'reason', p_reason)
    );

    RETURN jsonb_build_object('success', TRUE, 'revoked_token_id', p_token_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_public_report_token TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.run_governed_order_item_calculations(p_order_item_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
 item public.clinical_order_items%ROWTYPE;
 ord public.clinical_orders%ROWTYPE;
 patient public.patients%ROWTYPE;
 def RECORD;
 inp RECORD;
 source RECORD;
 inputs JSONB;
 input_snapshot JSONB;
 raw_value NUMERIC;
 shown NUMERIC;
 output_result UUID;
 run_status TEXT;
 error_code TEXT;
 dependency_hash TEXT;
 missing JSONB;
 source_count INT;
BEGIN
 SELECT * INTO item FROM public.clinical_order_items WHERE id=p_order_item_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='CALCULATION_ORDER_ITEM_NOT_FOUND'; END IF;
 IF item.status='SignedOff' THEN RETURN; END IF;

 SELECT * INTO ord FROM public.clinical_orders WHERE id=item.order_id;
 SELECT * INTO patient FROM public.patients WHERE id=ord.patient_id;

 FOR def IN SELECT f.* FROM public.clinical_calculation_formula_versions f
   JOIN public.parameters op ON op.id=f.output_parameter_id
   WHERE f.lifecycle_status='Approved'
     AND f.scope_test_id=item.test_id
     AND op.test_id=item.test_id
     AND f.effective_from<=now()
     AND (f.effective_to IS NULL OR f.effective_to>now())
   ORDER BY f.execution_order,f.formula_identifier,f.formula_version
 LOOP
  inputs:='{}';
  input_snapshot:='[]';
  missing:='[]';
  run_status:='Calculated';
  error_code:=NULL;

  SELECT tr.id INTO output_result FROM public.test_results tr WHERE tr.order_item_id=item.id AND tr.parameter_id=def.output_parameter_id FOR UPDATE;
  IF output_result IS NULL THEN CONTINUE; END IF;
  UPDATE public.test_results SET numeric_value=NULL,display_value='Pending calculation',updated_at=now() WHERE id=output_result;

  FOR inp IN SELECT * FROM public.clinical_calculation_formula_inputs WHERE formula_version_id=def.id ORDER BY ordinal LOOP
   SELECT NULL::UUID id,NULL::NUMERIC numeric_value,NULL::TEXT unit,NULL::UUID parameter_id,NULL::UUID source_item_id,NULL::BIGINT source_revision INTO source;
   source_count:=0;

   IF inp.source_type='SAME_TEST_PARAMETER' THEN
    SELECT tr.id,tr.numeric_value,tr.unit::TEXT,p.id parameter_id,item.id source_item_id,item.result_revision source_revision
      INTO source FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id
      WHERE tr.order_item_id=item.id AND p.id=inp.parameter_id;

   ELSIF inp.source_type='SAME_ORDER_CANONICAL_PARAMETER' THEN
    SELECT count(*) INTO source_count FROM public.test_results tr JOIN public.clinical_order_items oi ON oi.id=tr.order_item_id
      WHERE oi.order_id=item.order_id AND tr.parameter_id=inp.parameter_id AND tr.numeric_value IS NOT NULL;
    IF source_count>1 THEN
      RAISE EXCEPTION USING ERRCODE='21000',MESSAGE='CALCULATION_DEPENDENCY_AMBIGUOUS',DETAIL=jsonb_build_object('formula',def.formula_identifier,'input',inp.input_key)::TEXT;
    END IF;
    SELECT tr.id,tr.numeric_value,tr.unit::TEXT,tr.parameter_id,oi.id source_item_id,oi.result_revision source_revision
      INTO source FROM public.test_results tr JOIN public.clinical_order_items oi ON oi.id=tr.order_item_id
      WHERE oi.order_id=item.order_id AND tr.parameter_id=inp.parameter_id AND tr.numeric_value IS NOT NULL;

   ELSIF inp.source_type='PATIENT_DEMOGRAPHIC' THEN
    IF inp.source_identifier='AGE_YEARS' THEN
      source.numeric_value:=(CASE WHEN patient.dob IS NOT NULL THEN extract(year FROM age(ord.order_date_ad,patient.dob)) ELSE patient.age_years END)::NUMERIC;
      source.unit:='years'::TEXT;
    ELSIF inp.source_identifier='SEX_FEMALE' THEN
      source.numeric_value:=(CASE patient.gender WHEN 'Female' THEN 1 WHEN 'Male' THEN 0 ELSE NULL END)::NUMERIC;
      source.unit:='boolean'::TEXT;
    END IF;
    source.parameter_id:=NULL;
    source.id:=NULL;
    source.source_item_id:=NULL;
    source.source_revision:=0;

   ELSIF inp.source_type='FIXED_CONFIG_VALUE' THEN
    source.numeric_value:=NULLIF(inp.compatibility_rule->>'value','')::NUMERIC;
    source.unit:=inp.canonical_unit;
    source.source_revision:=0;
   END IF;

   IF source.numeric_value IS NULL THEN
    missing:=missing||jsonb_build_object('input_key',inp.input_key,'source_type',inp.source_type,'source_identifier',inp.source_identifier,'behavior',inp.missing_input_behavior);
    CONTINUE;
   END IF;

   raw_value:=public.normalize_clinical_calculation_input(source.numeric_value,source.unit,inp.canonical_unit);
   inputs:=jsonb_set(inputs,ARRAY[inp.input_key],to_jsonb(raw_value));
   input_snapshot:=input_snapshot||jsonb_build_object(
     'input_key',inp.input_key,
     'source_type',inp.source_type,
     'source_identifier',inp.source_identifier,
     'parameter_id',source.parameter_id,
     'result_id',source.id,
     'source_order_item_id',source.source_item_id,
     'source_revision',source.source_revision,
     'supplied_value',source.numeric_value,
     'supplied_unit',source.unit,
     'normalized_value',raw_value,
     'canonical_unit',inp.canonical_unit
   );
  END LOOP;

  dependency_hash:=encode(extensions.digest((input_snapshot||missing)::TEXT,'sha256'),'hex');

  IF jsonb_array_length(missing)>0 THEN
    run_status:='MissingInput';
    error_code:='CALCULATION_DEPENDENCY_MISSING';
  ELSE
   BEGIN
    raw_value:=public.evaluate_governed_formula(def.formula_key,inputs);
    shown:=round(raw_value,def.rounding_scale);
    UPDATE public.test_results SET numeric_value=shown,display_value=shown::TEXT,unit=def.output_unit,updated_at=now() WHERE id=output_result;
   EXCEPTION
    WHEN division_by_zero THEN
      run_status:='DivisionByZero';
      error_code:='CALCULATION_DIVISION_BY_ZERO';
      raw_value:=NULL;
      shown:=NULL;
    WHEN OTHERS THEN
      run_status:='InvalidInput';
      error_code:=SQLERRM;
      raw_value:=NULL;
      shown:=NULL;
   END;
  END IF;

  INSERT INTO public.clinical_calculation_runs(
    order_item_id,formula_version_id,output_result_id,source_result_revision,input_snapshot,
    calculated_raw_value,rounding_rule,displayed_value,output_unit,calculation_status,error_code,
    formula_snapshot,dependency_revision_hash
  )
  VALUES(
    item.id,def.id,output_result,item.result_revision,
    input_snapshot||jsonb_build_object('missing_dependencies',missing),
    raw_value,jsonb_build_object('mode',def.rounding_mode,'scale',def.rounding_scale),
    shown::TEXT,def.output_unit,run_status,error_code,
    jsonb_build_object('identifier',def.formula_identifier,'version',def.formula_version,'scope_test_id',def.scope_test_id,'expression',def.formula_expression,'definition_hash',def.definition_hash),
    dependency_hash
  )
  ON CONFLICT(order_item_id,formula_version_id,dependency_revision_hash) WHERE dependency_revision_hash IS NOT NULL DO NOTHING;
 END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.run_governed_order_item_calculations TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.save_pt_inr_reagent_config(
    p_reagent_name TEXT,
    p_isi NUMERIC,
    p_mnpt NUMERIC,
    p_manufacturer TEXT DEFAULT NULL,
    p_lot_number TEXT DEFAULT NULL,
    p_expiry_date DATE DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_new_id UUID;
    v_result jsonb;
BEGIN
    -- RBAC check: Admin only
    IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_catalogue') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Access denied: Only administrators can configure PT/INR reagent parameters (MNPT & ISI)' USING ERRCODE = '42501';
    END IF;

    -- Validation
    IF p_reagent_name IS NULL OR TRIM(p_reagent_name) = '' THEN
        RAISE EXCEPTION 'Reagent name is required';
    END IF;
    IF p_isi IS NULL OR p_isi <= 0 THEN
        RAISE EXCEPTION 'ISI must be a positive number greater than 0';
    END IF;
    IF p_mnpt IS NULL OR p_mnpt <= 0 THEN
        RAISE EXCEPTION 'MNPT must be a positive number in seconds greater than 0';
    END IF;

    -- Deactivate all currently active configs (preserve history)
    UPDATE public.pt_inr_reagent_configs
    SET is_active = FALSE,
        effective_to = NOW(),
        updated_at = NOW()
    WHERE is_active = TRUE;

    -- Insert new active config
    INSERT INTO public.pt_inr_reagent_configs (
        reagent_name,
        manufacturer,
        lot_number,
        expiry_date,
        isi,
        mnpt,
        effective_from,
        is_active,
        notes,
        created_by
    ) VALUES (
        TRIM(p_reagent_name),
        NULLIF(TRIM(p_manufacturer), ''),
        NULLIF(TRIM(p_lot_number), ''),
        p_expiry_date,
        p_isi,
        p_mnpt,
        NOW(),
        TRUE,
        NULLIF(TRIM(p_notes), ''),
        auth.uid()
    )
    RETURNING id INTO v_new_id;

    -- Audit logging
    INSERT INTO public.audit_logs (user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(),
        'Administrator',
        'PT_INR_REAGENT_CONFIG_UPDATED',
        'ReagentConfig',
        v_new_id::text,
        jsonb_build_object(
            'reagent_name', p_reagent_name,
            'isi', p_isi,
            'mnpt', p_mnpt,
            'lot_number', p_lot_number,
            'manufacturer', p_manufacturer,
            'expiry_date', p_expiry_date
        )
    );

    SELECT row_to_json(c.*)::jsonb INTO v_result
    FROM public.pt_inr_reagent_configs c
    WHERE c.id = v_new_id;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_pt_inr_reagent_config TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.save_pus_culture_worksheet(p_order_item_id UUID,p_payload JSONB,p_expected_revision BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE prior public.pus_culture_worksheets%ROWTYPE; saved public.pus_culture_worksheets%ROWTYPE; test_code TEXT;
 source_value TEXT:=btrim(COALESCE(p_payload->>'specimen_source','')); other_value TEXT:=NULLIF(btrim(COALESCE(p_payload->>'specimen_source_other','')),'');
 pus_cells TEXT:=btrim(COALESCE(p_payload->>'gram_stain_pus_cells','')); culture_value TEXT:=btrim(COALESCE(p_payload->>'culture_status',''));
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT public.has_permission('can_enter_results') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT t.code INTO test_code FROM public.clinical_order_items oi JOIN public.tests t ON t.id=oi.test_id WHERE oi.id=p_order_item_id;
 IF test_code IS DISTINCT FROM 'PUS_CULTURE_AND_SENSITIVITY' THEN RAISE EXCEPTION 'Pus Culture order item required.' USING ERRCODE='23514'; END IF;
 IF source_value NOT IN('Wound Swab','Abscess Aspirate','Surgical Site','Ulcer Swab','Tissue Biopsy','Other') OR
    pus_cells NOT IN('Occasional (0-1 / LPF)','Few (1-5 / HPF)','Moderate (5-20 / HPF)','Plenty / Numerous (>20 / HPF)') OR
    culture_value NOT IN('No growth after 48 hours of aerobic incubation at 37°C','Growth obtained (Pathogen isolated)','Mixed bacterial growth (Skin flora / Probable contamination)','Light growth of doubtful clinical significance') THEN
   RAISE EXCEPTION 'Complete the controlled specimen, smear and culture fields.' USING ERRCODE='23514';
 END IF;
 IF source_value='Other' AND other_value IS NULL THEN RAISE EXCEPTION 'Specify the Other specimen source/site.' USING ERRCODE='23514'; END IF;
 SELECT * INTO prior FROM public.pus_culture_worksheets WHERE order_item_id=p_order_item_id FOR UPDATE;
 IF FOUND AND prior.row_version<>p_expected_revision THEN RAISE EXCEPTION 'PUS_CULTURE_WORKSHEET_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 INSERT INTO public.pus_culture_worksheets(order_item_id,specimen_source,specimen_source_other,gram_stain_pus_cells,direct_smear_organisms,culture_status,final_remarks,status,created_by,updated_by)
 VALUES(p_order_item_id,source_value,other_value,pus_cells,btrim(COALESCE(p_payload->>'direct_smear_organisms','')),culture_value,btrim(COALESCE(p_payload->>'final_remarks','')),COALESCE(NULLIF(p_payload->>'status',''),'Draft'),auth.uid(),auth.uid())
 ON CONFLICT(order_item_id) DO UPDATE SET specimen_source=EXCLUDED.specimen_source,specimen_source_other=EXCLUDED.specimen_source_other,
  gram_stain_pus_cells=EXCLUDED.gram_stain_pus_cells,direct_smear_organisms=EXCLUDED.direct_smear_organisms,culture_status=EXCLUDED.culture_status,
  final_remarks=EXCLUDED.final_remarks,status=EXCLUDED.status,row_version=public.pus_culture_worksheets.row_version+1,updated_by=auth.uid(),updated_at=now()
 RETURNING * INTO saved;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
 VALUES(auth.uid(),public.catalogue_actor_name(),'PUS_CULTURE_WORKSHEET_SAVED','ClinicalOrderItem',p_order_item_id::TEXT,
  CASE WHEN prior.id IS NULL THEN NULL ELSE jsonb_build_object('row_version',prior.row_version,'status',prior.status) END,
  jsonb_build_object('row_version',saved.row_version,'status',saved.status,'specimen_source',saved.specimen_source,'culture_status',saved.culture_status));
 RETURN to_jsonb(saved);
END $$;

GRANT EXECUTE ON FUNCTION public.save_pus_culture_worksheet TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.save_referring_doctor(p_doctor JSONB) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result_id UUID; old_row JSONB;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_referring_doctors') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF btrim(COALESCE(p_doctor->>'full_name',''))='' THEN RAISE EXCEPTION 'Doctor name is required.' USING ERRCODE='22023'; END IF;
 IF NULLIF(p_doctor->>'id','') IS NOT NULL THEN SELECT to_jsonb(d),d.id INTO old_row,result_id FROM public.referring_doctors d WHERE d.id=(p_doctor->>'id')::UUID FOR UPDATE; IF result_id IS NULL THEN RAISE EXCEPTION 'Referring doctor no longer exists.' USING ERRCODE='P0002'; END IF; UPDATE public.referring_doctors SET full_name=btrim(p_doctor->>'full_name'),code=NULLIF(upper(btrim(p_doctor->>'code')),''),degree=NULLIF(btrim(p_doctor->>'degree'),''),institution=NULLIF(btrim(p_doctor->>'institution'),''),phone=NULLIF(btrim(p_doctor->>'phone'),''),email=NULLIF(btrim(p_doctor->>'email'),''),address=NULLIF(btrim(p_doctor->>'address'),''),is_active=COALESCE((p_doctor->>'is_active')::BOOLEAN,TRUE),updated_at=NOW() WHERE id=result_id;
 ELSE INSERT INTO public.referring_doctors(full_name,code,degree,institution,phone,email,address,is_active) VALUES(btrim(p_doctor->>'full_name'),NULLIF(upper(btrim(p_doctor->>'code')),''),NULLIF(btrim(p_doctor->>'degree'),''),NULLIF(btrim(p_doctor->>'institution'),''),NULLIF(btrim(p_doctor->>'phone'),''),NULLIF(btrim(p_doctor->>'email'),''),NULLIF(btrim(p_doctor->>'address'),''),COALESCE((p_doctor->>'is_active')::BOOLEAN,TRUE)) RETURNING id INTO result_id; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'REFERRING_DOCTOR_SAVED','ReferringDoctor',result_id::TEXT,old_row,(SELECT to_jsonb(d) FROM public.referring_doctors d WHERE d.id=result_id)); RETURN result_id;
END $$;

GRANT EXECUTE ON FUNCTION public.save_referring_doctor TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.save_reporting_personnel(p_personnel JSONB) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result_id UUID; old_row JSONB;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_personnel') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF btrim(COALESCE(p_personnel->>'full_name',''))='' OR btrim(COALESCE(p_personnel->>'qualification',''))='' OR btrim(COALESCE(p_personnel->>'registration_council',''))='' OR btrim(COALESCE(p_personnel->>'registration_number',''))='' THEN RAISE EXCEPTION 'Name, qualification, council and registration number are required.' USING ERRCODE='22023'; END IF;
 IF NULLIF(p_personnel->>'id','') IS NOT NULL THEN SELECT to_jsonb(r),r.id INTO old_row,result_id FROM public.reporting_personnel r WHERE r.id=(p_personnel->>'id')::UUID FOR UPDATE; IF result_id IS NULL THEN RAISE EXCEPTION 'Reporting personnel no longer exists.' USING ERRCODE='P0002'; END IF; UPDATE public.reporting_personnel SET full_name=btrim(p_personnel->>'full_name'),professional_type=(p_personnel->>'professional_type')::public.professional_type_enum,qualification=btrim(p_personnel->>'qualification'),registration_council=btrim(p_personnel->>'registration_council'),registration_number=btrim(p_personnel->>'registration_number'),specialization=NULLIF(btrim(p_personnel->>'specialization'),''),phone=NULLIF(btrim(p_personnel->>'phone'),''),email=NULLIF(btrim(p_personnel->>'email'),''),can_enter_results=COALESCE((p_personnel->>'can_enter_results')::BOOLEAN,TRUE),can_verify_results=COALESCE((p_personnel->>'can_verify_results')::BOOLEAN,FALSE),can_acknowledge_critical=COALESCE((p_personnel->>'can_acknowledge_critical')::BOOLEAN,FALSE),can_sign_reports=COALESCE((p_personnel->>'can_sign_reports')::BOOLEAN,FALSE),is_active=COALESCE((p_personnel->>'is_active')::BOOLEAN,TRUE),display_order=COALESCE((p_personnel->>'display_order')::INT,0),updated_at=NOW() WHERE id=result_id;
 ELSE INSERT INTO public.reporting_personnel(full_name,professional_type,qualification,registration_council,registration_number,specialization,phone,email,can_enter_results,can_verify_results,can_acknowledge_critical,can_sign_reports,is_active,display_order) VALUES(btrim(p_personnel->>'full_name'),(p_personnel->>'professional_type')::public.professional_type_enum,btrim(p_personnel->>'qualification'),btrim(p_personnel->>'registration_council'),btrim(p_personnel->>'registration_number'),NULLIF(btrim(p_personnel->>'specialization'),''),NULLIF(btrim(p_personnel->>'phone'),''),NULLIF(btrim(p_personnel->>'email'),''),COALESCE((p_personnel->>'can_enter_results')::BOOLEAN,TRUE),COALESCE((p_personnel->>'can_verify_results')::BOOLEAN,FALSE),COALESCE((p_personnel->>'can_acknowledge_critical')::BOOLEAN,FALSE),COALESCE((p_personnel->>'can_sign_reports')::BOOLEAN,FALSE),COALESCE((p_personnel->>'is_active')::BOOLEAN,TRUE),COALESCE((p_personnel->>'display_order')::INT,0)) RETURNING id INTO result_id; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'REPORTING_PERSONNEL_SAVED','ReportingPersonnel',result_id::TEXT,old_row,(SELECT to_jsonb(r) FROM public.reporting_personnel r WHERE r.id=result_id)); RETURN result_id;
END $$;

GRANT EXECUTE ON FUNCTION public.save_reporting_personnel TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.save_test_results(
  p_order_item_id UUID,
  p_results JSONB,
  p_target_status public.result_status_enum,
  p_amended_from_report_id UUID,
  p_amendment_reason TEXT,
  p_expected_revision BIGINT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
 response JSONB;
 source_order UUID;
 dependent RECORD;
BEGIN
 response:=public.save_test_results_scoping_internal_00090(
   p_order_item_id,p_results,p_target_status,p_amended_from_report_id,p_amendment_reason,p_expected_revision
 );
 SELECT order_id INTO source_order FROM public.clinical_order_items WHERE id=p_order_item_id;
 PERFORM public.run_governed_order_item_calculations(p_order_item_id);

 IF p_target_status='Verified' AND EXISTS(
   SELECT 1 FROM public.clinical_calculation_formula_versions f
   LEFT JOIN LATERAL(
     SELECT r.calculation_status FROM public.clinical_calculation_runs r
     WHERE r.order_item_id=p_order_item_id AND r.formula_version_id=f.id
     ORDER BY r.calculated_at DESC LIMIT 1
   ) latest ON TRUE
   WHERE f.scope_test_id=(SELECT test_id FROM public.clinical_order_items WHERE id=p_order_item_id)
     AND f.lifecycle_status='Approved'
     AND COALESCE(latest.calculation_status,'MissingInput')<>'Calculated'
 ) THEN
   RAISE EXCEPTION 'CALCULATION_DEPENDENCIES_BLOCK_VERIFICATION' USING ERRCODE='23514';
 END IF;

 FOR dependent IN SELECT DISTINCT oi.id FROM public.clinical_order_items oi
   JOIN public.clinical_calculation_formula_versions f ON f.scope_test_id=oi.test_id AND f.lifecycle_status='Approved'
   JOIN public.clinical_calculation_formula_inputs i ON i.formula_version_id=f.id
   WHERE oi.order_id=source_order AND oi.id<>p_order_item_id AND oi.status NOT IN('Verified','SignedOff') AND i.source_type='SAME_ORDER_CANONICAL_PARAMETER'
     AND i.parameter_id IN(SELECT parameter_id FROM public.test_results WHERE order_item_id=p_order_item_id)
 LOOP
   PERFORM public.run_governed_order_item_calculations(dependent.id);
 END LOOP;

 RETURN response;
END $$;

GRANT EXECUTE ON FUNCTION public.save_test_results TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.save_test_results_unversioned_internal(
    p_order_item_id UUID,
    p_results JSONB,
    p_target_status public.result_status_enum,
    p_amended_from_report_id UUID DEFAULT NULL,
    p_amendment_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_item public.clinical_order_items%ROWTYPE;
    v_order public.clinical_orders%ROWTYPE;
    v_parent public.diagnostic_reports%ROWTYPE;
    v_result JSONB;
    v_parameter public.parameters%ROWTYPE;
    v_existing public.test_results%ROWTYPE;
    v_user_name TEXT;
    v_is_amendment BOOLEAN := FALSE;
    v_count INT := 0;
    v_item_status TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF jsonb_typeof(p_results) <> 'array' OR jsonb_array_length(p_results) = 0 THEN
        RAISE EXCEPTION 'At least one result is required.' USING ERRCODE = '22023';
    END IF;
    IF p_target_status NOT IN ('Draft', 'SubmittedForVerification', 'ReturnedForCorrection', 'Verified') THEN
        RAISE EXCEPTION 'Unsupported result workflow state.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_item FROM public.clinical_order_items
    WHERE id = p_order_item_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Result work item was not found.' USING ERRCODE = 'P0002';
    END IF;
    SELECT * INTO v_order FROM public.clinical_orders WHERE id = v_item.order_id FOR UPDATE;

    IF p_amended_from_report_id IS NOT NULL THEN
        SELECT * INTO v_parent FROM public.diagnostic_reports
        WHERE id = p_amended_from_report_id AND order_id = v_item.order_id
          AND status IN ('SignedOff', 'Amended');
        IF NOT FOUND OR NULLIF(btrim(p_amendment_reason), '') IS NULL
           OR NOT public.has_permission('can_amend_reports') THEN
            RAISE EXCEPTION 'A valid authorized amendment and reason are required.' USING ERRCODE = '42501';
        END IF;
        v_is_amendment := TRUE;
    END IF;

    IF p_target_status IN ('Draft', 'SubmittedForVerification')
       AND NOT (public.has_permission('can_enter_results') OR public.has_permission('can_verify_results')) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF p_target_status IN ('ReturnedForCorrection', 'Verified')
       AND NOT public.has_permission('can_verify_results') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF v_item.status = 'SignedOff' AND NOT v_is_amendment THEN
        RAISE EXCEPTION 'This result can no longer be modified.' USING ERRCODE = '55000';
    END IF;

    IF p_target_status = 'ReturnedForCorrection'
       AND NOT EXISTS (SELECT 1 FROM public.test_results WHERE order_item_id = p_order_item_id AND status IN ('SubmittedForVerification', 'Verified')) THEN
        RAISE EXCEPTION 'Only submitted results may be returned for correction.' USING ERRCODE = '55000';
    END IF;

    IF p_target_status = 'Verified' AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_results) r
        WHERE COALESCE((r->>'is_critical')::BOOLEAN, FALSE)
          AND NOT COALESCE((r->>'critical_acknowledged')::BOOLEAN, FALSE)
    ) THEN
        RAISE EXCEPTION 'Critical results must be acknowledged before verification.' USING ERRCODE = '55000';
    END IF;

    SELECT COALESCE(full_name, 'Lab Staff') INTO v_user_name
    FROM public.user_profiles WHERE id = auth.uid();

    FOR v_result IN SELECT value FROM jsonb_array_elements(p_results)
    LOOP
        SELECT p.* INTO v_parameter
        FROM public.parameters p
        WHERE p.id = (v_result->>'parameter_id')::UUID
          AND (
            p.test_id = v_item.test_id
            OR p.test_id IN (
              SELECT cpc.component_test_id 
              FROM public.catalogue_panel_components cpc
              WHERE (cpc.panel_test_id = v_item.test_id OR cpc.panel_id = v_item.test_id)
                AND cpc.component_test_id IS NOT NULL
            )
            OR p.id IN (
              SELECT cpc.component_parameter_id
              FROM public.catalogue_panel_components cpc
              WHERE (cpc.panel_test_id = v_item.test_id OR cpc.panel_id = v_item.test_id)
                AND cpc.component_parameter_id IS NOT NULL
            )
          )
          AND p.is_active = TRUE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'A submitted parameter is not valid for this investigation.' USING ERRCODE = '22023';
        END IF;

        SELECT * INTO v_existing FROM public.test_results
        WHERE order_item_id = p_order_item_id AND parameter_id = v_parameter.id
        FOR UPDATE;
        IF FOUND AND v_existing.status = 'SignedOff' AND NOT v_is_amendment THEN
            RAISE EXCEPTION 'This result can no longer be modified.' USING ERRCODE = '55000';
        END IF;

        INSERT INTO public.test_results(
            order_item_id, parameter_id, parameter_name, unit, value_type,
            numeric_value, text_value, display_value, flag, is_critical,
            critical_acknowledged, critical_acknowledged_by, critical_acknowledged_at,
            normal_range_text, normal_min, normal_max, critical_low, critical_high,
            status, entered_by, entered_by_name, entered_at,
            verified_by, verified_by_name, verified_at, updated_at
        ) VALUES (
            p_order_item_id, v_parameter.id, v_parameter.name, v_parameter.unit, v_parameter.value_type,
            NULLIF(v_result->>'numeric_value', '')::NUMERIC,
            NULLIF(v_result->>'text_value', ''), COALESCE(v_result->>'display_value', ''),
            COALESCE((v_result->>'flag')::public.result_flag_enum, 'Normal'),
            COALESCE((v_result->>'is_critical')::BOOLEAN, FALSE),
            COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE),
            CASE WHEN COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE) THEN auth.uid() ELSE NULL END,
            CASE WHEN COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE) THEN NOW() ELSE NULL END,
            NULLIF(v_result->>'normal_range_text', ''), NULLIF(v_result->>'normal_min', '')::NUMERIC,
            NULLIF(v_result->>'normal_max', '')::NUMERIC, NULLIF(v_result->>'critical_low', '')::NUMERIC,
            NULLIF(v_result->>'critical_high', '')::NUMERIC, p_target_status,
            COALESCE(v_existing.entered_by, auth.uid()),
            COALESCE(v_existing.entered_by_name, v_user_name),
            COALESCE(v_existing.entered_at, NOW()),
            CASE WHEN p_target_status = 'Verified' THEN auth.uid() ELSE NULL END,
            CASE WHEN p_target_status = 'Verified' THEN v_user_name ELSE NULL END,
            CASE WHEN p_target_status = 'Verified' THEN NOW() ELSE NULL END,
            NOW()
        )
        ON CONFLICT (order_item_id, parameter_id) DO UPDATE SET
            parameter_name = EXCLUDED.parameter_name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
            numeric_value = EXCLUDED.numeric_value, text_value = EXCLUDED.text_value,
            display_value = EXCLUDED.display_value, flag = EXCLUDED.flag,
            is_critical = EXCLUDED.is_critical, critical_acknowledged = EXCLUDED.critical_acknowledged,
            critical_acknowledged_by = EXCLUDED.critical_acknowledged_by,
            critical_acknowledged_at = EXCLUDED.critical_acknowledged_at,
            normal_range_text = EXCLUDED.normal_range_text, normal_min = EXCLUDED.normal_min,
            normal_max = EXCLUDED.normal_max, critical_low = EXCLUDED.critical_low,
            critical_high = EXCLUDED.critical_high, status = EXCLUDED.status,
            entered_by = COALESCE(public.test_results.entered_by, EXCLUDED.entered_by),
            entered_by_name = COALESCE(public.test_results.entered_by_name, EXCLUDED.entered_by_name),
            entered_at = COALESCE(public.test_results.entered_at, EXCLUDED.entered_at),
            verified_by = EXCLUDED.verified_by, verified_by_name = EXCLUDED.verified_by_name,
            verified_at = EXCLUDED.verified_at, signed_off_by = NULL, signed_off_name = NULL,
            signed_off_at = NULL, updated_at = NOW();
        v_count := v_count + 1;
    END LOOP;

    v_item_status := CASE WHEN p_target_status = 'Verified' THEN 'Verified' ELSE 'ResultDrafted' END;
    UPDATE public.clinical_order_items SET status = v_item_status, updated_at = NOW()
    WHERE id = p_order_item_id;
    IF v_order.status = 'SignedOff' AND v_is_amendment THEN
        UPDATE public.clinical_orders SET status = 'InProgress', updated_at = NOW() WHERE id = v_order.id;
    END IF;

    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(), v_user_name,
        CASE p_target_status WHEN 'Verified' THEN 'RESULTS_VERIFIED'
          WHEN 'SubmittedForVerification' THEN 'RESULTS_SUBMITTED'
          WHEN 'ReturnedForCorrection' THEN 'RESULTS_RETURNED' ELSE 'RESULTS_SAVED' END,
        'ClinicalOrderItem', p_order_item_id::TEXT,
        jsonb_strip_nulls(jsonb_build_object(
            'status', p_target_status, 'result_count', v_count,
            'amended_from_report_id', p_amended_from_report_id,
            'amendment_reason_recorded', CASE WHEN v_is_amendment THEN TRUE ELSE NULL END
        ))
    );

    RETURN jsonb_build_object('success', TRUE, 'status', p_target_status, 'result_count', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_test_results_unversioned_internal TO authenticated, service_role;

CREATE FUNCTION public.search_audit_log(p_actor TEXT DEFAULT NULL,p_action TEXT DEFAULT NULL,p_entity TEXT DEFAULT NULL,p_date_from DATE DEFAULT NULL,p_date_to DATE DEFAULT NULL,p_exact_id TEXT DEFAULT NULL,p_cursor_timestamp TIMESTAMPTZ DEFAULT NULL,p_cursor_id UUID DEFAULT NULL,p_limit INT DEFAULT 50)
RETURNS TABLE(item JSONB,sort_timestamp TIMESTAMPTZ,sort_id UUID) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_view_audit_logs') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT jsonb_build_object('id',a.id,'action',a.action,'entity_type',a.entity_type,'entity_id',a.entity_id,'user_name',a.user_name,'timestamp',a.timestamp),a.timestamp,a.id
 FROM public.audit_logs a WHERE (p_actor IS NULL OR a.user_name ILIKE '%'||btrim(p_actor)||'%') AND (p_action IS NULL OR a.action ILIKE '%'||btrim(p_action)||'%')
  AND (p_entity IS NULL OR a.entity_type ILIKE '%'||btrim(p_entity)||'%') AND (p_exact_id IS NULL OR a.entity_id=p_exact_id)
  AND (p_date_from IS NULL OR (a.timestamp AT TIME ZONE 'Asia/Kathmandu')::DATE>=p_date_from) AND (p_date_to IS NULL OR (a.timestamp AT TIME ZONE 'Asia/Kathmandu')::DATE<=p_date_to)
  AND (p_cursor_timestamp IS NULL OR (a.timestamp,a.id)<(p_cursor_timestamp,p_cursor_id))
 ORDER BY a.timestamp DESC,a.id DESC LIMIT greatest(1,least(COALESCE(p_limit,50),101));
END $$;

GRANT EXECUTE ON FUNCTION public.search_audit_log TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.search_bill_registry(
  p_search TEXT DEFAULT NULL,
  p_payment_status TEXT DEFAULT NULL,
  p_date DATE DEFAULT NULL,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
) RETURNS TABLE(item JSONB)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE term TEXT:=NULLIF(btrim(p_search),''); escaped TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'Invalid bill page size.' USING ERRCODE='22023'; END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN RAISE EXCEPTION 'Incomplete bill cursor.' USING ERRCODE='22023'; END IF;
  escaped:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');
  RETURN QUERY SELECT jsonb_build_object(
    'id',b.id,'bill_number',b.bill_number,'patient_id',b.patient_id,
    'patient_uhid_snapshot',b.patient_uhid_snapshot,'patient_name_snapshot',b.patient_name_snapshot,
    'patient_mobile_snapshot',b.patient_mobile_snapshot,'patient_age_gender_snapshot',b.patient_age_gender_snapshot,
    'referring_doctor_name_snapshot',b.referring_doctor_name_snapshot,'gross_amount_paisa',b.gross_amount_paisa,
    'discount_amount_paisa',b.discount_amount_paisa,'discount_reason',b.discount_reason,
    'net_amount_paisa',b.net_amount_paisa,'paid_amount_paisa',b.paid_amount_paisa,
    'due_amount_paisa',b.due_amount_paisa,'payment_status',b.payment_status,'remarks',b.remarks,'created_at',b.created_at,
    'bill_items',COALESCE(items.rows,'[]'::jsonb),'payment_transactions',COALESCE(payments.rows,'[]'::jsonb),
    'outsource_samples',COALESCE(outsource.rows,'[]'::jsonb)
  ) FROM public.bills b
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object(
      'id',bi.id,'test_name_snapshot',bi.test_name_snapshot,'test_code_snapshot',bi.test_code_snapshot,
      'reporting_type',bi.reporting_type,'unit_price_paisa',bi.unit_price_paisa,
      'item_description',bi.item_description
    ) ORDER BY bi.created_at,bi.id) rows
    FROM public.bill_items bi WHERE bi.bill_id=b.id
  ) items ON TRUE
  LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object('id',pt.id,'receipt_number',pt.receipt_number,'amount_paisa',pt.amount_paisa,'payment_mode',pt.payment_mode,'transaction_reference',pt.transaction_reference,'created_at',pt.created_at) ORDER BY pt.created_at,pt.id) rows FROM public.payment_transactions pt WHERE pt.bill_id=b.id) payments ON TRUE
  LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object('id',os.id,'tracking_number',os.tracking_number,'service_description',os.service_description,'specimen_type',os.specimen_type,'status',os.status) ORDER BY os.created_at,os.id) rows FROM public.outsource_samples os WHERE os.bill_id=b.id) outsource ON TRUE
  WHERE (p_cursor_created_at IS NULL OR (b.created_at,b.id)<(p_cursor_created_at,p_cursor_id))
    AND (p_payment_status IS NULL OR p_payment_status='' OR b.payment_status::text=p_payment_status)
    AND (p_date IS NULL OR (b.created_at AT TIME ZONE 'Asia/Kathmandu')::date=p_date)
    AND (term IS NULL OR b.bill_number=upper(term) OR b.patient_uhid_snapshot=term
      OR b.patient_mobile_snapshot=regexp_replace(term,'[^0-9]','','g')
      OR lower(b.patient_name_snapshot) LIKE '%'||escaped||'%' ESCAPE '\'
      OR EXISTS(SELECT 1 FROM public.clinical_orders o WHERE o.bill_id=b.id AND o.order_number=upper(term)))
  ORDER BY b.created_at DESC,b.id DESC LIMIT p_limit+1;
END $$;

GRANT EXECUTE ON FUNCTION public.search_bill_registry TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.search_billable_catalogue(p_query TEXT, p_limit INT DEFAULT 20)
RETURNS TABLE(
  entity_type TEXT,
  entity_id UUID,
  code TEXT,
  name TEXT,
  short_name TEXT,
  category TEXT,
  specimen TEXT,
  container TEXT,
  price_paisa BIGINT,
  price_configured BOOLEAN,
  pricing_policy public.catalogue_pricing_policy_enum,
  allow_zero_price_billing BOOLEAN,
  reporting_type public.reporting_type_enum,
  rank_score INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
#variable_conflict use_column
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;

  RETURN QUERY WITH q AS (
    SELECT lower(btrim(COALESCE(p_query, ''))) value
  ),
  matches(entity_kind, item_id, item_code, item_name, item_short_name, item_category, item_specimen, item_container, item_price_paisa, item_price_configured, item_pricing_policy, item_zero_price, item_reporting_type, item_score) AS (
    SELECT
      'Test'::TEXT,
      t.id,
      t.code::TEXT,
      t.name::TEXT,
      t.short_name::TEXT,
      c.name::TEXT,
      t.sample_type::TEXT,
      t.container::TEXT,
      r.price_paisa,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      COALESCE(t.pricing_policy, 'Fixed'),
      t.allow_zero_price_billing,
      t.reporting_type,
      CASE
        WHEN lower(t.code) = q.value THEN 100
        WHEN lower(t.code) LIKE q.value || '%' THEN 90
        WHEN lower(t.name) LIKE q.value || '%' THEN 70
        ELSE 50
      END score
    FROM public.tests t
    CROSS JOIN q
    LEFT JOIN public.test_categories c ON c.id = t.category_id
    LEFT JOIN public.catalogue_rate_versions r ON r.test_id = t.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 2
      AND t.is_active = TRUE
      AND t.lifecycle_status = 'Active'
      AND (
        lower(t.code) LIKE '%' || q.value || '%'
        OR lower(t.name) LIKE '%' || q.value || '%'
        OR lower(COALESCE(t.short_name, '')) LIKE '%' || q.value || '%'
        OR EXISTS (
          SELECT 1 FROM public.test_aliases a
          WHERE a.test_id = t.id AND lower(a.alias_name) LIKE '%' || q.value || '%'
        )
      )

    UNION ALL

    SELECT
      'Package',
      p.id,
      p.code::TEXT,
      p.name::TEXT,
      NULL,
      'Health Packages',
      NULL,
      NULL,
      r.price_paisa,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      p.pricing_policy,
      FALSE,
      'NoReporting'::public.reporting_type_enum,
      CASE
        WHEN lower(p.code) = q.value THEN 100
        WHEN lower(p.code) LIKE q.value || '%' THEN 90
        WHEN lower(p.name) LIKE q.value || '%' THEN 70
        ELSE 50
      END
    FROM public.health_packages p
    CROSS JOIN q
    LEFT JOIN public.catalogue_rate_versions r ON r.package_id = p.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 2
      AND p.lifecycle_status = 'Active'
      AND (lower(p.code) LIKE '%' || q.value || '%' OR lower(p.name) LIKE '%' || q.value || '%')

    UNION ALL

    SELECT
      'Panel',
      ps.id,
      ps.code,
      ps.name,
      NULL,
      c.name,
      ps.specimen,
      ps.container,
      r.price_paisa,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      'Fixed'::public.catalogue_pricing_policy_enum,
      FALSE,
      ps.reporting_type,
      CASE
        WHEN lower(ps.code) = q.value THEN 100
        WHEN lower(ps.code) LIKE q.value || '%' THEN 90
        WHEN lower(ps.name) LIKE q.value || '%' THEN 70
        ELSE 50
      END
    FROM public.catalogue_panel_services ps
    JOIN public.test_categories c ON c.id = ps.category_id
    CROSS JOIN q
    LEFT JOIN public.catalogue_rate_versions r ON r.panel_service_id = ps.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 2
      AND ps.lifecycle_status = 'Active'
      AND (lower(ps.code) LIKE '%' || q.value || '%' OR lower(ps.name) LIKE '%' || q.value || '%')
  )
  SELECT
    m.entity_kind,
    m.item_id,
    m.item_code,
    m.item_name,
    m.item_short_name,
    m.item_category,
    m.item_specimen,
    m.item_container,
    m.item_price_paisa,
    m.item_price_configured,
    m.item_pricing_policy,
    m.item_zero_price,
    m.item_reporting_type,
    m.item_score
  FROM matches m
  ORDER BY m.item_score DESC, m.item_name
  LIMIT greatest(1, least(COALESCE(p_limit, 20), 50));
END $$;

GRANT EXECUTE ON FUNCTION public.search_billable_catalogue TO authenticated, service_role;

CREATE FUNCTION public.search_dashboard_orders(
  p_search TEXT DEFAULT NULL,
  p_workflow TEXT DEFAULT 'Today',
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 30
) RETURNS TABLE(item JSONB)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE term TEXT:=NULLIF(btrim(p_search),''); escaped TEXT;
BEGIN
  IF p_limit<1 OR p_limit>50 THEN RAISE EXCEPTION 'Invalid dashboard page size.' USING ERRCODE='22023'; END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN RAISE EXCEPTION 'Incomplete dashboard cursor.' USING ERRCODE='22023'; END IF;
  IF p_workflow NOT IN ('Today','Pending','Processing','AwaitingVerification','ReportReady') THEN RAISE EXCEPTION 'Invalid dashboard workflow.' USING ERRCODE='22023'; END IF;
  escaped:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');
  RETURN QUERY SELECT jsonb_build_object(
    'id',o.id,'order_number',o.order_number,'status',o.status,'created_at',o.created_at,'bill_id',o.bill_id,
    'patient',jsonb_build_object('uhid',p.uhid,'full_name',p.full_name,'mobile',p.mobile,'age_years',p.age_years,'gender',p.gender),
    'bill',jsonb_build_object('bill_number',b.bill_number),'items',COALESCE(items.rows,'[]'::jsonb)
  ) FROM public.clinical_orders o JOIN public.patients p ON p.id=o.patient_id JOIN public.bills b ON b.id=o.bill_id
  LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object('id',coi.id,'test_name',coi.test_name,'department',coi.department,'status',coi.status) ORDER BY coi.created_at,coi.id) rows FROM public.clinical_order_items coi WHERE coi.order_id=o.id) items ON TRUE
  WHERE (p_cursor_created_at IS NULL OR (o.created_at,o.id)<(p_cursor_created_at,p_cursor_id))
    AND (term IS NULL OR o.order_number=upper(term) OR b.bill_number=upper(term) OR p.uhid=term
      OR p.mobile=regexp_replace(term,'[^0-9]','','g') OR lower(p.full_name) LIKE '%'||escaped||'%' ESCAPE '\'
      OR EXISTS(SELECT 1 FROM public.clinical_order_items coi WHERE coi.order_id=o.id AND lower(coi.test_name) LIKE '%'||escaped||'%' ESCAPE '\'))
    AND (p_workflow<>'Today' OR (o.created_at AT TIME ZONE 'Asia/Kathmandu')::date=(now() AT TIME ZONE 'Asia/Kathmandu')::date)
    AND (p_workflow<>'Pending' OR EXISTS(SELECT 1 FROM public.samples s WHERE s.order_id=o.id AND s.status IN ('Pending','Collected')))
    AND (p_workflow<>'Processing' OR EXISTS(SELECT 1 FROM public.clinical_order_items coi WHERE coi.order_id=o.id AND coi.status IN ('SampleReceived','ResultDrafted')))
    AND (p_workflow<>'AwaitingVerification' OR EXISTS(SELECT 1 FROM public.test_results tr JOIN public.clinical_order_items coi ON coi.id=tr.order_item_id WHERE coi.order_id=o.id AND tr.status='SubmittedForVerification'))
    AND (p_workflow<>'ReportReady' OR EXISTS(SELECT 1 FROM public.clinical_order_items coi WHERE coi.order_id=o.id AND coi.status IN ('Verified','SignedOff')) OR EXISTS(SELECT 1 FROM public.diagnostic_reports r WHERE r.order_id=o.id AND r.status='SignedOff'))
  ORDER BY o.created_at DESC,o.id DESC LIMIT p_limit+1;
END $$;

GRANT EXECUTE ON FUNCTION public.search_dashboard_orders TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.search_laboratory_worklist(
  p_search TEXT DEFAULT NULL,
  p_department TEXT DEFAULT NULL,
  p_sample_status TEXT DEFAULT NULL,
  p_order_date DATE DEFAULT NULL,
  p_view TEXT DEFAULT 'All',
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
)
RETURNS TABLE(item JSONB)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path=public,pg_temp
AS $$
DECLARE
  term TEXT:=NULLIF(btrim(p_search),'');
  escaped_term TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN
    RAISE EXCEPTION 'Invalid worklist page size.' USING ERRCODE='22023';
  END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN
    RAISE EXCEPTION 'Incomplete worklist cursor.' USING ERRCODE='22023';
  END IF;
  IF p_view NOT IN ('All','Pending','ToVerify','Verified','Signed') THEN
    RAISE EXCEPTION 'Invalid worklist view.' USING ERRCODE='22023';
  END IF;
  escaped_term:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');

  RETURN QUERY
  SELECT jsonb_build_object(
    'id',coi.id,
    'order_id',coi.order_id,
    'test_id',coi.test_id,
    'test_name',coi.test_name,
    'department',coi.department,
    'reporting_type',coi.reporting_type,
    'outsource_lab_name',coi.outsource_lab_name,
    'status',coi.status,
    'created_at',coi.created_at,
    'order',jsonb_build_object(
      'id',o.id,'order_number',o.order_number,'order_date_ad',o.order_date_ad,
      'order_date_bs',o.order_date_bs,'patient',jsonb_build_object(
        'uhid',p.uhid,'full_name',p.full_name,'gender',p.gender,'age_years',p.age_years
      )
    ),
    'sample',CASE WHEN s.id IS NULL THEN NULL ELSE jsonb_build_object(
      'barcode',s.barcode,'status',s.status,'specimen_type',s.specimen_type,
      'container_type',s.container_type
    ) END,
    'results',COALESCE(result_set.results,'[]'::JSONB),
    'report',report_row.report
  )
  FROM public.clinical_order_items coi
  JOIN public.clinical_orders o ON o.id=coi.order_id
  JOIN public.patients p ON p.id=o.patient_id
  LEFT JOIN public.samples s ON s.id=coi.sample_id
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object(
      'id',tr.id,'flag',tr.flag,'is_critical',tr.is_critical,'status',tr.status
    ) ORDER BY tr.id) AS results
    FROM public.test_results tr WHERE tr.order_item_id=coi.id
  ) result_set ON TRUE
  LEFT JOIN LATERAL (
    SELECT jsonb_build_object('id',r.id,'report_number',r.report_number,'version',r.version,'status',r.status) AS report
    FROM public.diagnostic_reports r WHERE r.order_id=coi.order_id
    ORDER BY r.version DESC,r.created_at DESC,r.id DESC LIMIT 1
  ) report_row ON TRUE
  WHERE coi.reporting_type IN ('InHouse','OutsourceWithBimalReport')
    AND (p_cursor_created_at IS NULL OR (coi.created_at,coi.id)<(p_cursor_created_at,p_cursor_id))
    AND (p_department IS NULL OR p_department='' OR coi.department=p_department)
    AND (p_sample_status IS NULL OR p_sample_status='' OR s.status::TEXT=p_sample_status)
    AND (p_order_date IS NULL OR o.order_date_ad=p_order_date)
    AND (
      p_view='All'
      OR (p_view='Pending' AND coi.status IN ('SampleReceived','ResultDrafted'))
      OR (p_view='ToVerify' AND coi.status NOT IN ('Verified','SignedOff') AND EXISTS(
        SELECT 1 FROM public.test_results pending_result
        WHERE pending_result.order_item_id=coi.id AND pending_result.status='SubmittedForVerification'
      ))
      OR (p_view='Verified' AND coi.status='Verified' AND report_row.report IS NULL)
      OR (p_view='Signed' AND (coi.status='SignedOff' OR report_row.report IS NOT NULL))
    )
    AND (
      term IS NULL
      OR (term~*'^BPDC-[0-9]{8}$' AND o.order_number=upper(term))
      OR (term!~*'^BPDC-[0-9]{8}$' AND (
        lower(p.full_name) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(p.uhid) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(o.order_number) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(COALESCE(s.barcode,'')) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(coi.test_name) LIKE '%'||escaped_term||'%' ESCAPE '\'
      ))
    )
  ORDER BY coi.created_at DESC,coi.id DESC
  LIMIT p_limit+1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_laboratory_worklist TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.search_my_report_orders(
  p_query TEXT,
  p_limit INT DEFAULT 25,
  p_offset INT DEFAULT 0
) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_patient_id UUID;
  v_query TEXT;
  v_orders JSONB;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;

  -- Do not accept patient, UHID, or mobile identifiers from the client.
  SELECT patient_id INTO v_patient_id
  FROM public.patient_app_identities
  WHERE auth_user_id = v_uid AND status = 'LINKED';

  IF v_patient_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  v_query := btrim(coalesce(p_query, ''));
  IF v_query = '' THEN RETURN '[]'::jsonb; END IF;

  p_limit := least(greatest(coalesce(p_limit, 25), 1), 50);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT coalesce(jsonb_agg(x.row_data), '[]'::jsonb)
  INTO v_orders
  FROM (
    SELECT jsonb_build_object(
      'order_id', o.id,
      'order_number', o.order_number,
      'order_date_ad', o.order_date_ad,
      'order_date_bs', o.order_date_bs,
      'created_at', o.created_at,
      'total_groups', coalesce(grp.total_groups, 0),
      'ready_groups', coalesce(grp.ready_groups, 0),
      'overall_status', CASE
        WHEN coalesce(grp.total_groups, 0) = 0 THEN 'Pending'
        WHEN grp.ready_groups = grp.total_groups THEN 'Ready'
        WHEN grp.ready_groups > 0 THEN 'Partially Ready'
        ELSE 'Pending'
      END
    ) AS row_data
    FROM public.clinical_orders o
    LEFT JOIN LATERAL (
      SELECT
        count(g.id)::int AS total_groups,
        count(g.id) FILTER (
          WHERE EXISTS (
            SELECT 1
            FROM public.diagnostic_reports dr
            JOIN public.report_pdf_artifacts a ON a.diagnostic_report_id = dr.id
            WHERE dr.report_group_id = g.id
              AND dr.status IN ('SignedOff', 'Amended')
              AND a.generation_status = 'Ready'
          )
        )::int AS ready_groups
      FROM public.clinical_report_groups g
      WHERE g.order_id = o.id
    ) grp ON true
    WHERE o.patient_id = v_patient_id
      AND (
        o.order_number ILIKE '%' || v_query || '%'
        OR o.order_date_ad::TEXT ILIKE '%' || v_query || '%'
        OR coalesce(o.order_date_bs, '') ILIKE '%' || v_query || '%'
        OR EXISTS (
          SELECT 1
          FROM public.clinical_order_items oi
          WHERE oi.order_id = o.id
            AND coalesce(oi.test_name, '') ILIKE '%' || v_query || '%'
        )
      )
    ORDER BY o.order_date_ad DESC, o.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) x;

  RETURN v_orders;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_my_report_orders TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.search_patient_history(
  p_patient_id UUID,
  p_section TEXT,
  p_cursor_timestamp TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 25
)
RETURNS TABLE(item JSONB,sort_timestamp TIMESTAMPTZ,sort_id UUID)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_active_user() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF p_section='orders' THEN
  RETURN QUERY SELECT jsonb_build_object('id',o.id,'order_number',o.order_number,'status',o.status,'created_at',o.created_at,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('test_name',i.test_name) ORDER BY i.created_at) FROM public.clinical_order_items i WHERE i.order_id=o.id),'[]'::JSONB)),o.created_at,o.id FROM public.clinical_orders o WHERE o.patient_id=p_patient_id AND(p_cursor_timestamp IS NULL OR(o.created_at,o.id)<(p_cursor_timestamp,p_cursor_id)) ORDER BY o.created_at DESC,o.id DESC LIMIT greatest(1,least(COALESCE(p_limit,25),51));
 ELSIF p_section='bills' THEN
  RETURN QUERY SELECT jsonb_build_object('id',b.id,'bill_number',b.bill_number,'bill_date',b.created_at,'gross_amount_paisa',b.gross_amount_paisa,'net_amount_paisa',b.net_amount_paisa,'paid_amount_paisa',b.paid_amount_paisa,'due_amount_paisa',b.due_amount_paisa,'payment_status',b.payment_status,'created_at',b.created_at,'clinical_orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('order_number',o.order_number) ORDER BY o.created_at) FROM public.clinical_orders o WHERE o.bill_id=b.id),'[]'::JSONB),'payment_transactions',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pt.id,'receipt_number',pt.receipt_number,'amount_paisa',pt.amount_paisa,'payment_mode',pt.payment_mode,'created_at',pt.created_at) ORDER BY pt.created_at) FROM public.payment_transactions pt WHERE pt.bill_id=b.id),'[]'::JSONB)),b.created_at,b.id FROM public.bills b WHERE b.patient_id=p_patient_id AND(p_cursor_timestamp IS NULL OR(b.created_at,b.id)<(p_cursor_timestamp,p_cursor_id)) ORDER BY b.created_at DESC,b.id DESC LIMIT greatest(1,least(COALESCE(p_limit,25),51));
 ELSIF p_section='reports' THEN
  RETURN QUERY SELECT jsonb_build_object('id',r.id,'report_number',r.report_number,'version',r.version,'is_amendment',r.is_amendment,'amendment_reason',r.amendment_reason,'status',r.status,'signed_at',r.signed_at,'integrity_hash',r.integrity_hash),r.signed_at,r.id FROM public.diagnostic_reports r WHERE r.patient_id=p_patient_id AND(p_cursor_timestamp IS NULL OR(r.signed_at,r.id)<(p_cursor_timestamp,p_cursor_id)) ORDER BY r.signed_at DESC,r.id DESC LIMIT greatest(1,least(COALESCE(p_limit,25),51));
 ELSE RAISE EXCEPTION 'Unknown patient history section.' USING ERRCODE='22023'; END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.search_patient_history TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.search_patient_registry(
  p_search TEXT DEFAULT NULL,
  p_active_state TEXT DEFAULT 'Active',
  p_date DATE DEFAULT NULL,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
) RETURNS TABLE(item JSONB)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE term TEXT:=NULLIF(btrim(p_search),''); escaped TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'Invalid patient page size.' USING ERRCODE='22023'; END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN RAISE EXCEPTION 'Incomplete patient cursor.' USING ERRCODE='22023'; END IF;
  IF p_active_state NOT IN ('Active','Archived','All') THEN RAISE EXCEPTION 'Invalid patient state.' USING ERRCODE='22023'; END IF;
  escaped:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');
  RETURN QUERY SELECT jsonb_build_object(
    'id',p.id,'uhid',p.uhid,'mobile',p.mobile,'title',p.title,'full_name',p.full_name,
    'gender',p.gender,'dob',p.dob,'age_years',p.age_years,'age_months',p.age_months,
    'age_days',p.age_days,'address',p.address,'email',p.email,'identification_no',p.identification_no,
    'is_active',p.is_active,'archived_at',p.archived_at,'created_at',p.created_at
  ) FROM public.patients p
  WHERE (p_cursor_created_at IS NULL OR (p.created_at,p.id)<(p_cursor_created_at,p_cursor_id))
    AND (p_active_state='All' OR (p_active_state='Active' AND p.is_active) OR (p_active_state='Archived' AND NOT p.is_active))
    AND (p_date IS NULL OR (p.created_at AT TIME ZONE 'Asia/Kathmandu')::date=p_date)
    AND (term IS NULL OR p.uhid=term OR p.mobile=regexp_replace(term,'[^0-9]','','g')
      OR lower(p.full_name) LIKE '%'||escaped||'%' ESCAPE '\')
  ORDER BY p.created_at DESC,p.id DESC LIMIT p_limit+1;
END $$;

GRANT EXECUTE ON FUNCTION public.search_patient_registry TO authenticated, service_role;

CREATE FUNCTION public.search_report_registry(
  p_search TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_amendment_state TEXT DEFAULT 'All',
  p_date DATE DEFAULT NULL,
  p_cursor_signed_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
) RETURNS TABLE(item JSONB)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE term TEXT:=NULLIF(btrim(p_search),''); escaped TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'Invalid report page size.' USING ERRCODE='22023'; END IF;
  IF (p_cursor_signed_at IS NULL)<>(p_cursor_id IS NULL) THEN RAISE EXCEPTION 'Incomplete report cursor.' USING ERRCODE='22023'; END IF;
  IF p_amendment_state NOT IN ('All','Original','Amended') THEN RAISE EXCEPTION 'Invalid amendment state.' USING ERRCODE='22023'; END IF;
  escaped:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');
  RETURN QUERY SELECT jsonb_build_object(
    'id',r.id,'order_id',r.order_id,'patient_id',r.patient_id,'report_number',r.report_number,
    'version',r.version,'is_amendment',r.is_amendment,'amendment_reason',r.amendment_reason,
    'amended_from_report_id',r.amended_from_report_id,'status',r.status,'integrity_hash',r.integrity_hash,
    'performed_by_personnel_name',r.performed_by_personnel_name,'signed_by_personnel_name',r.signed_by_personnel_name,
    'signed_at',r.signed_at,'pdf_storage_path',r.pdf_storage_path,'clinical_snapshot_json',r.clinical_snapshot_json,
    'patient',jsonb_build_object('uhid',p.uhid,'full_name',p.full_name,'mobile',p.mobile),
    'order',jsonb_build_object('order_number',o.order_number)
  ) FROM public.diagnostic_reports r
  JOIN public.patients p ON p.id=r.patient_id JOIN public.clinical_orders o ON o.id=r.order_id
  WHERE (p_cursor_signed_at IS NULL OR (r.signed_at,r.id)<(p_cursor_signed_at,p_cursor_id))
    AND (p_status IS NULL OR p_status='' OR r.status=p_status)
    AND (p_amendment_state='All' OR (p_amendment_state='Original' AND NOT r.is_amendment) OR (p_amendment_state='Amended' AND r.is_amendment))
    AND (p_date IS NULL OR (r.signed_at AT TIME ZONE 'Asia/Kathmandu')::date=p_date)
    AND (term IS NULL OR lower(r.report_number)=lower(term) OR o.order_number=upper(term) OR p.uhid=term
      OR lower(p.full_name) LIKE '%'||escaped||'%' ESCAPE '\')
  ORDER BY r.signed_at DESC,r.id DESC LIMIT p_limit+1;
END $$;

GRANT EXECUTE ON FUNCTION public.search_report_registry TO authenticated, service_role;

CREATE FUNCTION public.search_sample_accessioning(
  p_search TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_specimen TEXT DEFAULT NULL,
  p_date DATE DEFAULT NULL,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
) RETURNS TABLE(item JSONB)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE term TEXT:=NULLIF(btrim(p_search),''); escaped TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'Invalid sample page size.' USING ERRCODE='22023'; END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN RAISE EXCEPTION 'Incomplete sample cursor.' USING ERRCODE='22023'; END IF;
  escaped:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');
  RETURN QUERY SELECT jsonb_build_object(
    'id',s.id,'barcode',s.barcode,'order_id',s.order_id,'patient_id',s.patient_id,
    'specimen_type',s.specimen_type,'container_type',s.container_type,'status',s.status,
    'collected_at',s.collected_at,'collected_by_name',s.collected_by_name,
    'received_at',s.received_at,'received_by_name',s.received_by_name,
    'rejected_at',s.rejected_at,'rejection_reason',s.rejection_reason,
    'recollected_from_sample_id',s.recollected_from_sample_id,'created_at',s.created_at,
    'order',jsonb_build_object('order_number',o.order_number,'order_date_bs',o.order_date_bs),
    'patient',jsonb_build_object('uhid',p.uhid,'full_name',p.full_name,'mobile',p.mobile,'gender',p.gender,'age_years',p.age_years),
    'items',COALESCE(items.rows,'[]'::jsonb)
  ) FROM public.samples s
  JOIN public.clinical_orders o ON o.id=s.order_id
  JOIN public.patients p ON p.id=s.patient_id
  LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object('id',coi.id,'test_name',coi.test_name,'department',coi.department,'reporting_type',coi.reporting_type) ORDER BY coi.created_at,coi.id) rows FROM public.clinical_order_items coi WHERE coi.sample_id=s.id) items ON TRUE
  WHERE (p_cursor_created_at IS NULL OR (s.created_at,s.id)<(p_cursor_created_at,p_cursor_id))
    AND (p_status IS NULL OR p_status='' OR s.status::text=p_status)
    AND (p_specimen IS NULL OR p_specimen='' OR s.specimen_type=p_specimen)
    AND (p_date IS NULL OR o.order_date_ad=p_date)
    AND (term IS NULL OR s.barcode=term OR o.order_number=upper(term) OR p.uhid=term
      OR lower(p.full_name) LIKE '%'||escaped||'%' ESCAPE '\')
  ORDER BY s.created_at DESC,s.id DESC LIMIT p_limit+1;
END $$;

GRANT EXECUTE ON FUNCTION public.search_sample_accessioning TO authenticated, service_role;

CREATE FUNCTION public.search_sms_delivery_status(p_status TEXT DEFAULT NULL,p_event_type TEXT DEFAULT NULL,p_search TEXT DEFAULT NULL,p_date DATE DEFAULT NULL,p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,p_cursor_id UUID DEFAULT NULL,p_limit INT DEFAULT 50)
RETURNS TABLE(item JSONB,sort_created_at TIMESTAMPTZ,sort_id UUID) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_users') OR public.is_super_admin()) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT jsonb_build_object('id',q.id,'event_type',CASE q.sms_type WHEN 'BillRegistration' THEN 'Payment Confirmation' WHEN 'ReportReady' THEN 'Report Ready' ELSE 'Transactional SMS' END,
  'lab_no',COALESCE(o.order_number,ro.order_number,b.bill_number),'mobile',q.recipient_phone,'status',q.status,
  'provider_status',left(COALESCE(q.error_message,CASE WHEN q.status='Sent' THEN 'Accepted' ELSE q.error_classification END,q.status),500),
  'provider_message_id',q.provider_message_id,'retry_count',q.delivery_attempt_count,'manual_retry_count',q.manual_retry_count,'created_at',q.created_at,'sent_at',q.sent_at),q.created_at,q.id
 FROM public.sms_queue_items q LEFT JOIN public.bills b ON b.id=q.bill_id LEFT JOIN public.clinical_orders o ON o.bill_id=q.bill_id
 LEFT JOIN public.diagnostic_reports r ON r.id=q.diagnostic_report_id LEFT JOIN public.clinical_orders ro ON ro.id=r.order_id
 WHERE (p_status IS NULL OR q.status=p_status) AND (p_event_type IS NULL OR q.sms_type=CASE p_event_type WHEN 'Payment Confirmation' THEN 'BillRegistration' WHEN 'Report Ready' THEN 'ReportReady' ELSE p_event_type END)
  AND (p_date IS NULL OR (q.created_at AT TIME ZONE 'Asia/Kathmandu')::DATE=p_date)
  AND (p_search IS NULL OR COALESCE(o.order_number,ro.order_number,b.bill_number,'') ILIKE '%'||btrim(p_search)||'%' OR q.recipient_phone ILIKE '%'||regexp_replace(p_search,'\s','','g')||'%')
  AND (p_cursor_created_at IS NULL OR (q.created_at,q.id)<(p_cursor_created_at,p_cursor_id))
 ORDER BY q.created_at DESC,q.id DESC LIMIT greatest(1,least(COALESCE(p_limit,50),101));
END $$;

GRANT EXECUTE ON FUNCTION public.search_sms_delivery_status TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.set_patient_archived(p_patient_id UUID, p_archived BOOLEAN)
RETURNS public.patients LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_patient public.patients%ROWTYPE;
BEGIN
  IF NOT public.has_permission('can_edit_patient') THEN RAISE EXCEPTION 'Not authorized to archive patients.' USING ERRCODE='42501'; END IF;
  UPDATE public.patients SET is_active=NOT p_archived,archived_at=CASE WHEN p_archived THEN NOW() ELSE NULL END,archived_by=CASE WHEN p_archived THEN auth.uid() ELSE NULL END,updated_at=NOW() WHERE id=p_patient_id RETURNING * INTO v_patient;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found.' USING ERRCODE='P0002'; END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.patient_actor_name(),CASE WHEN p_archived THEN 'PATIENT_ARCHIVED' ELSE 'PATIENT_RESTORED' END,'Patient',p_patient_id::TEXT,jsonb_build_object('uhid',v_patient.uhid));
  RETURN v_patient;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_patient_archived TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.set_sms_gateway_v2_claiming(p_instance_id UUID,p_enabled BOOLEAN,p_confirmation TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_confirmation<>(CASE WHEN p_enabled THEN 'ENABLE_SMS_GATEWAY_V2_CLAIMING' ELSE 'DISABLE_SMS_GATEWAY_V2_CLAIMING' END) THEN
    RAISE EXCEPTION 'Exact claiming confirmation is required.' USING ERRCODE='22023';
  END IF;
  IF p_enabled AND EXISTS(SELECT 1 FROM public.sms_queue_items WHERE status='Processing') THEN
    RAISE EXCEPTION 'SMS_GATEWAY_SWITCH_BLOCKED_BY_PROCESSING_ROWS' USING ERRCODE='55000';
  END IF;
  UPDATE public.sms_gateway_instances SET claiming_enabled=p_enabled,updated_at=now() WHERE instance_id=p_instance_id AND is_enabled;
  IF NOT FOUND THEN RAISE EXCEPTION 'Gateway instance not found or disabled.' USING ERRCODE='P0002'; END IF;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),'SMS_GATEWAY_V2_CLAIMING_CHANGED','SmsGatewayInstance',p_instance_id::TEXT,jsonb_build_object('claiming_enabled',p_enabled));
  RETURN jsonb_build_object('success',true,'instance_id',p_instance_id,'claiming_enabled',p_enabled);
END $$;

GRANT EXECUTE ON FUNCTION public.set_sms_gateway_v2_claiming TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.set_sms_gateway_v2_enabled(p_instance_id UUID,p_enabled BOOLEAN,p_confirmation TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_confirmation<>(CASE WHEN p_enabled THEN 'ENABLE_SMS_GATEWAY_V2_INSTANCE' ELSE 'DISABLE_SMS_GATEWAY_V2_INSTANCE' END) THEN
    RAISE EXCEPTION 'Exact instance-state confirmation is required.' USING ERRCODE='22023';
  END IF;
  UPDATE public.sms_gateway_instances SET is_enabled=p_enabled,
    claiming_enabled=CASE WHEN p_enabled THEN claiming_enabled ELSE FALSE END,updated_at=now()
  WHERE instance_id=p_instance_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Gateway instance not found.' USING ERRCODE='P0002'; END IF;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),'SMS_GATEWAY_V2_INSTANCE_STATE_CHANGED','SmsGatewayInstance',p_instance_id::TEXT,
    jsonb_build_object('is_enabled',p_enabled,'claiming_enabled',CASE WHEN p_enabled THEN NULL ELSE FALSE END));
  RETURN jsonb_build_object('success',true,'instance_id',p_instance_id,'is_enabled',p_enabled);
END $$;

GRANT EXECUTE ON FUNCTION public.set_sms_gateway_v2_enabled TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.sign_and_freeze_diagnostic_report(
    p_order_id UUID,
    p_performed_by_id UUID,
    p_signed_by_id UUID,
    p_amendment_reason TEXT DEFAULT NULL,
    p_amended_from_report_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order RECORD;
    v_bill RECORD;
    v_patient RECORD;
    v_performed_by RECORD;
    v_signed_by_id public.reporting_personnel.id%TYPE := NULL;
    v_signed_by_name public.reporting_personnel.full_name%TYPE := NULL;
    v_signed_by_qualification public.reporting_personnel.qualification%TYPE := NULL;
    v_signed_by_professional_type public.reporting_personnel.professional_type%TYPE := NULL;
    v_signed_by_specialization public.reporting_personnel.specialization%TYPE := NULL;
    v_signed_by_registration_council public.reporting_personnel.registration_council%TYPE := NULL;
    v_signed_by_registration_number public.reporting_personnel.registration_number%TYPE := NULL;
    v_signed_by_signature_url public.reporting_personnel.signature_url%TYPE := NULL;
    v_signed_by_is_active public.reporting_personnel.is_active%TYPE := NULL;
    v_signed_by_can_sign_reports public.reporting_personnel.can_sign_reports%TYPE := NULL;
    v_authorized_snapshot JSONB := NULL;
    v_readiness JSONB;
    v_version INT := 1;
    v_is_amendment BOOLEAN := FALSE;
    v_parent_report RECORD;
    v_report_number VARCHAR(50);
    v_current_year VARCHAR(4);
    v_report_id UUID;
    v_snapshot JSONB;
    v_investigations JSONB := '[]'::JSONB;
    v_item RECORD;
    v_results JSONB;
    v_param RECORD;
    v_hash_input TEXT;
    v_integrity_hash VARCHAR(128);
    v_sample_dates JSONB;
BEGIN
    -- ------------------------------------------------------------------------
    -- 0. CALLER & SIGNATORY CLINICAL AUTHORITY VALIDATION
    -- ------------------------------------------------------------------------
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    IF NOT public.has_permission('can_sign_reports') THEN
        RAISE EXCEPTION 'Access Denied: Caller does not possess can_sign_reports permission.';
    END IF;

    -- A separate authorizing identity is optional. When supplied, it must
    -- still satisfy the existing active/authorized personnel gates.
    IF p_signed_by_id IS NOT NULL THEN
        IF p_signed_by_id = p_performed_by_id THEN
            RAISE EXCEPTION 'Authorizing signatory must be distinct from performed-by reporting personnel.';
        END IF;

        SELECT
            id,
            full_name,
            qualification,
            professional_type,
            specialization,
            registration_council,
            registration_number,
            signature_url,
            is_active,
            can_sign_reports
        INTO
            v_signed_by_id,
            v_signed_by_name,
            v_signed_by_qualification,
            v_signed_by_professional_type,
            v_signed_by_specialization,
            v_signed_by_registration_council,
            v_signed_by_registration_number,
            v_signed_by_signature_url,
            v_signed_by_is_active,
            v_signed_by_can_sign_reports
        FROM public.reporting_personnel
        WHERE id = p_signed_by_id;

        IF v_signed_by_id IS NULL THEN
            RAISE EXCEPTION 'Authorizing signatory ID % does not exist.', p_signed_by_id;
        END IF;

        IF v_signed_by_is_active IS NOT TRUE THEN
            RAISE EXCEPTION 'Signatory % is currently marked inactive.', v_signed_by_name;
        END IF;

        IF v_signed_by_can_sign_reports IS NOT TRUE THEN
            RAISE EXCEPTION 'Signatory % is not clinically authorized to sign reports (can_sign_reports = FALSE).', v_signed_by_name;
        END IF;

        v_authorized_snapshot := jsonb_build_object(
            'id', v_signed_by_id,
            'full_name', v_signed_by_name,
            'qualification', v_signed_by_qualification,
            'professional_type', v_signed_by_professional_type,
            'specialization', v_signed_by_specialization,
            'registration_council', v_signed_by_registration_council,
            'registration_number', v_signed_by_registration_number,
            'signature_url', v_signed_by_signature_url
        );
    END IF;

    -- Validate Performed By signatory
    SELECT * INTO v_performed_by
    FROM public.reporting_personnel
    WHERE id = p_performed_by_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reporting personnel (performed by) ID % does not exist.', p_performed_by_id;
    END IF;

    IF v_performed_by.is_active IS NOT TRUE THEN
        RAISE EXCEPTION 'Reporting personnel % is currently marked inactive.', v_performed_by.full_name;
    END IF;

    -- ------------------------------------------------------------------------
    -- 1. ORDER-LEVEL READINESS GATE (Must be 100% verified, 0 unack criticals)
    -- ------------------------------------------------------------------------
    v_readiness := public.check_order_report_readiness(p_order_id);

    IF NOT (v_readiness->>'is_ready')::BOOLEAN THEN
        IF (v_readiness->>'unacknowledged_critical_count')::INT > 0 THEN
            RAISE EXCEPTION 'Cannot sign report: Order has % unacknowledged critical panic value(s). Immediate clinical documentation required.', v_readiness->>'unacknowledged_critical_count';
        ELSE
            RAISE EXCEPTION 'Cannot sign report: Clinical order is not ready (% unverified investigation(s) remaining).', v_readiness->>'unverified_count';
        END IF;
    END IF;

    -- ------------------------------------------------------------------------
    -- 2. AMENDMENT VS INITIAL VERSION RESOLUTION
    -- ------------------------------------------------------------------------
    IF p_amended_from_report_id IS NOT NULL THEN
        IF NOT public.has_permission('can_amend_reports') THEN
            RAISE EXCEPTION 'Access Denied: Missing can_amend_reports permission for amendment.';
        END IF;

        IF TRIM(COALESCE(p_amendment_reason, '')) = '' THEN
            RAISE EXCEPTION 'Amendment reason is mandatory when issuing report revision.';
        END IF;

        SELECT * INTO v_parent_report
        FROM public.diagnostic_reports
        WHERE id = p_amended_from_report_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Parent report % not found for amendment.', p_amended_from_report_id;
        END IF;

        v_version := v_parent_report.version + 1;
        v_is_amendment := TRUE;

        -- Mark parent report as Amended
        UPDATE public.diagnostic_reports
        SET status = 'Amended', updated_at = NOW()
        WHERE id = p_amended_from_report_id;
    ELSE
        v_version := 1;
        v_is_amendment := FALSE;
    END IF;

    -- ------------------------------------------------------------------------
    -- 3. SERVER-SIDE CALCULATION RECOMPUTATION & FETCH FULL METADATA
    -- ------------------------------------------------------------------------
    SELECT * INTO v_order FROM public.clinical_orders WHERE id = p_order_id;
    SELECT * INTO v_bill FROM public.bills WHERE id = v_order.bill_id;
    SELECT * INTO v_patient FROM public.patients WHERE id = v_order.patient_id;

    -- Collect sample collection/reception timestamps
    SELECT jsonb_build_object(
        'collected_at', MIN(collected_at),
        'received_at', MAX(received_at)
    ) INTO v_sample_dates
    FROM public.samples
    WHERE order_id = p_order_id;

    -- Build investigations array (Reportable items only)
    FOR v_item IN (
        SELECT coi.*, t.method, t.interpretation_template
        FROM public.clinical_order_items coi
        JOIN public.tests t ON coi.test_id = t.id
        WHERE coi.order_id = p_order_id
          AND coi.reporting_type IN ('InHouse', 'OutsourceWithBimalReport')
        ORDER BY coi.created_at ASC
    ) LOOP
        -- Execute authoritative server-side recalculation of calculated parameters
        PERFORM public.recompute_order_item_calculated_results(v_item.id);

        v_results := '[]'::JSONB;

        FOR v_param IN (
            SELECT tr.*, p.code as param_code, p.display_order, p.formula
            FROM public.test_results tr
            JOIN public.parameters p ON tr.parameter_id = p.id
            WHERE tr.order_item_id = v_item.id
            ORDER BY p.display_order ASC
        ) LOOP
            -- Check for mathematical calculation error
            IF v_param.value_type = 'Calculated' AND v_param.display_value = 'Calculation Error' THEN
                RAISE EXCEPTION 'Cannot sign report: Calculated parameter % has a mathematical error (e.g. divide by zero)', v_param.parameter_name;
            END IF;

            v_results := v_results || jsonb_build_object(
                'parameter_id', v_param.parameter_id,
                'code', v_param.param_code,
                'name', v_param.parameter_name,
                'value_type', v_param.value_type,
                'display_value', v_param.display_value,
                'numeric_value', v_param.numeric_value,
                'unit', v_param.unit,
                'formula', v_param.formula,
                'flag', v_param.flag,
                'is_critical', v_param.is_critical,
                'reference_range', COALESCE(
                    CASE 
                        WHEN v_param.normal_min IS NOT NULL AND v_param.normal_max IS NOT NULL 
                        THEN v_param.normal_min::TEXT || ' - ' || v_param.normal_max::TEXT 
                        ELSE NULL 
                    END,
                    v_param.normal_range_text,
                    'Standard'
                ),
                'normal_min', v_param.normal_min,
                'normal_max', v_param.normal_max,
                'critical_low', v_param.critical_low,
                'critical_high', v_param.critical_high
            );
        END LOOP;

        v_investigations := v_investigations || jsonb_build_object(
            'order_item_id', v_item.id,
            'test_id', v_item.test_id,
            'test_name', v_item.test_name,
            'department', v_item.department,
            'reporting_type', v_item.reporting_type,
            'outsource_lab_name', v_item.outsource_lab_name,
            'method', v_item.method,
            'interpretation_template', v_item.interpretation_template,
            'specimen_type', v_item.specimen_type,
            'container_type', v_item.container_type,
            'results', v_results
        );
    END LOOP;

    -- ------------------------------------------------------------------------
    -- 4. CONSTRUCT FROZEN IMMUTABLE SNAPSHOT
    -- ------------------------------------------------------------------------
    v_snapshot := jsonb_build_object(
        'organization', jsonb_build_object(
            'name_en', 'BIMAL PATHOLOGY & DIAGNOSTIC CENTER',
            'name_ne', 'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर',
            'address_en', 'Bharatpur-7, Chitwan, Nepal',
            'address_ne', 'भरतपुर-७, चितवन, नेपाल',
            'reg_no', '7-1496',
            'pan_no', '302481477',
            'phone', '056-593288'
        ),
        'patient', jsonb_build_object(
            'uhid', v_patient.uhid,
            'full_name', v_patient.full_name,
            'title', v_patient.title,
            'mobile', v_patient.mobile,
            'gender', v_patient.gender,
            'dob', v_patient.dob,
            'age_years', v_patient.age_years,
            'age_months', v_patient.age_months,
            'age_days', v_patient.age_days,
            'address', v_patient.address
        ),
        'order', jsonb_build_object(
            'order_number', v_order.order_number,
            'bill_number', v_bill.bill_number,
            'registered_date_ad', v_order.order_date_ad,
            'registered_date_bs', v_order.order_date_bs,
            'collected_at', v_sample_dates->>'collected_at',
            'received_at', v_sample_dates->>'received_at',
            'reported_at', NOW(),
            'referring_doctor_name', COALESCE(v_bill.referring_doctor_name_snapshot, 'Self / Walk-in')
        ),
        'signatories', jsonb_build_object(
            'performed_by', jsonb_build_object(
                'id', v_performed_by.id,
                'full_name', v_performed_by.full_name,
                'qualification', v_performed_by.qualification,
                'professional_type', v_performed_by.professional_type,
                'registration_council', v_performed_by.registration_council,
                'registration_number', v_performed_by.registration_number,
                'signature_url', v_performed_by.signature_url
            ),
            'authorized_by', v_authorized_snapshot
        ),
        'investigations', v_investigations,
        'meta', jsonb_build_object(
            'version', v_version,
            'is_amendment', v_is_amendment,
            'amendment_reason', p_amendment_reason,
            'amended_from_report_id', p_amended_from_report_id,
            'signed_at', NOW(),
            'signed_by_user_id', auth.uid()
        )
    );

    -- ------------------------------------------------------------------------
    -- 5. DETERMINISTIC SHA-256 INTEGRITY HASH (Using schema-qualified pgcrypto)
    -- ------------------------------------------------------------------------
    v_hash_input := v_order.order_number || '|v' || v_version::TEXT || '|' || v_snapshot::TEXT;
    v_integrity_hash := ENCODE(
        extensions.digest(
            CONVERT_TO(v_hash_input, 'UTF8'),
            'sha256'
        ),
        'hex'
    );

    -- ------------------------------------------------------------------------
    -- 6. INSERT DIAGNOSTIC REPORT
    -- ------------------------------------------------------------------------
    v_current_year := TO_CHAR(CURRENT_DATE, 'YYYY');
    v_report_number := 'REP-' || v_current_year || '-' || LPAD(NEXTVAL('report_seq')::TEXT, 5, '0');

    INSERT INTO public.diagnostic_reports (
        order_id,
        patient_id,
        report_number,
        version,
        is_amendment,
        amendment_reason,
        amended_from_report_id,
        status,
        integrity_hash,
        performed_by_personnel_id,
        performed_by_personnel_name,
        verified_by_personnel_id,
        verified_by_personnel_name,
        signed_by_personnel_id,
        signed_by_personnel_name,
        signed_at,
        pdf_storage_path,
        clinical_snapshot_json
    ) VALUES (
        p_order_id,
        v_order.patient_id,
        v_report_number,
        v_version,
        v_is_amendment,
        p_amendment_reason,
        p_amended_from_report_id,
        'SignedOff',
        v_integrity_hash,
        v_performed_by.id,
        v_performed_by.full_name,
        v_signed_by_id,
        v_signed_by_name,
        v_signed_by_id,
        v_signed_by_name,
        NOW(),
        'reports/' || p_order_id::TEXT || '/v' || v_version::TEXT || '/report.pdf',
        v_snapshot
    ) RETURNING id INTO v_report_id;

    -- ------------------------------------------------------------------------
    -- 7. UPDATE ORDER & RESULTS STATUS TO SIGNED OFF
    -- ------------------------------------------------------------------------
    UPDATE public.clinical_order_items
    SET status = 'SignedOff', updated_at = NOW()
    WHERE order_id = p_order_id;

    UPDATE public.test_results
    SET status = 'SignedOff',
        signed_off_by = auth.uid(),
        signed_off_name = v_signed_by_name,
        signed_off_at = NOW(),
        updated_at = NOW()
    WHERE order_item_id IN (
        SELECT id FROM public.clinical_order_items WHERE order_id = p_order_id
    );

    UPDATE public.clinical_orders
    SET status = 'SignedOff', updated_at = NOW()
    WHERE id = p_order_id;

    -- ------------------------------------------------------------------------
    -- 8. AUDIT LOGGING
    -- ------------------------------------------------------------------------
    INSERT INTO public.audit_logs (
        user_id,
        user_name,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        auth.uid(),
        v_performed_by.full_name,
        CASE WHEN v_is_amendment THEN 'REPORT_AMENDMENT_SIGNED' ELSE 'REPORT_SIGNED' END,
        'DiagnosticReport',
        v_report_number,
        jsonb_build_object(
            'report_id', v_report_id,
            'order_id', p_order_id,
            'order_number', v_order.order_number,
            'version', v_version,
            'integrity_hash', v_integrity_hash,
            'signed_by_personnel', v_signed_by_name,
            'performed_by_personnel', v_performed_by.full_name,
            'is_amendment', v_is_amendment,
            'amendment_reason', p_amendment_reason
        )
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'report_id', v_report_id,
        'report_number', v_report_number,
        'version', v_version,
        'integrity_hash', v_integrity_hash,
        'storage_path', 'reports/' || p_order_id::TEXT || '/v' || v_version::TEXT || '/report.pdf',
        'is_amendment', v_is_amendment,
        'snapshot', v_snapshot
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.sign_and_freeze_diagnostic_report TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.sign_and_queue_diagnostic_report(
    p_order_id UUID, p_performed_by_id UUID, p_signed_by_id UUID,
    p_amendment_reason TEXT, p_amended_from_report_id UUID,
    p_token_hash VARCHAR(128), p_public_report_url TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report_result JSONB; v_notification_result JSONB; v_notification_sqlstate TEXT;
    v_existing public.diagnostic_reports%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_permission('can_sign_reports') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(p_order_id::TEXT, 0));
    IF p_amended_from_report_id IS NULL THEN
        SELECT * INTO v_existing FROM public.diagnostic_reports
        WHERE order_id=p_order_id AND is_amendment=FALSE AND status IN ('SignedOff','Amended')
        ORDER BY version LIMIT 1;
    ELSE
        SELECT * INTO v_existing FROM public.diagnostic_reports
        WHERE order_id=p_order_id AND amended_from_report_id=p_amended_from_report_id
          AND status IN ('SignedOff','Amended') ORDER BY version LIMIT 1;
    END IF;
    IF FOUND THEN
        v_report_result := jsonb_build_object('success',TRUE,'report_id',v_existing.id,
          'report_number',v_existing.report_number,'version',v_existing.version,
          'integrity_hash',v_existing.integrity_hash,'idempotency_replay',TRUE);
    ELSE
        v_report_result := public.sign_and_freeze_diagnostic_report(
          p_order_id,p_performed_by_id,p_signed_by_id,p_amendment_reason,p_amended_from_report_id);
    END IF;
    BEGIN
        v_notification_result := public.create_public_report_token(
          (v_report_result->>'report_id')::UUID,p_token_hash,30,p_public_report_url);
    EXCEPTION WHEN OTHERS THEN
        v_notification_sqlstate:=SQLSTATE;
        v_notification_result:=jsonb_build_object('success',FALSE,'sms_queued',FALSE,
          'sms_status','Notification unavailable; report remains signed','error_code',v_notification_sqlstate);
    END;
    IF v_notification_sqlstate IS NOT NULL THEN
        INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
        VALUES(auth.uid(),'Authorized Signatory','REPORT_NOTIFICATION_FAILED','DiagnosticReport',
          v_report_result->>'report_number',jsonb_build_object('report_id',v_report_result->>'report_id','error_code',v_notification_sqlstate));
    END IF;
    RETURN v_report_result || jsonb_build_object('notification',v_notification_result,
      'sms_queued',COALESCE((v_notification_result->>'sms_queued')::BOOLEAN,FALSE),
      'sms_status',COALESCE(v_notification_result->>'sms_status',
        CASE WHEN COALESCE((v_notification_result->>'idempotency_replay')::BOOLEAN,FALSE)
          THEN 'Notification already processed' ELSE 'Notification status unavailable' END));
END;
$$;

GRANT EXECUTE ON FUNCTION public.sign_and_queue_diagnostic_report TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.sign_and_queue_report_group(p_report_group_id UUID,p_performed_by_id UUID,p_signed_by_id UUID,p_amendment_reason TEXT,p_amended_from_report_id UUID,p_token_hash TEXT,p_order_public_url TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE signed JSONB; report_id UUID; v_order_id UUID; token public.order_report_delivery_tokens%ROWTYPE;
BEGIN
 IF p_token_hash !~ '^[0-9a-f]{64}$' OR p_order_public_url !~ '^https://dashboard[.]bimalpathology[.]com[.]np/o/[A-Za-z0-9_-]+$' OR length(substring(p_order_public_url FROM '/o/([A-Za-z0-9_-]+)$')) NOT BETWEEN 32 AND 256 THEN RAISE EXCEPTION 'Invalid secure order delivery token.' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_report_group_id::text,0));
 signed:=public.sign_report_group(p_report_group_id,p_performed_by_id,p_signed_by_id,p_amendment_reason,p_amended_from_report_id);
 report_id:=(signed->>'report_id')::uuid; SELECT order_id INTO v_order_id FROM public.clinical_report_groups WHERE id=p_report_group_id;
 SELECT * INTO token FROM public.order_report_delivery_tokens WHERE order_id=v_order_id AND is_active AND revoked_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN
   INSERT INTO public.order_report_delivery_tokens(order_id,token_hash,expires_at,created_by) VALUES(v_order_id,p_token_hash,now()+interval '30 days',auth.uid()) RETURNING * INTO token;
   INSERT INTO public.order_report_delivery_entitlements(order_token_id,report_group_id) SELECT token.id,id FROM public.clinical_report_groups WHERE clinical_report_groups.order_id=v_order_id;
 ELSE
   -- The original opaque URL is retained only in guarded delivery intents; callers cannot replace the entitlement.
   SELECT public_url INTO p_order_public_url FROM public.report_pdf_delivery_intents WHERE order_token_id=token.id ORDER BY diagnostic_report_id LIMIT 1;
   IF p_order_public_url IS NULL THEN RAISE EXCEPTION 'Existing order entitlement has no recoverable delivery presentation.' USING ERRCODE='55000'; END IF;
 END IF;
 INSERT INTO public.report_pdf_delivery_intents(diagnostic_report_id,order_token_id,public_url) VALUES(report_id,token.id,p_order_public_url) ON CONFLICT(diagnostic_report_id) DO NOTHING;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'ORDER_REPORT_ENTITLEMENT_PROVISIONED','ClinicalReportGroup',p_report_group_id::text,jsonb_build_object('report_id',report_id,'order_id',v_order_id));
 RETURN signed||jsonb_build_object('delivery_mode','OrderPortal','sms_queued',false,'sms_status','Queued after PDF artifact is ready');
END $$;

GRANT EXECUTE ON FUNCTION public.sign_and_queue_report_group TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.sign_report_group(
    p_report_group_id UUID,
    p_performed_by_id UUID,
    p_signed_by_id UUID DEFAULT NULL::UUID,
    p_amendment_reason TEXT DEFAULT NULL::TEXT,
    p_amended_from_report_id UUID DEFAULT NULL::UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    g public.clinical_report_groups%ROWTYPE;
    o public.clinical_orders%ROWTYPE;
    b public.bills%ROWTYPE;
    patient public.patients%ROWTYPE;
    performer public.reporting_personnel%ROWTYPE;
    signer public.reporting_personnel%ROWTYPE;
    parent public.diagnostic_reports%ROWTYPE;
    ready JSONB;
    investigations JSONB;
    snapshot JSONB;
    version_no INT;
    report_id UUID;
    report_no TEXT;
    integrity TEXT;
    is_amendment BOOLEAN:=p_amended_from_report_id IS NOT NULL;
    item RECORD;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_permission('can_sign_reports') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
    END IF;

    SELECT * INTO g FROM public.clinical_report_groups WHERE id=p_report_group_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report group not found.' USING ERRCODE='P0002';
    END IF;

    SELECT * INTO o FROM public.clinical_orders WHERE id=g.order_id;
    SELECT * INTO b FROM public.bills WHERE id=o.bill_id;
    SELECT * INTO patient FROM public.patients WHERE id=o.patient_id;

    SELECT * INTO performer FROM public.reporting_personnel WHERE id=p_performed_by_id AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active reporting personnel is required.' USING ERRCODE='23514';
    END IF;

    IF p_signed_by_id IS NOT NULL THEN
        SELECT * INTO signer FROM public.reporting_personnel WHERE id=p_signed_by_id AND is_active AND can_sign_reports;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Active authorized signatory is required.' USING ERRCODE='23514';
        END IF;
    END IF;

    ready:=public.check_report_group_readiness(g.id);
    IF NOT (ready->>'is_ready')::boolean THEN
        RAISE EXCEPTION 'Report group is not ready: %', ready USING ERRCODE='23514';
    END IF;

    IF is_amendment THEN
        IF NOT public.has_permission('can_amend_reports') OR btrim(coalesce(p_amendment_reason,''))='' THEN
            RAISE EXCEPTION 'Amendment permission and reason are required.' USING ERRCODE='42501';
        END IF;
        SELECT * INTO parent FROM public.diagnostic_reports WHERE id=p_amended_from_report_id AND report_group_id=g.id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Amendment parent is outside this report group.' USING ERRCODE='23514';
        END IF;
        version_no:=parent.version+1;
        UPDATE public.diagnostic_reports SET status='Amended',updated_at=now() WHERE id=parent.id;
    ELSE
        IF EXISTS(SELECT 1 FROM public.diagnostic_reports WHERE report_group_id=g.id AND status='SignedOff') THEN
            RAISE EXCEPTION 'This report group is already signed.' USING ERRCODE='23505';
        END IF;
        SELECT coalesce(max(version),0)+1 INTO version_no FROM public.diagnostic_reports WHERE report_group_id=g.id;
    END IF;

    FOR item IN SELECT oi.id FROM public.clinical_report_group_items gi JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id WHERE gi.report_group_id=g.id LOOP
        PERFORM public.recompute_order_item_calculated_results(item.id);
    END LOOP;

    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'order_item_id', x.order_item_id,
        'test_id', x.test_id,
        'test_name', x.test_name,
        'test_code', x.test_code,
        'department', x.department,
        'reporting_type', x.reporting_type,
        'execution_route', x.execution_route,
        'outsource_lab_name', x.outsource_lab_name,
        'outsource_external_reference', x.outsource_external_reference,
        'outsource_source_report_reference', x.outsource_source_report_reference,
        'outsource_method', x.outsource_method,
        'outsource_interpretation', x.outsource_interpretation,
        'outsource_result_payload', x.outsource_result_payload,
        'method', x.method,
        'interpretation_template', x.interpretation_template,
        'specimen_type', x.specimen_type,
        'container_type', x.container_type,
        'results', x.results
    ) ORDER BY x.item_order), '[]'::jsonb)
    INTO investigations FROM (
        SELECT oi.id order_item_id, oi.test_id, gi.frozen_test_name test_name, gi.frozen_test_code test_code, oi.department, oi.reporting_type, oi.execution_route, oi.outsource_lab_name, oi.outsource_external_reference, oi.outsource_source_report_reference, oi.outsource_method, oi.outsource_interpretation, oi.outsource_result_payload, t.method, t.interpretation_template, oi.specimen_type, oi.container_type, gi.display_order item_order,
        coalesce(jsonb_agg(jsonb_build_object(
            'parameter_id', tr.parameter_id,
            'code', p.code,
            'name', tr.parameter_name,
            'value_type', tr.value_type,
            'display_value', tr.display_value,
            'numeric_value', tr.numeric_value,
            'unit', tr.unit,
            'formula', p.formula,
            'flag', tr.flag,
            'is_critical', tr.is_critical,
            'result_source', tr.result_source,
            'reference_range', coalesce(case when tr.normal_min is not null and tr.normal_max is not null then tr.normal_min::text||' - '||tr.normal_max::text end, tr.normal_range_text, 'Standard'),
            'normal_min', tr.normal_min,
            'normal_max', tr.normal_max,
            'critical_low', tr.critical_low,
            'critical_high', tr.critical_high
        ) ORDER BY p.display_order) FILTER(WHERE tr.id IS NOT NULL), '[]'::jsonb) results
        FROM public.clinical_report_group_items gi
        JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id
        JOIN public.tests t ON t.id=oi.test_id
        LEFT JOIN public.test_results tr ON tr.order_item_id=oi.id
        LEFT JOIN public.parameters p ON p.id=tr.parameter_id
        WHERE gi.report_group_id=g.id
        GROUP BY oi.id, gi.frozen_test_name, gi.frozen_test_code, t.method, t.interpretation_template, gi.display_order
    ) x;

    IF jsonb_array_length(investigations)=0 THEN
        RAISE EXCEPTION 'Report group contains no reportable investigations.' USING ERRCODE='23514';
    END IF;

    snapshot:=jsonb_build_object(
        'organization', jsonb_build_object(
            'name_en', 'BIMAL PATHOLOGY & DIAGNOSTIC CENTER',
            'name_ne', 'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर',
            'address_en', 'Bharatpur-7, Chitwan, Nepal',
            'reg_no', '7-1496',
            'pan_no', '302481477',
            'phone', '056-593288'
        ),
        'patient', jsonb_build_object(
            'uhid', patient.uhid,
            'full_name', patient.full_name,
            'title', patient.title,
            'mobile', patient.mobile,
            'gender', patient.gender,
            'dob', patient.dob,
            'age_years', patient.age_years,
            'age_months', patient.age_months,
            'age_days', patient.age_days,
            'address', patient.address
        ),
        'order', jsonb_build_object(
            'order_number', o.order_number,
            'bill_number', b.bill_number,
            'registered_date_ad', o.order_date_ad,
            'registered_date_bs', o.order_date_bs,
            'reported_at', now(),
            'referring_doctor_name', coalesce(b.referring_doctor_name_snapshot, 'Self / Walk-in')
        ),
        'report_group', jsonb_build_object(
            'id', g.id,
            'key', g.group_key,
            'title', g.title,
            'clinical_section', g.clinical_section,
            'configuration_version', g.configuration_version
        ),
        'signatories', jsonb_build_object(
            'performed_by', jsonb_build_object(
                'id', performer.id,
                'full_name', performer.full_name,
                'qualification', performer.qualification,
                'professional_type', performer.professional_type,
                'registration_council', performer.registration_council,
                'registration_number', performer.registration_number,
                'signature_url', performer.signature_url
            ),
            'authorized_by', case when signer.id is null then null else jsonb_build_object(
                'id', signer.id,
                'full_name', signer.full_name,
                'qualification', signer.qualification,
                'professional_type', signer.professional_type,
                'registration_council', signer.registration_council,
                'registration_number', signer.registration_number,
                'signature_url', signer.signature_url
            ) end
        ),
        'investigations', investigations,
        'meta', jsonb_build_object(
            'version', version_no,
            'is_amendment', is_amendment,
            'amendment_reason', p_amendment_reason,
            'amended_from_report_id', p_amended_from_report_id,
            'signed_at', now(),
            'signed_by_user_id', auth.uid()
        )
    );

    integrity:=encode(extensions.digest(convert_to(o.order_number||'|'||g.group_key||'|v'||version_no||'|'||snapshot::text,'UTF8'),'sha256'),'hex');
    report_no:='REP-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('report_seq')::text,5,'0');

    INSERT INTO public.diagnostic_reports(
        order_id, report_group_id, patient_id, report_number, version, is_amendment, amendment_reason, amended_from_report_id, status, integrity_hash, performed_by_personnel_id, performed_by_personnel_name, verified_by_personnel_id, verified_by_personnel_name, signed_by_personnel_id, signed_by_personnel_name, signed_at, pdf_storage_path, clinical_snapshot_json
    ) VALUES (
        o.id, g.id, o.patient_id, report_no, version_no, is_amendment, p_amendment_reason, p_amended_from_report_id, 'SignedOff', integrity, performer.id, performer.full_name, signer.id, signer.full_name, signer.id, signer.full_name, now(), 'reports/'||o.id||'/'||g.group_key||'/v'||version_no||'/report.pdf', snapshot
    ) RETURNING id INTO report_id;

    UPDATE public.clinical_order_items oi
    SET status='SignedOff',
        outsource_state=CASE WHEN oi.execution_route='OUTSOURCE' THEN 'Signed'::public.outsource_item_state_enum ELSE oi.outsource_state END,
        updated_at=now()
    FROM public.clinical_report_group_items gi
    WHERE gi.report_group_id=g.id AND gi.order_item_id=oi.id;

    UPDATE public.test_results tr
    SET status='SignedOff',
        signed_off_by=auth.uid(),
        signed_off_name=coalesce(signer.full_name, performer.full_name),
        signed_off_at=now(),
        updated_at=now()
    FROM public.clinical_report_group_items gi
    WHERE gi.report_group_id=g.id AND gi.order_item_id=tr.order_item_id;

    UPDATE public.clinical_report_groups
    SET lifecycle_state=CASE WHEN is_amendment THEN 'Amended' ELSE 'Signed' END,
        updated_at=now(),
        row_version=row_version+1
    WHERE id=g.id;

    UPDATE public.clinical_orders
    SET status=public.derive_order_reporting_state(o.id),
        updated_at=now()
    WHERE id=o.id;

    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(),
        performer.full_name,
        case when is_amendment then 'REPORT_GROUP_AMENDMENT_SIGNED' else 'REPORT_GROUP_SIGNED' end,
        'ClinicalReportGroup',
        g.id::text,
        jsonb_build_object('report_id', report_id, 'order_id', o.id, 'group_key', g.group_key, 'version', version_no, 'integrity_hash', integrity)
    );

    RETURN jsonb_build_object(
        'success', true,
        'report_id', report_id,
        'report_group_id', g.id,
        'report_group_key', g.group_key,
        'report_number', report_no,
        'version', version_no,
        'integrity_hash', integrity,
        'snapshot', snapshot,
        'order_reporting_state', public.derive_order_reporting_state(o.id)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.sign_report_group TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.sms_gateway_v2_preflight(p_instance_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE gateway public.sms_gateway_instances%ROWTYPE;
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  SELECT * INTO gateway FROM public.sms_gateway_instances WHERE instance_id=p_instance_id;
  RETURN jsonb_build_object('success',true,'instance_id',gateway.instance_id,'claiming_enabled',gateway.claiming_enabled,
    'provider_name',gateway.provider_name,'gateway_version',gateway.gateway_version);
END $$;

GRANT EXECUTE ON FUNCTION public.sms_gateway_v2_preflight TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.sync_my_patient_identity() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_raw_phone TEXT;
  v_clean_phone TEXT;
  v_matches UUID[];
  v_match_count INT;
  v_patient_id UUID;
  v_status TEXT;
  v_patient_name TEXT;
  v_identity_id UUID;
  v_linked_at TIMESTAMPTZ;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  -- Derive phone STRICTLY from auth.users verified phone or auth.jwt()
  -- Do NOT trust user_metadata / raw_user_meta_data
  SELECT phone INTO v_raw_phone
  FROM auth.users
  WHERE id = v_uid;

  IF v_raw_phone IS NULL OR v_raw_phone = '' THEN
    v_raw_phone := coalesce(
      auth.jwt() ->> 'phone',
      auth.jwt() -> 'app_metadata' ->> 'phone'
    );
  END IF;

  v_clean_phone := public.normalize_nepal_mobile(v_raw_phone);

  IF v_clean_phone IS NULL THEN
    v_status := 'NO_MATCH';
    v_match_count := 0;
    v_patient_id := NULL;
    v_linked_at := NULL;
  ELSE
    SELECT coalesce(array_agg(p.id), ARRAY[]::UUID[])
    INTO v_matches
    FROM public.patients p
    WHERE public.normalize_nepal_mobile(p.mobile) = v_clean_phone;

    v_match_count := coalesce(array_length(v_matches, 1), 0);

    IF v_match_count = 1 THEN
      v_status := 'LINKED';
      v_patient_id := v_matches[1];
      v_linked_at := now();
      SELECT full_name INTO v_patient_name FROM public.patients WHERE id = v_patient_id;
    ELSIF v_match_count > 1 THEN
      v_status := 'REQUIRES_REVIEW';
      v_patient_id := NULL;
      v_linked_at := NULL;
    ELSE
      v_status := 'NO_MATCH';
      v_patient_id := NULL;
      v_linked_at := NULL;
    END IF;
  END IF;

  INSERT INTO public.patient_app_identities (
    auth_user_id,
    phone,
    status,
    patient_id,
    match_count,
    linked_at,
    last_synced_at
  ) VALUES (
    v_uid,
    coalesce(v_clean_phone, coalesce(v_raw_phone, 'UNKNOWN')),
    v_status,
    v_patient_id,
    v_match_count,
    v_linked_at,
    now()
  )
  ON CONFLICT (auth_user_id) DO UPDATE SET
    phone = EXCLUDED.phone,
    status = EXCLUDED.status,
    patient_id = EXCLUDED.patient_id,
    match_count = EXCLUDED.match_count,
    linked_at = CASE
      WHEN EXCLUDED.status = 'LINKED' THEN coalesce(public.patient_app_identities.linked_at, now())
      ELSE NULL
    END,
    last_synced_at = now()
  RETURNING id INTO v_identity_id;

  RETURN jsonb_build_object(
    'identity_id', v_identity_id,
    'auth_user_id', v_uid,
    'mobile', coalesce(v_clean_phone, v_raw_phone),
    'status', v_status,
    'match_count', v_match_count,
    'patient_id', CASE WHEN v_status = 'LINKED' THEN v_patient_id ELSE NULL END,
    'linked_patient_name', CASE WHEN v_status = 'LINKED' THEN v_patient_name ELSE NULL END,
    'linked_at', v_linked_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_my_patient_identity TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.transition_outsource_order_item(p_order_item_id UUID,p_to_state public.outsource_item_state_enum,p_destination_id UUID DEFAULT NULL,p_external_reference TEXT DEFAULT NULL,p_payload JSONB DEFAULT '{}'::jsonb,p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE oi public.clinical_order_items%ROWTYPE; old_state public.outsource_item_state_enum; allowed BOOLEAN:=false; tracker public.outsource_samples%ROWTYPE; new_tracking TEXT;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_outsource_tracking') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO oi FROM public.clinical_order_items WHERE id=p_order_item_id FOR UPDATE;
 IF NOT FOUND OR oi.execution_route<>'OUTSOURCE' THEN RAISE EXCEPTION 'Outsource order item not found.' USING ERRCODE='P0002'; END IF;
 old_state:=oi.outsource_state;
 allowed:=CASE
  WHEN old_state='AwaitingDispatch' AND p_to_state IN ('Dispatched','Rejected','Cancelled','UnableToPerform') THEN true
  WHEN old_state='Dispatched' AND p_to_state IN ('AwaitingExternalResult','ResultReceived','Rejected','RecollectionRequired','Cancelled','UnableToPerform') THEN true
  WHEN old_state='AwaitingExternalResult' AND p_to_state IN ('ResultReceived','Rejected','RecollectionRequired','Cancelled','UnableToPerform') THEN true
  WHEN old_state='ResultReceived' AND p_to_state='InternalReview' THEN true
  WHEN old_state='InternalReview' AND p_to_state='Verified' THEN true
  WHEN old_state='RecollectionRequired' AND p_to_state='Dispatched' THEN true
  WHEN old_state='Verified' AND p_to_state='Signed' THEN true ELSE false END;
 IF NOT allowed THEN RAISE EXCEPTION 'Invalid outsource transition: % to %',old_state,p_to_state USING ERRCODE='23514'; END IF;
 IF p_to_state='Dispatched' AND (p_destination_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.reference_laboratories WHERE id=p_destination_id AND is_active)) THEN RAISE EXCEPTION 'An active reference laboratory is required for dispatch.' USING ERRCODE='23514'; END IF;
 IF p_to_state='ResultReceived' AND coalesce(p_payload,'{}'::jsonb)='{}'::jsonb THEN RAISE EXCEPTION 'External result evidence is required.' USING ERRCODE='23514'; END IF;
 IF p_to_state='ResultReceived' AND (p_payload->>'result_type' NOT IN ('NUMERIC','QUALITATIVE','NARRATIVE','STRUCTURED') OR jsonb_typeof(p_payload->'results')<>'array' OR jsonb_array_length(p_payload->'results')=0 OR nullif(btrim(p_payload->>'source_report_reference'),'') IS NULL) THEN RAISE EXCEPTION 'Result type, structured result values, and source report reference are required.' USING ERRCODE='23514'; END IF;
 UPDATE public.clinical_order_items SET outsource_state=p_to_state,
  reference_laboratory_id=coalesce(p_destination_id,reference_laboratory_id),outsource_lab_name=coalesce((SELECT name FROM public.reference_laboratories WHERE id=p_destination_id),outsource_lab_name),
  outsource_external_reference=coalesce(nullif(p_external_reference,''),outsource_external_reference),
  outsource_source_report_reference=coalesce(nullif(p_payload->>'source_report_reference',''),outsource_source_report_reference),
  outsource_method=coalesce(nullif(p_payload->>'method',''),outsource_method),outsource_interpretation=coalesce(nullif(p_payload->>'interpretation',''),outsource_interpretation),
  outsource_result_payload=CASE WHEN p_to_state='ResultReceived' THEN p_payload ELSE outsource_result_payload END,
  outsource_result_received_at=CASE WHEN p_to_state='ResultReceived' THEN now() ELSE outsource_result_received_at END,
  outsource_result_received_by=CASE WHEN p_to_state='ResultReceived' THEN auth.uid() ELSE outsource_result_received_by END,
  outsource_reviewed_at=CASE WHEN p_to_state='InternalReview' THEN now() ELSE outsource_reviewed_at END,
  outsource_reviewed_by=CASE WHEN p_to_state='InternalReview' THEN auth.uid() ELSE outsource_reviewed_by END,
  status=CASE WHEN p_to_state='Verified' THEN 'Verified' ELSE status END,
  updated_at=now(),result_revision=result_revision+1 WHERE id=oi.id;
 IF p_to_state='ResultReceived' THEN
  UPDATE public.test_results tr SET display_value=nullif(v->>'display_value',''),numeric_value=CASE WHEN nullif(v->>'numeric_value','') IS NULL THEN NULL ELSE (v->>'numeric_value')::numeric END,text_value=nullif(v->>'text_value',''),status='SubmittedForVerification',updated_at=now()
  FROM jsonb_array_elements(p_payload->'results')v JOIN public.parameters p ON p.test_id=oi.test_id AND p.code=v->>'parameter_code' AND p.is_active
  WHERE tr.order_item_id=oi.id AND tr.parameter_id=p.id;
  IF NOT EXISTS(SELECT 1 FROM public.test_results WHERE order_item_id=oi.id AND nullif(btrim(display_value),'') IS NOT NULL) THEN RAISE EXCEPTION 'No external result matched the governed test structure.' USING ERRCODE='23514'; END IF;
 ELSIF p_to_state='Verified' THEN
  IF EXISTS(SELECT 1 FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id WHERE tr.order_item_id=oi.id AND p.is_mandatory AND nullif(btrim(tr.display_value),'') IS NULL) THEN RAISE EXCEPTION 'Required external result fields are incomplete.' USING ERRCODE='23514'; END IF;
  UPDATE public.test_results SET status='Verified',verified_by=auth.uid(),verified_by_name=public.catalogue_actor_name(),verified_at=now(),updated_at=now() WHERE order_item_id=oi.id;
 END IF;
 SELECT * INTO tracker FROM public.outsource_samples WHERE order_item_id=oi.id AND status NOT IN ('Rejected','Cancelled','LostInTransit') ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 IF FOUND AND p_to_state='Dispatched' THEN
  UPDATE public.outsource_samples SET status='DispatchedToReferenceLab',reference_laboratory_id=p_destination_id,reference_lab_name=(SELECT name FROM public.reference_laboratories WHERE id=p_destination_id),dispatched_at=now(),dispatched_by=auth.uid(),dispatched_by_name=public.catalogue_actor_name(),dispatch_notes=coalesce(p_reason,dispatch_notes),updated_at=now() WHERE id=tracker.id;
  INSERT INTO public.outsource_sample_events(outsource_sample_id,event_type,from_status,to_status,notes,meta,performed_by,performed_by_name) VALUES(tracker.id,'ORDER_ITEM_DISPATCH',tracker.status,'DispatchedToReferenceLab',p_reason,jsonb_build_object('destination_id',p_destination_id,'external_reference',p_external_reference),auth.uid(),public.catalogue_actor_name());
 ELSIF FOUND AND p_to_state='ResultReceived' THEN
  UPDATE public.outsource_samples SET status='ResultReceived',external_report_received=true,reference_lab_report_no=coalesce(nullif(p_payload->>'source_report_reference',''),reference_lab_report_no),result_received_at=now(),result_received_by=auth.uid(),result_received_by_name=public.catalogue_actor_name(),result_notes=coalesce(nullif(p_payload->>'interpretation',''),result_notes),updated_at=now() WHERE id=tracker.id;
  INSERT INTO public.outsource_sample_events(outsource_sample_id,event_type,from_status,to_status,notes,meta,performed_by,performed_by_name) VALUES(tracker.id,'ORDER_ITEM_EXTERNAL_RESULT',tracker.status,'ResultReceived',p_reason,jsonb_build_object('evidence_recorded',true),auth.uid(),public.catalogue_actor_name());
 ELSIF FOUND AND p_to_state='RecollectionRequired' THEN
  UPDATE public.outsource_samples SET status='Rejected',updated_at=now() WHERE id=tracker.id;
  INSERT INTO public.outsource_sample_events(outsource_sample_id,event_type,from_status,to_status,notes,meta,performed_by,performed_by_name) VALUES(tracker.id,'REFERENCE_LAB_REJECTION',tracker.status,'Rejected',p_reason,'{"recollection_required":true}'::jsonb,auth.uid(),public.catalogue_actor_name());
  new_tracking:='OUT-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('outsource_tracking_seq')::text,5,'0');
  INSERT INTO public.outsource_samples(tracking_number,bill_id,bill_item_id,patient_id,test_id,service_description,specimen_type,specimen_description,quantity_received,reference_lab_name,status,received_by,received_by_name,order_item_id,reference_laboratory_id,recollects_outsource_sample_id)
  VALUES(new_tracking,tracker.bill_id,tracker.bill_item_id,tracker.patient_id,tracker.test_id,tracker.service_description,tracker.specimen_type,'Recollection required: '||coalesce(p_reason,'reference laboratory rejection'),tracker.quantity_received,tracker.reference_lab_name,'ReceivedAtBimal',auth.uid(),public.catalogue_actor_name(),oi.id,tracker.reference_laboratory_id,tracker.id);
 END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'OUTSOURCE_ITEM_TRANSITION','ClinicalOrderItem',oi.id::text,jsonb_build_object('state',old_state),jsonb_build_object('state',p_to_state,'destination_id',coalesce(p_destination_id,oi.reference_laboratory_id),'external_reference',p_external_reference,'reason',p_reason));
 RETURN jsonb_build_object('success',true,'order_item_id',oi.id,'from_state',old_state,'to_state',p_to_state,'revision',oi.result_revision+1);
END $$;

GRANT EXECUTE ON FUNCTION public.transition_outsource_order_item TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.transition_sample_lifecycle(
    p_sample_id UUID,
    p_to_status sample_status_enum,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_sample public.samples%ROWTYPE;
    v_actor public.user_profiles%ROWTYPE;
    v_now TIMESTAMPTZ := NOW();
    v_new_sample_id UUID;
    v_new_barcode TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_actor
    FROM public.user_profiles
    WHERE id = auth.uid() AND is_active = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account is inactive or unavailable.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_sample FROM public.samples WHERE id = p_sample_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sample not found.' USING ERRCODE = 'P0002';
    END IF;

    IF p_to_status = 'Collected' THEN
        IF NOT public.has_permission('can_collect_sample') THEN
            RAISE EXCEPTION 'Permission denied for sample collection.' USING ERRCODE = '42501';
        END IF;
        IF v_sample.status <> 'Pending' THEN
            RAISE EXCEPTION 'Invalid sample transition: only Pending samples can be collected.' USING ERRCODE = '22023';
        END IF;
        UPDATE public.samples SET status = 'Collected', collected_at = v_now,
            collected_by = v_actor.id, collected_by_name = v_actor.full_name, updated_at = v_now
        WHERE id = v_sample.id;
        UPDATE public.clinical_order_items SET status = 'SampleCollected', updated_at = v_now
        WHERE sample_id = v_sample.id AND status = 'Pending';

    ELSIF p_to_status = 'Received' THEN
        IF NOT public.has_permission('can_receive_sample') THEN
            RAISE EXCEPTION 'Permission denied for sample receipt.' USING ERRCODE = '42501';
        END IF;
        IF v_sample.status <> 'Collected' THEN
            RAISE EXCEPTION 'Invalid sample transition: only Collected samples can be received.' USING ERRCODE = '22023';
        END IF;
        UPDATE public.samples SET status = 'Received', received_at = v_now,
            received_by = v_actor.id, received_by_name = v_actor.full_name, updated_at = v_now
        WHERE id = v_sample.id;
        UPDATE public.clinical_order_items SET status = 'SampleReceived', updated_at = v_now
        WHERE sample_id = v_sample.id AND status = 'SampleCollected';

    ELSIF p_to_status = 'Rejected' THEN
        IF NOT public.has_permission('can_reject_sample') THEN
            RAISE EXCEPTION 'Permission denied for sample rejection.' USING ERRCODE = '42501';
        END IF;
        IF v_sample.status NOT IN ('Pending', 'Collected', 'Received') THEN
            RAISE EXCEPTION 'Invalid sample transition: this sample cannot be rejected.' USING ERRCODE = '22023';
        END IF;
        IF btrim(COALESCE(p_reason, '')) = '' THEN
            RAISE EXCEPTION 'A rejection reason is required.' USING ERRCODE = '22023';
        END IF;
        UPDATE public.samples SET status = 'Rejected', rejected_at = v_now,
            rejected_by = v_actor.id, rejected_by_name = v_actor.full_name,
            rejection_reason = btrim(p_reason), updated_at = v_now
        WHERE id = v_sample.id;

    ELSIF p_to_status = 'Pending' THEN
        -- Rejected -> Pending means create a new recollection specimen; clinical
        -- history on the rejected row is never rewritten.
        IF NOT public.has_permission('can_collect_sample') THEN
            RAISE EXCEPTION 'Permission denied for recollection.' USING ERRCODE = '42501';
        END IF;
        IF v_sample.status <> 'Rejected' THEN
            RAISE EXCEPTION 'Invalid sample transition: only Rejected samples can be recollected.' USING ERRCODE = '22023';
        END IF;
        v_new_barcode := 'SMP-' || to_char(CURRENT_DATE, 'YYYY') || '-' || lpad(nextval('sample_seq')::TEXT, 5, '0');
        INSERT INTO public.samples(
            barcode, order_id, patient_id, specimen_type, container_type,
            status, recollected_from_sample_id
        ) VALUES (
            v_new_barcode, v_sample.order_id, v_sample.patient_id,
            v_sample.specimen_type, v_sample.container_type, 'Pending', v_sample.id
        ) RETURNING id INTO v_new_sample_id;
        UPDATE public.clinical_order_items SET sample_id = v_new_sample_id,
            status = 'Pending', updated_at = v_now
        WHERE sample_id = v_sample.id AND status <> 'SignedOff';
        INSERT INTO public.sample_lifecycle_events(
            sample_id, from_status, to_status, reason, performed_by, performed_by_name, timestamp
        ) VALUES (
            v_new_sample_id, 'Pending', 'Pending',
            COALESCE(NULLIF(btrim(p_reason), ''), 'Recollection ordered for rejected sample ' || v_sample.barcode),
            v_actor.id, v_actor.full_name, v_now
        );
        RETURN jsonb_build_object('success', TRUE, 'sample_id', v_new_sample_id,
            'barcode', v_new_barcode, 'status', 'Pending', 'recollected_from_sample_id', v_sample.id);
    ELSE
        RAISE EXCEPTION 'Unsupported sample transition.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.sample_lifecycle_events(
        sample_id, from_status, to_status, reason, performed_by, performed_by_name, timestamp
    ) VALUES (
        v_sample.id, v_sample.status, p_to_status, NULLIF(btrim(COALESCE(p_reason, '')), ''),
        v_actor.id, v_actor.full_name, v_now
    );

    RETURN jsonb_build_object('success', TRUE, 'sample_id', v_sample.id,
        'barcode', v_sample.barcode, 'from_status', v_sample.status, 'status', p_to_status);
END;
$$;

GRANT EXECUTE ON FUNCTION public.transition_sample_lifecycle TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_outsource_sample_status(
    p_sample_id UUID,
    p_to_status outsource_sample_status_enum,
    p_notes TEXT DEFAULT NULL,
    p_meta JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_sample RECORD;
    v_user_name VARCHAR(255);
    v_now TIMESTAMPTZ := NOW();
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT full_name INTO v_user_name FROM public.user_profiles WHERE user_id = auth.uid();
    v_user_name := COALESCE(v_user_name, 'Staff');

    SELECT * INTO v_sample FROM public.outsource_samples WHERE id = p_sample_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Outsource sample with ID % not found.', p_sample_id;
    END IF;

    -- Update main record based on transition state
    UPDATE public.outsource_samples
    SET status = p_to_status,
        updated_at = v_now,
        -- Dispatch payload mapping
        dispatched_at = CASE WHEN p_to_status = 'DispatchedToReferenceLab' THEN v_now ELSE dispatched_at END,
        dispatched_by = CASE WHEN p_to_status = 'DispatchedToReferenceLab' THEN auth.uid() ELSE dispatched_by END,
        dispatched_by_name = CASE WHEN p_to_status = 'DispatchedToReferenceLab' THEN v_user_name ELSE dispatched_by_name END,
        reference_lab_name = COALESCE(p_meta->>'reference_lab_name', reference_lab_name),
        courier_name = COALESCE(p_meta->>'courier_name', courier_name),
        courier_tracking_no = COALESCE(p_meta->>'courier_tracking_no', courier_tracking_no),
        items_sent_count = COALESCE(p_meta->>'items_sent_count', items_sent_count),
        dispatch_notes = COALESCE(p_meta->>'dispatch_notes', dispatch_notes),
        
        -- Result Receipt payload mapping
        external_report_received = CASE WHEN p_to_status IN ('ResultReceived', 'MaterialReturned', 'Completed') THEN TRUE ELSE external_report_received END,
        external_report_date = COALESCE((p_meta->>'external_report_date')::DATE, external_report_date),
        reference_lab_report_no = COALESCE(p_meta->>'reference_lab_report_no', reference_lab_report_no),
        result_received_at = CASE WHEN p_to_status = 'ResultReceived' THEN v_now ELSE result_received_at END,
        result_received_by = CASE WHEN p_to_status = 'ResultReceived' THEN auth.uid() ELSE result_received_by END,
        result_received_by_name = CASE WHEN p_to_status = 'ResultReceived' THEN v_user_name ELSE result_received_by_name END,
        result_notes = COALESCE(p_meta->>'result_notes', result_notes),
        
        -- Material Return payload mapping
        material_returned = CASE WHEN p_to_status IN ('MaterialReturned', 'Completed') THEN TRUE ELSE material_returned END,
        material_returned_at = CASE WHEN p_to_status = 'MaterialReturned' THEN v_now ELSE material_returned_at END,
        blocks_returned_count = COALESCE((p_meta->>'blocks_returned_count')::INT, blocks_returned_count),
        slides_returned_count = COALESCE((p_meta->>'slides_returned_count')::INT, slides_returned_count),
        material_received_by = CASE WHEN p_to_status = 'MaterialReturned' THEN auth.uid() ELSE material_received_by END,
        material_received_by_name = CASE WHEN p_to_status = 'MaterialReturned' THEN v_user_name ELSE material_received_by_name END,
        return_notes = COALESCE(p_meta->>'return_notes', return_notes),
        
        completed_at = CASE WHEN p_to_status = 'Completed' THEN v_now ELSE completed_at END
    WHERE id = p_sample_id;

    -- Append Immutable Audit Event
    INSERT INTO public.outsource_sample_events (
        outsource_sample_id,
        event_type,
        from_status,
        to_status,
        notes,
        meta,
        performed_by,
        performed_by_name
    ) VALUES (
        p_sample_id,
        'STATUS_TRANSITION_' || p_to_status::TEXT,
        v_sample.status,
        p_to_status,
        p_notes,
        p_meta,
        auth.uid(),
        v_user_name
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'sample_id', p_sample_id,
        'from_status', v_sample.status,
        'to_status', p_to_status,
        'updated_at', v_now
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_outsource_sample_status TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_patient_demographics(p_patient_id UUID, p_patient_data JSONB)
RETURNS public.patients
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old public.patients%ROWTYPE;
  v_new public.patients%ROWTYPE;
  v_mobile TEXT := public.patient_normalize_mobile(p_patient_data->>'mobile');
  v_name TEXT := public.patient_clean_text(p_patient_data->>'full_name');
  v_address TEXT := public.patient_clean_text(p_patient_data->>'address');
  v_changed TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF NOT public.has_permission('can_edit_patient') THEN
    RAISE EXCEPTION 'Not authorized to edit patients.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_old FROM public.patients WHERE id = p_patient_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found.' USING ERRCODE = 'P0002'; END IF;
  IF NOT v_old.is_active THEN RAISE EXCEPTION 'Archived patients must be restored before editing.' USING ERRCODE = '55000'; END IF;
  IF v_name = '' OR v_address = '' THEN RAISE EXCEPTION 'Patient name and address are required.' USING ERRCODE = '22023'; END IF;
  IF COALESCE(p_patient_data->>'gender','') NOT IN ('Male','Female','Other') THEN RAISE EXCEPTION 'Invalid patient gender.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_years','')::INT NOT BETWEEN 0 AND 120 AND NULLIF(p_patient_data->>'age_years','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age years must be from 0 to 120.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_months','')::INT NOT BETWEEN 0 AND 11 AND NULLIF(p_patient_data->>'age_months','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age months must be from 0 to 11.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_days','')::INT NOT BETWEEN 0 AND 31 AND NULLIF(p_patient_data->>'age_days','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age days must be from 0 to 31.' USING ERRCODE = '22023'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('patient-mobile:' || v_mobile, 0));
  IF EXISTS (SELECT 1 FROM public.patients WHERE mobile = v_mobile AND id <> p_patient_id) THEN
    RAISE EXCEPTION 'A different patient with this mobile number already exists. Patients are never auto-merged.' USING ERRCODE = '23505';
  END IF;

  IF v_old.full_name IS DISTINCT FROM v_name THEN v_changed := array_append(v_changed,'full_name'); END IF;
  IF v_old.mobile IS DISTINCT FROM v_mobile THEN v_changed := array_append(v_changed,'mobile'); END IF;
  IF v_old.address IS DISTINCT FROM v_address THEN v_changed := array_append(v_changed,'address'); END IF;
  IF v_old.dob IS DISTINCT FROM NULLIF(p_patient_data->>'dob','')::DATE THEN v_changed := array_append(v_changed,'dob'); END IF;
  IF v_old.gender IS DISTINCT FROM p_patient_data->>'gender' THEN v_changed := array_append(v_changed,'gender'); END IF;
  IF v_old.age_years IS DISTINCT FROM NULLIF(p_patient_data->>'age_years','')::INT
     OR v_old.age_months IS DISTINCT FROM NULLIF(p_patient_data->>'age_months','')::INT
     OR v_old.age_days IS DISTINCT FROM NULLIF(p_patient_data->>'age_days','')::INT THEN
    v_changed := array_append(v_changed,'age');
  END IF;

  UPDATE public.patients
  SET mobile = v_mobile,
      title = NULLIF(public.patient_clean_text(p_patient_data->>'title'),''),
      full_name = v_name,
      gender = p_patient_data->>'gender',
      dob = NULLIF(p_patient_data->>'dob','')::DATE,
      age_years = NULLIF(p_patient_data->>'age_years','')::INT,
      age_months = NULLIF(p_patient_data->>'age_months','')::INT,
      age_days = NULLIF(p_patient_data->>'age_days','')::INT,
      address = v_address,
      email = NULLIF(public.patient_clean_text(p_patient_data->>'email'),''),
      identification_no = NULLIF(public.patient_clean_text(p_patient_data->>'identification_no'),''),
      updated_at = NOW()
  WHERE id = p_patient_id
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES (
    auth.uid(), public.patient_actor_name(), 'PATIENT_DEMOGRAPHICS_UPDATED', 'Patient', p_patient_id::TEXT,
    jsonb_build_object('uhid',v_old.uhid,'changed_fields',v_changed),
    jsonb_build_object('uhid',v_old.uhid,'changed_fields',v_changed)
  );
  RETURN v_new;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_patient_demographics TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_sms_status(
    p_sms_id UUID,
    p_status VARCHAR(50),
    p_provider_msg_id VARCHAR(100) DEFAULT NULL,
    p_provider_response JSONB DEFAULT NULL,
    p_error_msg TEXT DEFAULT NULL,
    p_is_permanent_failure BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_sms public.sms_queue_items%ROWTYPE;
    v_new_status VARCHAR(50);
    v_new_attempts INT;
    v_next_delay_secs INT;
BEGIN
    SELECT * INTO v_sms
      FROM public.sms_queue_items
     WHERE id = p_sms_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SMS item % not found.', p_sms_id;
    END IF;

    IF v_sms.status = 'Sent' THEN
        RETURN jsonb_build_object('success', TRUE, 'status', 'Sent', 'already_completed', TRUE);
    END IF;
    IF v_sms.status <> 'Processing' THEN
        RAISE EXCEPTION 'SMS item % is %, expected Processing.', p_sms_id, v_sms.status
            USING ERRCODE = '55000';
    END IF;

    IF p_status = 'Sent' THEN
        v_new_status := 'Sent';
        UPDATE public.sms_queue_items
           SET status = 'Sent',
               sent_at = NOW(),
               provider_message_id = p_provider_msg_id,
               provider_response_json = p_provider_response,
               error_message = NULL,
               updated_at = NOW()
         WHERE id = p_sms_id AND status = 'Processing';

        INSERT INTO public.audit_logs(action, entity_type, entity_id, new_data)
        VALUES ('SMS_SENT', 'SmsQueueItem', p_sms_id::TEXT,
            jsonb_build_object('sms_id', p_sms_id, 'provider_message_id', p_provider_msg_id));
    ELSE
        v_new_attempts := v_sms.retry_count + 1;
        IF p_is_permanent_failure OR v_new_attempts >= v_sms.max_attempts THEN
            v_new_status := 'DeadLetter';
            v_next_delay_secs := 0;
        ELSE
            v_new_status := 'Pending';
            v_next_delay_secs := CASE
                WHEN v_new_attempts = 1 THEN 120
                WHEN v_new_attempts = 2 THEN 600
                WHEN v_new_attempts = 3 THEN 1800
                ELSE 3600
            END;
        END IF;

        UPDATE public.sms_queue_items
           SET status = v_new_status,
               retry_count = v_new_attempts,
               error_message = p_error_msg,
               provider_response_json = p_provider_response,
               scheduled_at = CASE WHEN v_new_status = 'Pending'
                   THEN NOW() + make_interval(secs => v_next_delay_secs)
                   ELSE scheduled_at END,
               updated_at = NOW()
         WHERE id = p_sms_id AND status = 'Processing';

        INSERT INTO public.audit_logs(action, entity_type, entity_id, new_data)
        VALUES ('SMS_FAILED', 'SmsQueueItem', p_sms_id::TEXT,
            jsonb_build_object('sms_id', p_sms_id, 'attempt', v_new_attempts,
                'status', v_new_status, 'error', p_error_msg));
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'status', v_new_status);
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_sms_status TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_user_access(p_user_id UUID,p_is_active BOOLEAN,p_is_super_admin BOOLEAN,p_role_ids UUID[] DEFAULT ARRAY[]::UUID[])
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE target public.user_profiles%ROWTYPE; role_count INT; technician_role CONSTANT UUID:='00000000-0000-0000-0000-000000000004';
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() OR NOT public.is_active_user() THEN RAISE EXCEPTION 'System Owner authority is required.' USING ERRCODE='42501'; END IF;
  SELECT * INTO target FROM public.user_profiles WHERE id=p_user_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'User account was not found.' USING ERRCODE='P0002'; END IF;
  IF p_user_id=auth.uid() AND NOT p_is_active THEN RAISE EXCEPTION 'You cannot deactivate your own account.' USING ERRCODE='22023'; END IF;
  IF target.is_super_admin AND (NOT p_is_active OR NOT p_is_super_admin) AND NOT EXISTS(SELECT 1 FROM public.user_profiles u WHERE u.id<>p_user_id AND u.is_active AND u.is_super_admin) THEN RAISE EXCEPTION 'At least one active Super Admin is required.' USING ERRCODE='23514'; END IF;
  SELECT count(*) INTO role_count FROM unnest(COALESCE(p_role_ids,ARRAY[]::UUID[])) r(id);
  IF role_count>1 OR (role_count=1 AND p_role_ids[1]<>technician_role) THEN RAISE EXCEPTION 'Lab Technician is the only normally assignable role.' USING ERRCODE='22023'; END IF;
  UPDATE public.user_profiles SET is_active=p_is_active,is_super_admin=p_is_super_admin,updated_at=now() WHERE id=p_user_id;
  DELETE FROM public.user_roles WHERE user_id=p_user_id AND role_id=technician_role;
  IF role_count=1 THEN INSERT INTO public.user_roles(user_id,role_id) VALUES(p_user_id,technician_role) ON CONFLICT DO NOTHING; END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'USER_ACCESS_UPDATED','UserProfile',p_user_id::TEXT,jsonb_build_object('changed_fields',jsonb_build_array('is_active','is_super_admin','lab_technician_assignment'),'lab_technician_assigned',role_count=1));
  RETURN jsonb_build_object('success',TRUE,'user_id',p_user_id);
END $$;

GRANT EXECUTE ON FUNCTION public.update_user_access TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.uuid_generate_v4()
RETURNS UUID
LANGUAGE sql
VOLATILE
SET search_path = extensions, pg_temp
AS $$ SELECT extensions.uuid_generate_v4() $$;

GRANT EXECUTE ON FUNCTION public.uuid_generate_v4 TO authenticated, service_role;

CREATE FUNCTION public.validate_report_pdf_artifact_identity()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE report public.diagnostic_reports%ROWTYPE;
BEGIN
  SELECT * INTO report FROM public.diagnostic_reports WHERE id=NEW.diagnostic_report_id;
  IF NOT FOUND OR report.status NOT IN('SignedOff','Amended')
     OR report.version<>NEW.report_version
     OR report.integrity_hash<>NEW.report_integrity_hash
     OR encode(extensions.digest(report.clinical_snapshot_json::TEXT,'sha256'),'hex')<>NEW.frozen_snapshot_sha256 THEN
    RAISE EXCEPTION 'Report PDF artifact identity does not match the frozen signed report.' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION public.validate_report_pdf_artifact_identity TO authenticated, service_role;



-- ============================================================================
-- 6. MASTER SEED DATA
-- ============================================================================


INSERT INTO public.analyzers (code, name, manufacturer, model, laboratory_location, lifecycle_status, row_version) VALUES
('COUNCELL_23_EXCEL', 'CounCell 23 Excel', 'Coral Clinical Systems / Tulip Diagnostics', 'CounCell 23 Excel', 'Hematology Laboratory', 'Active', 1),
('CORALAB_ACE', 'CORALAB ACE', 'Coral Clinical Systems / Tulip Diagnostics', 'CORALAB ACE', 'Clinical Biochemistry Laboratory', 'Active', 1),
('FIACHECK', 'FIAcheck', 'Goldsite Diagnostics / FIAcheck', 'FIAcheck-100', 'Immunology & Hormone Laboratory', 'Active', 1)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name, manufacturer = EXCLUDED.manufacturer, model = EXCLUDED.model,
    laboratory_location = EXCLUDED.laboratory_location, lifecycle_status = 'Active';

-- ALG-0049: Food Allergy Panel — direct parameters (pure SQL, test_id resolved by subquery)
INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active, lifecycle_status, clinical_configuration_status)
SELECT t.id, v.code, v.name, v.unit, v.value_type::public.parameter_value_type_enum, v.display_order, v.is_mandatory, TRUE, 'Active', 'Configured'
FROM public.tests t
CROSS JOIN (VALUES
    ('ALG-0049-01', 'Food Specific IgE Panel Result', 'kU/L', 'Text', 1, TRUE),
    ('ALG-0049-02', 'Allergen Sensitization Summary', NULL,   'Text', 2, FALSE)
) AS v(code, name, unit, value_type, display_order, is_mandatory)
WHERE t.code = 'ALG-0049' AND t.is_active = TRUE
ON CONFLICT (test_id, code) DO UPDATE SET
    name = EXCLUDED.name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
    display_order = EXCLUDED.display_order, is_active = TRUE, lifecycle_status = 'Active';


INSERT INTO public.analyzer_parameter_mappings (
    id, analyzer_id, channel_code, channel_name, test_id, parameter_id,
    measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
)
SELECT
    src.id, a.id, src.channel_code, src.channel_name, t.id, p.id,
    src.measurement_type, src.analytical_method, src.unit, src.differential_type,
    src.is_automated_5part_supported
FROM (
    VALUES
('80051f74-7015-42da-af5b-3d91a0b20824'::UUID, 'COUNCELL_23_EXCEL', 'GRAN_ABS', 'Absolute Granulocyte Count (3-Part GRAN#)', 'HEM-0001', 'GRAN_ABS', 'ANALYZER_CALCULATED', 'Analyzer Differential GRAN#', '10^9/L', '3-Part', FALSE),
('1f2f379b-7a1d-48c3-a9c8-54535e83c30a'::UUID, 'COUNCELL_23_EXCEL', 'GRAN_PERCENT', 'Granulocyte % (Neutrophils/Eos/Baso)', 'HEM-0001', 'GRAN_PERCENT', 'DIRECT_MEASURED', 'Electrical Impedance (Large cell cluster)', '%', '3-Part', FALSE),
('60db7b77-573f-443b-8c43-50089440e0c5'::UUID, 'COUNCELL_23_EXCEL', 'HCT', 'Hematocrit (HCT/PCV)', 'HEM-0001', 'HCT', 'ANALYZER_CALCULATED', 'Analyzer Calculated HCT', '%', 'Not Applicable', FALSE),
('3ac33bf3-d809-4001-9aae-61febdd5712e'::UUID, 'COUNCELL_23_EXCEL', 'HGB', 'Hemoglobin (HGB)', 'HEM-0001', 'HGB', 'DIRECT_MEASURED', 'Cyanide-free Colorimetry', 'g/dL', 'Not Applicable', FALSE),
('b4c2bf01-42f8-46bb-9457-fd134762c3dc'::UUID, 'COUNCELL_23_EXCEL', 'LYM_ABS', 'Absolute Lymphocyte Count (3-Part LYM#)', 'HEM-0001', 'LYM_ABS', 'ANALYZER_CALCULATED', 'Analyzer Differential LYM#', '10^9/L', '3-Part', FALSE),
('d604ab6b-b4ca-432c-9591-98d3d8e75aad'::UUID, 'COUNCELL_23_EXCEL', 'LYM_PERCENT', 'Lymphocyte % (3-Part)', 'HEM-0001', 'LYM_PERCENT', 'DIRECT_MEASURED', 'Electrical Impedance (Small cell cluster)', '%', '3-Part', FALSE),
('7d34dad1-d431-47ab-bc7e-ed5884557ec5'::UUID, 'COUNCELL_23_EXCEL', 'MCH', 'Mean Corpuscular Hemoglobin (MCH)', 'HEM-0001', 'MCH', 'ANALYZER_CALCULATED', 'Analyzer Calculated MCH', 'pg', 'Not Applicable', FALSE),
('477fa01e-ab93-4636-a3de-6df3d4bf5741'::UUID, 'COUNCELL_23_EXCEL', 'MCHC', 'Mean Corpuscular Hemoglobin Conc. (MCHC)', 'HEM-0001', 'MCHC', 'ANALYZER_CALCULATED', 'Analyzer Calculated MCHC', 'g/dL', 'Not Applicable', FALSE),
('46e9ab94-db4c-4ae0-a267-53a2b9ecd587'::UUID, 'COUNCELL_23_EXCEL', 'MCV', 'Mean Corpuscular Volume (MCV)', 'HEM-0001', 'MCV', 'ANALYZER_DERIVED', 'Derived from RBC histogram peak', 'fL', 'Not Applicable', FALSE),
('2524931d-04a9-4586-9667-f70f36583bc7'::UUID, 'COUNCELL_23_EXCEL', 'MID_ABS', 'Absolute Mid-Cell Count (3-Part MID#)', 'HEM-0001', 'MID_ABS', 'ANALYZER_CALCULATED', 'Analyzer Differential MID#', '10^9/L', '3-Part', FALSE),
('3d63a0a7-19c2-4adc-a5e9-3c23e057ffec'::UUID, 'COUNCELL_23_EXCEL', 'MID_PERCENT', 'Mid-Cell % (Monocytes/Eos/Baso cluster)', 'HEM-0001', 'MID_PERCENT', 'DIRECT_MEASURED', 'Electrical Impedance (Mid-size cell cluster)', '%', '3-Part', FALSE),
('61818bdd-e86c-48ac-a02f-144af9b8a975'::UUID, 'COUNCELL_23_EXCEL', 'MPV', 'Mean Platelet Volume (MPV)', 'HEM-0001', 'MPV', 'ANALYZER_DERIVED', 'PLT size histogram analysis', 'fL', 'Not Applicable', FALSE),
('55733a1b-3a67-453c-a875-2207be07c2e3'::UUID, 'COUNCELL_23_EXCEL', 'NLR', 'Neutrophil-to-Lymphocyte Ratio (NLR)', 'HEM-0001', 'NLR', 'ANALYZER_CALCULATED', 'Analyzer Calculated NLR', 'Ratio', 'Not Applicable', FALSE),
('53a36f80-3404-4edf-95e1-36cd1f9e0e54'::UUID, 'COUNCELL_23_EXCEL', 'P_LCC', 'Platelet Large Cell Count (P-LCC)', 'HEM-0001', 'P_LCC', 'ANALYZER_CALCULATED', 'Analyzer Calculated P-LCC', '10^9/L', 'Not Applicable', FALSE),
('1604ed4f-fdaf-494d-9e59-320c7f3afa0b'::UUID, 'COUNCELL_23_EXCEL', 'P_LCR', 'Platelet Large Cell Ratio (P-LCR)', 'HEM-0001', 'P_LCR', 'ANALYZER_DERIVED', 'PLT histogram analysis (>12 fL)', '%', 'Not Applicable', FALSE),
('422a3d23-96c2-40a0-a5d1-24502e8129ea'::UUID, 'COUNCELL_23_EXCEL', 'PCT', 'Plateletcrit (PCT)', 'HEM-0001', 'PCT', 'ANALYZER_CALCULATED', 'Analyzer Calculated PCT', '%', 'Not Applicable', FALSE),
('bf7729ed-39eb-4122-9114-fa65540858b5'::UUID, 'COUNCELL_23_EXCEL', 'PDW_CV', 'Platelet Distribution Width (PDW-CV)', 'HEM-0001', 'PDW_CV', 'ANALYZER_DERIVED', 'PLT volume variation coefficient', '%', 'Not Applicable', FALSE),
('ab686259-3dfa-45c1-8406-8ee3c2394a11'::UUID, 'COUNCELL_23_EXCEL', 'PDW_SD', 'Platelet Distribution Width (PDW-SD)', 'HEM-0001', 'PDW_SD', 'ANALYZER_DERIVED', 'PLT volume standard deviation', 'fL', 'Not Applicable', FALSE),
('f618b769-e74f-4ee0-8ea2-1cfaaaee00b8'::UUID, 'COUNCELL_23_EXCEL', 'PLR', 'Platelet-to-Lymphocyte Ratio (PLR)', 'HEM-0001', 'PLR', 'ANALYZER_CALCULATED', 'Analyzer Calculated PLR', 'Ratio', 'Not Applicable', FALSE),
('32fb1cf2-be3b-4c07-b08a-2736b42b9180'::UUID, 'COUNCELL_23_EXCEL', 'PLT', 'Platelet Count (PLT)', 'HEM-0001', 'PLT', 'DIRECT_MEASURED', 'Electrical Impedance', '10^3/µL', 'Not Applicable', FALSE),
('b3f1598f-0925-45a7-96a3-76a9eec03d6d'::UUID, 'COUNCELL_23_EXCEL', 'RBC', 'Red Blood Cell Count (RBC)', 'HEM-0001', 'RBC', 'DIRECT_MEASURED', 'Electrical Impedance', '10^6/µL', 'Not Applicable', FALSE),
('fb0c2f6d-3174-4b55-a0cf-84ae0df2f3ca'::UUID, 'COUNCELL_23_EXCEL', 'RDW_CV', 'RBC Distribution Width (RDW-CV)', 'HEM-0001', 'RDW_CV', 'ANALYZER_DERIVED', 'RBC volume variation coefficient', '%', 'Not Applicable', FALSE),
('f261947b-117c-48c9-9486-17e923e20ec6'::UUID, 'COUNCELL_23_EXCEL', 'RDW_SD', 'RBC Distribution Width (RDW-SD)', 'HEM-0001', 'RDW_SD', 'ANALYZER_DERIVED', 'RBC histogram width at 20% height', 'fL', 'Not Applicable', FALSE),
('7d21c435-0818-4712-ba2c-7b44747dbcc7'::UUID, 'COUNCELL_23_EXCEL', 'WBC', 'Total Leukocyte Count (WBC)', 'HEM-0001', 'WBC', 'DIRECT_MEASURED', 'Electrical Impedance', '10^3/µL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000001'::UUID, 'CORALAB_ACE', 'ALT', 'Alanine Aminotransferase (ALT/SGPT)', 'BIO-0021', 'BIO-0021', 'DIRECT_MEASURED', 'UV Kinetic (IFCC)', 'U/L', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000002'::UUID, 'CORALAB_ACE', 'AST', 'Aspartate Aminotransferase (AST/SGOT)', 'BIO-0020', 'BIO-0020', 'DIRECT_MEASURED', 'UV Kinetic (IFCC)', 'U/L', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000003'::UUID, 'CORALAB_ACE', 'ALP', 'Alkaline Phosphatase (ALP)', 'BIO-0022', 'BIO-0022', 'DIRECT_MEASURED', 'p-NPP Kinetic (IFCC)', 'U/L', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000004'::UUID, 'CORALAB_ACE', 'TBIL', 'Total Bilirubin', 'BIO-0017', 'BIO-0017', 'DIRECT_MEASURED', 'Modified Jendrassik-Grof / DPD', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000005'::UUID, 'CORALAB_ACE', 'DBIL', 'Direct Bilirubin', 'BIO-0018', 'BIO-0018', 'DIRECT_MEASURED', 'Modified Jendrassik-Grof / DPD', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000006'::UUID, 'CORALAB_ACE', 'TP', 'Total Protein', 'BIO-0013', 'BIO-0013', 'DIRECT_MEASURED', 'Biuret End Point', 'g/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000007'::UUID, 'CORALAB_ACE', 'ALB', 'Albumin', 'BIO-0014', 'BIO-0014', 'DIRECT_MEASURED', 'Bromocresol Green (BCG)', 'g/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000008'::UUID, 'CORALAB_ACE', 'GGT', 'Gamma-Glutamyl Transferase (GGT)', 'BIO-0023', 'BIO-0023', 'DIRECT_MEASURED', 'Szasz Kinetic (IFCC)', 'U/L', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000009'::UUID, 'CORALAB_ACE', 'CREAT', 'Creatinine', 'BIO-0010', 'BIO-0010', 'DIRECT_MEASURED', 'Modified Jaffé Kinetic', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000010'::UUID, 'CORALAB_ACE', 'UREA', 'Urea', 'BIO-0008', 'BIO-0008', 'DIRECT_MEASURED', 'GLDH / Urease Kinetic', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000011'::UUID, 'CORALAB_ACE', 'URIC', 'Uric Acid', 'BIO-0012', 'BIO-0012', 'DIRECT_MEASURED', 'Uricase / POD End Point', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000012'::UUID, 'CORALAB_ACE', 'GLU_FASTING', 'Glucose, Fasting (FBS)', 'BIO-0001', 'BIO-0001', 'DIRECT_MEASURED', 'GOD-POD End Point', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000013'::UUID, 'CORALAB_ACE', 'GLU_PP', 'Glucose, Postprandial 2 hr (PPBS)', 'BIO-0003', 'BIO-0003', 'DIRECT_MEASURED', 'GOD-POD End Point', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000014'::UUID, 'CORALAB_ACE', 'GLU_RANDOM', 'Glucose, Random (RBS)', 'BIO-0002', 'BIO-0002', 'DIRECT_MEASURED', 'GOD-POD End Point', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000015'::UUID, 'CORALAB_ACE', 'CHOL', 'Total Cholesterol', 'BIO-0027', 'BIO-0027', 'DIRECT_MEASURED', 'CHOD-PAP End Point', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000016'::UUID, 'CORALAB_ACE', 'TRIG', 'Triglycerides', 'BIO-0028', 'BIO-0028', 'DIRECT_MEASURED', 'GPO-PAP End Point', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000017'::UUID, 'CORALAB_ACE', 'HDL', 'HDL Cholesterol', 'BIO-0029', 'BIO-0029', 'DIRECT_MEASURED', 'Direct Immunoinhibition / Detergent', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000018'::UUID, 'CORALAB_ACE', 'LDL_DIRECT', 'LDL Cholesterol, Direct', 'BIO-0030', 'BIO-0030', 'DIRECT_MEASURED', 'Direct Clearance / Selective Detergent', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000019'::UUID, 'CORALAB_ACE', 'CALC', 'Calcium, Total', 'BIO-0041', 'BIO-0041', 'DIRECT_MEASURED', 'Arsenazo III / O-CPC', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000020'::UUID, 'CORALAB_ACE', 'PHOS', 'Phosphorus', 'BIO-0043', 'BIO-0043', 'DIRECT_MEASURED', 'Phosphomolybdate UV', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000021'::UUID, 'CORALAB_ACE', 'MAG', 'Magnesium', 'BIO-0044', 'BIO-0044', 'DIRECT_MEASURED', 'Calmagite / Xylidyl Blue', 'mg/dL', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000022'::UUID, 'CORALAB_ACE', 'NA_PHOTOMETRIC', 'Sodium (Photometric)', 'BIO-0037', 'BIO-0037', 'DIRECT_MEASURED', 'Enzymatic / Colorimetric (Photometric Non-ISE)', 'mmol/L', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000023'::UUID, 'CORALAB_ACE', 'K_PHOTOMETRIC', 'Potassium (Photometric)', 'BIO-0038', 'BIO-0038', 'DIRECT_MEASURED', 'Enzymatic / Turbidimetric (Photometric Non-ISE)', 'mmol/L', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000024'::UUID, 'CORALAB_ACE', 'CL_PHOTOMETRIC', 'Chloride (Photometric)', 'BIO-0039', 'BIO-0039', 'DIRECT_MEASURED', 'Mercuric Thiocyanate (Photometric Non-ISE)', 'mmol/L', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000025'::UUID, 'CORALAB_ACE', 'CK_TOTAL', 'CK Total (Creatine Kinase)', 'BIO-0060', 'BIO-0060', 'DIRECT_MEASURED', 'CK-NAC / Modified IFCC Kinetic', 'U/L', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000026'::UUID, 'CORALAB_ACE', 'CK_MB', 'CK-MB Activity', 'BIO-0062', 'BIO-0062', 'DIRECT_MEASURED', 'Immunoinhibition Kinetic', 'U/L', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000027'::UUID, 'CORALAB_ACE', 'LDH', 'Lactate Dehydrogenase (LDH)', 'BIO-0024', 'BIO-0024', 'DIRECT_MEASURED', 'DGKC / IFCC UV Kinetic', 'U/L', 'Not Applicable', FALSE),
('a01a0001-0000-4000-8000-000000000028'::UUID, 'CORALAB_ACE', 'AMYLASE', 'Amylase', 'BIO-0058', 'BIO-0058', 'DIRECT_MEASURED', 'CNP-G3 Direct Substrate', 'U/L', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000001'::UUID, 'FIACHECK', 'TSH', 'Thyroid Stimulating Hormone (TSH)', 'END-0001', 'END-0001', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'µIU/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000002'::UUID, 'FIACHECK', 'FT3', 'Free Triiodothyronine (FT3)', 'END-0003', 'END-0003', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'pg/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000003'::UUID, 'FIACHECK', 'FT4', 'Free Thyroxine (FT4)', 'END-0002', 'END-0002', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/dL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000004'::UUID, 'FIACHECK', 'TT3', 'Total Triiodothyronine (Total T3)', 'END-0005', 'END-0005', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000005'::UUID, 'FIACHECK', 'TT4', 'Total Thyroxine (Total T4)', 'END-0004', 'END-0004', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'µg/dL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000006'::UUID, 'FIACHECK', 'VIT_D', '25-OH Vitamin D', 'BIO-0053', 'BIO-0053', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000007'::UUID, 'FIACHECK', 'VIT_B12', 'Vitamin B12', 'BIO-0051', 'BIO-0051', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'pg/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000008'::UUID, 'FIACHECK', 'CTNI', 'Cardiac Troponin I (cTnI)', 'BIO-0063', 'BIO-0063', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000009'::UUID, 'FIACHECK', 'CKMB_MASS', 'CK-MB Mass', 'BIO-0061', 'BIO-0061', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000010'::UUID, 'FIACHECK', 'MYO', 'Myoglobin', 'BIO-0065', 'BIO-0065', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000011'::UUID, 'FIACHECK', 'NT_PROBNP', 'NT-proBNP', 'BIO-0067', 'BIO-0067', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'pg/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000012'::UUID, 'FIACHECK', 'D_DIMER', 'D-Dimer (FEU)', 'COA-0006', 'COA-0006', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'µg/mL FEU', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000013'::UUID, 'FIACHECK', 'HS_CRP', 'High Sensitivity CRP (hs-CRP)', 'BIO-0068', 'BIO-0068', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'mg/L', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000014'::UUID, 'FIACHECK', 'PCT_SEPSIS', 'Procalcitonin (PCT Sepsis)', 'PCT_SEPSIS', 'PCT_SEPSIS', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000015'::UUID, 'FIACHECK', 'B_HCG', 'Quantitative Beta-hCG', 'END-0039', 'END-0039', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'mIU/mL', 'Not Applicable', FALSE),
('b01b0001-0000-4000-8000-000000000016'::UUID, 'FIACHECK', 'FERRITIN', 'Ferritin', 'BIO-0050', 'BIO-0050', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE)
) AS src(id, analyzer_code, channel_code, channel_name, test_code, param_code, measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported)
JOIN public.analyzers a ON a.code = src.analyzer_code
LEFT JOIN public.tests t ON t.code = src.test_code
LEFT JOIN public.parameters p ON p.test_id = t.id AND (p.code = src.param_code OR p.code = src.channel_code)
ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
    test_id = EXCLUDED.test_id,
    parameter_id = EXCLUDED.parameter_id,
    measurement_type = EXCLUDED.measurement_type,
    analytical_method = EXCLUDED.analytical_method,
    unit = EXCLUDED.unit;


COMMIT;
