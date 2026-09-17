-- HMIS 9.5-style non-public facility monthly reporting.
-- Stores configuration, manual values and immutable finalized snapshots only.

INSERT INTO public.role_permissions(role_id,permission_key)
VALUES
('00000000-0000-0000-0000-000000000001','can_view_hmis_reports'),
('00000000-0000-0000-0000-000000000001','can_edit_hmis_reports'),
('00000000-0000-0000-0000-000000000001','can_finalize_hmis_reports')
ON CONFLICT DO NOTHING;

CREATE TABLE public.hmis_facility_configuration(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_key text NOT NULL DEFAULT 'primary' UNIQUE,
 configuration jsonb NOT NULL DEFAULT '{}'::jsonb, updated_by uuid REFERENCES public.user_profiles(id),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.hmis_monthly_reports(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), report_month date NOT NULL CHECK(date_trunc('month',report_month)=report_month),
 fiscal_year text NOT NULL, reference_no text, status text NOT NULL DEFAULT 'Draft' CHECK(status IN ('Draft','Finalized','Submitted')),
 current_version integer NOT NULL DEFAULT 0 CHECK(current_version>=0), created_by uuid NOT NULL REFERENCES public.user_profiles(id),
 finalized_by uuid REFERENCES public.user_profiles(id), finalized_at timestamptz, submitted_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(report_month)
);
CREATE TABLE public.hmis_monthly_manual_values(
 report_id uuid PRIMARY KEY REFERENCES public.hmis_monthly_reports(id) ON DELETE CASCADE,
 values_json jsonb NOT NULL DEFAULT '{}'::jsonb, updated_by uuid NOT NULL REFERENCES public.user_profiles(id), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.hmis_monthly_report_versions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), report_id uuid NOT NULL REFERENCES public.hmis_monthly_reports(id) ON DELETE RESTRICT,
 version integer NOT NULL CHECK(version>0), snapshot_json jsonb NOT NULL, sha256 text NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'),
 generated_by uuid NOT NULL REFERENCES public.user_profiles(id), finalized_by uuid NOT NULL REFERENCES public.user_profiles(id), finalized_at timestamptz NOT NULL DEFAULT now(), parent_version integer,
 revision_reason text, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(report_id,version)
);
ALTER TABLE public.hmis_monthly_report_versions ADD CONSTRAINT hmis_version_parent_fk FOREIGN KEY(report_id,parent_version) REFERENCES public.hmis_monthly_report_versions(report_id,version) ON DELETE RESTRICT;
CREATE TABLE public.hmis_submission_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), report_id uuid NOT NULL REFERENCES public.hmis_monthly_reports(id) ON DELETE RESTRICT,
 report_version integer NOT NULL, submitted boolean NOT NULL DEFAULT true, submission_date date NOT NULL,
 submitted_to text NOT NULL, method text NOT NULL CHECK(method IN ('Physical','Email','Portal','Other')),
 reference_receipt_no text, remarks text, attachment_path text, recorded_by uuid NOT NULL REFERENCES public.user_profiles(id), created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(report_id,report_version) REFERENCES public.hmis_monthly_report_versions(report_id,version) ON DELETE RESTRICT
);

CREATE INDEX hmis_versions_report_idx ON public.hmis_monthly_report_versions(report_id,version DESC);
CREATE INDEX hmis_submission_report_idx ON public.hmis_submission_events(report_id,created_at DESC);
ALTER TABLE public.hmis_facility_configuration ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hmis_monthly_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hmis_monthly_manual_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hmis_monthly_report_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hmis_submission_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY hmis_config_read ON public.hmis_facility_configuration FOR SELECT TO authenticated USING(public.has_permission('can_view_hmis_reports'));
CREATE POLICY hmis_config_write ON public.hmis_facility_configuration FOR ALL TO authenticated USING(public.has_permission('can_edit_hmis_reports')) WITH CHECK(public.has_permission('can_edit_hmis_reports'));
CREATE POLICY hmis_reports_read ON public.hmis_monthly_reports FOR SELECT TO authenticated USING(public.has_permission('can_view_hmis_reports'));
CREATE POLICY hmis_reports_create ON public.hmis_monthly_reports FOR INSERT TO authenticated WITH CHECK(public.has_permission('can_edit_hmis_reports') AND created_by=auth.uid());
CREATE POLICY hmis_manual_read ON public.hmis_monthly_manual_values FOR SELECT TO authenticated USING(public.has_permission('can_view_hmis_reports'));
CREATE POLICY hmis_manual_write ON public.hmis_monthly_manual_values FOR ALL TO authenticated USING(public.has_permission('can_edit_hmis_reports') AND EXISTS(SELECT 1 FROM public.hmis_monthly_reports r WHERE r.id=report_id AND r.status='Draft')) WITH CHECK(public.has_permission('can_edit_hmis_reports') AND updated_by=auth.uid() AND EXISTS(SELECT 1 FROM public.hmis_monthly_reports r WHERE r.id=report_id AND r.status='Draft'));
CREATE POLICY hmis_versions_read ON public.hmis_monthly_report_versions FOR SELECT TO authenticated USING(public.has_permission('can_view_hmis_reports'));
CREATE POLICY hmis_submissions_read ON public.hmis_submission_events FOR SELECT TO authenticated USING(public.has_permission('can_view_hmis_reports'));

CREATE OR REPLACE FUNCTION public.hmis_auto_summary(p_month date) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
 WITH bounds AS (SELECT date_trunc('month',p_month)::date s,(date_trunc('month',p_month)+interval '1 month')::date e),
 registered AS (SELECT p.id,p.gender,COALESCE(p.dob,(p.created_at AT TIME ZONE 'Asia/Kathmandu')::date-make_interval(years=>COALESCE(p.age_years,0),months=>COALESCE(p.age_months,0),days=>COALESCE(p.age_days,0))) dob FROM patients p,bounds b WHERE p.created_at>=b.s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND p.created_at<b.e::timestamp AT TIME ZONE 'Asia/Kathmandu'),
 age_counts AS (SELECT CASE WHEN age<1 THEN '<1 Year' WHEN age<5 THEN '1–4 Years' WHEN age<10 THEN '5–9 Years' WHEN age<15 THEN '10–14 Years' WHEN age<20 THEN '15–19 Years' WHEN age<30 THEN '20–29 Years' WHEN age<60 THEN '30–59 Years' WHEN age<70 THEN '60–69 Years' ELSE '70+ Years' END grp,gender,count(*) n FROM (SELECT gender,extract(year FROM age((SELECT s FROM bounds),dob))::int age FROM registered) x GROUP BY 1,2),
 ages AS (SELECT COALESCE(jsonb_object_agg(grp,counts),'{}') value FROM (SELECT grp,jsonb_build_object('Female',sum(n) FILTER(WHERE gender='Female'),'Male',sum(n) FILTER(WHERE gender='Male')) counts FROM age_counts GROUP BY grp)y),
 metrics AS (SELECT
 (SELECT count(*) FROM registered) registered_patients,
 (SELECT count(*) FROM bills,bounds WHERE created_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND created_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu') bills_visits,
 (SELECT count(*) FROM clinical_order_items,bounds WHERE created_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND created_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu') investigations,
 (SELECT count(*) FROM clinical_order_items,bounds WHERE updated_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND updated_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu' AND status IN('Verified','SignedOff')) completed_tests,
 (SELECT count(*) FROM clinical_order_items,bounds WHERE created_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND created_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu' AND reporting_type='OutsourceWithBimalReport') outsource_count,
 (SELECT count(*) FROM diagnostic_reports,bounds WHERE created_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND created_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu') report_count,
 (SELECT count(*) FROM samples,bounds WHERE created_at>=s::timestamp AT TIME ZONE 'Asia/Kathmandu' AND created_at<e::timestamp AT TIME ZONE 'Asia/Kathmandu') sample_count)
 SELECT jsonb_build_object('registeredPatients',registered_patients,'totalBillsVisits',bills_visits,'totalInvestigations',investigations,'completedTests',completed_tests,'outsourceCount',outsource_count,'reportCount',report_count,'sampleCount',sample_count,'newClientsByAgeSex',ages.value)
 FROM metrics,ages WHERE public.has_permission('can_view_hmis_reports');
$$;
REVOKE ALL ON FUNCTION public.hmis_auto_summary(date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.hmis_auto_summary(date) TO authenticated;

CREATE OR REPLACE FUNCTION public.hmis_identity_options() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT COALESCE(jsonb_agg(x ORDER BY x->>'name'),'[]'::jsonb) FROM (
  SELECT jsonb_build_object('source','ReportingPersonnel','id',rp.id,'name',rp.full_name,'designation',concat_ws(', ',rp.professional_type::text,nullif(rp.qualification,'')),'signatureUrl',rp.signature_url) x FROM reporting_personnel rp WHERE rp.is_active
  UNION ALL
  SELECT jsonb_build_object('source','Staff','id',up.id,'name',up.full_name,'designation',COALESCE((SELECT string_agg(r.name,', ' ORDER BY r.name) FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=up.id),'Staff'),'signatureUrl',NULL) FROM user_profiles up WHERE up.is_active
 ) options WHERE public.has_permission('can_view_hmis_reports');
$$;
REVOKE ALL ON FUNCTION public.hmis_identity_options() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.hmis_identity_options() TO authenticated;

CREATE OR REPLACE FUNCTION public.finalize_hmis_report(p_report_id uuid,p_snapshot jsonb,p_revision_reason text DEFAULT NULL) RETURNS public.hmis_monthly_report_versions LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
DECLARE r public.hmis_monthly_reports; v public.hmis_monthly_report_versions; n int; h text;
BEGIN
 IF NOT public.has_permission('can_finalize_hmis_reports') THEN RAISE EXCEPTION 'HMIS finalize permission required' USING ERRCODE='42501'; END IF;
 SELECT * INTO r FROM public.hmis_monthly_reports WHERE id=p_report_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'HMIS report not found'; END IF;
 IF r.current_version>0 AND nullif(trim(p_revision_reason),'') IS NULL THEN RAISE EXCEPTION 'Revision reason required'; END IF;
 IF p_snapshot::text ~* '"(patientName|patientMobile|patientUhid|patientAddress|mobile|uhid|resultValues|clinicalSnapshot)"\s*:' THEN RAISE EXCEPTION 'Patient-identifiable or clinical-detail keys are forbidden in HMIS snapshots'; END IF;
 n:=r.current_version+1; h:=encode(extensions.digest(convert_to(p_snapshot::text,'UTF8'),'sha256'),'hex');
 IF COALESCE(p_snapshot#>>'{identities,prepared,id}','')='' THEN RAISE EXCEPTION 'Prepared By must be selected explicitly'; END IF;
 INSERT INTO public.hmis_monthly_report_versions(report_id,version,snapshot_json,sha256,generated_by,finalized_by,parent_version,revision_reason) VALUES(p_report_id,n,p_snapshot,h,auth.uid(),auth.uid(),CASE WHEN n>1 THEN n-1 ELSE NULL END,p_revision_reason) RETURNING * INTO v;
 UPDATE public.hmis_monthly_reports SET status='Finalized',current_version=n,finalized_by=auth.uid(),finalized_at=v.finalized_at,updated_at=now() WHERE id=p_report_id;
 RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.finalize_hmis_report(uuid,jsonb,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_hmis_report(uuid,jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.prevent_hmis_version_mutation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Finalized HMIS versions are immutable'; END $$;
CREATE TRIGGER hmis_versions_immutable BEFORE UPDATE OR DELETE ON public.hmis_monthly_report_versions FOR EACH ROW EXECUTE FUNCTION public.prevent_hmis_version_mutation();

CREATE OR REPLACE FUNCTION public.record_hmis_submission(p_report_id uuid,p_submission_date date,p_submitted_to text,p_method text,p_reference text DEFAULT NULL,p_remarks text DEFAULT NULL,p_attachment_path text DEFAULT NULL) RETURNS public.hmis_submission_events LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.hmis_monthly_reports; e public.hmis_submission_events;
BEGIN
 IF NOT public.has_permission('can_finalize_hmis_reports') THEN RAISE EXCEPTION 'HMIS finalize permission required' USING ERRCODE='42501'; END IF;
 SELECT * INTO r FROM public.hmis_monthly_reports WHERE id=p_report_id FOR UPDATE; IF r.current_version=0 THEN RAISE EXCEPTION 'Finalize before submission'; END IF;
 INSERT INTO public.hmis_submission_events(report_id,report_version,submission_date,submitted_to,method,reference_receipt_no,remarks,attachment_path,recorded_by) VALUES(r.id,r.current_version,p_submission_date,p_submitted_to,p_method,p_reference,p_remarks,p_attachment_path,auth.uid()) RETURNING * INTO e;
 UPDATE public.hmis_monthly_reports SET status='Submitted',submitted_at=now(),updated_at=now() WHERE id=r.id; RETURN e;
END $$;
REVOKE ALL ON FUNCTION public.record_hmis_submission(uuid,date,text,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_hmis_submission(uuid,date,text,text,text,text,text) TO authenticated;

COMMENT ON TABLE public.hmis_monthly_report_versions IS 'Append-only immutable HMIS snapshots; clinical source rows are not duplicated.';
