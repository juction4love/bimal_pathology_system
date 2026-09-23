import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { isReportableWorklistItem, splitWorklistPage, worklistCursor } from '../src/features/worklist/worklistQuery.ts';

const migration = fs.readFileSync('supabase/migrations_legacy_archive/00072_worklist_server_search_pagination.sql','utf8');
const page = (count) => Array.from({length:count},(_,index)=>({
  id:`00000000-0000-4000-8000-${String(index).padStart(12,'0')}`,
  created_at:new Date(Date.UTC(2026,0,1,0,0,200-index)).toISOString(),
}));

test('an exact Lab No is evaluated server-side, outside any initial page',()=>{
  assert.match(migration,/term~\*'\^BPDC-\[0-9\]\{8\}\$' AND o\.order_number=upper\(term\)/);
  assert.match(migration,/p_search TEXT DEFAULT NULL/);
  assert.doesNotMatch(migration,/LIMIT 150/i);
});

test('patient and identifier searches run in the bounded server query',()=>{
  for(const expression of ['lower(p.full_name)','lower(p.uhid)','lower(o.order_number)','lower(COALESCE(s.barcode','lower(coi.test_name)']){
    assert.ok(migration.includes(expression),expression);
  }
  assert.match(migration,/LIMIT p_limit\+1/);
});

test('status views are also server-side so page-local filtering cannot omit matches',()=>{
  assert.match(migration,/p_view TEXT DEFAULT 'All'/);
  assert.match(migration,/p_view='ToVerify'/);
  assert.match(migration,/pending_result\.status='SubmittedForVerification'/);
  assert.match(migration,/p_view='Signed'/);
});

test('more than 150 rows paginate without omission or duplicates',()=>{
  const all=page(201);
  const p1=splitWorklistPage(all.slice(0,51));
  const p2=splitWorklistPage(all.slice(50,101));
  const p3=splitWorklistPage(all.slice(100,151));
  const p4=splitWorklistPage(all.slice(150,201));
  assert.equal(p1.rows.length,50); assert.equal(p4.rows.length,50);
  assert.equal(p1.hasNext,true); assert.equal(p4.hasNext,true);
  const displayed=[...p1.rows,...p2.rows,...p3.rows,...p4.rows];
  assert.equal(new Set(displayed.map(x=>x.id)).size,200);
  assert.deepEqual(worklistCursor(p1.rows.at(-1)),{createdAt:p1.rows.at(-1).created_at,id:p1.rows.at(-1).id});
});

test('stable compound cursor and ordering are enforced',()=>{
  assert.match(migration,/\(coi\.created_at,coi\.id\)<\(p_cursor_created_at,p_cursor_id\)/);
  assert.match(migration,/ORDER BY coi\.created_at DESC,coi\.id DESC/);
  assert.match(migration,/clinical_order_items\(created_at DESC,id DESC\)/);
});

test('clinical eligibility remains fail closed',()=>{
  assert.equal(isReportableWorklistItem({clinical_reporting_enabled:true,reporting_type:'InHouse'}),true);
  assert.equal(isReportableWorklistItem({clinical_reporting_enabled:true,reporting_type:'OutsourceWithBimalReport'}),true);
  assert.equal(isReportableWorklistItem({reporting_type:'InHouse'}),true);
  assert.equal(isReportableWorklistItem({reporting_type:'NoReporting'}),false);
  assert.match(migration,/coi\.reporting_type IN \('InHouse','OutsourceWithBimalReport'\)/);
});

test('RPC preserves RLS and narrow authenticated grant',()=>{
  assert.match(migration,/SECURITY INVOKER/);
  assert.match(migration,/FROM PUBLIC,anon,service_role/);
  assert.match(migration,/TO authenticated/);
  assert.doesNotMatch(migration,/SECURITY DEFINER/);
});
