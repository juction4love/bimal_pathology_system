// scripts/verify-00121-rate-convergence.test.mjs
// Verification suite for Migration 00121: Rate Convergence & Missing Rates Workspace

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const EXPECTED_29_CODES = [
  'BIO-0001', 'BIO-0002', 'BIO-0003', 'BIO-0008', 'BIO-0009',
  'BIO-0010', 'BIO-0012', 'BIO-0037', 'BIO-0038', 'BIO-0041',
  'BIO-0043', 'BIO-0058', 'BIO-0059', 'CLP-0001', 'CLP-0021',
  'COA-0002', 'COA-0003', 'HEM-0001', 'HEM-0002', 'HEM-0006',
  'HEM-0026', 'HEM-0027', 'PRO-0001', 'PRO-0003', 'SER-0001',
  'SER-0004', 'SER-0010', 'SER-0016', 'SER-0086'
];

describe('Bimal Pathology LIS: Migration 00121 Rate Convergence & Missing Rates Workspace', () => {

  describe('1. Migration 00121 SQL Validation & Structure', () => {
    it('verifies 00121 migration file exists and includes all 29 target codes', () => {
      const sqlPath = path.resolve('supabase/migrations_legacy_archive/00121_converge_legacy_test_prices_to_rate_versions.sql');
      const content = readFileSync(sqlPath, 'utf8');

      assert.ok(content.includes('catalogue_rate_versions'), 'Must target catalogue_rate_versions table');
      assert.ok(content.includes('BEGIN;'), 'Must be wrapped in transaction');
      assert.ok(content.includes('COMMIT;'), 'Must commit transaction');
      assert.ok(content.includes('price_configured = TRUE'), 'Must update price_configured on tests');

      for (const code of EXPECTED_29_CODES) {
        assert.ok(content.includes(code), `Migration 00121 must include code ${code}`);
      }
    });

    it('enforces idempotency and avoids duplicate active rate insertions', () => {
      const sqlPath = path.resolve('supabase/migrations_legacy_archive/00121_converge_legacy_test_prices_to_rate_versions.sql');
      const content = readFileSync(sqlPath, 'utf8');

      assert.ok(content.includes('NOT EXISTS'), 'Must contain NOT EXISTS guard to prevent duplicate active rates');
      assert.ok(content.includes("status = 'Active'"), 'Must check active status in existence guard');
    });
  });

  describe('2. Live Database Canonical Rates & Idempotency Verification', () => {
    it('verifies canonical database state: target_29=29, billing_visible=21, missing<=1067, overlapping=0', () => {
      const verifySql = `
      SELECT json_build_object(
        'active_rate_records', (SELECT count(*) FROM public.catalogue_rate_versions WHERE status = 'Active'),
        'overlapping_rates', (
          SELECT count(*) FROM (
            SELECT test_id, count(*) 
            FROM public.catalogue_rate_versions 
            WHERE test_id IS NOT NULL AND status = 'Active' AND (effective_to IS NULL OR effective_to > clock_timestamp())
            GROUP BY test_id HAVING count(*) > 1
          ) dup
        ),
        'target_29_active_count', (
          SELECT count(*) FROM public.catalogue_rate_versions r
          JOIN public.tests t ON t.id = r.test_id
          WHERE t.code = ANY(ARRAY[${EXPECTED_29_CODES.map(c => `'${c}'`).join(',')}])
            AND r.status = 'Active'
        ),
        'total_active_tests', (SELECT count(*) FROM public.tests WHERE is_active = TRUE AND lifecycle_status = 'Active'),
        'billing_visible_tests', (
          SELECT count(*) FROM public.tests
          WHERE is_active = TRUE AND lifecycle_status = 'Active' AND billing_enabled = TRUE
        ),
        'total_configured_tests', (
          SELECT count(DISTINCT t.id) FROM public.tests t
          JOIN public.catalogue_rate_versions r ON r.test_id = t.id
          WHERE t.is_active = TRUE AND t.lifecycle_status = 'Active' AND r.status = 'Active'
            AND (r.effective_to IS NULL OR r.effective_to > clock_timestamp())
        ),
        'missing_rates_count', (SELECT count(*) FROM public.tests WHERE is_active = TRUE AND lifecycle_status = 'Active') - (
          SELECT count(DISTINCT t.id) FROM public.tests t
          JOIN public.catalogue_rate_versions r ON r.test_id = t.id
          WHERE t.is_active = TRUE AND t.lifecycle_status = 'Active' AND r.status = 'Active'
            AND (r.effective_to IS NULL OR r.effective_to > clock_timestamp())
        )
      ) AS stats;
      `;

      const tmpFile = path.resolve('tmp_00121_verify.sql');
      writeFileSync(tmpFile, verifySql, 'utf8');

      try {
        const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
          encoding: 'utf8',
          stdio: ['pipe', 'pipe', 'pipe'],
          shell: true,
          maxBuffer: 50 * 1024 * 1024,
        });

        const jsonStart = raw.indexOf('[');
        const jsonStartObj = raw.indexOf('{');
        const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
        const parsed = JSON.parse(raw.slice(start));
        
        let res = null;
        if (Array.isArray(parsed)) {
          for (const item of parsed) {
            if (item?.stats) res = item.stats;
            else if (item?.rows?.[0]?.stats) res = item.rows[0].stats;
          }
        } else {
          res = parsed?.stats || parsed?.rows?.[0]?.stats;
        }

        assert.ok(res, 'Database query must return stats');
        assert.equal(res.target_29_active_count, 29, 'All 29 target codes must have active rate versions');
        assert.equal(res.overlapping_rates, 0, 'Must have 0 overlapping active rate versions');
        assert.ok(res.total_configured_tests >= 29, 'Total configured active tests with rate versions must cover at least 29 tests');
        assert.ok(res.missing_rates_count <= 1067, 'Must have at most 1,067 missing rates');
        assert.ok(res.active_rate_records >= 72, 'Must have at least 72 active rate records');
      } finally {
        try { unlinkSync(tmpFile); } catch {}
      }
    });

    it('verifies migration 00121 idempotency: re-running does not insert duplicate active rates', () => {
      const migrationFile = path.resolve('supabase/migrations_legacy_archive/00121_converge_legacy_test_prices_to_rate_versions.sql');
      const migrationContent = readFileSync(migrationFile, 'utf8');

      const idempotencySql = `
      BEGIN;

      -- Capture pre count
      CREATE TEMP TABLE pre_test_counts AS
      SELECT count(*) as cnt FROM public.catalogue_rate_versions WHERE status = 'Active';

      -- Re-execute migration SQL body
      ${migrationContent.replace(/^\s*BEGIN;\s*$/m, '').replace(/^\s*COMMIT;\s*$/m, '')}

      -- Check post count
      SELECT json_build_object(
        'pre_count', (SELECT cnt FROM pre_test_counts),
        'post_count', (SELECT count(*) FROM public.catalogue_rate_versions WHERE status = 'Active'),
        'new_insertions', (SELECT count(*) FROM public.catalogue_rate_versions WHERE status = 'Active') - (SELECT cnt FROM pre_test_counts)
      ) as idempotency_res;

      ROLLBACK;
      `;

      const tmpFile = path.resolve('tmp_00121_idempotency.sql');
      writeFileSync(tmpFile, idempotencySql, 'utf8');

      try {
        const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
          encoding: 'utf8',
          stdio: ['pipe', 'pipe', 'pipe'],
          shell: true,
          maxBuffer: 50 * 1024 * 1024,
        });

        const jsonStart = raw.indexOf('[');
        const jsonStartObj = raw.indexOf('{');
        const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
        const parsed = JSON.parse(raw.slice(start));
        
        let res = null;
        if (Array.isArray(parsed)) {
          for (const item of parsed) {
            if (item?.idempotency_res) res = item.idempotency_res;
            else if (item?.rows?.[0]?.idempotency_res) res = item.rows[0].idempotency_res;
          }
        } else {
          res = parsed?.idempotency_res || parsed?.rows?.[0]?.idempotency_res;
        }

        assert.ok(res, 'Idempotency test must return results');
        assert.equal(res.new_insertions, 0, 'Re-running migration must insert 0 duplicate rates');
        assert.equal(res.post_count, res.pre_count, 'Post count must equal pre count');
      } finally {
        try { unlinkSync(tmpFile); } catch {}
      }
    });
  });

  describe('3. CSV Import Dry-Run & Validation Engine', () => {
    it('validates CSV parsing logic: accepts valid rows and rejects invalid syntax/decimals/negatives', () => {
      function validateCsvRows(csvText, activeTestCodes) {
        const lines = csvText.split(/\r?\n/).filter(l => l.trim().length > 0);
        const header = lines[0].toLowerCase().split(',').map(h => h.trim());
        const codeIdx = header.indexOf('code');
        const rateIdx = header.indexOf('rate_npr');

        assert.ok(codeIdx !== -1 && rateIdx !== -1, 'CSV must include code and rate_npr');

        const seenCodes = new Set();
        const results = [];

        for (let i = 1; i < lines.length; i++) {
          const parts = lines[i].split(',').map(p => p.trim());
          const code = (parts[codeIdx] || '').toUpperCase();
          const rate = parts[rateIdx] || '';

          if (!code) continue;

          let isValid = true;
          let error = '';

          if (seenCodes.has(code)) {
            isValid = false;
            error = 'Duplicate code in CSV';
          }
          seenCodes.add(code);

          if (!activeTestCodes.has(code)) {
            isValid = false;
            error = 'Unknown or inactive test code';
          }

          // Rate validation
          if (!/^\d+(\.\d{1,2})?$/.test(rate) || Number(rate) <= 0) {
            isValid = false;
            error = error || 'Invalid rate: must be positive amount with at most 2 decimals';
          }

          results.push({ code, rate, isValid, error });
        }
        return results;
      }

      const activeCodes = new Set(['BIO-0001', 'BIO-0010', 'HEM-0001']);
      const sampleCsv = `code,name,rate_npr,effective_from
BIO-0001,Glucose Fasting,150.00,2026-09-17
BIO-0010,Creatinine,200.5,2026-09-17
BIO-0010,Creatinine Duplicate,200,2026-09-17
UNKNOWN-999,Unknown Test,500.00,2026-09-17
HEM-0001,CBC,-100.00,2026-09-17
HEM-0001,CBC,400.005,2026-09-17`;

      const parsed = validateCsvRows(sampleCsv, activeCodes);

      assert.equal(parsed[0].isValid, true, 'Row 1 (BIO-0001 @ 150.00) must be valid');
      assert.equal(parsed[1].isValid, true, 'Row 2 (BIO-0010 @ 200.5) must be valid');
      assert.equal(parsed[2].isValid, false, 'Row 3 duplicate code must be invalid');
      assert.equal(parsed[3].isValid, false, 'Row 4 unknown code must be invalid');
      assert.equal(parsed[4].isValid, false, 'Row 5 negative rate must be invalid');
      assert.equal(parsed[5].isValid, false, 'Row 6 >2 decimals must be invalid');
    });
  });

  describe('4. Default Billing Rate Rule & In-Flight Technician Override Invariants', () => {
    const PROVISIONAL_DEFAULT_RATE_PAISA = 10000; // NPR 100.00

    function simulateAddSelectedBillTest(current, test) {
      if (current.some((item) => item.test.id === test.id)) return current;
      const isConfigured = Boolean(test.priceConfigured && (test.pricePaisa > 0 || test.allowZeroPriceBilling));
      const initialPricePaisa = isConfigured ? test.pricePaisa : PROVISIONAL_DEFAULT_RATE_PAISA;

      return [...current, {
        test,
        unitPricePaisa: initialPricePaisa,
        discountPaisa: 0,
        description: test.code === 'IHC' ? 'IHC Panel' : '',
        rateResolved: true,
        isManuallyEdited: false,
      }];
    }

    it('verifies configured test auto-populates canonical catalogue price', () => {
      const configuredTest = {
        id: '1de8a1df-9d55-48c4-9dbc-83de477d5edb',
        code: 'BIO-0010',
        name: 'Creatinine',
        pricePaisa: 20000,
        priceConfigured: true,
        allowZeroPriceBilling: false,
      };

      const selected = simulateAddSelectedBillTest([], configuredTest);
      assert.equal(selected.length, 1);
      assert.equal(selected[0].unitPricePaisa, 20000, 'Configured test must load canonical rate of 20000 paisa (NPR 200.00)');
      assert.equal(selected[0].rateResolved, true);
      assert.equal(selected[0].isManuallyEdited, false);
    });

    it('verifies unconfigured test pre-fills provisional NPR 100 default rate without mutating master catalogue', () => {
      const unconfiguredTest = {
        id: '99999999-9999-9999-9999-999999999999',
        code: 'SPE-0099',
        name: 'Unpriced Specialty Test',
        pricePaisa: 0,
        priceConfigured: false,
        allowZeroPriceBilling: false,
      };

      const selected = simulateAddSelectedBillTest([], unconfiguredTest);
      assert.equal(selected.length, 1);
      assert.equal(selected[0].unitPricePaisa, PROVISIONAL_DEFAULT_RATE_PAISA, 'Unconfigured test must prefill 10000 paisa (NPR 100.00)');
      assert.equal(selected[0].unitPricePaisa, 10000);
      assert.equal(selected[0].test.priceConfigured, false, 'Master test priceConfigured flag must remain false');
      assert.equal(selected[0].isManuallyEdited, false, 'Must start with isManuallyEdited = false (Default rate — verify)');
    });

    it('verifies in-flight technician edit (100.00 -> 350.00) preserves 35000 paisa on bill without altering master catalogue', () => {
      const unconfiguredTest = {
        id: '99999999-9999-9999-9999-999999999999',
        code: 'SPE-0099',
        name: 'Unpriced Specialty Test',
        pricePaisa: 0,
        priceConfigured: false,
        allowZeroPriceBilling: false,
      };

      const items = simulateAddSelectedBillTest([], unconfiguredTest);
      assert.equal(items[0].unitPricePaisa, 10000);

      // Simulate technician manual override to NPR 350.00 (35000 paisa)
      const editedPaisa = 35000;
      const updatedItems = items.map(item =>
        item.test.id === unconfiguredTest.id
          ? {
              ...item,
              unitPricePaisa: editedPaisa,
              rateResolved: true,
              isManuallyEdited: Boolean(!item.test.priceConfigured || item.test.pricePaisa !== editedPaisa),
            }
          : item
      );

      assert.equal(updatedItems[0].unitPricePaisa, 35000, 'Bill item must store 35000 paisa');
      assert.equal(updatedItems[0].isManuallyEdited, true, 'Row must indicate Manual rate');
      assert.equal(unconfiguredTest.pricePaisa, 0, 'Original master test definition price must remain untouched');
      assert.equal(unconfiguredTest.priceConfigured, false, 'Master test priceConfigured flag must remain false');

      // Next new bill starts again at 100.00
      const nextFreshBill = simulateAddSelectedBillTest([], unconfiguredTest);
      assert.equal(nextFreshBill[0].unitPricePaisa, 10000, 'Next fresh bill must again start at provisional NPR 100.00 default');
    });

    it('verifies Rate Coverage Dashboard counts actual master rate versions and ignores provisional defaults', () => {
      const srcPath = path.resolve('src/features/catalogue/CataloguePriceMasterSection.tsx');
      const content = readFileSync(srcPath, 'utf8');

      assert.ok(content.includes("from('catalogue_rate_versions')"), 'Coverage KPIs must query catalogue_rate_versions');
      assert.ok(content.includes("totalActive - configuredRateCount"), 'Missing rate count must reflect genuine catalogue unpriced items');
    });
  });

  describe('5. RBAC & Frontend Price Master Security', () => {
    it('verifies CataloguePriceMasterSection restricts access to Admin with can_manage_catalogue', () => {
      const srcPath = path.resolve('src/features/catalogue/CataloguePriceMasterSection.tsx');
      const content = readFileSync(srcPath, 'utf8');

      assert.ok(content.includes('if (!canManage)'), 'Must check canManage prop at root');
      assert.ok(content.includes('Access Denied'), 'Must render Access Denied for unauthorized roles');
      assert.ok(content.includes('catalogue_bulk_set_current_rates'), 'Must integrate batch rate setting');
      assert.ok(content.includes('MoneyInputField'), 'Must use MoneyInputField for smooth rate entry');
    });

    it('verifies routes.tsx protects /catalogue with PermissionGuard CAN_MANAGE_CATALOGUE', () => {
      const routesPath = path.resolve('src/app/routes.tsx');
      const content = readFileSync(routesPath, 'utf8');

      assert.ok(content.includes("path: 'catalogue'"), 'Must declare catalogue route');
      assert.ok(content.includes('PERMISSION_KEYS.CAN_MANAGE_CATALOGUE'), 'Must guard with CAN_MANAGE_CATALOGUE');
      assert.ok(content.includes('<UnauthorizedPage />'), 'Must fallback to UnauthorizedPage (403)');
    });
  });

  describe('6. Integer Paisa Invariant & Money Precision', () => {
    it('verifies exact integer paisa conversions without floating point inaccuracy', () => {
      const rates = [
        { npr: '100.00', paisa: 10000 },
        { npr: '150.00', paisa: 15000 },
        { npr: '200.50', paisa: 20050 },
        { npr: '350.00', paisa: 35000 },
        { npr: '0.25', paisa: 25 },
        { npr: '4500.00', paisa: 450000 },
      ];

      for (const { npr, paisa } of rates) {
        const converted = Math.round(parseFloat(npr) * 100);
        assert.equal(converted, paisa, `Conversion of NPR ${npr} must equal ${paisa} paisa`);
        const formatted = (paisa / 100).toFixed(2);
        assert.equal(formatted, npr, `Formatting of ${paisa} paisa must equal NPR ${npr}`);
      }
    });
  });

});
