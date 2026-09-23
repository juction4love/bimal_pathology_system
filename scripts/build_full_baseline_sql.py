"""
Full Clean Baseline Migration Builder
Assembles the authoritative single migration:
supabase/migrations/00001_bimal_pathology_clean_baseline.sql
"""

import os
import re
import glob

LEGACY_DIR = 'supabase/migrations_legacy_archive'
CURRENT_BASELINE = 'supabase/migrations/00001_bimal_pathology_clean_baseline.sql'

# 1. Read existing baseline to keep clean master data and base schemas
current_sql = open(CURRENT_BASELINE, 'r', encoding='utf-8').read()

# Extract master data sections from current baseline
# Master data starts from -- 6. SEED DATA / MASTER CATALOGUE or similar
seed_start = current_sql.find('-- ============================================================================')
seed_idx = current_sql.find('-- 6. SEED DATA', seed_start)
if seed_idx == -1:
    seed_idx = current_sql.find('-- 7. COMPLETE MASTER TEST CATALOGUE')
if seed_idx == -1:
    seed_idx = current_sql.find('INSERT INTO public.test_categories')

# Let's find where master seed data begins
master_seed_sql = current_sql[seed_idx:] if seed_idx != -1 else ""

# Extract functions from legacy migrations
legacy_files = sorted(glob.glob(os.path.join(LEGACY_DIR, '*.sql')))
functions_map = {}
for f in legacy_files:
    content = open(f, 'r', encoding='utf-8').read()
    # Match CREATE OR REPLACE FUNCTION public.func_name(...)
    matches = re.finditer(
        r'(CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-zA-Z0-9_]+)\s*\([^)]*?\)\s*RETURNS[\s\S]*?(?:AS\s*\$\$[\s\S]*?\$\$|\$func\$[\s\S]*?\$func\$|\$body\$[\s\S]*?\$body\$)[\s\S]*?;)',
        content,
        re.IGNORECASE
    )
    for m in matches:
        func_sql = m.group(1)
        func_name = m.group(2)
        functions_map[func_name] = func_sql

print(f"Extracted {len(functions_map)} unique functions from legacy archive.")

# Tables to add to baseline if not present
extra_tables_sql = """
-- Additional Operational & Workflow Tables

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
    interpretation VARCHAR(20) NOT NULL CHECK (interpretation IN ('Susceptible', 'Intermediate', 'Resistant', 'Susceptible-Dose-Dependent', 'Non-Susceptible', 'Not-Applicable', 'Pending')),
    breakpoint_rule_id UUID REFERENCES public.ast_breakpoint_rules(id) ON DELETE SET NULL,
    method VARCHAR(50) DEFAULT 'Kirby-Bauer Disk Diffusion',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ast_observation_audit (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    observation_id UUID NOT NULL REFERENCES public.ast_observations(id) ON DELETE CASCADE,
    previous_interpretation VARCHAR(20),
    new_interpretation VARCHAR(20),
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
    status VARCHAR(50) NOT NULL DEFAULT 'Draft' CHECK (status IN ('Draft', 'Submitted', 'Finalized', 'Locked')),
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
"""

print("Writing full baseline with all tables, functions, triggers, and master seed data...")
"""
Let's assemble the whole file cleanly.
"""
