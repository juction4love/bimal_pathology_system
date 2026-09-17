-- CBC V1/V2/V3 source governance only.
-- This migration imports immutable operator-authorized evidence but does not
-- approve a range, activate a parameter/test, or alter historical policies.

CREATE TABLE public.clinical_source_imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_version TEXT NOT NULL UNIQUE,
    source_name TEXT NOT NULL,
    source_sha256 TEXT NOT NULL CHECK (source_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    source_received_on DATE NOT NULL,
    provenance TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID NULL REFERENCES auth.users(id)
);

CREATE TABLE public.clinical_source_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    import_id UUID NOT NULL REFERENCES public.clinical_source_imports(id),
    source_key TEXT NOT NULL,
    canonical_parameter TEXT NOT NULL,
    supplied_value TEXT NOT NULL,
    supplied_unit TEXT NULL,
    supplied_context TEXT NOT NULL DEFAULT 'Unspecified age/applicability',
    source_note TEXT NULL,
    target_test_code TEXT NULL,
    target_parameter_code TEXT NULL,
    normalized_representation JSONB NULL,
    source_classification TEXT NOT NULL CHECK (source_classification IN (
        'AuthorizedUnspecifiedAge',
        'AuthorizedSexSpecificAgeBoundsMissing',
        'AuthorizedContextDependent',
        'AuthorizedApproximateReviewRequired',
        'SourceVersionChanged',
        'SeparateCandidateParameter'
    )),
    conflict_key TEXT NULL,
    review_state TEXT NOT NULL DEFAULT 'PendingTechnicalReview' CHECK (review_state IN (
        'PendingTechnicalReview','DecisionRecorded','ApprovedForMaterialization','Rejected'
    )),
    row_version BIGINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(import_id, source_key)
);

CREATE TABLE public.clinical_source_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_item_id UUID NOT NULL REFERENCES public.clinical_source_items(id),
    decision_version INTEGER NOT NULL CHECK (decision_version > 0),
    action TEXT NOT NULL CHECK (action IN (
        'AcceptSource','RetainOlderPolicy','CorrectLaboratoryPolicy',
        'RestrictApplicability','RejectSource'
    )),
    selected_policy JSONB NOT NULL DEFAULT '{}'::JSONB,
    reason TEXT NOT NULL CHECK (length(btrim(reason)) >= 5),
    status TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN ('Draft','Approved','Superseded')),
    reviewer_id UUID NOT NULL REFERENCES auth.users(id),
    reviewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_by UUID NULL REFERENCES auth.users(id),
    approved_at TIMESTAMPTZ NULL,
    materialized_range_id UUID NULL REFERENCES public.reference_ranges(id),
    row_version BIGINT NOT NULL DEFAULT 1,
    UNIQUE(source_item_id, decision_version),
    CHECK ((status <> 'Approved') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);

ALTER TABLE public.reference_ranges
    ADD COLUMN source_decision_id UUID NULL REFERENCES public.clinical_source_decisions(id),
    ADD COLUMN supplied_value_snapshot TEXT NULL,
    ADD COLUMN supplied_unit_snapshot TEXT NULL,
    ADD COLUMN normalized_source_snapshot JSONB NULL,
    ADD COLUMN policy_version INTEGER NULL;

CREATE UNIQUE INDEX reference_ranges_source_decision_unique
    ON public.reference_ranges(source_decision_id)
    WHERE source_decision_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.reject_clinical_source_evidence_mutation()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
    RAISE EXCEPTION 'Clinical source evidence is immutable; import a successor source version.'
      USING ERRCODE='55000';
END $$;

CREATE TRIGGER clinical_source_imports_immutable
BEFORE UPDATE OR DELETE ON public.clinical_source_imports
FOR EACH ROW EXECUTE FUNCTION public.reject_clinical_source_evidence_mutation();

CREATE TRIGGER clinical_source_items_immutable_content
BEFORE DELETE ON public.clinical_source_items
FOR EACH ROW EXECUTE FUNCTION public.reject_clinical_source_evidence_mutation();

CREATE OR REPLACE FUNCTION public.guard_clinical_source_item_update()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
    IF (to_jsonb(NEW) - ARRAY['review_state','row_version'])
       IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['review_state','row_version']) THEN
        RAISE EXCEPTION 'Imported clinical source content is immutable.' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER clinical_source_items_guard
BEFORE UPDATE ON public.clinical_source_items
FOR EACH ROW EXECUTE FUNCTION public.guard_clinical_source_item_update();

ALTER TABLE public.clinical_source_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_source_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_source_decisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY clinical_source_imports_manager_read ON public.clinical_source_imports
FOR SELECT TO authenticated USING (public.has_permission('can_manage_catalogue'));
CREATE POLICY clinical_source_items_manager_read ON public.clinical_source_items
FOR SELECT TO authenticated USING (public.has_permission('can_manage_catalogue'));
CREATE POLICY clinical_source_decisions_manager_read ON public.clinical_source_decisions
FOR SELECT TO authenticated USING (public.has_permission('can_manage_catalogue'));

REVOKE ALL ON public.clinical_source_imports,public.clinical_source_items,public.clinical_source_decisions FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.clinical_source_imports,public.clinical_source_items,public.clinical_source_decisions TO authenticated;

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

CREATE OR REPLACE FUNCTION public.catalogue_approve_clinical_source_decision(
    p_decision_id UUID,
    p_expected_version BIGINT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.clinical_source_decisions%ROWTYPE;
BEGIN
    PERFORM public.catalogue_require_manager();
    SELECT * INTO v FROM public.clinical_source_decisions WHERE id=p_decision_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Clinical decision not found.' USING ERRCODE='P0002'; END IF;
    IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Clinical decision changed. Reload latest.' USING ERRCODE='PT409'; END IF;
    IF v.status<>'Draft' THEN RAISE EXCEPTION 'Only a Draft decision may be approved.' USING ERRCODE='23514'; END IF;
    IF v.action<>'RejectSource' AND (
       NULLIF(btrim(v.selected_policy->>'applicability_basis'),'') IS NULL OR
       NULLIF(btrim(v.selected_policy->>'method_or_analyzer_context'),'') IS NULL OR
       NOT (v.selected_policy ? 'critical_limits_reviewed') OR
       NOT (v.selected_policy ? 'age_min_days') OR NOT (v.selected_policy ? 'age_max_days') OR
       NULLIF(btrim(v.selected_policy->>'gender'),'') IS NULL OR
       NULLIF(btrim(v.selected_policy->>'unit'),'') IS NULL
    ) THEN
       RAISE EXCEPTION 'Clinical approval requires complete age, sex, applicability, method/analyzer, unit, and critical-limit review.' USING ERRCODE='23514';
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
           jsonb_build_object('source_item_id',v.source_item_id,'action',v.action));
END $$;

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

CREATE OR REPLACE VIEW public.clinical_source_review_matrix
WITH (security_invoker=true) AS
SELECT i.source_version,i.source_name,s.id source_item_id,s.source_key,s.canonical_parameter,
       s.supplied_value,s.supplied_unit,s.supplied_context,s.source_note,s.source_classification,
       s.conflict_key,s.target_test_code,s.target_parameter_code,s.normalized_representation,
       s.review_state,s.row_version,
       d.id decision_id,d.decision_version,d.action selected_action,d.selected_policy,d.reason,
       d.status decision_status,d.reviewer_id,d.reviewed_at,d.approved_by,d.approved_at,d.materialized_range_id,d.row_version decision_row_version,
       p.id current_parameter_id,
       COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'min',r.normal_min,'max',r.normal_max,'text',r.normal_text,
          'unit',r.unit,'sex',r.gender,'age_min_days',r.age_min_days,'age_max_days',r.age_max_days,
          'validation',r.validation_state,'lifecycle',r.lifecycle_status) ORDER BY r.created_at)
          FROM public.reference_ranges r WHERE r.parameter_id=p.id),'[]'::JSONB) current_lis_policies
FROM public.clinical_source_items s
JOIN public.clinical_source_imports i ON i.id=s.import_id
LEFT JOIN public.tests t ON t.code=s.target_test_code
LEFT JOIN public.parameters p ON p.test_id=t.id AND p.code=s.target_parameter_code
LEFT JOIN LATERAL (
    SELECT x.* FROM public.clinical_source_decisions x WHERE x.source_item_id=s.id
    ORDER BY x.decision_version DESC LIMIT 1
) d ON TRUE;

GRANT SELECT ON public.clinical_source_review_matrix TO authenticated;

CREATE OR REPLACE FUNCTION public.catalogue_cbc_source_completeness()
RETURNS TABLE(parameter_code TEXT,mandatory BOOLEAN,v3_source_status TEXT,technical_decision_status TEXT,current_validated_policy BOOLEAN,blocker TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
WITH required(code) AS (VALUES ('HB'),('TLC'),('NEUT'),('LYMPH'),('EOSIN'),('MONO'),('BASO'),('RBC'),('PCV'),('MCV'),('MCH'),('MCHC'),('RDW'),('PLT')),
v3 AS (
 SELECT target_parameter_code code,
        CASE WHEN bool_or(source_classification='AuthorizedApproximateReviewRequired') THEN 'Approximate'
             WHEN bool_or(source_classification='AuthorizedContextDependent') THEN 'ContextDependent'
             WHEN bool_or(source_classification='SourceVersionChanged') THEN 'SourceVersionChanged'
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
            WHEN v3.status='ContextDependent' THEN 'CBC_APPLICABILITY_INCOMPLETE'
            WHEN v3.status='SourceVersionChanged' THEN 'CBC_SOURCE_CONFLICT'
            WHEN v3.review_state<>'ApprovedForMaterialization' THEN 'CBC_TECHNICAL_DECISION_REQUIRED'
            ELSE NULL END
FROM required r LEFT JOIN v3 ON v3.code=r.code ORDER BY array_position(ARRAY['HB','TLC','NEUT','LYMPH','EOSIN','MONO','BASO','RBC','PCV','MCV','MCH','MCHC','RDW','PLT'],r.code);
$$;

REVOKE ALL ON FUNCTION public.catalogue_record_clinical_source_decision(UUID,TEXT,JSONB,TEXT,BIGINT),
 public.catalogue_approve_clinical_source_decision(UUID,BIGINT),
 public.catalogue_materialize_clinical_source_decision(UUID,BIGINT),
 public.catalogue_cbc_source_completeness() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_record_clinical_source_decision(UUID,TEXT,JSONB,TEXT,BIGINT),
 public.catalogue_approve_clinical_source_decision(UUID,BIGINT),
 public.catalogue_materialize_clinical_source_decision(UUID,BIGINT),
 public.catalogue_cbc_source_completeness() TO authenticated;

INSERT INTO public.clinical_source_imports(id,source_version,source_name,source_sha256,source_received_on,provenance)
VALUES
 ('61000000-0000-0000-0000-000000000001','CBC-V1','Bimal Pathology operator-authorized hematology dataset V1','c7c26d2a7ccef1ce7f90de57354965a984561a75453854a9d806229ea0ea8f33','2026-08-28','Operator-provided source; governance input, not automatic clinical validation'),
 ('61000000-0000-0000-0000-000000000002','CBC-V2','Bimal Pathology operator-authorized clinical dataset V2','2e455b25698b7bf97e3d5566651a73c7bbb49d8eae9012730b74d535e8bba923','2026-08-28','Operator-provided source; governance input, not automatic clinical validation'),
 ('61000000-0000-0000-0000-000000000003','CBC-V3','Bimal Pathology operator-authorized CBC/Differential/RBC/Platelet dataset V3','b76dd0154e2a8ce6fa0858b003e25316bd1280765d24c6d339740be7c118dd91','2026-08-28','Operator-authorized V3 source evidence; supersession requires explicit technical decision');

WITH data(version,key,name,value,unit,context,note,test_code,param_code,normalized,class,conflict) AS (VALUES
-- V1 evidence
('CBC-V1','HB','Hemoglobin','11.0–18.0','g/dL','Unspecified age/sex','Varies by hospital (Hetauda 11–16.5; TU Teaching 13.5–18)','CBC','HB','{"normal_min":11.0,"normal_max":18.0,"unit":"g/dL"}'::jsonb,'AuthorizedContextDependent','CBC.HB'),
('CBC-V1','TLC','TLC/WBC','4.0–10.0','×10³/mm³','Unspecified age','', 'CBC','TLC','{"normal_min":4000,"normal_max":10000,"unit":"/cumm","conversion":"multiply supplied bounds by 1000; 1 mm3 = 1 cumm"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.TLC'),
('CBC-V1','RBC','RBC Count','4.0–6.5','million/mm³','Unspecified age/sex','Hetauda hospital range','CBC','RBC','{"normal_min":4.0,"normal_max":6.5,"unit":"million/cumm","conversion":"1 mm3 = 1 cumm"}'::jsonb,'AuthorizedContextDependent','CBC.RBC'),
('CBC-V1','PLT','Platelet Count','150,000–350,000','/mm³','Unspecified age','', 'CBC','PLT','{"normal_min":150000,"normal_max":350000,"unit":"/cumm","conversion":"1 mm3 = 1 cumm"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.PLT'),
('CBC-V1','ESR','ESR (Westergren)','0–10','mm/hr','Westergren; age/sex unspecified','', 'ESR','ESR','{"normal_min":0,"normal_max":10,"unit":"mm/hr","method":"Westergren"}'::jsonb,'AuthorizedUnspecifiedAge','ESR.WESTERGREN'),
('CBC-V1','MCV','MCV','80–100','fL','Unspecified age/sex','Approximate','CBC','MCV','{"normal_min":80,"normal_max":100,"unit":"fL"}'::jsonb,'AuthorizedApproximateReviewRequired','CBC.MCV'),
('CBC-V1','MCH','MCH','27–33','pg','Unspecified age/sex','Approximate','CBC','MCH','{"normal_min":27,"normal_max":33,"unit":"pg"}'::jsonb,'AuthorizedApproximateReviewRequired','CBC.MCH'),
('CBC-V1','MCHC','MCHC','32–36','g/dL','Unspecified age/sex','Approximate','CBC','MCHC','{"normal_min":32,"normal_max":36,"unit":"g/dL"}'::jsonb,'AuthorizedApproximateReviewRequired','CBC.MCHC'),
('CBC-V1','MPV','MPV','7–11','fL','Unspecified age/sex','Approximate',NULL,NULL,'{"normal_min":7,"normal_max":11,"unit":"fL"}'::jsonb,'AuthorizedApproximateReviewRequired','PLATELET.MPV'),
('CBC-V1','RDW','RDW-CV','11.5–14.5','%','Unspecified age/sex','Approximate','CBC','RDW','{"normal_min":11.5,"normal_max":14.5,"unit":"%"}'::jsonb,'AuthorizedApproximateReviewRequired','CBC.RDW'),
('CBC-V1','PDW','PDW','25–65','%','Unspecified age/sex','Approximate',NULL,NULL,'{"normal_min":25,"normal_max":65,"unit":"%"}'::jsonb,'AuthorizedApproximateReviewRequired','PLATELET.PDW'),
('CBC-V1','NLR','NLR','1–3','ratio','Unspecified age/sex','Approximate',NULL,NULL,'{"normal_min":1,"normal_max":3,"unit":"ratio"}'::jsonb,'AuthorizedApproximateReviewRequired','CBC.NLR'),
-- V2 evidence
('CBC-V2','HB','Hemoglobin','12–18','gm/dl','Unspecified age/sex','', 'CBC','HB','{"normal_min":12,"normal_max":18,"unit":"g/dL","conversion":"gm/dl to g/dL identity"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.HB'),
('CBC-V2','TLC','TLC/WBC','4–10','×10³/mm³','Unspecified age','', 'CBC','TLC','{"normal_min":4000,"normal_max":10000,"unit":"/cumm","conversion":"multiply supplied bounds by 1000; 1 mm3 = 1 cumm"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.TLC'),
('CBC-V2','RBC','RBC Count','4–5','million/mm³','Unspecified age/sex','', 'CBC','RBC','{"normal_min":4,"normal_max":5,"unit":"million/cumm","conversion":"1 mm3 = 1 cumm"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.RBC'),
('CBC-V2','PLT','Platelet Count','150,000–350,000','/mm³','Unspecified age','', 'CBC','PLT','{"normal_min":150000,"normal_max":350000,"unit":"/cumm","conversion":"1 mm3 = 1 cumm"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.PLT'),
('CBC-V2','ESR','ESR (Westergren)','0–10','mm/hr','Westergren; age/sex unspecified','', 'ESR','ESR','{"normal_min":0,"normal_max":10,"unit":"mm/hr","method":"Westergren"}'::jsonb,'AuthorizedUnspecifiedAge','ESR.WESTERGREN'),
('CBC-V2','MCV','MCV','80–100','fL','Unspecified age/sex','Approximate','CBC','MCV','{"normal_min":80,"normal_max":100,"unit":"fL"}'::jsonb,'AuthorizedApproximateReviewRequired','CBC.MCV'),
('CBC-V2','MCH','MCH','27–33','pg','Unspecified age/sex','Approximate','CBC','MCH','{"normal_min":27,"normal_max":33,"unit":"pg"}'::jsonb,'AuthorizedApproximateReviewRequired','CBC.MCH'),
('CBC-V2','MCHC','MCHC','32–36','g/dL','Unspecified age/sex','Approximate','CBC','MCHC','{"normal_min":32,"normal_max":36,"unit":"g/dL"}'::jsonb,'AuthorizedApproximateReviewRequired','CBC.MCHC'),
('CBC-V2','MPV','MPV','7–11','fL','Unspecified age/sex','Approximate',NULL,NULL,'{"normal_min":7,"normal_max":11,"unit":"fL"}'::jsonb,'AuthorizedApproximateReviewRequired','PLATELET.MPV'),
('CBC-V2','RDW','RDW-CV','11.5–14.5','%','Unspecified age/sex','Approximate','CBC','RDW','{"normal_min":11.5,"normal_max":14.5,"unit":"%"}'::jsonb,'AuthorizedApproximateReviewRequired','CBC.RDW'),
('CBC-V2','PDW','PDW','25–65','%','Unspecified age/sex','Approximate',NULL,NULL,'{"normal_min":25,"normal_max":65,"unit":"%"}'::jsonb,'AuthorizedApproximateReviewRequired','PLATELET.PDW'),
('CBC-V2','NLR','NLR','1–3','ratio','Unspecified age/sex','Approximate',NULL,NULL,'{"normal_min":1,"normal_max":3,"unit":"ratio"}'::jsonb,'AuthorizedApproximateReviewRequired','CBC.NLR'),
-- V3 differential and government-laboratory evidence
('CBC-V3','NEUT_PCT','Neutrophils','40–70','%','Nepal case report; age unspecified','', 'CBC','NEUT','{"normal_min":40,"normal_max":70,"unit":"%"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.NEUT'),
('CBC-V3','LYMPH_PCT','Lymphocytes','20–40','%','Nepal case report; age unspecified','', 'CBC','LYMPH','{"normal_min":20,"normal_max":40,"unit":"%"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.LYMPH'),
('CBC-V3','MONO_PCT','Monocytes','2–10','%','Nepal case report; age unspecified','', 'CBC','MONO','{"normal_min":2,"normal_max":10,"unit":"%"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.MONO'),
('CBC-V3','EOSIN_PCT','Eosinophils','2–6','%','Nepal case report; age unspecified','', 'CBC','EOSIN','{"normal_min":2,"normal_max":6,"unit":"%"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.EOSIN'),
('CBC-V3','BASO_PCT','Basophils','0–1','%','Nepal case report; age unspecified','', 'CBC','BASO','{"normal_min":0,"normal_max":1,"unit":"%"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.BASO'),
('CBC-V3','ANC','Absolute Neutrophil Count','1.78–5.38','×10⁹/L','Frontier research data; age unspecified','Separate candidate; not routine CBC replacement','ANC',NULL,'{"normal_min":1.78,"normal_max":5.38,"unit":"x10^9/L"}'::jsonb,'SeparateCandidateParameter','ABSOLUTE_DLC.ANC'),
('CBC-V3','ALC','Absolute Lymphocyte Count','1.32–3.57','×10⁹/L','Frontier research data; age unspecified','Separate candidate; not routine CBC replacement',NULL,NULL,'{"normal_min":1.32,"normal_max":3.57,"unit":"x10^9/L"}'::jsonb,'SeparateCandidateParameter','ABSOLUTE_DLC.ALC'),
('CBC-V3','AMC','Absolute Monocyte Count','0.62–0.67','×10⁹/L','Frontier research data; age unspecified','Separate candidate; not routine CBC replacement',NULL,NULL,'{"normal_min":0.62,"normal_max":0.67,"unit":"x10^9/L"}'::jsonb,'SeparateCandidateParameter','ABSOLUTE_DLC.AMC'),
('CBC-V3','WBC_GOV','WBC','4–10','×10³/mm³','Phungling Municipality government laboratory; age unspecified','', 'CBC','TLC','{"normal_min":4000,"normal_max":10000,"unit":"/cumm","conversion":"multiply supplied bounds by 1000; 1 mm3 = 1 cumm"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.TLC'),
('CBC-V3','RBC_GOV','RBC','4–5','million/mm³','Phungling Municipality government laboratory; age unspecified','', 'CBC','RBC','{"normal_min":4,"normal_max":5,"unit":"million/cumm","conversion":"1 mm3 = 1 cumm"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.RBC'),
('CBC-V3','PLT_GOV','Platelets','150,000–350,000','/mm³','Phungling Municipality government laboratory; age unspecified','Conflicts inside V3 with platelet-policy upper bound 400,000','CBC','PLT','{"normal_min":150000,"normal_max":350000,"unit":"/cumm","conversion":"1 mm3 = 1 cumm"}'::jsonb,'SourceVersionChanged','CBC.PLT'),
('CBC-V3','ESR_GOV','ESR','0–10','mm/hr','Phungling Municipality government laboratory; method/age/sex unspecified','', 'ESR','ESR','{"normal_min":0,"normal_max":10,"unit":"mm/hr"}'::jsonb,'AuthorizedContextDependent','ESR'),
-- V3 RBC policies
('CBC-V3','HB_M','Hemoglobin — Male','13.5–17.5','g/dL','Male; Nepal healthy adults; numeric adult age bounds unspecified','', 'CBC','HB','{"normal_min":13.5,"normal_max":17.5,"unit":"g/dL","gender":"Male"}'::jsonb,'AuthorizedSexSpecificAgeBoundsMissing','CBC.HB'),
('CBC-V3','HB_F','Hemoglobin — Female','12.0–16.0','g/dL','Female; Nepal healthy adults; numeric adult age bounds unspecified','', 'CBC','HB','{"normal_min":12.0,"normal_max":16.0,"unit":"g/dL","gender":"Female"}'::jsonb,'AuthorizedSexSpecificAgeBoundsMissing','CBC.HB'),
('CBC-V3','PCV_M','Hematocrit / PCV — Male','41–53','%','Male; Nepal healthy adults; numeric adult age bounds unspecified','', 'CBC','PCV','{"normal_min":41,"normal_max":53,"unit":"%","gender":"Male"}'::jsonb,'AuthorizedSexSpecificAgeBoundsMissing','CBC.PCV'),
('CBC-V3','PCV_F','Hematocrit / PCV — Female','36–46','%','Female; Nepal healthy adults; numeric adult age bounds unspecified','', 'CBC','PCV','{"normal_min":36,"normal_max":46,"unit":"%","gender":"Female"}'::jsonb,'AuthorizedSexSpecificAgeBoundsMissing','CBC.PCV'),
('CBC-V3','MCV','MCV','80–100','fL','Nepal healthy adults; numeric adult age bounds unspecified','', 'CBC','MCV','{"normal_min":80,"normal_max":100,"unit":"fL"}'::jsonb,'AuthorizedContextDependent','CBC.MCV'),
('CBC-V3','MCH','MCH','25–35','pg','Nepal healthy adults; numeric adult age bounds unspecified','', 'CBC','MCH','{"normal_min":25,"normal_max":35,"unit":"pg"}'::jsonb,'AuthorizedContextDependent','CBC.MCH'),
('CBC-V3','MCHC','MCHC','31–36','g/dL','Nepal healthy adults; numeric adult age bounds unspecified','', 'CBC','MCHC','{"normal_min":31,"normal_max":36,"unit":"g/dL"}'::jsonb,'AuthorizedContextDependent','CBC.MCHC'),
('CBC-V3','RDW','RDW','11.5–16.0','%','Nepal pediatric study; adult applicability may differ','Do not use as unrestricted adult CBC range','CBC','RDW','{"normal_min":11.5,"normal_max":16.0,"unit":"%"}'::jsonb,'AuthorizedContextDependent','CBC.RDW'),
-- V3 platelet policies
('CBC-V3','PLT_POLICY','Platelet Count','150,000–400,000','/mm³','Unspecified age','V3 upper bound differs from V1/V2 and V3 government evidence','CBC','PLT','{"normal_min":150000,"normal_max":400000,"unit":"/cumm","conversion":"1 mm3 = 1 cumm"}'::jsonb,'SourceVersionChanged','CBC.PLT'),
('CBC-V3','MPV','MPV','7–11','fL','Unspecified age/sex','Approximate',NULL,NULL,'{"normal_min":7,"normal_max":11,"unit":"fL"}'::jsonb,'AuthorizedApproximateReviewRequired','PLATELET.MPV'),
('CBC-V3','PDW','PDW','25–65','%','Unspecified age/sex','Approximate',NULL,NULL,'{"normal_min":25,"normal_max":65,"unit":"%"}'::jsonb,'AuthorizedApproximateReviewRequired','PLATELET.PDW'),
('CBC-V3','P_LCR','P-LCR','15–35','%','Unspecified age/sex','Approximate',NULL,NULL,'{"normal_min":15,"normal_max":35,"unit":"%"}'::jsonb,'AuthorizedApproximateReviewRequired','PLATELET.P_LCR')
)
INSERT INTO public.clinical_source_items(import_id,source_key,canonical_parameter,supplied_value,supplied_unit,supplied_context,source_note,target_test_code,target_parameter_code,normalized_representation,source_classification,conflict_key)
SELECT i.id,d.key,d.name,d.value,d.unit,d.context,NULLIF(d.note,''),d.test_code,d.param_code,d.normalized,d.class,d.conflict
FROM data d JOIN public.clinical_source_imports i ON i.source_version=d.version;

DO $$
DECLARE v_count INT;
BEGIN
 SELECT count(*) INTO v_count FROM public.clinical_source_items s JOIN public.clinical_source_imports i ON i.id=s.import_id WHERE i.source_version IN ('CBC-V1','CBC-V2','CBC-V3');
 IF v_count<>48 THEN RAISE EXCEPTION 'CBC clinical source import expected 48 immutable items, found %.',v_count; END IF;
 IF EXISTS(SELECT 1 FROM public.reference_ranges WHERE source_decision_id IS NOT NULL) THEN RAISE EXCEPTION 'Source import must not materialize clinical policies automatically.'; END IF;
 IF (SELECT clinical_reporting_enabled FROM public.tests WHERE code='CBC') THEN RAISE EXCEPTION 'CBC must remain clinically disabled pending technical decisions.'; END IF;
END $$;
