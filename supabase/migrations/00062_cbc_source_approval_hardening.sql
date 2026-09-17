-- Forward-only hardening for the CBC source-review contract introduced by
-- 00061. Approximate/context-incomplete source evidence cannot be accepted as
-- though it were already a complete laboratory policy, and null applicability
-- bounds cannot pass technical approval.

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

REVOKE ALL ON FUNCTION public.catalogue_approve_clinical_source_decision(UUID,BIGINT),
 public.catalogue_cbc_source_completeness() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_approve_clinical_source_decision(UUID,BIGINT),
 public.catalogue_cbc_source_completeness() TO authenticated;

