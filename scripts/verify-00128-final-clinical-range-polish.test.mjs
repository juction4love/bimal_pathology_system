import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';

describe('Migration 00128: Final Clinical Range Polish & Safety Guards', () => {
  const migPath = path.resolve('supabase/migrations_legacy_archive/00128_final_clinical_range_polish.sql');

  test('migration file 00128 exists and has valid SQL structure', () => {
    assert.ok(existsSync(migPath), '00128 migration file must exist');
    const content = readFileSync(migPath, 'utf8');
    assert.ok(content.includes('BEGIN;'), 'Must have BEGIN;');
    assert.ok(content.includes('COMMIT;'), 'Must have COMMIT;');
  });

  test('configures Manual Differential 5-part microscopy with exact approved ranges', () => {
    const content = readFileSync(migPath, 'utf8');
    // HEM-0015 Neutrophils: 40.0 - 70.0 %
    assert.ok(content.includes('HEM-0015'), 'Must target HEM-0015');
    assert.ok(content.includes('40.0, 70.0'), 'Neutrophil range must be 40.0 - 70.0');

    // HEM-0016 Lymphocytes: 20.0 - 40.0 %
    assert.ok(content.includes('HEM-0016'), 'Must target HEM-0016');
    assert.ok(content.includes('20.0, 40.0'), 'Lymphocyte range must be 20.0 - 40.0');

    // HEM-0017 Monocytes: 2.0 - 10.0 %
    assert.ok(content.includes('HEM-0017'), 'Must target HEM-0017');
    assert.ok(content.includes('2.0, 10.0'), 'Monocyte range must be 2.0 - 10.0');

    // HEM-0018 Eosinophils: 1.0 - 6.0 %
    assert.ok(content.includes('HEM-0018'), 'Must target HEM-0018');
    assert.ok(content.includes('1.0, 6.0'), 'Eosinophil range must be 1.0 - 6.0');

    // HEM-0019 Basophils: 0.0 - 1.0 %
    assert.ok(content.includes('HEM-0019'), 'Must target HEM-0019');
    assert.ok(content.includes('0.0, 1.0'), 'Basophil range must be 0.0 - 1.0');
  });

  test('configures Vitamin D (25-OH) with exact approved interpretation and NO unapproved labels', () => {
    const content = readFileSync(migPath, 'utf8');
    assert.ok(content.includes('BIO-0053'), 'Must target BIO-0053');
    assert.ok(content.includes('30.0, 100.0'), 'Sufficient range must be 30.0 - 100.0');
    assert.ok(content.includes('<20 Deficient'), 'Must document <20 Deficient interpretation');
    assert.ok(content.includes('20-30 Insufficient'), 'Must document 20-30 Insufficient interpretation');
    assert.ok(!content.includes('Toxicity'), 'Must NOT include unapproved Toxicity interpretation');
    assert.ok(!content.includes('>100'), 'Must NOT include unapproved >100 interpretation');
  });

  test('configures Vitamin B12 with exact approved range, borderline note, and NO unapproved labels', () => {
    const content = readFileSync(migPath, 'utf8');
    assert.ok(content.includes('BIO-0051'), 'Must target BIO-0051');
    assert.ok(content.includes('200.0, 900.0'), 'Reference range must be 200.0 - 900.0');
    assert.ok(content.includes('Borderline: 200 - 300 pg/mL'), 'Must document Borderline: 200 - 300 pg/mL interpretation');
    assert.ok(!content.includes('<200 Deficient'), 'Must NOT add unapproved <200 Deficient label');
    assert.ok(!content.includes('>300 Normal'), 'Must NOT add unapproved >300 Normal label');
  });

  test('enforces server-side structural zero-parameter clinical order guard', () => {
    const content = readFileSync(migPath, 'utf8');
    assert.ok(content.includes('create_patient_bill_order_with_packages'), 'Must update create_patient_bill_order_with_packages');
    assert.ok(content.includes("t.reporting_type <> 'NoReporting'"), 'Must whitelist NoReporting');
    assert.ok(content.includes('catalogue_panel_components'), 'Must whitelist valid profile containers with components');
    assert.ok(content.includes('public.parameters'), 'Must check active reporting parameters');
    assert.ok(content.includes('Configuration Incomplete: Reportable single test with 0 reporting parameters cannot be clinically ordered.'), 'Must raise explicit structural exception');
  });

  test('preserves safety invariants: no price changes, no test renaming', () => {
    const content = readFileSync(migPath, 'utf8');
    assert.ok(!content.includes('UPDATE public.tests SET price'), 'No price changes');
    assert.ok(!content.includes('UPDATE public.tests SET name'), 'No test renaming');
    assert.ok(!content.includes('UPDATE public.tests SET code'), 'No test code changes');
  });
});
