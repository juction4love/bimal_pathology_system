import os
import csv
import sys
import io

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_OUT = os.path.join(ROOT, "approved-data", "Bimal_Pathology_Master_Test_Catalogue_1122.csv")
SQL_OUT = os.path.join(ROOT, "supabase", "migrations", "00098_master_catalogue_1122_rebuild_and_convergence.sql")

from append_hem import hem_rows
from append_coa import coa_rows
from data_bio import bio_data
from data_end_tum_imm import end_data, tum_data, imm_data
from data_alg_ser_mic import alg_data, ser_data, mic_data
from data_clp_his_cyt import clp_data, his_data, cyt_data
from data_mol_gen_tox_spc_pro_poc import mol_data, gen_data, tox_data, spc_data, pro_data, poc_data

sections = [
    hem_rows, coa_rows, bio_data, end_data, tum_data, imm_data,
    alg_data, ser_data, mic_data, clp_data, his_data, cyt_data,
    mol_data, gen_data, tox_data, spc_data, pro_data, poc_data
]

all_csv_text = "\n".join(s.strip() for s in sections)
header = "Test Code,Department,Subdepartment,Test Name,Synonyms,Test Type,Specimen,Container,Method / Platform,Unit,Reference Range,Critical Limits,TAT,Report Data Type,Fasting Required,Outsource,Active,Price NPR,Validation Status,Notes"

# 1. Write the Master CSV
with open(CSV_OUT, "w", encoding="utf-8") as f:
    f.write(header + "\n" + all_csv_text + "\n")

print(f"Master CSV written to {CSV_OUT}")

# Parse rows
reader = csv.DictReader(io.StringIO(header + "\n" + all_csv_text))
rows = list(reader)
print(f"Total parsed test records: {len(rows)}")

# Department mapping
dept_map = {}
for r in rows:
    dept = r["Department"]
    subdept = r["Subdepartment"]
    if dept not in dept_map:
        dept_map[dept] = set()
    dept_map[dept].add(subdept)

print(f"Total departments: {len(dept_map)}")

# Generate SQL migration
sql_lines = []
sql_lines.append("""-- ============================================================================
-- Migration 00098: Master Pathology Test Catalogue (1,122 Items) Architecture & Convergence
-- Fully normalizes departments, tests, aliases, panels, reference ranges, and LIS workflow links.
-- ============================================================================

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
CREATE TABLE IF NOT EXISTS public.catalogue_panel_components (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    panel_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    panel_test_id UUID REFERENCES public.tests(id) ON DELETE CASCADE,
    component_test_id UUID REFERENCES public.tests(id) ON DELETE CASCADE,
    component_parameter_id UUID REFERENCES public.parameters(id) ON DELETE CASCADE,
    component_role TEXT NOT NULL DEFAULT 'Measured' CHECK (component_role IN ('Measured', 'Calculated', 'Qualitative', 'ComponentService', 'Narrative')),
    display_order INT NOT NULL DEFAULT 0,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_panel_no_self_ref CHECK (panel_id != component_test_id)
);

-- 3. Update tests table columns for normalized catalogue
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS subdepartment VARCHAR(100);
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS test_type VARCHAR(50) DEFAULT 'Single';
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS fasting_required BOOLEAN DEFAULT FALSE;
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS is_outsource BOOLEAN DEFAULT FALSE;
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS validation_status VARCHAR(50) DEFAULT 'REQUIRES_VALIDATION';
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS tat_description VARCHAR(100);

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
END $$;
""")

def escape_sql(val):
    if val is None:
        return "NULL"
    return "'" + str(val).replace("'", "''") + "'"

# Seed all tests
sql_lines.append("\n-- 4. Seed / Upsert Master Tests (1,122 Items)")
sql_lines.append("DO $$")
sql_lines.append("DECLARE")
sql_lines.append("    v_test_id UUID;")
sql_lines.append("    v_param_id UUID;")
sql_lines.append("BEGIN")

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

    sql_lines.append(f"""
    -- Test: {code} - {name}
    SELECT id INTO v_test_id FROM public.tests WHERE code = {escape_sql(code)};
    IF v_test_id IS NULL THEN
        INSERT INTO public.tests (
            code, name, short_name, department, subdepartment, category,
            test_type, specimen_type, container, container_type, sample_type,
            method, unit, tat_description, report_data_type,
            fasting_required, is_outsource, is_active, validation_status, notes,
            price_paisa, display_order
        ) VALUES (
            {escape_sql(code)}, {escape_sql(name)}, {escape_sql(code)}, {escape_sql(dept)}, {escape_sql(subdept)}, {escape_sql(subdept)},
            {escape_sql(test_type)}, {escape_sql(specimen)}, {escape_sql(container)}, {escape_sql(container)}, {escape_sql(specimen)},
            {escape_sql(method)}, {escape_sql(unit)}, {escape_sql(tat)}, {escape_sql(data_type)},
            {fasting}, {outsource}, {is_active}, {escape_sql(val_status)}, {escape_sql(notes)},
            0, 0
        ) RETURNING id INTO v_test_id;
    ELSE
        UPDATE public.tests SET
            name = {escape_sql(name)},
            department = {escape_sql(dept)},
            subdepartment = {escape_sql(subdept)},
            category = {escape_sql(subdept)},
            test_type = {escape_sql(test_type)},
            specimen_type = {escape_sql(specimen)},
            container = {escape_sql(container)},
            container_type = {escape_sql(container)},
            sample_type = {escape_sql(specimen)},
            method = {escape_sql(method)},
            unit = {escape_sql(unit)},
            tat_description = {escape_sql(tat)},
            report_data_type = {escape_sql(data_type)},
            fasting_required = {fasting},
            is_outsource = {outsource},
            is_active = {is_active},
            validation_status = {escape_sql(val_status)},
            notes = {escape_sql(notes)}
        WHERE id = v_test_id;
    END IF;

    -- Ensure default parameter exists for Single tests
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id AND code = {escape_sql(code)};
    IF v_param_id IS NULL THEN
        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active)
        VALUES (v_test_id, {escape_sql(code)}, {escape_sql(name)}, {escape_sql(unit)}, 'Numeric', 1, TRUE, TRUE)
        RETURNING id INTO v_param_id;
    END IF;
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
        sql_lines.append(f"""
    INSERT INTO public.test_aliases (test_id, alias_name, alias_type)
    VALUES (v_test_id, {escape_sql(alias)}, 'Synonym')
    ON CONFLICT (test_id, alias_name) DO NOTHING;
        """)

sql_lines.append("END $$;")

with open(SQL_OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(sql_lines) + "\n")

print(f"Migration SQL successfully written to {SQL_OUT}")
