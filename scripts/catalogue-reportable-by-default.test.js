import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql=readFileSync('supabase/migrations/00090_reportable_by_default_technician_exception_control.sql','utf8');
const ui=readFileSync('src/features/catalogue/CatalogueReadinessPanel.tsx','utf8');

test('new active supported tests are ready without approval or price gates',()=>{
 assert.match(sql,/ELSE 'Approved'::public\.catalogue_readiness_state_enum/);
 assert.match(sql,/Ready by default; Lab Technician exception control applies/);
 assert.doesNotMatch(sql,/Fixed production price is not configured|Clinically validated reference ranges are missing/);
});
test('genuine result and specimen invariants remain',()=>{
 for(const value of ['Required result structure is missing','Required specimen/container configuration is missing','A qualitative result vocabulary is missing','Approved calculation formula']) assert.ok(sql.includes(value),value);
});
test('technician exception decisions are server authoritative and audited',()=>{
 assert.match(sql,/PERFORM public\.catalogue_require_readiness_staff\(\)/);
 for(const value of ['MarkReady','MarkReportable','NeedsConfiguration','Suspend','Reactivate','MarkNonReportable']) assert.ok(sql.includes(value),value);
 assert.match(sql,/INSERT INTO public\.catalogue_configuration_evidence/);
 assert.match(sql,/previous_state,new_state,reason,actor_id,actor_role/);
});
test('machine, inactive and anonymous identities remain denied by readiness guard and grants',()=>{
 assert.match(sql,/REVOKE ALL ON FUNCTION public\.catalogue_decide_readiness[\s\S]*PUBLIC,anon,authenticated,service_role/);
 assert.doesNotMatch(sql,/GRANT EXECUTE ON FUNCTION public\.catalogue_decide_readiness[^\n]*service_role/);
});
test('reconciliation is exact and preserves explicit decisions',()=>{
 assert.match(sql,/decision_reason='Catalogue test entered readiness governance\.'/);
 assert.match(sql,/NOT EXISTS\(SELECT 1 FROM public\.catalogue_configuration_evidence/);
 assert.match(sql,/Explicit suspension, non-reporting, inactive\/archive, and reviewed decisions are untouched/);
});
test('default readiness metadata does not turn creation into reviewed evidence',()=>{
 const wrapper=sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION public.catalogue_save_test('),sql.indexOf('CREATE OR REPLACE FUNCTION public.catalogue_service_readiness_checklist'));
 assert.doesNotMatch(wrapper,/INSERT INTO public\.catalogue_configuration_evidence/);
});
test('readiness UI is operational rather than approval driven',()=>{
 for(const value of ['Ready & Reportable','Needs Attention','Suspended','Non-Reportable Service','Mark Not Reportable']) assert.ok(ui.includes(value),value);
 for(const value of ['Approve & activate','Submit for review','Technical reviews do not activate reporting']) assert.ok(!ui.includes(value),value);
});
