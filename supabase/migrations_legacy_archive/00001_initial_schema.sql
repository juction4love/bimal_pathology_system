-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- PostgreSQL Initial Schema (Phase 0)
-- All financial amounts stored strictly as integer PAISA (1 NPR = 100 Paisa)
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- ENUM TYPES
-- ============================================================================

CREATE TYPE reporting_type_enum AS ENUM (
    'InHouse',
    'OutsourceWithBimalReport',
    'NoReporting'
);

CREATE TYPE sample_status_enum AS ENUM (
    'Pending',
    'Collected',
    'Received',
    'Rejected',
    'Recollected',
    'Processing',
    'Completed'
);

CREATE TYPE result_status_enum AS ENUM (
    'Draft',
    'SubmittedForVerification',
    'Verified',
    'SignedOff',
    'ReturnedForCorrection'
);

CREATE TYPE result_flag_enum AS ENUM (
    'Normal',
    'Low',
    'High',
    'CriticalLow',
    'CriticalHigh',
    'Abnormal',
    'NoRange'
);

CREATE TYPE payment_mode_enum AS ENUM (
    'Cash',
    'Fonepay',
    'eSewa',
    'Khalti',
    'Card',
    'Bank',
    'Credit',
    'Other'
);

CREATE TYPE payment_status_enum AS ENUM (
    'Paid',
    'Partial',
    'Due'
);

CREATE TYPE professional_type_enum AS ENUM (
    'Pathologist',
    'Lab Technologist',
    'Lab Technician',
    'Lab Assistant',
    'Receptionist',
    'Admin'
);

CREATE TYPE parameter_value_type_enum AS ENUM (
    'Numeric',
    'Text',
    'Select',
    'Boolean',
    'Heading',
    'Calculated'
);

-- ============================================================================
-- 1. AUTHENTICATION & ACCESS CONTROL
-- ============================================================================

CREATE TABLE user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL UNIQUE,
    full_name VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_super_admin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_system BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE role_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_key VARCHAR(100) NOT NULL,
    UNIQUE(role_id, permission_key)
);

CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE user_direct_permissions (
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    permission_key VARCHAR(100) NOT NULL,
    is_granted BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (user_id, permission_key)
);

-- ============================================================================
-- 2. CLINICIANS & REPORTING PERSONNEL
-- ============================================================================

CREATE TABLE referring_doctors (
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

CREATE TABLE reporting_personnel (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
    full_name VARCHAR(255) NOT NULL,
    professional_type professional_type_enum NOT NULL,
    qualification VARCHAR(255) NOT NULL,
    registration_council VARCHAR(255) NOT NULL, -- e.g. "Nepal Medical Council (NMC)", "NHPC"
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

-- ============================================================================
-- 3. PATIENT REGISTRY (PATIENT RULE: Created during Billing Only)
-- ============================================================================

CREATE TABLE patients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    uhid VARCHAR(50) NOT NULL UNIQUE, -- e.g. BP-2026-00001
    mobile VARCHAR(20) NOT NULL,       -- Mandatory lookup key
    title VARCHAR(20),                -- Mr., Mrs., Ms., Dr., Baby
    full_name VARCHAR(255) NOT NULL,
    gender VARCHAR(20) NOT NULL CHECK (gender IN ('Male', 'Female', 'Other')),
    dob DATE,
    age_years INT,
    age_months INT,
    age_days INT,
    address TEXT NOT NULL,
    email VARCHAR(255),
    identification_no VARCHAR(100),   -- Citizenship / Passport
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_patients_mobile ON patients(mobile);
CREATE INDEX idx_patients_uhid ON patients(uhid);
CREATE INDEX idx_patients_full_name ON patients(full_name);

-- ============================================================================
-- 4. FINANCIAL BILLING & ATOMIC TRANSACTIONS (PAISA BIGINT)
-- ============================================================================

CREATE TABLE bills (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_number VARCHAR(50) NOT NULL UNIQUE, -- e.g. INV-2026-00001
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE RESTRICT,
    patient_uhid_snapshot VARCHAR(50) NOT NULL,
    patient_name_snapshot VARCHAR(255) NOT NULL,
    patient_mobile_snapshot VARCHAR(20) NOT NULL,
    patient_age_gender_snapshot VARCHAR(50) NOT NULL,
    referring_doctor_id UUID REFERENCES referring_doctors(id) ON DELETE SET NULL,
    referring_doctor_name_snapshot VARCHAR(255),
    
    -- Financial integer paisa
    gross_amount_paisa BIGINT NOT NULL CHECK (gross_amount_paisa >= 0),
    discount_amount_paisa BIGINT NOT NULL DEFAULT 0 CHECK (discount_amount_paisa >= 0),
    discount_reason VARCHAR(255),
    net_amount_paisa BIGINT NOT NULL CHECK (net_amount_paisa >= 0),
    paid_amount_paisa BIGINT NOT NULL DEFAULT 0 CHECK (paid_amount_paisa >= 0),
    due_amount_paisa BIGINT NOT NULL DEFAULT 0 CHECK (due_amount_paisa >= 0),
    
    payment_status payment_status_enum NOT NULL DEFAULT 'Due',
    remarks TEXT,
    created_by UUID REFERENCES user_profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT chk_bill_math CHECK (net_amount_paisa = gross_amount_paisa - discount_amount_paisa),
    CONSTRAINT chk_bill_due CHECK (due_amount_paisa = net_amount_paisa - paid_amount_paisa)
);

CREATE TABLE bill_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    test_id UUID NOT NULL,
    test_code_snapshot VARCHAR(50) NOT NULL,
    test_name_snapshot VARCHAR(255) NOT NULL,
    reporting_type reporting_type_enum NOT NULL,
    outsource_lab_name VARCHAR(255),
    unit_price_paisa BIGINT NOT NULL CHECK (unit_price_paisa >= 0),
    discount_paisa BIGINT NOT NULL DEFAULT 0 CHECK (discount_paisa >= 0),
    net_price_paisa BIGINT NOT NULL CHECK (net_price_paisa >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE payment_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES bills(id) ON DELETE RESTRICT,
    receipt_number VARCHAR(50) NOT NULL UNIQUE,
    amount_paisa BIGINT NOT NULL CHECK (amount_paisa > 0),
    payment_mode payment_mode_enum NOT NULL,
    transaction_reference VARCHAR(100),
    remarks TEXT,
    received_by UUID REFERENCES user_profiles(id),
    received_by_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 5. TEST CATALOGUE, PARAMETERS & REFERENCE RANGES
-- ============================================================================

CREATE TABLE tests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    short_name VARCHAR(100),
    department VARCHAR(100) NOT NULL,
    category VARCHAR(100) NOT NULL,
    reporting_type reporting_type_enum NOT NULL DEFAULT 'InHouse',
    outsource_lab_name VARCHAR(255),
    price_paisa BIGINT NOT NULL CHECK (price_paisa >= 0),
    sample_type VARCHAR(100) NOT NULL,
    container VARCHAR(100) NOT NULL,
    method VARCHAR(100),
    tat_hours INT,
    interpretation_template TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE parameters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    test_id UUID NOT NULL REFERENCES tests(id) ON DELETE CASCADE,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    value_type parameter_value_type_enum NOT NULL DEFAULT 'Numeric',
    unit VARCHAR(50),
    options JSONB,                -- For Select type
    formula TEXT,                 -- For Calculated type e.g. "TOTAL_PROTEIN - ALBUMIN"
    formula_dependencies TEXT[],  -- Array of dependency parameter codes
    display_order INT NOT NULL DEFAULT 0,
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(test_id, code)
);

CREATE TABLE reference_ranges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parameter_id UUID NOT NULL REFERENCES parameters(id) ON DELETE CASCADE,
    gender VARCHAR(20) NOT NULL DEFAULT 'All' CHECK (gender IN ('All', 'Male', 'Female')),
    age_min_days INT NOT NULL DEFAULT 0,
    age_max_days INT NOT NULL DEFAULT 43800, -- 120 years
    normal_min NUMERIC(10, 3),
    normal_max NUMERIC(10, 3),
    critical_low NUMERIC(10, 3),
    critical_high NUMERIC(10, 3),
    normal_text TEXT,             -- For qualitative e.g. "Non-Reactive", "Negative"
    unit TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 6. CLINICAL ORDERS, SPECIMENS & APPEND-ONLY LIFECYCLE
-- ============================================================================

CREATE TABLE clinical_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES bills(id) ON DELETE RESTRICT,
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE RESTRICT,
    order_number VARCHAR(50) NOT NULL UNIQUE, -- Lab No. e.g. LAB-2026-00001
    order_date_ad DATE NOT NULL DEFAULT CURRENT_DATE,
    order_date_bs VARCHAR(50) NOT NULL,       -- Single BS registered date snapshot
    status VARCHAR(50) NOT NULL DEFAULT 'Registered' CHECK (status IN ('Registered', 'InLab', 'PartiallyCompleted', 'Completed', 'SignedOff')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE samples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    barcode VARCHAR(50) NOT NULL UNIQUE, -- e.g. SMP-2026-00001
    order_id UUID NOT NULL REFERENCES clinical_orders(id) ON DELETE RESTRICT,
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE RESTRICT,
    specimen_type VARCHAR(100) NOT NULL,
    container_type VARCHAR(100) NOT NULL,
    status sample_status_enum NOT NULL DEFAULT 'Pending',
    
    collected_at TIMESTAMPTZ,
    collected_by UUID REFERENCES user_profiles(id),
    collected_by_name VARCHAR(255),
    
    received_at TIMESTAMPTZ,
    received_by UUID REFERENCES user_profiles(id),
    received_by_name VARCHAR(255),
    
    rejected_at TIMESTAMPTZ,
    rejected_by UUID REFERENCES user_profiles(id),
    rejected_by_name VARCHAR(255),
    rejection_reason TEXT,
    
    recollected_from_sample_id UUID REFERENCES samples(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sample_lifecycle_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sample_id UUID NOT NULL REFERENCES samples(id) ON DELETE CASCADE,
    from_status sample_status_enum NOT NULL,
    to_status sample_status_enum NOT NULL,
    reason TEXT,
    performed_by UUID REFERENCES user_profiles(id),
    performed_by_name VARCHAR(255) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE clinical_order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES clinical_orders(id) ON DELETE CASCADE,
    bill_item_id UUID NOT NULL REFERENCES bill_items(id) ON DELETE RESTRICT,
    test_id UUID NOT NULL REFERENCES tests(id) ON DELETE RESTRICT,
    test_name VARCHAR(255) NOT NULL,
    department VARCHAR(100) NOT NULL,
    reporting_type reporting_type_enum NOT NULL CHECK (reporting_type IN ('InHouse', 'OutsourceWithBimalReport')),
    outsource_lab_name VARCHAR(255),
    specimen_type VARCHAR(100) NOT NULL,
    container_type VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending', 'SampleCollected', 'SampleReceived', 'ResultDrafted', 'Verified', 'SignedOff')),
    sample_id UUID REFERENCES samples(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 7. RESULT ENGINE, VERIFICATION & IMMUTABLE SIGNED REPORTS
-- ============================================================================

CREATE TABLE test_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_item_id UUID NOT NULL REFERENCES clinical_order_items(id) ON DELETE CASCADE,
    parameter_id UUID NOT NULL REFERENCES parameters(id) ON DELETE RESTRICT,
    parameter_name VARCHAR(255) NOT NULL,
    unit VARCHAR(50),
    value_type parameter_value_type_enum NOT NULL,
    
    numeric_value NUMERIC(14, 4),
    text_value TEXT,
    display_value TEXT NOT NULL,
    
    flag result_flag_enum NOT NULL DEFAULT 'Normal',
    is_critical BOOLEAN NOT NULL DEFAULT FALSE,
    critical_acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
    critical_acknowledged_by UUID REFERENCES user_profiles(id),
    critical_acknowledged_at TIMESTAMPTZ,
    
    normal_range_text TEXT,
    normal_min NUMERIC(10, 3),
    normal_max NUMERIC(10, 3),
    critical_low NUMERIC(10, 3),
    critical_high NUMERIC(10, 3),
    
    status result_status_enum NOT NULL DEFAULT 'Draft',
    entered_by UUID REFERENCES user_profiles(id),
    entered_by_name VARCHAR(255),
    entered_at TIMESTAMPTZ,
    
    verified_by UUID REFERENCES user_profiles(id),
    verified_by_name VARCHAR(255),
    verified_at TIMESTAMPTZ,
    
    signed_off_by UUID REFERENCES user_profiles(id),
    signed_off_name VARCHAR(255),
    signed_off_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE diagnostic_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES clinical_orders(id) ON DELETE RESTRICT,
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE RESTRICT,
    report_number VARCHAR(50) NOT NULL UNIQUE, -- e.g. REP-2026-00001
    version INT NOT NULL DEFAULT 1,
    is_amendment BOOLEAN NOT NULL DEFAULT FALSE,
    amendment_reason TEXT,
    amended_from_report_id UUID REFERENCES diagnostic_reports(id) ON DELETE SET NULL,
    
    status VARCHAR(50) NOT NULL DEFAULT 'SignedOff' CHECK (status IN ('Draft', 'SignedOff', 'Amended')),
    integrity_hash VARCHAR(128) NOT NULL, -- SHA-256 hash of signed clinical snapshot
    
    performed_by_personnel_id UUID REFERENCES reporting_personnel(id),
    performed_by_personnel_name VARCHAR(255) NOT NULL,
    
    verified_by_personnel_id UUID REFERENCES reporting_personnel(id),
    verified_by_personnel_name VARCHAR(255) NOT NULL,
    
    signed_by_personnel_id UUID REFERENCES reporting_personnel(id),
    signed_by_personnel_name VARCHAR(255) NOT NULL,
    signed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    pdf_storage_path TEXT,
    clinical_snapshot_json JSONB NOT NULL, -- Immutable frozen clinical record for PDF
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 8. APPEND-ONLY AUDIT TRAIL
-- ============================================================================

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
    user_name VARCHAR(255),
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id VARCHAR(100) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    ip_address VARCHAR(50),
    user_agent TEXT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
