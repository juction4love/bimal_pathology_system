import { execFileSync } from 'node:child_process';
import fs from 'node:fs';

const container = process.env.ACCEPTANCE_DB_CONTAINER || 'supabase_db_authenticated-00075';
const database = process.env.ACCEPTANCE_DB_NAME || 'lis_remediation_00075';
const sql = `WITH component_owners AS (
 SELECT p.id panel_id,coalesce(pc.component_test_id,owner.id) test_id
 FROM catalogue_panels p LEFT JOIN catalogue_panel_components pc ON pc.panel_id=p.id
 LEFT JOIN parameters prm ON prm.id=pc.component_parameter_id LEFT JOIN tests owner ON owner.id=prm.test_id
), panel_counts AS (
 SELECT panel_id,count(distinct test_id)::int total,
 count(distinct test_id) filter(where catalogue_test_result_readiness(test_id)='Ready')::int ready,
 coalesce(jsonb_agg(distinct jsonb_build_object('code',t.code,'name',t.name,'readiness',catalogue_test_result_readiness(t.id))) filter(where catalogue_test_result_readiness(t.id)<>'Ready'),'[]') unresolved
 FROM component_owners o LEFT JOIN tests t ON t.id=o.test_id GROUP BY panel_id
)
SELECT jsonb_build_object('panel_id',p.id,'panel_name',p.name,'display_order',p.display_order,
 'total_components',coalesce(c.total,0),'ready_components',coalesce(c.ready,0),'unresolved_components',coalesce(c.total-c.ready,0),
 'unresolved',c.unresolved,'billable_identity_code',coalesce(ps.code,t.code),'billable_identity_kind',case when ps.id is null then 'Test' else 'Panel' end,
 'active_rate_count',coalesce((select count(*) from catalogue_rate_versions r where (r.panel_service_id=ps.id or r.test_id=t.id) and r.status='Active'),0),
 'full_result_entry_possible',coalesce(c.total-c.ready,0)=0)
FROM catalogue_panels p LEFT JOIN panel_counts c ON c.panel_id=p.id LEFT JOIN catalogue_panel_services ps ON ps.panel_id=p.id LEFT JOIN tests t ON t.id=p.id ORDER BY p.display_order`;
const output = execFileSync('docker', ['exec', container, 'psql', '-U', 'postgres', '-d', database, '-At', '-c', sql], { encoding: 'utf8' });
const panels = output.trim().split(/\r?\n/).filter(Boolean).map(JSON.parse);
const artifact = {
  generated_at: new Date().toISOString(),
  environment: 'isolated 00000→00075; migration 00070 excluded',
  panel_count: panels.length,
  generic_ready_panels: panels.filter((p) => p.full_result_entry_possible).length,
  specialist_non_generic_panels: panels.filter((p) => !p.full_result_entry_possible).map((p) => p.panel_name),
  panels,
};
fs.writeFileSync('qa-artifacts/catalogue-00075/panel-readiness-final.json', `${JSON.stringify(artifact, null, 2)}\n`);
console.log(JSON.stringify({ panel_count: artifact.panel_count, generic_ready_panels: artifact.generic_ready_panels, specialist_non_generic_panels: artifact.specialist_non_generic_panels }));
