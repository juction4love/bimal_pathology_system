import os
import csv
import io
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_OUT = os.path.join(ROOT, "approved-data", "Bimal_Pathology_Master_Test_Catalogue_1122.csv")
SQL_OUT = os.path.join(ROOT, "supabase", "migrations", "00098_master_catalogue_1122_rebuild_and_convergence.sql")

with open(CSV_OUT, "r", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

print(f"Loaded {len(rows)} records from master CSV")

PANELS_MAP = {
    "HEM-0001": [
        ("HEM-0002", "Hemoglobin (Hb)", 1, True, False),
        ("HEM-0004", "RBC Count", 2, True, False),
        ("HEM-0003", "Hematocrit (HCT/PCV)", 3, True, False),
        ("HEM-0007", "MCV", 4, True, True),
        ("HEM-0008", "MCH", 5, True, True),
        ("HEM-0009", "MCHC", 6, True, True),
        ("HEM-0010", "RDW-CV", 7, True, False),
        ("HEM-0011", "RDW-SD", 8, False, False),
        ("HEM-0005", "WBC Count / TLC", 9, True, False),
        ("HEM-0015", "Neutrophil %", 10, True, False),
        ("HEM-0016", "Lymphocyte %", 11, True, False),
        ("HEM-0017", "Monocyte %", 12, True, False),
        ("HEM-0018", "Eosinophil %", 13, True, False),
        ("HEM-0019", "Basophil %", 14, True, False),
        ("HEM-0020", "Absolute Neutrophil Count", 15, False, True),
        ("HEM-0021", "Absolute Lymphocyte Count", 16, False, True),
        ("HEM-0022", "Absolute Eosinophil Count", 17, False, True),
        ("HEM-0006", "Platelet Count", 18, True, False),
        ("HEM-0012", "MPV", 19, False, False),
        ("HEM-0013", "PDW", 20, False, False),
        ("HEM-0014", "PCT (Plateletcrit)", 21, False, False),
    ],
    "PRO-0001": [ # LFT
        ("BIO-0017", "Total Bilirubin", 1, True, False),
        ("BIO-0018", "Direct Bilirubin", 2, True, False),
        ("BIO-0019", "Indirect Bilirubin", 3, True, True),
        ("BIO-0020", "AST (SGOT)", 4, True, False),
        ("BIO-0021", "ALT (SGPT)", 5, True, False),
        ("BIO-0022", "Alkaline Phosphatase (ALP)", 6, True, False),
        ("BIO-0013", "Total Protein", 7, True, False),
        ("BIO-0014", "Albumin", 8, True, False),
        ("BIO-0015", "Globulin", 9, True, True),
        ("BIO-0016", "A/G Ratio", 10, True, True),
        ("BIO-0023", "GGT", 11, False, False),
    ],
    "PRO-0002": [ # RFT / KFT
        ("BIO-0008", "Urea", 1, True, False),
        ("BIO-0009", "Blood Urea Nitrogen (BUN)", 2, False, True),
        ("BIO-0010", "Creatinine", 3, True, False),
        ("BIO-0011", "eGFR", 4, False, True),
        ("BIO-0012", "Uric Acid", 5, True, False),
        ("BIO-0037", "Sodium", 6, True, False),
        ("BIO-0038", "Potassium", 7, True, False),
        ("BIO-0039", "Chloride", 8, True, False),
    ],
    "PRO-0003": [ # Lipid Profile
        ("BIO-0027", "Total Cholesterol", 1, True, False),
        ("BIO-0028", "Triglycerides", 2, True, False),
        ("BIO-0029", "HDL Cholesterol", 3, True, False),
        ("BIO-0031", "LDL Cholesterol, Calculated", 4, True, True),
        ("BIO-0032", "VLDL Cholesterol", 5, True, True),
        ("BIO-0033", "Non-HDL Cholesterol", 6, True, True),
    ],
    "PRO-0004": [ # Thyroid Profile
        ("END-0001", "TSH", 1, True, False),
        ("END-0002", "Free T4 (FT4)", 2, True, False),
        ("END-0003", "Free T3 (FT3)", 3, True, False),
    ],
    "PRO-0005": [ # Iron Profile
        ("BIO-0045", "Iron", 1, True, False),
        ("BIO-0046", "TIBC", 2, True, False),
        ("BIO-0047", "UIBC", 3, False, True),
        ("BIO-0049", "Transferrin Saturation", 4, True, True),
        ("BIO-0050", "Ferritin", 5, True, False),
    ],
    "PRO-0006": [ # Diabetes Profile
        ("BIO-0001", "Glucose, Fasting", 1, True, False),
        ("BIO-0003", "Glucose, Postprandial 2 hr", 2, True, False),
        ("BIO-0006", "HbA1c", 3, True, False),
    ],
    "PRO-0007": [ # Cardiac Marker Panel
        ("BIO-0063", "Troponin I, High Sensitivity", 1, True, False),
        ("BIO-0061", "CK-MB Mass", 2, True, False),
        ("BIO-0065", "Myoglobin", 3, False, False),
    ],
    "PRO-0008": [ # Electrolyte Panel
        ("BIO-0037", "Sodium", 1, True, False),
        ("BIO-0038", "Potassium", 2, True, False),
        ("BIO-0039", "Chloride", 3, True, False),
        ("BIO-0040", "Bicarbonate / Total CO2", 4, True, False),
    ],
    "PRO-0009": [ # Bone Mineral Profile
        ("BIO-0041", "Calcium, Total", 1, True, False),
        ("BIO-0043", "Phosphorus", 2, True, False),
        ("BIO-0022", "Alkaline Phosphatase (ALP)", 3, True, False),
        ("BIO-0053", "Vitamin D, 25-OH", 4, True, False),
        ("END-0011", "PTH, Intact", 5, True, False),
    ],
    "PRO-0014": [ # Coagulation Screen
        ("COA-0001", "Prothrombin Time (PT)", 1, True, False),
        ("COA-0002", "INR", 2, True, True),
        ("COA-0003", "Activated Partial Thromboplastin Time (APTT)", 3, True, False),
    ],
    "CLP-0001": [ # Urine Routine Examination (RE/ME)
        ("CLP-0002", "Urine Color", 1, True, False),
        ("CLP-0003", "Urine Appearance", 2, True, False),
        ("CLP-0004", "Urine Specific Gravity", 3, True, False),
        ("CLP-0005", "Urine pH", 4, True, False),
        ("CLP-0006", "Urine Protein, Dipstick", 5, True, False),
        ("CLP-0007", "Urine Glucose, Dipstick", 6, True, False),
        ("CLP-0008", "Urine Ketone", 7, True, False),
        ("CLP-0009", "Urine Blood/Hemoglobin", 8, True, False),
        ("CLP-0010", "Urine Bilirubin", 9, True, False),
        ("CLP-0011", "Urine Urobilinogen", 10, True, False),
        ("CLP-0012", "Urine Nitrite", 11, True, False),
        ("CLP-0013", "Urine Leukocyte Esterase", 12, True, False),
        ("CLP-0014", "Urine RBC Microscopy", 13, True, False),
        ("CLP-0015", "Urine WBC/Pus Cells", 14, True, False),
        ("CLP-0016", "Urine Epithelial Cells", 15, True, False),
        ("CLP-0017", "Urine Casts", 16, False, False),
        ("CLP-0018", "Urine Crystals", 17, False, False),
        ("CLP-0019", "Urine Bacteria", 18, False, False),
    ],
    "CLP-0021": [ # Stool Routine Examination
        ("CLP-0022", "Stool Color", 1, True, False),
        ("CLP-0023", "Stool Consistency", 2, True, False),
        ("CLP-0024", "Stool Mucus", 3, True, False),
        ("CLP-0025", "Stool Occult Blood", 4, True, False),
        ("CLP-0028", "Stool Reducing Substance", 5, False, False),
        ("CLP-0032", "Stool Ova & Parasite Examination", 6, True, False),
        ("CLP-0033", "Stool RBC", 7, True, False),
        ("CLP-0034", "Stool WBC/Pus Cells", 8, True, False),
    ],
    "CLP-0038": [ # Semen Analysis
        ("CLP-0039", "Semen Volume", 1, True, False),
        ("CLP-0040", "Semen pH", 2, True, False),
        ("CLP-0041", "Sperm Concentration", 3, True, False),
        ("CLP-0042", "Total Sperm Count", 4, True, True),
        ("CLP-0043", "Progressive Motility", 5, True, False),
        ("CLP-0044", "Non-progressive Motility", 6, True, False),
        ("CLP-0045", "Immotile Sperm", 7, True, False),
        ("CLP-0046", "Normal Morphology", 8, True, False),
        ("CLP-0047", "Sperm Vitality", 9, True, False),
        ("CLP-0048", "Round Cells", 10, False, False),
    ],
    "POC-0001": [ # ABG
        ("POC-0003", "pH, Blood Gas", 1, True, False),
        ("POC-0004", "pCO2, Blood Gas", 2, True, False),
        ("POC-0005", "pO2, Blood Gas", 3, True, False),
        ("POC-0006", "HCO3-, Blood Gas", 4, True, True),
        ("POC-0007", "Base Excess", 5, True, True),
        ("POC-0008", "Oxygen Saturation, Blood Gas", 6, True, False),
        ("POC-0009", "Lactate, Blood Gas", 7, False, False),
    ]
}

def escape_sql(val):
    if val is None:
        return "NULL"
    return "'" + str(val).replace("'", "''") + "'"

sql = []
sql.append("""-- ============================================================================
-- Migration 00098: Master Pathology Test Catalogue (1,122 Items) Rebuild & Convergence
-- Fully normalizes departments, tests, aliases, panels, reference ranges, and LIS workflow links.
-- ============================================================================

-- 0. Clean old development catalogue rows safely (development rebuild)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_freeze_test_delivery_configuration') THEN
        ALTER TABLE public.tests DISABLE TRIGGER trg_freeze_test_delivery_configuration;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ensure_catalogue_test_readiness_trigger') THEN
        ALTER TABLE public.tests DISABLE TRIGGER ensure_catalogue_test_readiness_trigger;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'catalogue_master_sources_immutable') THEN
        ALTER TABLE public.catalogue_master_sources DISABLE TRIGGER catalogue_master_sources_immutable;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'catalogue_master_rows_immutable') THEN
        ALTER TABLE public.catalogue_master_source_rows DISABLE TRIGGER catalogue_master_rows_immutable;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'catalogue_configuration_evidence_immutable') THEN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_configuration_evidence') THEN
            ALTER TABLE public.catalogue_configuration_evidence DISABLE TRIGGER catalogue_configuration_evidence_immutable;
        END IF;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'clinical_calculation_runs_immutable') THEN
        ALTER TABLE public.clinical_calculation_runs DISABLE TRIGGER clinical_calculation_runs_immutable;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'clinical_calculation_checks_immutable') THEN
        ALTER TABLE public.clinical_calculation_consistency_checks DISABLE TRIGGER clinical_calculation_checks_immutable;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'report_calculation_provenance_immutable') THEN
        ALTER TABLE public.report_calculation_provenance DISABLE TRIGGER report_calculation_provenance_immutable;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'clinical_calculation_formula_version_rewrite_guard') THEN
        ALTER TABLE public.clinical_calculation_formula_versions DISABLE TRIGGER clinical_calculation_formula_version_rewrite_guard;
    END IF;

    -- Clean calculation tables
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'report_calculation_provenance') THEN
        EXECUTE 'DELETE FROM public.report_calculation_provenance';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clinical_calculation_consistency_checks') THEN
        EXECUTE 'DELETE FROM public.clinical_calculation_consistency_checks';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clinical_calculation_runs') THEN
        EXECUTE 'DELETE FROM public.clinical_calculation_runs';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clinical_calculation_tolerance_versions') THEN
        EXECUTE 'DELETE FROM public.clinical_calculation_tolerance_versions';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clinical_calculation_formula_inputs') THEN
        EXECUTE 'DELETE FROM public.clinical_calculation_formula_inputs';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clinical_calculation_formula_versions') THEN
        EXECUTE 'DELETE FROM public.clinical_calculation_formula_versions';
    END IF;

    -- Clean authoring and template tables
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_test_template_drafts') THEN
        EXECUTE 'DELETE FROM public.catalogue_test_template_drafts';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_test_templates') THEN
        EXECUTE 'DELETE FROM public.catalogue_test_templates';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_test_database_entries') THEN
        EXECUTE 'DELETE FROM public.catalogue_test_database_entries';
    END IF;

    -- Clean bill panel and panel service references
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'bill_panel_components') THEN
        EXECUTE 'DELETE FROM public.bill_panel_components';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'bill_panel_selections') THEN
        EXECUTE 'DELETE FROM public.bill_panel_selections';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'bill_package_components') THEN
        EXECUTE 'DELETE FROM public.bill_package_components';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'bill_package_selections') THEN
        EXECUTE 'DELETE FROM public.bill_package_selections';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_rate_versions') THEN
        EXECUTE 'DELETE FROM public.catalogue_rate_versions';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_panel_identity_resolution') THEN
        EXECUTE 'DELETE FROM public.catalogue_panel_identity_resolution';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_panel_services') THEN
        EXECUTE 'DELETE FROM public.catalogue_panel_services';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_panel_ratelist_links') THEN
        EXECUTE 'DELETE FROM public.catalogue_panel_ratelist_links';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_panel_components') THEN
        EXECUTE 'DROP TABLE IF EXISTS public.catalogue_panel_components CASCADE';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_panels') THEN
        EXECUTE 'DROP TABLE IF EXISTS public.catalogue_panels CASCADE';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'health_package_components') THEN
        EXECUTE 'DELETE FROM public.health_package_components';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'health_packages') THEN
        EXECUTE 'DELETE FROM public.health_packages';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_profile_components') THEN
        EXECUTE 'DELETE FROM public.catalogue_profile_components';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_master_source_rows') THEN
        EXECUTE 'DELETE FROM public.catalogue_master_source_rows';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_master_sources') THEN
        EXECUTE 'DELETE FROM public.catalogue_master_sources';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_identity_conflicts') THEN
        EXECUTE 'DELETE FROM public.catalogue_identity_conflicts';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'test_rate_history') THEN
        EXECUTE 'DELETE FROM public.test_rate_history';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'test_price_history') THEN
        EXECUTE 'DELETE FROM public.test_price_history';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_test_readiness_approvals') THEN
        EXECUTE 'DELETE FROM public.catalogue_test_readiness_approvals';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_readiness_checklist') THEN
        EXECUTE 'DELETE FROM public.catalogue_readiness_checklist';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_result_structure_reconciliation') THEN
        EXECUTE 'DELETE FROM public.catalogue_result_structure_reconciliation';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_configuration_evidence') THEN
        EXECUTE 'DELETE FROM public.catalogue_configuration_evidence';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_service_readiness') THEN
        EXECUTE 'DELETE FROM public.catalogue_service_readiness';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sample_collection_requirements') THEN
        EXECUTE 'DELETE FROM public.sample_collection_requirements';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'outsource_sample_trackers') THEN
        EXECUTE 'DELETE FROM public.outsource_sample_trackers';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clinical_source_decisions') THEN
        EXECUTE 'UPDATE public.clinical_source_decisions SET materialized_range_id = NULL WHERE materialized_range_id IS NOT NULL';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'test_aliases') THEN
        EXECUTE 'DELETE FROM public.test_aliases';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'reference_ranges') THEN
        EXECUTE 'DELETE FROM public.reference_ranges';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'parameters') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'parameters' AND column_name = 'parent_parameter_id') THEN
            EXECUTE 'UPDATE public.parameters SET parent_parameter_id = NULL WHERE parent_parameter_id IS NOT NULL';
        END IF;
        EXECUTE 'DELETE FROM public.parameters';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tests') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tests' AND column_name = 'retired_duplicate_of') THEN
            EXECUTE 'UPDATE public.tests SET retired_duplicate_of = NULL, retirement_reason = NULL WHERE retired_duplicate_of IS NOT NULL OR retirement_reason IS NOT NULL';
        END IF;
        EXECUTE 'DELETE FROM public.tests';
    END IF;
END $$;

-- 1. Create canonical test_aliases table if not exists
CREATE TABLE IF NOT EXISTS public.test_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    alias_name VARCHAR(255) NOT NULL,
    alias_type VARCHAR(50) NOT NULL DEFAULT 'Synonym' CHECK (alias_type IN ('Synonym', 'Acronym', 'LegacyCode', 'AlternativeName', 'ShortName')),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(test_id, alias_name)
);

CREATE INDEX IF NOT EXISTS idx_test_aliases_name ON public.test_aliases(LOWER(alias_name));
CREATE INDEX IF NOT EXISTS idx_test_aliases_test_id ON public.test_aliases(test_id);

-- 2. Ensure test_components / catalogue_panel_components table exists with clean constraints
DROP TABLE IF EXISTS public.catalogue_panel_components CASCADE;
CREATE TABLE public.catalogue_panel_components (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    panel_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    panel_test_id UUID REFERENCES public.tests(id) ON DELETE CASCADE,
    component_test_id UUID REFERENCES public.tests(id) ON DELETE CASCADE,
    component_parameter_id UUID REFERENCES public.parameters(id) ON DELETE CASCADE,
    component_role TEXT NOT NULL DEFAULT 'Measured' CHECK (component_role IN ('Measured', 'Calculated', 'Qualitative', 'ComponentService', 'Narrative')),
    display_order INT NOT NULL DEFAULT 0,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_panel_no_self_ref CHECK (panel_id != component_test_id),
    UNIQUE(panel_id, component_test_id)
);

-- 3. Update tests table columns for normalized catalogue
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS subdepartment VARCHAR(100);
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS test_type VARCHAR(50) DEFAULT 'Single';
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS specimen_type VARCHAR(100);
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS container_type VARCHAR(100);
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS sample_type VARCHAR(100);
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS container VARCHAR(100);
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS method VARCHAR(100);
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS unit VARCHAR(50);
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS report_data_type VARCHAR(50) DEFAULT 'Numeric';
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS fasting_required BOOLEAN DEFAULT FALSE;
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS is_outsource BOOLEAN DEFAULT FALSE;
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS validation_status VARCHAR(50) DEFAULT 'REQUIRES_VALIDATION';
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS tat_description VARCHAR(100);
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS calculation_formula TEXT;
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS calculation_dependencies TEXT[];

-- Enable RLS
ALTER TABLE public.test_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_panel_components ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'test_aliases_read' AND tablename = 'test_aliases') THEN
        CREATE POLICY test_aliases_read ON public.test_aliases FOR SELECT TO authenticated USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'test_aliases_write' AND tablename = 'test_aliases') THEN
        CREATE POLICY test_aliases_write ON public.test_aliases FOR ALL TO authenticated USING (public.has_permission('can_manage_catalogue'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'panel_components_read' AND tablename = 'catalogue_panel_components') THEN
        CREATE POLICY panel_components_read ON public.catalogue_panel_components FOR SELECT TO authenticated USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'panel_components_write' AND tablename = 'catalogue_panel_components') THEN
        CREATE POLICY panel_components_write ON public.catalogue_panel_components FOR ALL TO authenticated USING (public.has_permission('can_manage_catalogue'));
    END IF;
END $$;
""")

# Build test insertion statements
sql.append("\n-- 4. Seed / Upsert Master Tests (1,122 Items)")
sql.append("DO $$")
sql.append("DECLARE")
sql.append("    v_test_id UUID;")
sql.append("    v_param_id UUID;")
sql.append("    v_panel_id UUID;")
sql.append("    v_comp_id UUID;")
sql.append("BEGIN")

canonical_aliases = {
    "BIO-0021": ["ALT", "SGPT", "Alanine Aminotransferase", "Serum Glutamic Pyruvic Transaminase"],
    "BIO-0020": ["AST", "SGOT", "Aspartate Aminotransferase", "Serum Glutamic Oxaloacetic Transaminase"],
    "BIO-0001": ["FBS", "Fasting Blood Sugar", "Fasting Blood Glucose", "Fasting Glucose"],
    "BIO-0003": ["PPBS", "Postprandial Blood Sugar", "PPBS 2hr", "Post Prandial Glucose"],
    "HEM-0001": ["CBC", "FBC", "Full Blood Count", "Complete Blood Picture"],
    "HEM-0002": ["Hb", "Hemoglobin", "Haemoglobin", "Hgb"],
}

for r in rows:
    code = r["Test Code"].strip()
    dept = r["Department"].strip()
    subdept = r["Subdepartment"].strip()
    name = r["Test Name"].strip()
    synonyms = r["Synonyms"].strip()
    test_type = r["Test Type"].strip() or "Single"
    specimen = r["Specimen"].strip() or "Blood"
    container = r["Container"].strip() or "Plain"
    method = r["Method / Platform"].strip()
    unit = r["Unit"].strip()
    tat = r["TAT"].strip() or "Routine"
    data_type = r["Report Data Type"].strip() or "Numeric"
    fasting = "TRUE" if r["Fasting Required"].strip().lower() in ("yes", "true") else "FALSE"
    outsource = "TRUE" if r["Outsource"].strip().lower() in ("yes", "true") else "FALSE"
    is_active = "TRUE" if r["Active"].strip().lower() in ("yes", "true") else "FALSE"
    val_status = "REQUIRES_VALIDATION"
    notes = r["Notes"].strip()

    sql.append(f"""
    INSERT INTO public.tests (
        code, name, short_name, department, subdepartment, category,
        test_type, specimen_type, container, container_type, sample_type,
        method, unit, tat_description, report_data_type,
        fasting_required, is_outsource, is_active, validation_status, notes,
        price_paisa, price_configured, allow_zero_price_billing, display_order
    ) VALUES (
        {escape_sql(code)}, {escape_sql(name)}, {escape_sql(code)}, {escape_sql(dept)}, {escape_sql(subdept)}, {escape_sql(subdept)},
        {escape_sql(test_type)}, {escape_sql(specimen)}, {escape_sql(container)}, {escape_sql(container)}, {escape_sql(specimen)},
        {escape_sql(method)}, {escape_sql(unit)}, {escape_sql(tat)}, {escape_sql(data_type)},
        {fasting}, {outsource}, {is_active}, {escape_sql(val_status)}, {escape_sql(notes)},
        0, FALSE, TRUE, 0
    ) RETURNING id INTO v_test_id;

    INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active)
    VALUES (v_test_id, {escape_sql(code)}, {escape_sql(name)}, {escape_sql(unit)}, 'Numeric', 1, TRUE, TRUE)
    RETURNING id INTO v_param_id;
    """)

    # Aliases
    alias_list = []
    if code in canonical_aliases:
        alias_list.extend(canonical_aliases[code])
    if synonyms:
        for syn in synonyms.split(","):
            s_clean = syn.strip().strip('"')
            if s_clean and s_clean not in alias_list:
                alias_list.append(s_clean)
    
    for alias in alias_list:
        sql.append(f"""
    INSERT INTO public.test_aliases (test_id, alias_name, alias_type)
    VALUES (v_test_id, {escape_sql(alias)}, 'Synonym')
    ON CONFLICT (test_id, alias_name) DO NOTHING;
        """)

# Build Panel Component hierarchy
sql.append("\n    -- ========================================================")
sql.append("    -- 5. Seed Composite Panel Component Hierarchies")
sql.append("    -- ========================================================")
for p_code, comps in PANELS_MAP.items():
    sql.append(f"\n    -- Panel {p_code}")
    sql.append(f"    SELECT id INTO v_panel_id FROM public.tests WHERE code = '{p_code}';")
    sql.append(f"    IF v_panel_id IS NOT NULL THEN")
    for c_code, c_name, order, req, calc in comps:
        role = "Calculated" if calc else "Measured"
        req_str = "TRUE" if req else "FALSE"
        sql.append(f"""
        SELECT id INTO v_comp_id FROM public.tests WHERE code = '{c_code}';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, {order}, {req_str}, '{role}')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET
                display_order = {order},
                is_required = {req_str},
                component_role = '{role}';
        END IF;
        """)
    sql.append("    END IF;")

sql.append("END $$;")

sql.append("""
-- 6. Re-enable triggers
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_freeze_test_delivery_configuration') THEN
        ALTER TABLE public.tests ENABLE TRIGGER trg_freeze_test_delivery_configuration;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ensure_catalogue_test_readiness_trigger') THEN
        ALTER TABLE public.tests ENABLE TRIGGER ensure_catalogue_test_readiness_trigger;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'catalogue_master_sources_immutable') THEN
        ALTER TABLE public.catalogue_master_sources ENABLE TRIGGER catalogue_master_sources_immutable;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'catalogue_master_rows_immutable') THEN
        ALTER TABLE public.catalogue_master_source_rows ENABLE TRIGGER catalogue_master_rows_immutable;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'catalogue_configuration_evidence_immutable') THEN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'catalogue_configuration_evidence') THEN
            ALTER TABLE public.catalogue_configuration_evidence ENABLE TRIGGER catalogue_configuration_evidence_immutable;
        END IF;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'clinical_calculation_runs_immutable') THEN
        ALTER TABLE public.clinical_calculation_runs ENABLE TRIGGER clinical_calculation_runs_immutable;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'clinical_calculation_checks_immutable') THEN
        ALTER TABLE public.clinical_calculation_consistency_checks ENABLE TRIGGER clinical_calculation_checks_immutable;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'report_calculation_provenance_immutable') THEN
        ALTER TABLE public.report_calculation_provenance ENABLE TRIGGER report_calculation_provenance_immutable;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'clinical_calculation_formula_version_rewrite_guard') THEN
        ALTER TABLE public.clinical_calculation_formula_versions ENABLE TRIGGER clinical_calculation_formula_version_rewrite_guard;
    END IF;
END $$;
""")

with open(SQL_OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(sql))

print(f"Complete migration SQL written to {SQL_OUT}")
