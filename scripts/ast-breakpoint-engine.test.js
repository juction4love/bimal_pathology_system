import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations/00075_catalogue_readiness_approval_workflow.sql', import.meta.url), 'utf8');
const ui = readFileSync(new URL('../src/features/worklist/AstCultureResultEntry.tsx', import.meta.url), 'utf8');
const report = readFileSync(new URL('../src/features/reports/ReportDocument.tsx', import.meta.url), 'utf8');

test('AST baseline is explicitly local, versioned and immutable after use', () => {
  assert.match(migration, /Operator-approved local breakpoint baseline/);
  assert.match(migration, /CREATE TABLE public\.ast_breakpoint_sets/);
  assert.match(migration, /UNIQUE\(name,version\)/);
  assert.match(migration, /Historically used breakpoint versions are immutable; clone a new version/);
  assert.doesNotMatch(migration, /current CLSI|current EUCAST/i);
});

test('three canonical groups and all 23 antibiotic identities are seeded', () => {
  for (const code of ['STAPHYLOCOCCUS_SPP', 'ENTEROBACTERALES', 'PSEUDOMONAS_AERUGINOSA']) assert.ok(migration.includes(code));
  for (const code of ['AB_FOX','AB_PEN','AB_CIP','AB_CLI','AB_ERY','AB_GEN','AB_LZD','AB_COT','AB_DOX','AB_VAN','AB_AMP','AB_AMC','AB_TZP','AB_CTX','AB_CTR','AB_CAZ','AB_FEP','AB_MEM','AB_IPM','AB_AMK','AB_LEV','AB_TOB','AB_COL']) assert.ok(migration.includes(`'${code}'`));
  assert.match(migration, /AST_ANTIBIOTIC_MASTER_COUNT_INVALID/);
});

test('structured NUMERIC thresholds preserve S, I, R, SDD and compound MIC components', () => {
  assert.match(migration, /susceptible_min NUMERIC/);
  assert.match(migration, /intermediate_secondary_min NUMERIC/);
  assert.match(migration, /resistant_secondary NUMERIC/);
  assert.match(migration, /intermediate_semantics TEXT[\s\S]*'SDD'/);
  assert.match(migration, /'ENTEROBACTERALES','AB_FEP','Disk','30 µg',TRUE,25[\s\S]*19,24[\s\S]*'SDD'/);
});

test('invalid disk methods and resistance-mechanism inference fail safely', () => {
  assert.match(migration, /'STAPHYLOCOCCUS_SPP','AB_VAN','Disk',NULL,FALSE/);
  assert.match(migration, /'PSEUDOMONAS_AERUGINOSA','AB_COL','Disk',NULL,FALSE/);
  assert.match(migration, /MIC required for breakpoint interpretation/);
  assert.match(migration, /'mechanism_inference',FALSE/);
  assert.match(migration, /MRSA surrogate/);
});

test('manual overrides are reasoned, audited and revision protected', () => {
  assert.match(migration, /Manual interpretation or override requires an explicit reason/);
  assert.match(migration, /AST_INTERPRETATION_OVERRIDDEN/);
  assert.match(migration, /AST observation changed\. Reload before saving/);
  assert.match(migration, /can_manage_ast_breakpoints/);
});

test('specialist UI and frozen report expose clinical AST data without internal rule IDs', () => {
  for (const label of ['Organism', 'Zone/MIC', 'Automatic Interpretation', 'Final Interpretation', 'Override reason']) assert.ok(ui.includes(label));
  assert.match(ui, /No approved breakpoint configured/);
  assert.match(report, /isolate\.observations/);
  assert.match(report, /breakpoint_reference/);
  assert.doesNotMatch(report, /breakpoint_rule_id/);
});
