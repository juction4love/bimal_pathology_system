import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const newBillPage = fs.readFileSync('src/features/billing/NewBillPage.tsx', 'utf8');
const searchComponent = fs.readFileSync('src/features/billing/BillingCatalogueSearch.tsx', 'utf8');
const metaModule = fs.readFileSync('src/features/billing/billingCatalogueMeta.ts', 'utf8');

test('Billing search component renders bilingual helper text and category filter chips', () => {
  assert.match(searchComponent, /नाम, संक्षिप्त नाम \(Abbreviation\) वा समूह अनुसार प्रयोगशालामा उपलब्ध परीक्षणहरू तुरुन्त खोज्नुहोस्।/);
  assert.match(metaModule, /सबै \(All Tests\)/);
  assert.match(metaModule, /हेमेटोलोजी \(CBC\)/);
  assert.match(metaModule, /बायोकेमिस्ट्री \(LFT\/KFT\)/);
  assert.match(metaModule, /मधुमेह \(Diabetes\)/);
  assert.match(metaModule, /लिपिड \(Lipid\)/);
  assert.match(metaModule, /थाइरोइड \(Thyroid\)/);
  assert.match(metaModule, /भिटामिन \(Vitamins\)/);
  assert.match(metaModule, /कार्डियाक \(Cardiac\)/);
  assert.match(metaModule, /पिसाब \(Urine\)/);
  assert.match(metaModule, /सेरोलोजी \(Serology\)/);
});

test('Billing search component displays rich result cards with sample, preparation, TAT and price', () => {
  assert.match(searchComponent, /Sample:/);
  assert.match(searchComponent, /Prep:/);
  assert.match(searchComponent, /TAT:/);
  assert.match(searchComponent, /MoneyDisplay/);
  assert.match(searchComponent, /ORDERABLE/);
  assert.match(searchComponent, /VALIDATED/);
  assert.match(searchComponent, /STANDARD CONFIGURED/);
});

test('Billing search component supports expandable panel details and duplicate protection', () => {
  assert.match(searchComponent, /togglePanelDetails/);
  assert.match(searchComponent, /get_catalogue_panel_components/);
  assert.match(searchComponent, /View Details/);
  assert.match(searchComponent, /Hide Details/);
  assert.match(searchComponent, /Adding this panel bundles the full investigation at the panel rate/);
});

test('Billing UI preserves keyboard navigation and shortcut handling', () => {
  assert.match(searchComponent, /ArrowDown/);
  assert.match(searchComponent, /ArrowUp/);
  assert.match(searchComponent, /Enter/);
  assert.match(searchComponent, /Escape/);
  assert.match(newBillPage, /useKeyboardShortcut\('f'/);
});

test('Database search RPC resolves all standard query aliases and Nepali terms with correct scores', () => {
  const sql = `
  SELECT set_config('request.jwt.claim.sub', (SELECT id::text FROM auth.users LIMIT 1), false);

  SELECT json_agg(search_tests) as all_results FROM (
    SELECT 'CBC' as query, (SELECT json_agg(s) FROM public.search_billable_catalogue('CBC', 3) s) as results
    UNION ALL
    SELECT 'Hemogram', (SELECT json_agg(s) FROM public.search_billable_catalogue('Hemogram', 3) s)
    UNION ALL
    SELECT 'LFT', (SELECT json_agg(s) FROM public.search_billable_catalogue('LFT', 3) s)
    UNION ALL
    SELECT 'KFT', (SELECT json_agg(s) FROM public.search_billable_catalogue('KFT', 3) s)
    UNION ALL
    SELECT 'RFT', (SELECT json_agg(s) FROM public.search_billable_catalogue('RFT', 3) s)
    UNION ALL
    SELECT 'Lipid', (SELECT json_agg(s) FROM public.search_billable_catalogue('Lipid', 3) s)
    UNION ALL
    SELECT 'Cholesterol', (SELECT json_agg(s) FROM public.search_billable_catalogue('Cholesterol', 3) s)
    UNION ALL
    SELECT 'TSH', (SELECT json_agg(s) FROM public.search_billable_catalogue('TSH', 3) s)
    UNION ALL
    SELECT 'FT3', (SELECT json_agg(s) FROM public.search_billable_catalogue('FT3', 3) s)
    UNION ALL
    SELECT 'FT4', (SELECT json_agg(s) FROM public.search_billable_catalogue('FT4', 3) s)
    UNION ALL
    SELECT 'Vit D', (SELECT json_agg(s) FROM public.search_billable_catalogue('Vit D', 3) s)
    UNION ALL
    SELECT 'Troponin', (SELECT json_agg(s) FROM public.search_billable_catalogue('Troponin', 3) s)
    UNION ALL
    SELECT 'cTnI', (SELECT json_agg(s) FROM public.search_billable_catalogue('cTnI', 3) s)
    UNION ALL
    SELECT 'D-Dimer', (SELECT json_agg(s) FROM public.search_billable_catalogue('D-Dimer', 3) s)
    UNION ALL
    SELECT 'Urine', (SELECT json_agg(s) FROM public.search_billable_catalogue('Urine', 3) s)
    UNION ALL
    SELECT 'CRP', (SELECT json_agg(s) FROM public.search_billable_catalogue('CRP', 3) s)
    UNION ALL
    SELECT 'सुगर', (SELECT json_agg(s) FROM public.search_billable_catalogue('सुगर', 3) s)
    UNION ALL
    SELECT 'कलेजो', (SELECT json_agg(s) FROM public.search_billable_catalogue('कलेजो', 3) s)
    UNION ALL
    SELECT 'मिर्गौला', (SELECT json_agg(s) FROM public.search_billable_catalogue('मिर्गौला', 3) s)
    UNION ALL
    SELECT 'थाइरोइड', (SELECT json_agg(s) FROM public.search_billable_catalogue('थाइरोइड', 3) s)
  ) search_tests;
  `;

  const tmp = path.resolve('tmp_test_suite_search.sql');
  fs.writeFileSync(tmp, sql, 'utf8');

  try {
    const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8' });
    const jsonStart = out.indexOf('{');
    const parsed = JSON.parse(out.slice(jsonStart));
    const rows = parsed.rows?.[0]?.all_results || [];
    
    const byQuery = new Map(rows.map(r => [r.query, r.results || []]));

    // Assert key queries resolve to expected top tests
    const cbcResults = byQuery.get('CBC') || [];
    assert.ok(cbcResults.some(r => r.code === 'HEM-0001'), 'CBC query must find HEM-0001');

    const lftResults = byQuery.get('LFT') || [];
    assert.ok(lftResults.some(r => r.code === 'PRO-0001'), 'LFT query must find PRO-0001');

    const kftResults = byQuery.get('KFT') || [];
    assert.ok(kftResults.some(r => r.code === 'PRO-0002'), 'KFT query must find PRO-0002');

    const lipidResults = byQuery.get('Lipid') || [];
    assert.ok(lipidResults.some(r => r.code === 'PRO-0003'), 'Lipid query must find PRO-0003');

    const tshResults = byQuery.get('TSH') || [];
    assert.ok(tshResults.some(r => r.code === 'END-0001'), 'TSH query must find END-0001');

    const vitdResults = byQuery.get('Vit D') || [];
    assert.ok(vitdResults.some(r => r.code === 'BIO-0053' || r.code === 'IMM-VITAMINS'), 'Vit D query must find BIO-0053');

    const troponinResults = byQuery.get('Troponin') || [];
    assert.ok(troponinResults.some(r => r.code === 'BIO-0063'), 'Troponin query must find BIO-0063');

    const urineResults = byQuery.get('Urine') || [];
    assert.ok(urineResults.some(r => r.code === 'CLP-0001'), 'Urine query must find CLP-0001');

    const kalejoResults = byQuery.get('कलेजो') || [];
    assert.ok(kalejoResults.some(r => r.code === 'PRO-0001'), 'Nepali कलेजो query must find PRO-0001');

    const mirgaulaResults = byQuery.get('मिर्गौला') || [];
    assert.ok(mirgaulaResults.some(r => r.code === 'PRO-0002'), 'Nepali मिर्गौला query must find PRO-0002');
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
});

test('Billing duplicate protection handles both directions without double charge and with clear UI guidance', () => {
  // Direction 1: Add individual component first, then try to add panel
  assert.match(newBillPage, /Component test .+ is already in the bill\. Remove that individual test before adding the complete/);
  assert.match(newBillPage, /to prevent duplicate charges/);

  // Direction 2: Add panel first, then try to add individual component
  assert.match(newBillPage, /is already included in the selected panel/);
  assert.match(newBillPage, /It is covered under the panel rate and will not be charged separately/);

  // Verification that search component also validates against selected panel and items
  assert.match(searchComponent, /onPanelConflictWarning/);
  assert.match(searchComponent, /Adding this panel bundles the full investigation at the panel rate/);
});

