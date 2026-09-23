// scripts/generate_baseline_migration_sql.mjs
// Synthesizes the single clean baseline migration: 00001_bimal_pathology_clean_baseline.sql

import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const masterPayload = JSON.parse(readFileSync(path.resolve('scripts/output/extracted_master_payload.json'), 'utf8'));

function sqlStr(val) {
  if (val === null || val === undefined) return 'NULL';
  return `'${String(val).replace(/'/g, "''")}'`;
}

function sqlJson(val) {
  if (val === null || val === undefined) return 'NULL';
  return `'${JSON.stringify(val).replace(/'/g, "''")}'::jsonb`;
}

function sqlArray(arr) {
  if (!arr || !Array.isArray(arr) || arr.length === 0) return 'NULL';
  return `ARRAY[${arr.map(sqlStr).join(', ')}]`;
}

console.log('Generating 00001_bimal_pathology_clean_baseline.sql...');

let sql = `-- ============================================================================
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
INSERT INTO public.analyzers (code, name, manufacturer, model, laboratory_location, lifecycle_status, row_version) VALUES
('COUNCELL_23_EXCEL', 'CounCell 23 Excel', 'Coral Clinical Systems / Tulip Diagnostics', 'CounCell 23 Excel', 'Hematology Laboratory', 'Active', 1),
('CORALAB_ACE', 'CORALAB ACE', 'Coral Clinical Systems / Tulip Diagnostics', 'CORALAB ACE', 'Clinical Biochemistry Laboratory', 'Active', 1),
('FIACHECK', 'FIAcheck', 'Goldsite Diagnostics / FIAcheck', 'FIAcheck-100', 'Immunology & Hormone Laboratory', 'Active', 1)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name, manufacturer = EXCLUDED.manufacturer, model = EXCLUDED.model,
    laboratory_location = EXCLUDED.laboratory_location, lifecycle_status = 'Active';

-- Test Categories
`;

// Insert Test Categories
sql += `INSERT INTO public.test_categories (id, code, name, description, lifecycle_status, display_order) VALUES\n`;
const catLines = (masterPayload.test_categories || []).map(tc => {
  return `(${sqlStr(tc.id)}, ${sqlStr(tc.code)}, ${sqlStr(tc.name)}, ${sqlStr(tc.description)}, ${sqlStr(tc.lifecycle_status || 'Active')}::public.catalogue_lifecycle_enum, ${tc.display_order || 0})`;
});
sql += catLines.join(',\n') + `\nON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, code = EXCLUDED.code, lifecycle_status = EXCLUDED.lifecycle_status;\n\n`;

// Insert 1,139 Tests
sql += `-- ============================================================================
-- 7. COMPLETE MASTER TEST CATALOGUE (1,139 TESTS)
-- ============================================================================
INSERT INTO public.tests (
    id, code, name, short_name, department, category, category_id,
    reporting_type, outsource_lab_name, price_paisa, sample_type, container,
    method, tat_hours, interpretation_template, is_active, display_order,
    test_type, workflow_type, reporting_model, clinical_reporting_enabled,
    billing_enabled, price_configured, pricing_policy, lifecycle_status
) VALUES\n`;

const testLines = (masterPayload.tests || []).map(t => {
  return `(${sqlStr(t.id)}, ${sqlStr(t.code)}, ${sqlStr(t.name)}, ${sqlStr(t.short_name)}, ${sqlStr(t.department)}, ${sqlStr(t.category)}, ${sqlStr(t.category_id)}, ${sqlStr(t.reporting_type || 'InHouse')}::public.reporting_type_enum, ${sqlStr(t.outsource_lab_name)}, ${t.price_paisa || 0}, ${sqlStr(t.sample_type || 'Serum')}, ${sqlStr(t.container || 'Clot Activator (Yellow/Red)')}, ${sqlStr(t.method)}, ${t.tat_hours || 24}, ${sqlStr(t.interpretation_template)}, ${t.is_active ? 'TRUE' : 'FALSE'}, ${t.display_order || 0}, ${sqlStr(t.test_type || 'Individual')}, ${sqlStr(t.workflow_type || 'Standard')}, ${sqlStr(t.reporting_model || 'NUMERIC_SINGLE_ANALYTE')}, ${t.clinical_reporting_enabled !== false ? 'TRUE' : 'FALSE'}, ${t.billing_enabled !== false ? 'TRUE' : 'FALSE'}, ${t.price_configured ? 'TRUE' : 'FALSE'}, ${sqlStr(t.pricing_policy || 'Fixed')}, ${sqlStr(t.lifecycle_status || 'Active')})`;
});
sql += testLines.join(',\n') + `\nON CONFLICT (id) DO UPDATE SET
    code = EXCLUDED.code, name = EXCLUDED.name, short_name = EXCLUDED.short_name,
    department = EXCLUDED.department, category = EXCLUDED.category, category_id = EXCLUDED.category_id,
    reporting_type = EXCLUDED.reporting_type, price_paisa = EXCLUDED.price_paisa,
    sample_type = EXCLUDED.sample_type, container = EXCLUDED.container, method = EXCLUDED.method,
    tat_hours = EXCLUDED.tat_hours, is_active = EXCLUDED.is_active, display_order = EXCLUDED.display_order,
    test_type = EXCLUDED.test_type, workflow_type = EXCLUDED.workflow_type,
    reporting_model = EXCLUDED.reporting_model, clinical_reporting_enabled = EXCLUDED.clinical_reporting_enabled,
    billing_enabled = EXCLUDED.billing_enabled, price_configured = EXCLUDED.price_configured,
    pricing_policy = EXCLUDED.pricing_policy, lifecycle_status = EXCLUDED.lifecycle_status;\n\n`;

// Insert 1,184 Parameters
sql += `-- ============================================================================
-- 8. REPORTABLE CLINICAL PARAMETERS (1,184 PARAMETERS)
-- ============================================================================
INSERT INTO public.parameters (
    id, test_id, code, name, value_type, unit, options,
    formula, formula_dependencies, calculation_identifier, display_order,
    is_mandatory, is_active, lifecycle_status, clinical_configuration_status,
    interpretation_config
) VALUES\n`;

const paramLines = (masterPayload.parameters || []).map(p => {
  return `(${sqlStr(p.id)}, ${sqlStr(p.test_id)}, ${sqlStr(p.code)}, ${sqlStr(p.name)}, ${sqlStr(p.value_type || 'Numeric')}::public.parameter_value_type_enum, ${sqlStr(p.unit)}, ${sqlJson(p.options)}, ${sqlStr(p.formula)}, ${sqlArray(p.formula_dependencies)}, ${sqlStr(p.calculation_identifier)}, ${p.display_order || 0}, ${p.is_mandatory !== false ? 'TRUE' : 'FALSE'}, ${p.is_active !== false ? 'TRUE' : 'FALSE'}, ${sqlStr(p.lifecycle_status || 'Active')}, ${sqlStr(p.clinical_configuration_status || 'Configured')}, ${sqlJson(p.interpretation_config)})`;
});
sql += paramLines.join(',\n') + `\nON CONFLICT (test_id, code) DO UPDATE SET
    name = EXCLUDED.name, value_type = EXCLUDED.value_type, unit = EXCLUDED.unit,
    options = EXCLUDED.options, formula = EXCLUDED.formula,
    formula_dependencies = EXCLUDED.formula_dependencies,
    calculation_identifier = EXCLUDED.calculation_identifier,
    display_order = EXCLUDED.display_order, is_mandatory = EXCLUDED.is_mandatory,
    is_active = EXCLUDED.is_active, lifecycle_status = EXCLUDED.lifecycle_status,
    clinical_configuration_status = EXCLUDED.clinical_configuration_status,
    interpretation_config = EXCLUDED.interpretation_config;\n\n`;

// Insert 187 Reference Ranges
sql += `-- ============================================================================
-- 9. BIOLOGICAL REFERENCE RANGES (187 RULES)
-- ============================================================================
INSERT INTO public.reference_ranges (
    id, parameter_id, gender, age_min_days, age_max_days,
    normal_min, normal_max, critical_low, critical_high, normal_text, unit
) VALUES\n`;

const refLines = (masterPayload.reference_ranges || []).map(rr => {
  return `(${sqlStr(rr.id)}, ${sqlStr(rr.parameter_id)}, ${sqlStr(rr.gender || 'All')}, ${rr.age_min_days ?? 0}, ${rr.age_max_days ?? 43800}, ${rr.normal_min ?? 'NULL'}, ${rr.normal_max ?? 'NULL'}, ${rr.critical_low ?? 'NULL'}, ${rr.critical_high ?? 'NULL'}, ${sqlStr(rr.normal_text)}, ${sqlStr(rr.unit)})`;
});
sql += refLines.join(',\n') + `\nON CONFLICT (id) DO UPDATE SET
    parameter_id = EXCLUDED.parameter_id, gender = EXCLUDED.gender,
    age_min_days = EXCLUDED.age_min_days, age_max_days = EXCLUDED.age_max_days,
    normal_min = EXCLUDED.normal_min, normal_max = EXCLUDED.normal_max,
    critical_low = EXCLUDED.critical_low, critical_high = EXCLUDED.critical_high,
    normal_text = EXCLUDED.normal_text, unit = EXCLUDED.unit;\n\n`;

// Insert Profile / Panel Components
sql += `-- ============================================================================
-- 10. PROFILE / PANEL COMPONENT RELATIONSHIPS
-- ============================================================================
INSERT INTO public.catalogue_panel_components (
    id, panel_id, panel_test_id, component_test_id, component_parameter_id,
    display_order, is_required, component_role
) VALUES\n`;

const compLines = (masterPayload.catalogue_panel_components || []).map(c => {
  return `(${sqlStr(c.id)}, ${sqlStr(c.panel_test_id)}, ${sqlStr(c.panel_test_id)}, ${sqlStr(c.component_test_id)}, ${sqlStr(c.component_parameter_id)}, ${c.display_order || 0}, ${c.is_required !== false ? 'TRUE' : 'FALSE'}, ${sqlStr(c.component_role || 'Primary')})`;
});
sql += compLines.join(',\n') + `\nON CONFLICT (id) DO UPDATE SET
    panel_id = EXCLUDED.panel_id, panel_test_id = EXCLUDED.panel_test_id,
    component_test_id = EXCLUDED.component_test_id, component_parameter_id = EXCLUDED.component_parameter_id,
    display_order = EXCLUDED.display_order, is_required = EXCLUDED.is_required,
    component_role = EXCLUDED.component_role;\n\n`;

// Insert Analyzer Mappings
sql += `-- ============================================================================
-- 11. ANALYZER CHANNEL MAPPINGS
-- ============================================================================
INSERT INTO public.analyzer_parameter_mappings (
    id, analyzer_id, channel_code, channel_name, test_id, parameter_id,
    measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
)
SELECT
    src.id, a.id, src.channel_code, src.channel_name, t.id, p.id,
    src.measurement_type, src.analytical_method, src.unit, src.differential_type,
    src.is_automated_5part_supported
FROM (
    VALUES\n`;

const mapLines = (masterPayload.analyzer_parameter_mappings || []).map(m => {
  return `(${sqlStr(m.id)}::UUID, ${sqlStr(m.analyzer_code)}, ${sqlStr(m.channel_code)}, ${sqlStr(m.channel_name)}, ${sqlStr(m.test_code)}, ${sqlStr(m.parameter_code)}, ${sqlStr(m.measurement_type)}, ${sqlStr(m.analytical_method)}, ${sqlStr(m.unit)}, ${sqlStr(m.differential_type)}, ${m.is_automated_5part_supported ? 'TRUE' : 'FALSE'})`;
});
sql += mapLines.join(',\n') + `\n) AS src(id, analyzer_code, channel_code, channel_name, test_code, parameter_code, measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported)
JOIN public.analyzers a ON a.code = src.analyzer_code
LEFT JOIN public.tests t ON t.code = src.test_code
LEFT JOIN public.parameters p ON p.test_id = t.id AND p.code = src.parameter_code
ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
    channel_name = EXCLUDED.channel_name, test_id = EXCLUDED.test_id,
    parameter_id = EXCLUDED.parameter_id, measurement_type = EXCLUDED.measurement_type,
    analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit,
    differential_type = EXCLUDED.differential_type,
    is_automated_5part_supported = EXCLUDED.is_automated_5part_supported;\n\n`;

// Insert Rate Versions
sql += `-- ============================================================================
-- 12. ACTIVE MASTER RATE VERSIONS
-- ============================================================================
INSERT INTO public.catalogue_rate_versions (
    id, entity_type, test_id, version_number, price_paisa, effective_from, status
)
SELECT
    src.id, src.entity_type::public.catalogue_billable_entity_enum, t.id,
    src.version_number, src.price_paisa, src.effective_from::TIMESTAMPTZ, src.status
FROM (
    VALUES\n`;

const rateLines = (masterPayload.catalogue_rate_versions || []).map(r => {
  return `(${sqlStr(r.id)}::UUID, ${sqlStr(r.entity_type)}, ${sqlStr(r.test_code)}, ${r.version_number || 1}, ${r.price_paisa}, ${sqlStr(r.effective_from || 'NOW()')}, ${sqlStr(r.status || 'Active')})`;
});
sql += rateLines.join(',\n') + `\n) AS src(id, entity_type, test_code, version_number, price_paisa, effective_from, status)
JOIN public.tests t ON t.code = src.test_code
ON CONFLICT (id) DO UPDATE SET
    price_paisa = EXCLUDED.price_paisa, status = EXCLUDED.status;\n\n`;

sql += `COMMIT;\n`;

writeFileSync(path.resolve('supabase/migrations/00001_bimal_pathology_clean_baseline.sql'), sql, 'utf8');
console.log('Successfully written supabase/migrations/00001_bimal_pathology_clean_baseline.sql');
