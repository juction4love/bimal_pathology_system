import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql=fs.readFileSync('supabase/migrations_legacy_archive/00075_catalogue_readiness_approval_workflow.sql','utf8');
const expected={
  PANEL_CBC_WITH_ABSOLUTE_COUNTS:40000,
  PANEL_KFT_WITHOUT_EGFR:70000,
  PANEL_ELECTROLYTES_PANEL:60000,
  PANEL_ARTHRITIS_PROFILE:350000,
  PANEL_PROTEIN_FRACTION:45000,
  PANEL_TORCH_PROFILE:400000,
  PANEL_AMH_PANEL:250000,
  PANEL_VIRAL_MARKER:120000,
  PANEL_PCOD_PANEL:500000,
  PANEL_CBC_WITH_MORPHOLOGY:50000,
};

test('exact ten operator-approved panel prices are seeded in paisa',()=>{
  for(const [code,price] of Object.entries(expected)) assert.match(sql,new RegExp(`\\('${code}',${price}::BIGINT\\)`),code);
  assert.match(sql,/OPERATOR_PANEL_PRICE_SEED_INCOMPLETE/);
});

test('initial panel rates remain versioned and active',()=>{
  assert.match(sql,/INSERT INTO public\.catalogue_rate_versions\(entity_type,panel_service_id,version_number,price_paisa,effective_from,status\)/);
  assert.match(sql,/SELECT 'Panel',ps\.id,1/);
  assert.match(sql,/THEN 'Draft' ELSE 'Active'/);
  assert.match(sql,/catalogue_rate_one_active_panel/);
});

test('future price changes preserve snapshots and use guarded manager RPCs',()=>{
  assert.match(sql,/catalogue_create_rate_version[\s\S]*catalogue_require_manager/);
  assert.match(sql,/catalogue_activate_rate[\s\S]*status='Inactive'/);
  assert.match(sql,/panel_price_paisa BIGINT NOT NULL/);
  assert.match(sql,/rate_version_id UUID NOT NULL/);
  assert.match(sql,/catalogue_rate_history[\s\S]*used_by_bill_count/);
  assert.match(sql,/catalogue_delete_or_archive_rate[\s\S]*r\.status='Draft'[\s\S]*DELETE FROM public\.catalogue_rate_versions/);
  assert.match(sql,/catalogue_delete_or_archive_rate[\s\S]*ArchivedUsedRate/);
});

test('technician technical permission is not commercial price authority',()=>{
  assert.match(sql,/can_configure_catalogue_technical/);
  assert.doesNotMatch(sql,/catalogue_create_rate_version[\s\S]{0,300}catalogue_require_technical/);
});
