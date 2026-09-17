\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE mixed_results(n int primary key,name text);
GRANT ALL ON mixed_results TO authenticated;
CREATE OR REPLACE FUNCTION pg_temp.ok(n int,name text,condition boolean) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF NOT coalesce(condition,false) THEN RAISE EXCEPTION 'TEST_%_FAILED: %',n,name; END IF; INSERT INTO mixed_results VALUES(n,name); RAISE NOTICE 'PASS %: %',n,name; END$$;
INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES('99300000-0000-0000-0000-000000000001','mixed-tech@example.invalid','{"full_name":"Mixed Runtime Technician"}') ON CONFLICT DO NOTHING;
UPDATE public.user_profiles SET is_active=true,is_super_admin=false WHERE id='99300000-0000-0000-0000-000000000001';
INSERT INTO public.user_roles(user_id,role_id) SELECT '99300000-0000-0000-0000-000000000001',id FROM public.roles WHERE name='Lab Technician' ON CONFLICT DO NOTHING;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','99300000-0000-0000-0000-000000000001',true);

DO $$DECLARE items jsonb[]; response jsonb; repeated jsonb; oid uuid; bid uuid; svc record; first_component boolean:=true; c record;
BEGIN
 SELECT s.id service_id,p.row_version INTO svc FROM public.catalogue_panel_services s JOIN public.catalogue_panels p ON p.id=s.panel_id WHERE s.code='PANEL_ELECTROLYTES_PANEL';
 FOR c IN SELECT x.test_id,x.display_order FROM public.catalogue_panel_service_components(svc.service_id)x ORDER BY x.display_order LOOP
  items:=array_append(items,jsonb_build_object('test_id',c.test_id,'unit_price_paisa',CASE WHEN first_component THEN 50000 ELSE 0 END,'manual_price_paisa',CASE WHEN first_component THEN 50000 ELSE 0 END,'discount_paisa',0,'zero_price_acknowledged',NOT first_component)); first_component:=false;
 END LOOP;
 items:=array_append(items,(SELECT jsonb_build_object('test_id',id,'unit_price_paisa',15000,'manual_price_paisa',15000,'discount_paisa',0,'zero_price_acknowledged',false) FROM public.tests WHERE code='URINE_RE'));
 items:=array_append(items,(SELECT jsonb_build_object('test_id',id,'unit_price_paisa',100000,'manual_price_paisa',100000,'discount_paisa',0,'zero_price_acknowledged',false) FROM public.tests WHERE code='LFT'));
 response:=public.create_patient_bill_order_mixed_catalogue(jsonb_build_object('mobile','9800000192','full_name','Synthetic Mixed Catalogue Patient','gender','Male','age_years',35,'address','Synthetic'),jsonb_build_object('discount_amount_paisa',0,'paid_amount_paisa',0,'order_date_bs','2083-05-15','remarks','rollback mixed runtime'),items,NULL,'mixed-catalogue-00092','[]',svc.service_id,svc.row_version,50000);
 repeated:=public.create_patient_bill_order_mixed_catalogue(jsonb_build_object('mobile','9800000192','full_name','Synthetic Mixed Catalogue Patient','gender','Male','age_years',35,'address','Synthetic'),jsonb_build_object('discount_amount_paisa',0,'paid_amount_paisa',0,'order_date_bs','2083-05-15','remarks','rollback mixed runtime'),items,NULL,'mixed-catalogue-00092','[]',svc.service_id,svc.row_version,50000);
 oid:=(response->>'order_id')::uuid; bid:=(response->>'bill_id')::uuid; PERFORM set_config('mixed.order',oid::text,true); PERFORM set_config('mixed.bill',bid::text,true);
 PERFORM pg_temp.ok(1,'one patient',1=(SELECT count(*) FROM public.patients WHERE mobile='9800000192'));
 PERFORM pg_temp.ok(2,'one bill',1=(SELECT count(*) FROM public.bills WHERE id=bid));
 PERFORM pg_temp.ok(3,'one order',1=(SELECT count(*) FROM public.clinical_orders WHERE id=oid));
 PERFORM pg_temp.ok(4,'expected bill and clinical items',7=(SELECT count(*) FROM public.bill_items WHERE bill_id=bid) AND 7=(SELECT count(*) FROM public.clinical_order_items WHERE order_id=oid));
 PERFORM pg_temp.ok(5,'panel bundled price preserved',50000=(SELECT panel_price_paisa FROM public.bill_panel_selections WHERE bill_id=bid));
 PERFORM pg_temp.ok(6,'standalone and profile prices preserved',15000=(SELECT unit_price_paisa FROM public.bill_items bi JOIN public.tests t ON t.id=bi.test_id WHERE bi.bill_id=bid AND t.code='URINE_RE') AND 100000=(SELECT unit_price_paisa FROM public.bill_items bi JOIN public.tests t ON t.id=bi.test_id WHERE bi.bill_id=bid AND t.code='LFT'));
 PERFORM pg_temp.ok(7,'panel components preserved without recomputation',5=(SELECT count(*) FROM public.bill_panel_components pc JOIN public.bill_panel_selections ps ON ps.id=pc.bill_panel_selection_id WHERE ps.bill_id=bid) AND 50000=(SELECT sum(bi.unit_price_paisa) FROM public.bill_panel_components pc JOIN public.bill_panel_selections ps ON ps.id=pc.bill_panel_selection_id JOIN public.bill_items bi ON bi.id=pc.bill_item_id WHERE ps.bill_id=bid));
 PERFORM pg_temp.ok(8,'immutable price snapshots balance',165000=(SELECT gross_amount_paisa FROM public.bills WHERE id=bid) AND 165000=(SELECT sum(unit_price_paisa) FROM public.bill_items WHERE bill_id=bid));
 PERFORM pg_temp.ok(9,'idempotent repeat returns same identities',response->>'bill_id'=repeated->>'bill_id' AND response->>'order_id'=repeated->>'order_id');
 PERFORM pg_temp.ok(10,'no duplicate items',7=(SELECT count(DISTINCT test_id) FROM public.bill_items WHERE bill_id=bid));
 PERFORM pg_temp.ok(11,'samples use canonical requirement identities',NOT EXISTS(SELECT 1 FROM public.samples WHERE order_id=oid GROUP BY specimen_requirement_key HAVING count(*)>1));
END$$;
DO $$DECLARE svc record; BEGIN SELECT s.id,p.row_version INTO svc FROM public.catalogue_panel_services s JOIN public.catalogue_panels p ON p.id=s.panel_id WHERE s.code='PANEL_ELECTROLYTES_PANEL'; BEGIN PERFORM public.create_patient_bill_order_mixed_catalogue('{"mobile":"9800000192","full_name":"Changed Payload","gender":"Male","age_years":35}'::jsonb,'{"discount_amount_paisa":0,"paid_amount_paisa":1}'::jsonb,ARRAY[]::jsonb[],NULL,'mixed-catalogue-00092','[]',svc.id,svc.row_version,50000); RAISE EXCEPTION 'changed payload accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='changed payload accepted' THEN RAISE; END IF; PERFORM pg_temp.ok(12,'changed-payload idempotency rejected',true); END; END$$;
SELECT pg_temp.ok(13,'full accounting reconciliation',NOT EXISTS(SELECT 1 FROM public.bills b WHERE b.id=current_setting('mixed.bill')::uuid AND (b.gross_amount_paisa<>(SELECT coalesce(sum(unit_price_paisa),0) FROM public.bill_items WHERE bill_id=b.id) OR b.net_amount_paisa<>b.gross_amount_paisa-b.discount_amount_paisa OR b.due_amount_paisa<>b.net_amount_paisa-b.paid_amount_paisa)));
SELECT count(*) passed,0 failed FROM mixed_results;
ROLLBACK;
