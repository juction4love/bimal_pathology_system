-- Migration 00112: Billing Fast Catalogue Search, Panel Component Resolution & Bilingual Aliases
--
-- Authoritative Billing Search Capabilities:
-- 1. Fast, ranking-aware search across test codes, canonical names, short names, abbreviations,
--    aliases, panel names/components, departments, clinical categories, and Nepali terms.
-- 2. Expandable Panel component resolution with duplicate billing prevention.
-- 3. Ingests standard billing abbreviations, clinical synonyms, and Nepali aliases.
-- 4. Preserves backward compatibility and strict LIS security invariants.

BEGIN;

-- 1. Seed Comprehensive Billing Search Aliases into public.test_aliases
DO $$
DECLARE
    v_test_id UUID;
BEGIN
    -- A. Complete Blood Count (CBC / Hemogram / पूर्ण रक्त गणना) -> HEM-0001
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0001';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'CBC', 'Acronym'),
        (v_test_id, 'Hemogram', 'Synonym'),
        (v_test_id, 'Complete Hemogram', 'Synonym'),
        (v_test_id, 'Complete Blood Count', 'Synonym'),
        (v_test_id, 'पूर्ण रक्त गणना', 'Synonym'),
        (v_test_id, 'रक्त गणना', 'Synonym'),
        (v_test_id, 'सीबीसी', 'Acronym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- B. Liver Function Test (LFT / कलेजो परीक्षण) -> PRO-0001
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'PRO-0001';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'LFT', 'Acronym'),
        (v_test_id, 'Liver Function Test', 'Synonym'),
        (v_test_id, 'Liver Panel', 'Synonym'),
        (v_test_id, 'Hepatic Function Panel', 'Synonym'),
        (v_test_id, 'कलेजो परीक्षण', 'Synonym'),
        (v_test_id, 'कलेजो जाँच', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- C. Renal Function Test (RFT / KFT / मिर्गौला परीक्षण) -> PRO-0002
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'PRO-0002';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'KFT', 'Acronym'),
        (v_test_id, 'RFT', 'Acronym'),
        (v_test_id, 'Kidney Function', 'Synonym'),
        (v_test_id, 'Renal Function', 'Synonym'),
        (v_test_id, 'Kidney Function Test', 'Synonym'),
        (v_test_id, 'Renal Function Test', 'Synonym'),
        (v_test_id, 'मिर्गौला परीक्षण', 'Synonym'),
        (v_test_id, 'मिर्गौला जाँच', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- D. Lipid Profile (Lipid / Cholesterol / लिपिड प्रोफाइल) -> PRO-0003
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'PRO-0003';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Lipid', 'Acronym'),
        (v_test_id, 'Lipid Profile', 'Synonym'),
        (v_test_id, 'Lipid Panel', 'Synonym'),
        (v_test_id, 'Cholesterol Profile', 'Synonym'),
        (v_test_id, 'लिपिड प्रोफाइल (कोलेस्ट्रोल)', 'Synonym'),
        (v_test_id, 'लिपिड प्रोफाइल', 'Synonym'),
        (v_test_id, 'कोलेस्ट्रोल परीक्षण', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- E. Thyroid Profile (FT3, FT4, TSH / थाइरोइड प्रोफाइल) -> PRO-0004
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'PRO-0004';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Thyroid', 'Acronym'),
        (v_test_id, 'Thyroid Profile', 'Synonym'),
        (v_test_id, 'TFT', 'Acronym'),
        (v_test_id, 'Free Thyroid Profile', 'Synonym'),
        (v_test_id, 'थाइरोइड प्रोफाइल', 'Synonym'),
        (v_test_id, 'थाइरोइड परीक्षण', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- F. TSH (Endocrinology) -> END-0001
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0001';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'TSH', 'Acronym'),
        (v_test_id, 'Thyroid Stimulating Hormone', 'Synonym'),
        (v_test_id, 'थाइरोइड हर्मोन TSH', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- G. FT4 -> END-0002
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0002';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'FT4', 'Acronym'),
        (v_test_id, 'Free T4', 'Synonym'),
        (v_test_id, 'Free Thyroxine', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- H. FT3 -> END-0003
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0003';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'FT3', 'Acronym'),
        (v_test_id, 'Free T3', 'Synonym'),
        (v_test_id, 'Free Triiodothyronine', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- I. Vitamin D, 25-OH -> BIO-0053
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0053';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Vit D', 'Acronym'),
        (v_test_id, 'Vitamin D', 'Synonym'),
        (v_test_id, '25-OH', 'Acronym'),
        (v_test_id, '25-OH Vitamin D', 'Synonym'),
        (v_test_id, '25-Hydroxy Vitamin D', 'Synonym'),
        (v_test_id, 'भिटामिन डी', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- J. Vitamin B12 -> BIO-0051
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0051';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Vit B12', 'Acronym'),
        (v_test_id, 'Vitamin B12', 'Synonym'),
        (v_test_id, 'Cobalamin', 'Synonym'),
        (v_test_id, 'भिटामिन बी१२', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- K. Troponin I, High Sensitivity -> BIO-0063
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0063';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Troponin', 'Acronym'),
        (v_test_id, 'cTnI', 'Acronym'),
        (v_test_id, 'hs-cTnI', 'Acronym'),
        (v_test_id, 'Troponin I', 'Synonym'),
        (v_test_id, 'Cardiac Troponin I', 'Synonym'),
        (v_test_id, 'कार्डियाक ट्रोपोनिन', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- L. NT-proBNP -> BIO-0067
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0067';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'BNP', 'Acronym'),
        (v_test_id, 'NT-proBNP', 'Acronym'),
        (v_test_id, 'Brain Natriuretic Peptide', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- M. D-Dimer -> COA-0006
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'COA-0006';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'D-Dimer', 'Acronym'),
        (v_test_id, 'D Dimer', 'Synonym'),
        (v_test_id, 'डी-डाइमर', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- N. Urine Routine Examination (RE/ME) -> CLP-0001
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'CLP-0001';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Urine', 'Acronym'),
        (v_test_id, 'Urine RE/ME', 'Acronym'),
        (v_test_id, 'Urine Routine', 'Synonym'),
        (v_test_id, 'Urinalysis', 'Synonym'),
        (v_test_id, 'पिसाब', 'Synonym'),
        (v_test_id, 'पिसाब परीक्षण', 'Synonym'),
        (v_test_id, 'पिसाब जाँच', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- O. Fasting Blood Glucose -> BIO-0001
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0001';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'FBS', 'Acronym'),
        (v_test_id, 'Sugar', 'Synonym'),
        (v_test_id, 'Fasting Sugar', 'Synonym'),
        (v_test_id, 'Glucose Fasting', 'Synonym'),
        (v_test_id, 'खाली पेटको सुगर', 'Synonym'),
        (v_test_id, 'रक्त ग्लुकोज', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- P. HbA1c -> BIO-0004
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0004';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'HbA1c', 'Acronym'),
        (v_test_id, 'Glycated Hemoglobin', 'Synonym'),
        (v_test_id, 'A1c', 'Acronym'),
        (v_test_id, '३ महिने सुगर (HbA1c)', 'Synonym'),
        (v_test_id, 'एचबिएवानसी', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Q. Total Cholesterol -> BIO-0027
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0027';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Cholesterol', 'Acronym'),
        (v_test_id, 'Total Cholesterol', 'Synonym'),
        (v_test_id, 'कोलेस्ट्रोल', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- R. CRP -> BIO-0068
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0068';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'CRP', 'Acronym'),
        (v_test_id, 'C-Reactive Protein', 'Synonym'),
        (v_test_id, 'सीआरपी', 'Acronym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- S. Diabetes Profile -> PRO-0006
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'PRO-0006';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Diabetes', 'Acronym'),
        (v_test_id, 'Diabetes Profile', 'Synonym'),
        (v_test_id, 'Diabetic Panel', 'Synonym'),
        (v_test_id, 'मधुमेह परीक्षण', 'Synonym'),
        (v_test_id, 'मधुमेह प्रोफाइल', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- T. Cardiac Marker Panel -> PRO-0007
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'PRO-0007';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Cardiac', 'Acronym'),
        (v_test_id, 'Cardiac Panel', 'Synonym'),
        (v_test_id, 'Cardiac Profile', 'Synonym'),
        (v_test_id, 'मुटु सम्बन्धी परीक्षण', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- U. Electrolyte Panel -> PRO-0008
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'PRO-0008';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Electrolytes', 'Acronym'),
        (v_test_id, 'Serum Electrolytes', 'Synonym'),
        (v_test_id, 'इलेक्ट्रोलाइट्स', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- V. Vitamins Suite -> IMM-VITAMINS
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'IMM-VITAMINS';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Vitamins', 'Acronym'),
        (v_test_id, 'Vitamins Profile', 'Synonym'),
        (v_test_id, 'भिटामिन प्रोफाइल', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;
END $$;

-- 2. Enhanced Fast Catalogue Search Function
CREATE OR REPLACE FUNCTION public.search_billable_catalogue(p_query TEXT, p_limit INT DEFAULT 30)
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
  IF auth.uid() IS NULL OR NOT (public.has_permission('can_create_bill') OR public.has_permission('can_manage_catalogue')) THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;

  RETURN QUERY WITH q AS (
    SELECT lower(btrim(COALESCE(p_query, ''))) value
  ),
  matches(entity_kind, item_id, item_code, item_name, item_short_name, item_category, item_specimen, item_container, item_price_paisa, item_price_configured, item_pricing_policy, item_zero_price, item_reporting_type, item_score) AS (
    -- A. Tests & Profiles
    SELECT
      CASE WHEN t.reporting_type = 'NoReporting' THEN 'Test'::TEXT ELSE 'Test'::TEXT END,
      t.id,
      t.code::TEXT,
      t.name::TEXT,
      t.short_name::TEXT,
      COALESCE(c.name, t.department, t.category)::TEXT,
      COALESCE(r_spec.preferred_specimen, t.sample_type, 'Blood / Specimen')::TEXT,
      COALESCE(r_spec.primary_tube_color, t.container, 'Standard Container')::TEXT,
      COALESCE(r.price_paisa, t.price_paisa, 0)::BIGINT,
      (COALESCE(r.price_paisa, t.price_paisa) IS NOT NULL AND COALESCE(r.price_paisa, t.price_paisa) > 0),
      COALESCE(t.pricing_policy, 'Fixed'),
      COALESCE(t.allow_zero_price_billing, FALSE),
      t.reporting_type,
      CASE
        -- 1. Exact Code or Short Name match (100)
        WHEN lower(t.code) = q.value OR lower(COALESCE(t.short_name, '')) = q.value THEN 100
        -- 2. Exact Canonical Name match (95)
        WHEN lower(t.name) = q.value THEN 95
        -- 3. Exact Alias match (90)
        WHEN EXISTS (SELECT 1 FROM public.test_aliases a WHERE a.test_id = t.id AND lower(a.alias_name) = q.value) THEN 90
        -- 4. Starts-with Code, Short Name, or Name match (85)
        WHEN lower(t.code) LIKE q.value || '%' OR lower(COALESCE(t.short_name, '')) LIKE q.value || '%' OR lower(t.name) LIKE q.value || '%' THEN 85
        -- 5. Starts-with Alias match (80)
        WHEN EXISTS (SELECT 1 FROM public.test_aliases a WHERE a.test_id = t.id AND lower(a.alias_name) LIKE q.value || '%') THEN 80
        -- 6. Substring match in Name or Alias (70)
        WHEN lower(t.name) LIKE '%' || q.value || '%' OR EXISTS (SELECT 1 FROM public.test_aliases a WHERE a.test_id = t.id AND lower(a.alias_name) LIKE '%' || q.value || '%') THEN 70
        -- 7. Panel Component match (65)
        WHEN EXISTS (
          SELECT 1 FROM public.catalogue_panel_components cpc
          JOIN public.tests ct ON ct.id = cpc.component_test_id
          WHERE cpc.panel_test_id = t.id
            AND (lower(ct.name) LIKE '%' || q.value || '%' OR lower(ct.code) LIKE '%' || q.value || '%')
        ) THEN 65
        -- 8. Department or Category match (50)
        WHEN lower(COALESCE(t.department, '')) LIKE '%' || q.value || '%' OR lower(COALESCE(c.name, '')) LIKE '%' || q.value || '%' THEN 50
        ELSE 40
      END score
    FROM public.tests t
    CROSS JOIN q
    LEFT JOIN public.test_categories c ON c.id = t.category_id
    LEFT JOIN public.catalogue_rate_versions r ON r.test_id = t.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    LEFT JOIN public.assay_specimen_governance_rules r_spec ON r_spec.test_id = t.id
    WHERE length(q.value) >= 1
      AND t.is_active = TRUE
      AND t.lifecycle_status = 'Active'
      AND (
        lower(t.code) LIKE '%' || q.value || '%'
        OR lower(t.name) LIKE '%' || q.value || '%'
        OR lower(COALESCE(t.short_name, '')) LIKE '%' || q.value || '%'
        OR lower(COALESCE(t.department, '')) LIKE '%' || q.value || '%'
        OR lower(COALESCE(c.name, '')) LIKE '%' || q.value || '%'
        OR EXISTS (
          SELECT 1 FROM public.test_aliases a
          WHERE a.test_id = t.id AND lower(a.alias_name) LIKE '%' || q.value || '%'
        )
        OR EXISTS (
          SELECT 1 FROM public.catalogue_panel_components cpc
          JOIN public.tests ct ON ct.id = cpc.component_test_id
          WHERE cpc.panel_test_id = t.id
            AND (lower(ct.name) LIKE '%' || q.value || '%' OR lower(ct.code) LIKE '%' || q.value || '%')
        )
      )

    UNION ALL

    -- B. Health Packages
    SELECT
      'Package'::TEXT,
      p.id,
      p.code::TEXT,
      p.name::TEXT,
      NULL,
      'Health Packages'::TEXT,
      'Multiple specimens as configured'::TEXT,
      'As required'::TEXT,
      COALESCE(r.price_paisa, 0)::BIGINT,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      p.pricing_policy,
      FALSE,
      'NoReporting'::public.reporting_type_enum,
      CASE
        WHEN lower(p.code) = q.value THEN 100
        WHEN lower(p.name) = q.value THEN 95
        WHEN lower(p.code) LIKE q.value || '%' THEN 90
        WHEN lower(p.name) LIKE q.value || '%' THEN 85
        ELSE 50
      END
    FROM public.health_packages p
    CROSS JOIN q
    LEFT JOIN public.catalogue_rate_versions r ON r.package_id = p.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 1
      AND p.lifecycle_status = 'Active'
      AND (lower(p.code) LIKE '%' || q.value || '%' OR lower(p.name) LIKE '%' || q.value || '%')

    UNION ALL

    -- C. Bundled Panel Services
    SELECT
      'Panel'::TEXT,
      ps.id,
      ps.code::TEXT,
      ps.name::TEXT,
      NULL,
      c.name::TEXT,
      COALESCE(ps.specimen, 'Serum / Plasma')::TEXT,
      COALESCE(ps.container, 'Standard Tube')::TEXT,
      COALESCE(r.price_paisa, 0)::BIGINT,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      'Fixed'::public.catalogue_pricing_policy_enum,
      FALSE,
      ps.reporting_type,
      CASE
        WHEN lower(ps.code) = q.value THEN 100
        WHEN lower(ps.name) = q.value THEN 95
        WHEN lower(ps.code) LIKE q.value || '%' THEN 90
        WHEN lower(ps.name) LIKE q.value || '%' THEN 85
        ELSE 50
      END
    FROM public.catalogue_panel_services ps
    JOIN public.test_categories c ON c.id = ps.category_id
    CROSS JOIN q
    LEFT JOIN public.catalogue_rate_versions r ON r.panel_service_id = ps.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 1
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
  ORDER BY m.item_score DESC, m.item_name ASC
  LIMIT greatest(1, least(COALESCE(p_limit, 30), 100));
END $$;

-- 3. Helper RPC to fetch Panel Components for UI details and validation
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

-- 4. Grant Access Privileges
GRANT EXECUTE ON FUNCTION public.search_billable_catalogue(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_catalogue_panel_components(UUID) TO authenticated;
GRANT SELECT ON public.catalogue_panel_components TO authenticated;
GRANT SELECT ON public.test_aliases TO authenticated;
GRANT SELECT ON public.assay_specimen_governance_rules TO authenticated;

COMMIT;
