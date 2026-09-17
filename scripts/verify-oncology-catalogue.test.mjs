import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

test('Oncology, Routine Monitoring, Pre-Op, Tumor Marker & Supportive Care Regression Suite', async (t) => {

  await t.test('1. Migration 00120 SQL Validation & Structure', () => {
    const migration = readFileSync('supabase/migrations/00120_oncology_routine_preop_tumor_marker_catalogue_reconciliation.sql', 'utf8');
    
    // LBC is billing only
    assert.ok(migration.includes("WHERE code = 'CYT-0008'"), 'Reconciles CYT-0008 (LBC)');
    assert.ok(migration.includes("reporting_type = 'NoReporting'"), 'Enforces NoReporting for LBC');
    
    // HPV DNA is billing only and 450000 paisa
    assert.ok(migration.includes("WHERE code = 'MOL-0014'"), 'Reconciles MOL-0014 (HPV DNA)');
    assert.ok(migration.includes("price_paisa = 450000"), 'Sets HPV DNA rate to 450000 paisa');

    // Panels created
    assert.ok(migration.includes("'PRO-0031'"), 'Creates PRO-0031 Viral Serology Panel');
    assert.ok(migration.includes("'PRO-0032'"), 'Creates PRO-0032 Chemotherapy Routine Monitoring Panel');
    assert.ok(migration.includes("'PRO-0033'"), 'Creates PRO-0033 Pre-operative Coagulation Panel');

    // Component links
    assert.ok(migration.includes("'SER-0086'"), 'Links HIV Rapid');
    assert.ok(migration.includes("'SER-0087'"), 'Links HBsAg Rapid');
    assert.ok(migration.includes("'SER-0088'"), 'Links HCV Rapid');
    assert.ok(migration.includes("'HEM-0001'"), 'Links CBC');
    assert.ok(migration.includes("'PRO-0001'"), 'Links LFT');
    assert.ok(migration.includes("'PRO-0002'"), 'Links KFT/RFT');
    assert.ok(migration.includes("'PRO-0008'"), 'Links Electrolytes');
    assert.ok(migration.includes("'CLP-0001'"), 'Links Urine R/E');
  });

  await t.test('2. Live Database Dry-Run of Migration 00119 + 00120', () => {
    const m119 = readFileSync('supabase/migrations/00119_pt_inr_bt_ct_clinical_configuration.sql', 'utf8');
    const m120 = readFileSync('supabase/migrations/00120_oncology_routine_preop_tumor_marker_catalogue_reconciliation.sql', 'utf8');

    const dryRunSql = `
    BEGIN;
    ${m119.replace(/^BEGIN;/m, '-- BEGIN 119').replace(/^COMMIT;/m, '-- COMMIT 119')}
    ${m120.replace(/^BEGIN;/m, '-- BEGIN 120').replace(/^COMMIT;/m, '-- COMMIT 120')}

    SELECT json_build_object(
      'lbc_reporting', (SELECT reporting_type FROM public.tests WHERE code = 'CYT-0008'),
      'hpv_reporting', (SELECT reporting_type FROM public.tests WHERE code = 'MOL-0014'),
      'hpv_price', (SELECT price_paisa FROM public.tests WHERE code = 'MOL-0014'),
      'pt_inr_price', (SELECT price_paisa FROM public.tests WHERE code = 'COA-0001'),
      'bt_ct_price', (SELECT price_paisa FROM public.tests WHERE code = 'PRO-0030'),
      'viral_panel_count', (SELECT count(*) FROM public.catalogue_panel_components pc JOIN public.tests p ON p.id = pc.panel_id WHERE p.code = 'PRO-0031'),
      'chemo_panel_count', (SELECT count(*) FROM public.catalogue_panel_components pc JOIN public.tests p ON p.id = pc.panel_id WHERE p.code = 'PRO-0032'),
      'preop_panel_count', (SELECT count(*) FROM public.catalogue_panel_components pc JOIN public.tests p ON p.id = pc.panel_id WHERE p.code = 'PRO-0033')
    ) AS verification;

    ROLLBACK;
    `;

    const tmpFile = path.resolve('tmp_verify_oncology.sql');
    writeFileSync(tmpFile, dryRunSql, 'utf8');

    try {
      const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
        encoding: 'utf8',
        shell: true,
        maxBuffer: 20 * 1024 * 1024
      });
      const jsonStart = raw.indexOf('[');
      const jsonStartObj = raw.indexOf('{');
      const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
      const parsed = JSON.parse(raw.slice(start));
      const res = Array.isArray(parsed) ? parsed[0]?.verification : parsed.rows?.[0]?.verification;
      
      assert.equal(res.lbc_reporting, 'NoReporting', 'LBC must be NoReporting (billing-only)');
      assert.equal(res.hpv_reporting, 'NoReporting', 'HPV DNA must be NoReporting (billing-only)');
      assert.equal(res.hpv_price, 450000, 'HPV DNA rate must be 450000 paisa (NPR 4,500)');
      assert.equal(res.pt_inr_price, 50000, 'PT/INR rate must be 50000 paisa (NPR 500)');
      assert.equal(res.bt_ct_price, 20000, 'BT & CT combo rate must be 20000 paisa (NPR 200)');
      assert.equal(res.viral_panel_count, 3, 'Viral Serology Panel must have 3 components');
      assert.equal(res.chemo_panel_count, 5, 'Chemo Routine Monitoring Panel must have 5 components');
      assert.equal(res.preop_panel_count, 4, 'Pre-op Coagulation Panel must have 4 components');
    } finally {
      unlinkSync(tmpFile);
    }
  });
});
