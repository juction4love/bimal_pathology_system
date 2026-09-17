import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const ui=fs.readFileSync('src/features/catalogue/CatalogueCompletionQueue.tsx','utf8');
const migration=fs.readFileSync('supabase/migrations/00075_catalogue_readiness_approval_workflow.sql','utf8');
const extract=(name)=>JSON.parse(`[${ui.match(new RegExp(`const ${name} = \\[([^;]+)\\];`))[1].replaceAll("'",'"')}]`);

test('completion queue contains only the exact current actions',()=>{
  assert.equal(extract('structureCodes').length,33);
  assert.equal(extract('optionCodes').length,13);
  assert.equal(extract('priceCodes').length,10);
  assert.doesNotMatch(ui,/178 incomplete/i);
});

test('queues are live and completed items disappear',()=>{
  assert.match(ui,/!structurallyValid\(test\)/);
  assert.match(ui,/status==='Active'&&rate\.price_paisa!=null/);
  assert.match(ui,/await load\(\)/);
  assert.match(ui,/Result structures remaining:/);
  assert.match(ui,/Qualitative selections remaining:/);
  assert.match(ui,/Prices remaining:/);
});

test('technician configuration uses narrow guarded RPCs',()=>{
  assert.match(ui,/catalogue_set_parameter_option_set/);
  assert.match(ui,/catalogue_save_option_set/);
  assert.match(ui,/catalogue_save_option_value/);
  assert.match(migration,/catalogue_require_technical[\s\S]*can_configure_catalogue_technical/);
  assert.match(migration,/catalogue_set_parameter_option_set[\s\S]*catalogue_require_technical/);
});

test('price completion is manager-only, versioned, and future-safe',()=>{
  assert.match(ui,/disabled=\{!canManage\}/);
  assert.match(ui,/catalogue_create_rate_version/);
  assert.match(ui,/catalogue_activate_rate/);
  assert.match(ui,/Historical bill prices are unchanged/);
  assert.match(migration,/catalogue_create_rate_version[\s\S]*catalogue_require_manager/);
});

test('option vocabulary is never selected automatically',()=>{
  assert.match(ui,/<em>No selection<\/em>/);
  assert.match(ui,/Creating a vocabulary does not assign it automatically/);
  assert.doesNotMatch(ui,/defaultValue=.*POSITIVE_NEGATIVE/);
});
