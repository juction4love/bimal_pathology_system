-- Migration: 00123_import_missing_rates_from_gm_reference.sql
-- Goal: Import verified missing master catalogue prices into Bimal Pathology LIS from GM Diagnostic reference rate card (RATE GM.pdf).
--
-- Clinical & Financial Invariants:
--  1. Applies ONLY to the 53 verified missing tests where no active catalogue_rate_versions record currently exists.
--  2. Never overwrites or modifies pre-existing configured rates (e.g. migrations 00114-00121).
--  3. All monetary values are strictly positive integer paisa (NPR * 100), eliminating floating-point errors.
--  4. Does NOT mutate historical bills, lab_orders, invoices, or verified clinical reports.
--  5. Updates public.tests with price_configured = TRUE and pricing_policy = 'Fixed' for canonical billing engine resolution.
--  6. Fully idempotent: safe to execute multiple times without producing duplicate active rate versions.
--
-- Audit Source: G:\bimal_pathology_cloud\RATE GM.pdf

BEGIN;

-- 1. Insert active rate-version records for the 53 safe missing test items
WITH rate_source(code, price_paisa) AS (
  VALUES
  ('BIO-0021', 30000::BIGINT), -- PDF #6: SGPT(ALT) (NPR 300.00) -> ALT (SGPT)
  ('BIO-0020', 30000::BIGINT), -- PDF #7: SGOT(AST) (NPR 300.00) -> AST (SGOT)
  ('BIO-0022', 25000::BIGINT), -- PDF #8: Alkaline Phosphetes(ALP) (NPR 250.00) -> Alkaline Phosphatase (ALP)
  ('BIO-0014', 20000::BIGINT), -- PDF #9: Albumin (NPR 200.00) -> Albumin
  ('BIO-0013', 20000::BIGINT), -- PDF #10: T Protein (NPR 200.00) -> Total Protein
  ('BIO-0023', 80000::BIGINT), -- PDF #11: Gamma GT (NPR 800.00) -> GGT
  ('PRO-0002', 100000::BIGINT), -- PDF #12: Renal Funtion Test (NPR 1000.00) -> Renal Function Test (RFT/KFT)
  ('BIO-0027', 20000::BIGINT), -- PDF #18: T Cholesterol (NPR 200.00) -> Total Cholesterol
  ('BIO-0028', 25000::BIGINT), -- PDF #19: Triglyceride TG (NPR 250.00) -> Triglycerides
  ('BIO-0029', 25000::BIGINT), -- PDF #20: HDL (NPR 250.00) -> HDL Cholesterol
  ('BIO-0030', 45000::BIGINT), -- PDF #21: LDL (NPR 450.00) -> LDL Cholesterol, Direct
  ('BIO-0062', 100000::BIGINT), -- PDF #24: CPK/MB (NPR 1000.00) -> CK-MB Activity
  ('BIO-0024', 50000::BIGINT), -- PDF #27: LDH (NPR 500.00) -> LDH
  ('BIO-0132', 100000::BIGINT), -- PDF #28: ADA (NPR 1000.00) -> Pleural Fluid ADA
  ('HEM-0039', 40000::BIGINT), -- PDF #34: TC/DC (NPR 400.00) -> Manual Differential Count
  ('HEM-0004', 30000::BIGINT), -- PDF #38: RBC Count (NPR 300.00) -> RBC Count
  ('HEM-0023', 50000::BIGINT), -- PDF #41: Reticulocyte count (NPR 500.00) -> Reticulocyte Count
  ('HEM-0058', 10000::BIGINT), -- PDF #43: Blood Grouping (NPR 100.00) -> ABO & Rh Typing
  ('CLP-0008', 20000::BIGINT), -- PDF #47: ketone/acetone bodies (NPR 200.00) -> Urine Ketone
  ('CLP-0025', 20000::BIGINT), -- PDF #50: Occoult Blood (NPR 200.00) -> Stool Occult Blood
  ('MIC-0011', 50000::BIGINT), -- PDF #52: Urine Culture (NPR 500.00) -> Urine Culture & Sensitivity
  ('MIC-0012', 60000::BIGINT), -- PDF #53: Stool Culture (NPR 600.00) -> Stool Culture & Sensitivity
  ('MIC-0001', 20000::BIGINT), -- PDF #54: Gram Stain (NPR 200.00) -> Gram Stain
  ('MIC-0002', 20000::BIGINT), -- PDF #55: AFB Stain (1st&2nd) (NPR 200.00) -> AFB Smear by Ziehl-Neelsen
  ('MIC-0004', 40000::BIGINT), -- PDF #56: KOH Preparation (NPR 400.00) -> KOH Mount
  ('CLP-0038', 50000::BIGINT), -- PDF #58: Semen Analysis (NPR 500.00) -> Semen Analysis
  ('SER-0059', 150000::BIGINT), -- PDF #61: Kalazar (NPR 1500.00) -> Kala-azar rK39 Antibody
  ('SER-0028', 60000::BIGINT), -- PDF #67: TPHA (NPR 600.00) -> TPHA/TPPA
  ('SER-0027', 40000::BIGINT), -- PDF #70: VDRL (NPR 400.00) -> VDRL
  ('SER-0011', 250000::BIGINT), -- PDF #73: HAV (NPR 2500.00) -> HAV IgM
  ('SER-0013', 250000::BIGINT), -- PDF #74: HEV (NPR 2500.00) -> HEV IgM
  ('SER-0042', 120000::BIGINT), -- PDF #75: H. Pylori (Ab) Blood (NPR 1200.00) -> H. pylori IgG
  ('SER-0023', 100000::BIGINT), -- PDF #77: Typhoid (NPR 1000.00) -> Salmonella Typhi IgM
  ('END-0006', 200000::BIGINT), -- PDF #79: Anti TPO (NPR 2000.00) -> Anti-TPO Antibody
  ('IMM-0005', 220000::BIGINT), -- PDF #81: ANA (NPR 2200.00) -> ANA by IFA
  ('TUM-0003', 200000::BIGINT), -- PDF #82: CA125 (NPR 2000.00) -> CA 125
  ('TUM-0005', 200000::BIGINT), -- PDF #83: CA15.3 (NPR 2000.00) -> CA 15-3
  ('TUM-0004', 200000::BIGINT), -- PDF #84: CA19.9 (NPR 2000.00) -> CA 19-9
  ('END-0030', 250000::BIGINT), -- PDF #86: Progestrone (NPR 2500.00) -> Progesterone
  ('END-0013', 250000::BIGINT), -- PDF #87: Cortisol (NPR 2500.00) -> Cortisol, 8 AM
  ('IMM-0007', 300000::BIGINT), -- PDF #89: Ds-DNA (NPR 3000.00) -> Anti-dsDNA
  ('PRO-0005', 250000::BIGINT), -- PDF #91: Iron Profile (NPR 2500.00) -> Iron Profile
  ('BIO-0052', 200000::BIGINT), -- PDF #92: Folic Acid (NPR 2000.00) -> Folate
  ('HEM-0032', 600000::BIGINT), -- PDF #94: G6PD (NPR 6000.00) -> G6PD Quantitative
  ('END-0022', 200000::BIGINT), -- PDF #95: Growth Hormone (NPR 2000.00) -> Growth Hormone (GH)
  ('END-0041', 300000::BIGINT), -- PDF #96: Insulin (NPR 3000.00) -> Insulin, Fasting
  ('BIO-0051', 180000::BIGINT), -- PDF #102: Vitamin B12 (NPR 1800.00) -> Vitamin B12
  ('END-0011', 300000::BIGINT), -- PDF #104: PTH (NPR 3000.00) -> PTH, Intact
  ('HEM-0037', 600000::BIGINT), -- PDF #203: BONE MARROW (NPR 6000.00) -> Bone Marrow Aspiration Examination
  ('HIS-0001', 250000::BIGINT), -- PDF #205: SMALL BIOPSY (NPR 2500.00) -> Small Biopsy Histopathology
  ('HIS-0002', 350000::BIGINT), -- PDF #206: MEDIUM BIOPSY (NPR 3500.00) -> Medium Biopsy Histopathology
  ('HIS-0003', 500000::BIGINT), -- PDF #207: LARGE BIOPSY (NPR 5000.00) -> Large Specimen Histopathology
  ('SPC-0014', 600000::BIGINT) -- PDF #208: QUARDE (NPR 6000.00) -> Quadruple Marker Screen
)
INSERT INTO public.catalogue_rate_versions (
  entity_type,
  test_id,
  version_number,
  price_paisa,
  effective_from,
  status
)
SELECT
  'Test'::public.catalogue_billable_entity_enum,
  t.id,
  COALESCE((SELECT MAX(r.version_number) + 1 FROM public.catalogue_rate_versions r WHERE r.test_id = t.id), 1),
  rs.price_paisa,
  clock_timestamp(),
  'Active'
FROM rate_source rs
JOIN public.tests t ON t.code = rs.code
WHERE NOT EXISTS (
  SELECT 1 
  FROM public.catalogue_rate_versions r 
  WHERE r.test_id = t.id 
    AND r.status = 'Active' 
    AND (r.effective_to IS NULL OR r.effective_to > clock_timestamp())
);

-- 2. Mark price_configured = TRUE and pricing_policy = 'Fixed' on tests table
UPDATE public.tests
SET 
  price_configured = TRUE,
  pricing_policy = 'Fixed',
  updated_at = clock_timestamp()
WHERE code IN (
  'BIO-0021',
  'BIO-0020',
  'BIO-0022',
  'BIO-0014',
  'BIO-0013',
  'BIO-0023',
  'PRO-0002',
  'BIO-0027',
  'BIO-0028',
  'BIO-0029',
  'BIO-0030',
  'BIO-0062',
  'BIO-0024',
  'BIO-0132',
  'HEM-0039',
  'HEM-0004',
  'HEM-0023',
  'HEM-0058',
  'CLP-0008',
  'CLP-0025',
  'MIC-0011',
  'MIC-0012',
  'MIC-0001',
  'MIC-0002',
  'MIC-0004',
  'CLP-0038',
  'SER-0059',
  'SER-0028',
  'SER-0027',
  'SER-0011',
  'SER-0013',
  'SER-0042',
  'SER-0023',
  'END-0006',
  'IMM-0005',
  'TUM-0003',
  'TUM-0005',
  'TUM-0004',
  'END-0030',
  'END-0013',
  'IMM-0007',
  'PRO-0005',
  'BIO-0052',
  'HEM-0032',
  'END-0022',
  'END-0041',
  'BIO-0051',
  'END-0011',
  'HEM-0037',
  'HIS-0001',
  'HIS-0002',
  'HIS-0003',
  'SPC-0014'
)
AND (price_configured IS NOT TRUE OR pricing_policy IS DISTINCT FROM 'Fixed');

COMMIT;
