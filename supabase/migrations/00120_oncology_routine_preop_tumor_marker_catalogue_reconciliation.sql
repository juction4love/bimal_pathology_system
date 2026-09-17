-- ==============================================================================
-- Migration: 00120_oncology_routine_preop_tumor_marker_catalogue_reconciliation.sql
-- Description: Oncology, Routine Monitoring, Pre-operative, Tumor Marker, Cytology,
--              and Supportive Care Catalogue Reconciliation & Search Optimization.
-- Governance: Admin-only catalogue governance; Lab Technician operational-only RBAC.
-- Integrity: Preserves all historical bills, results, reports, and rate snapshots.
-- ==============================================================================

BEGIN;

-- 1. Ensure LBC (CYT-0008) is Billing-Only (NoReporting)
UPDATE public.tests
SET 
  reporting_type = 'NoReporting',
  clinical_configuration_status = 'Configured',
  search_aliases = ARRAY['LBC', 'Liquid Based Cytology', 'Liquid-Based Cytology', 'Pap Smear LBC', 'एलबीसी'],
  updated_at = clock_timestamp()
WHERE code = 'CYT-0008';

-- 2. Ensure HPV DNA (MOL-0014) is Billing-Only (NoReporting) with NPR 4,500 rate
UPDATE public.tests
SET 
  name = 'HPV DNA (High Risk PCR)',
  short_name = 'HPV DNA',
  reporting_type = 'NoReporting',
  price_paisa = 450000,
  clinical_configuration_status = 'Configured',
  search_aliases = ARRAY['HPV DNA', 'High Risk HPV', 'HPV PCR', 'HPV DNA High Risk PCR', 'Human Papillomavirus DNA', 'एचपिभी डिएनए'],
  updated_at = clock_timestamp()
WHERE code = 'MOL-0014';

-- Record rate version for HPV DNA if not already recorded
UPDATE public.catalogue_rate_versions
SET status = 'Archived', effective_to = clock_timestamp(), updated_at = clock_timestamp()
WHERE test_id = (SELECT id FROM public.tests WHERE code = 'MOL-0014') AND status = 'Active';

INSERT INTO public.catalogue_rate_versions (
  entity_type,
  test_id,
  version_number,
  price_paisa,
  effective_from,
  status
)
SELECT 
  'Test',
  t.id,
  COALESCE((SELECT MAX(version_number) + 1 FROM public.catalogue_rate_versions WHERE test_id = t.id), 1),
  450000,
  clock_timestamp(),
  'Active'
FROM public.tests t
WHERE t.code = 'MOL-0014';

-- 3. Create Convenience Ordering Panel: PRO-0031 (Viral Serology Panel / Pre-operative Viral Screen)
INSERT INTO public.tests (
  id,
  code,
  name,
  short_name,
  department,
  category,
  category_id,
  test_type,
  specimen_type,
  sample_type,
  container,
  container_type,
  method,
  unit,
  reporting_type,
  test_kind,
  reporting_model,
  price_paisa,
  price_configured,
  allow_zero_price_billing,
  is_active,
  billing_enabled,
  clinical_reporting_enabled,
  lifecycle_status,
  clinical_configuration_status,
  search_aliases,
  created_at,
  updated_at
)
VALUES (
  '8fcfdb3d-6b58-48b4-82a9-c062829da031',
  'PRO-0031',
  'Viral Serology Panel',
  'Viral Serology',
  'Profiles / Packages',
  'Profiles & Health Packages',
  (SELECT id FROM public.test_categories WHERE name = 'Profiles & Health Packages' LIMIT 1),
  'Panel',
  'Serum / Whole Blood',
  'Serum / Whole Blood',
  'Serum Separator Tube (Gold) / Plain Tube (Red)',
  'Serum Separator Tube (Gold) / Plain Tube (Red)',
  'Immunochromatographic Rapid Assay',
  'Panel',
  'InHouse',
  'Profile',
  'Profile',
  0,
  false,
  true,
  true,
  true,
  true,
  'Active',
  'Configured',
  ARRAY['Viral Serology Panel', 'Pre-operative Viral Screen', 'Viral Screen', 'HIV HBsAg HCV', 'भाइरल सेरोलोजी'],
  clock_timestamp(),
  clock_timestamp()
)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  short_name = EXCLUDED.short_name,
  department = EXCLUDED.department,
  category = EXCLUDED.category,
  category_id = EXCLUDED.category_id,
  reporting_type = EXCLUDED.reporting_type,
  test_kind = EXCLUDED.test_kind,
  reporting_model = EXCLUDED.reporting_model,
  search_aliases = EXCLUDED.search_aliases,
  updated_at = clock_timestamp();

-- Link components for PRO-0031 (HIV Rapid, HBsAg Rapid, HCV Rapid)
INSERT INTO public.catalogue_panel_components (panel_id, component_test_id, display_order, is_required)
SELECT 
  '8fcfdb3d-6b58-48b4-82a9-c062829da031',
  t.id,
  ord.display_order,
  true
FROM (
  VALUES 
    ('SER-0086', 1),
    ('SER-0087', 2),
    ('SER-0088', 3)
) AS ord(code, display_order)
JOIN public.tests t ON t.code = ord.code
ON CONFLICT (panel_id, component_test_id) DO UPDATE SET
  display_order = EXCLUDED.display_order,
  is_required = EXCLUDED.is_required;

-- 4. Create Convenience Ordering Preset: PRO-0032 (Chemotherapy Routine Monitoring Panel)
INSERT INTO public.tests (
  id,
  code,
  name,
  short_name,
  department,
  category,
  category_id,
  test_type,
  specimen_type,
  sample_type,
  container,
  container_type,
  method,
  unit,
  reporting_type,
  test_kind,
  reporting_model,
  price_paisa,
  price_configured,
  allow_zero_price_billing,
  is_active,
  billing_enabled,
  clinical_reporting_enabled,
  lifecycle_status,
  clinical_configuration_status,
  search_aliases,
  created_at,
  updated_at
)
VALUES (
  '8fcfdb3d-6b58-48b4-82a9-c062829da032',
  'PRO-0032',
  'Chemotherapy Routine Monitoring Panel',
  'Chemo Routine',
  'Profiles / Packages',
  'Profiles & Health Packages',
  (SELECT id FROM public.test_categories WHERE name = 'Profiles & Health Packages' LIMIT 1),
  'Panel',
  'Multiple Specimens (Blood, Serum, Urine)',
  'Multiple Specimens (Blood, Serum, Urine)',
  'EDTA Tube (Lavender), SST (Gold), Sterile Urine Container',
  'EDTA Tube (Lavender), SST (Gold), Sterile Urine Container',
  'Automated & Manual Multi-discipline Methods',
  'Panel',
  'InHouse',
  'Profile',
  'Profile',
  0,
  false,
  true,
  true,
  true,
  true,
  'Active',
  'Configured',
  ARRAY['Chemo Routine Monitoring', 'Chemotherapy Monitoring', 'Chemo Routine Panel', 'केमो रुटिन मनिटरिङ'],
  clock_timestamp(),
  clock_timestamp()
)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  short_name = EXCLUDED.short_name,
  department = EXCLUDED.department,
  category = EXCLUDED.category,
  category_id = EXCLUDED.category_id,
  reporting_type = EXCLUDED.reporting_type,
  test_kind = EXCLUDED.test_kind,
  reporting_model = EXCLUDED.reporting_model,
  search_aliases = EXCLUDED.search_aliases,
  updated_at = clock_timestamp();

-- Link components for PRO-0032 (CBC, LFT, KFT/RFT, Electrolytes, Urine R/E)
INSERT INTO public.catalogue_panel_components (panel_id, component_test_id, display_order, is_required)
SELECT 
  '8fcfdb3d-6b58-48b4-82a9-c062829da032',
  t.id,
  ord.display_order,
  true
FROM (
  VALUES 
    ('HEM-0001', 1),
    ('PRO-0001', 2),
    ('PRO-0002', 3),
    ('PRO-0008', 4),
    ('CLP-0001', 5)
) AS ord(code, display_order)
JOIN public.tests t ON t.code = ord.code
ON CONFLICT (panel_id, component_test_id) DO UPDATE SET
  display_order = EXCLUDED.display_order,
  is_required = EXCLUDED.is_required;

-- 5. Create Convenience Ordering Preset: PRO-0033 (Pre-operative Coagulation Panel)
INSERT INTO public.tests (
  id,
  code,
  name,
  short_name,
  department,
  category,
  category_id,
  test_type,
  specimen_type,
  sample_type,
  container,
  container_type,
  method,
  unit,
  reporting_type,
  test_kind,
  reporting_model,
  price_paisa,
  price_configured,
  allow_zero_price_billing,
  is_active,
  billing_enabled,
  clinical_reporting_enabled,
  lifecycle_status,
  clinical_configuration_status,
  search_aliases,
  created_at,
  updated_at
)
VALUES (
  '8fcfdb3d-6b58-48b4-82a9-c062829da033',
  'PRO-0033',
  'Pre-operative Coagulation Panel',
  'Pre-op Coag',
  'Profiles / Packages',
  'Profiles & Health Packages',
  (SELECT id FROM public.test_categories WHERE name = 'Profiles & Health Packages' LIMIT 1),
  'Panel',
  'Citrated Plasma & Capillary Blood',
  'Citrated Plasma & Capillary Blood',
  'Sodium Citrate Tube (Blue), Capillary Tube',
  'Sodium Citrate Tube (Blue), Capillary Tube',
  'Tilt Tube, Manual Duke & Capillary Tube Methods',
  'Panel',
  'InHouse',
  'Profile',
  'Profile',
  0,
  false,
  true,
  true,
  true,
  true,
  'Active',
  'Configured',
  ARRAY['Pre-operative Coagulation Panel', 'Pre-op Coagulation', 'Coagulation Screen Pre-op', 'अपरेसन अगाडिको रगत जाँच'],
  clock_timestamp(),
  clock_timestamp()
)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  short_name = EXCLUDED.short_name,
  department = EXCLUDED.department,
  category = EXCLUDED.category,
  category_id = EXCLUDED.category_id,
  reporting_type = EXCLUDED.reporting_type,
  test_kind = EXCLUDED.test_kind,
  reporting_model = EXCLUDED.reporting_model,
  search_aliases = EXCLUDED.search_aliases,
  updated_at = clock_timestamp();

-- Link components for PRO-0033 (PT/INR, APTT, BT, CT)
INSERT INTO public.catalogue_panel_components (panel_id, component_test_id, display_order, is_required)
SELECT 
  '8fcfdb3d-6b58-48b4-82a9-c062829da033',
  t.id,
  ord.display_order,
  true
FROM (
  VALUES 
    ('COA-0001', 1),
    ('COA-0003', 2),
    ('COA-0007', 3),
    ('COA-0008', 4)
) AS ord(code, display_order)
JOIN public.tests t ON t.code = ord.code
ON CONFLICT (panel_id, component_test_id) DO UPDATE SET
  display_order = EXCLUDED.display_order,
  is_required = EXCLUDED.is_required;

-- 6. Comprehensive Search Aliases Reconciliation for Oncology, Pre-Op, Monitoring, Tumor & Supportive Care Tests
UPDATE public.tests SET search_aliases = ARRAY['CBC', 'Complete Blood Count', 'Hemogram', 'Haemogram', 'CBC Test', 'सिबिसि', 'रगत जाँच'] WHERE code = 'HEM-0001';
UPDATE public.tests SET search_aliases = ARRAY['ANC', 'Absolute Neutrophil Count', 'Neutrophil Count', 'एएनसि'] WHERE code = 'HEM-0020';
UPDATE public.tests SET search_aliases = ARRAY['LFT', 'Liver Function Test', 'Liver Profile', 'Liver Panel', 'एलएफटी', 'कलेजो जाँच'] WHERE code = 'PRO-0001';
UPDATE public.tests SET search_aliases = ARRAY['KFT', 'RFT', 'Kidney Function Test', 'Renal Function Test', 'Renal Profile', 'Kidney Profile', 'केएफटी', 'आरएफटी', 'मिर्गौला जाँच'] WHERE code = 'PRO-0002';
UPDATE public.tests SET search_aliases = ARRAY['Creatinine', 'Serum Creatinine', 'Cr', 'क्रिएटिनिन'] WHERE code = 'BIO-0010';
UPDATE public.tests SET search_aliases = ARRAY['Urea', 'Blood Urea', 'BUN', 'युरिया'] WHERE code = 'BIO-0008';
UPDATE public.tests SET search_aliases = ARRAY['Electrolytes', 'Serum Electrolytes', 'Electrolyte Panel', 'Na K Cl', 'Sodium Potassium', 'इलेक्ट्रोलाइट्स'] WHERE code = 'PRO-0008';
UPDATE public.tests SET search_aliases = ARRAY['Sodium', 'Na', 'Na+', 'सोडियम'] WHERE code = 'BIO-0037';
UPDATE public.tests SET search_aliases = ARRAY['Potassium', 'K', 'K+', 'पोटासियम'] WHERE code = 'BIO-0038';
UPDATE public.tests SET search_aliases = ARRAY['Chloride', 'Cl', 'Cl-', 'क्लोराइड'] WHERE code = 'BIO-0039';
UPDATE public.tests SET search_aliases = ARRAY['Urine RE', 'Urine R/E', 'Urine Routine', 'Urinalysis', 'Urine Routine & Microscopy', 'Urine Examination', 'पिसाब जाँच'] WHERE code = 'CLP-0001';
UPDATE public.tests SET search_aliases = ARRAY['APTT', 'aPTT', 'Activated Partial Thromboplastin Time', 'एपिटिटि'] WHERE code = 'COA-0003';
UPDATE public.tests SET search_aliases = ARRAY['Blood Group', 'Blood Grouping', 'ABO', 'Rh Typing', 'Blood Group & Rh', 'ABO & Rh Typing', 'रगत समूह'] WHERE code = 'HEM-0058';

-- Tumor Markers Aliases
UPDATE public.tests SET search_aliases = ARRAY['CEA', 'Carcinoembryonic Antigen', 'सिइए'] WHERE code = 'TUM-0002';
UPDATE public.tests SET search_aliases = ARRAY['AFP', 'Alpha-Fetoprotein', 'Alpha Fetoprotein', 'एएफपि'] WHERE code = 'TUM-0001';
UPDATE public.tests SET search_aliases = ARRAY['CA 125', 'CA125', 'CA-125', 'Cancer Antigen 125', 'सिए १२५'] WHERE code = 'TUM-0003';
UPDATE public.tests SET search_aliases = ARRAY['CA 19-9', 'CA19-9', 'CA-19-9', 'Carbohydrate Antigen 19-9', 'सिए १९-९'] WHERE code = 'TUM-0004';
UPDATE public.tests SET search_aliases = ARRAY['CA 15-3', 'CA15-3', 'CA-15-3', 'Cancer Antigen 15-3', 'सिए १५-३'] WHERE code = 'TUM-0005';
UPDATE public.tests SET search_aliases = ARRAY['PSA', 'Total PSA', 'PSA Total', 'Prostate Specific Antigen', 'पिएसए'] WHERE code = 'TUM-0007';
UPDATE public.tests SET search_aliases = ARRAY['Free PSA', 'PSA Free', 'पिएसए फ्रि'] WHERE code = 'TUM-0008';
UPDATE public.tests SET search_aliases = ARRAY['Beta hCG', 'Beta-hCG', 'hCG Quantitative', 'Beta-hCG Quantitative', 'b-hCG', 'बेटा एचसिजि'] WHERE code = 'END-0039';

-- Cytology / Biopsy Aliases
UPDATE public.tests SET search_aliases = ARRAY['FNAC Thyroid', 'FNAC - Thyroid', 'Fine Needle Aspiration Thyroid', 'थाइरोइड एफएनएसी'] WHERE code = 'CYT-0001';
UPDATE public.tests SET search_aliases = ARRAY['FNAC Breast', 'FNAC - Breast', 'Fine Needle Aspiration Breast', 'स्तन एफएनएसी'] WHERE code = 'CYT-0002';
UPDATE public.tests SET search_aliases = ARRAY['FNAC Lymph Node', 'FNAC - Lymph Node', 'Fine Needle Aspiration Lymph Node', 'लिम्फ नोड एफएनएसी'] WHERE code = 'CYT-0003';
UPDATE public.tests SET search_aliases = ARRAY['FNAC Salivary Gland', 'FNAC - Salivary Gland', 'Fine Needle Aspiration Salivary Gland'] WHERE code = 'CYT-0004';
UPDATE public.tests SET search_aliases = ARRAY['FNAC Soft Tissue', 'FNAC - Soft Tissue', 'Fine Needle Aspiration Soft Tissue'] WHERE code = 'CYT-0005';
UPDATE public.tests SET search_aliases = ARRAY['FNAC Other Site', 'FNAC', 'Fine Needle Aspiration Cytology', 'एफएनएसी'] WHERE code = 'CYT-0006';
UPDATE public.tests SET search_aliases = ARRAY['Small Biopsy', 'Biopsy Small', 'Histopathology Small', 'बायोप्सी'] WHERE code = 'HIS-0001';
UPDATE public.tests SET search_aliases = ARRAY['Medium Biopsy', 'Biopsy Medium', 'Histopathology Medium'] WHERE code = 'HIS-0002';
UPDATE public.tests SET search_aliases = ARRAY['Large Biopsy', 'Biopsy Large', 'Histopathology Large', 'Large Specimen Histopathology'] WHERE code = 'HIS-0003';
UPDATE public.tests SET search_aliases = ARRAY['Pleural Fluid Cytology', 'Pleural Fluid', 'Fluid Cytology Pleural', 'प्लुरल फ्लुइड साइटोलोजी'] WHERE code = 'CYT-0009';
UPDATE public.tests SET search_aliases = ARRAY['Ascitic Fluid Cytology', 'Ascitic Fluid', 'Peritoneal Fluid Cytology', 'असाइटिक फ्लुइड साइटोलोजी'] WHERE code = 'CYT-0010';
UPDATE public.tests SET search_aliases = ARRAY['Pericardial Fluid Cytology', 'Pericardial Fluid'] WHERE code = 'CYT-0011';

-- Supportive Care Aliases
UPDATE public.tests SET search_aliases = ARRAY['Ferritin', 'Serum Ferritin', 'फेरिटिन'] WHERE code = 'BIO-0050';
UPDATE public.tests SET search_aliases = ARRAY['Iron Profile', 'Iron Panel', 'Serum Iron Profile', 'आइरन प्रोफाइल'] WHERE code = 'PRO-0005';
UPDATE public.tests SET search_aliases = ARRAY['Vitamin D', 'Vit D', '25-OH Vitamin D', 'Vitamin D3', 'भिटामिन डि'] WHERE code = 'BIO-0053';
UPDATE public.tests SET search_aliases = ARRAY['Vitamin B12', 'Vit B12', 'B12', 'Cyanocobalamin', 'भिटामिन बि१२'] WHERE code = 'BIO-0051';
UPDATE public.tests SET search_aliases = ARRAY['hs-CRP', 'hsCRP', 'High Sensitivity CRP', 'High Sensitive CRP', 'एचएस सिआरपी'] WHERE code = 'BIO-0068';
UPDATE public.tests SET search_aliases = ARRAY['PCT', 'Procalcitonin', 'Procalcitonin PCT', 'प्रोकल्सिटोनिन'] WHERE code = 'PCT_SEPSIS';

-- 7. Synchronize public.test_aliases table
INSERT INTO public.test_aliases (test_id, alias_name, alias_type, is_primary, created_at)
SELECT 
  t.id,
  alias_elem,
  'Synonym',
  false,
  clock_timestamp()
FROM public.tests t,
LATERAL unnest(t.search_aliases) AS alias_elem
WHERE t.code IN (
  'HEM-0001', 'HEM-0020', 'PRO-0001', 'PRO-0002', 'BIO-0010', 'BIO-0008',
  'PRO-0008', 'BIO-0037', 'BIO-0038', 'BIO-0039', 'CLP-0001',
  'COA-0001', 'COA-0003', 'COA-0007', 'COA-0008', 'PRO-0030', 'HEM-0058',
  'SER-0086', 'SER-0087', 'SER-0088', 'PRO-0031', 'PRO-0032', 'PRO-0033',
  'TUM-0002', 'TUM-0001', 'TUM-0003', 'TUM-0004', 'TUM-0005', 'TUM-0007', 'TUM-0008', 'END-0039',
  'CYT-0001', 'CYT-0002', 'CYT-0003', 'CYT-0004', 'CYT-0005', 'CYT-0006', 'CYT-0008', 'MOL-0014',
  'HIS-0001', 'HIS-0002', 'HIS-0003', 'CYT-0009', 'CYT-0010', 'CYT-0011',
  'BIO-0050', 'PRO-0005', 'BIO-0053', 'BIO-0051', 'BIO-0068', 'PCT_SEPSIS'
)
ON CONFLICT (test_id, alias_name) DO NOTHING;

COMMIT;
