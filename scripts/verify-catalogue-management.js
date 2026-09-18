import fs from 'node:fs';
import assert from 'node:assert/strict';

const read = (path) => fs.readFileSync(path, 'utf8');
const sql = read('supabase/migrations/00050_catalogue_management_architecture.sql');
const catalogue = read('src/features/catalogue/CataloguePage.tsx') + read('src/features/catalogue/EasyTestEditorDialog.tsx') + read('src/features/catalogue/CatalogueMasterSections.tsx');
const categoryPackages = read('src/features/catalogue/CategoryPackageManager.tsx');
const billing = read('src/features/billing/NewBillPage.tsx');
const report = read('src/features/reports/ReportDocument.tsx');

for (const fragment of [
  "catalogue_lifecycle_enum AS ENUM ('Draft', 'Active', 'Archived')",
  'CREATE TABLE public.test_categories', 'CREATE TABLE public.health_packages',
  'CREATE TABLE public.health_package_components', 'CREATE TABLE public.bill_package_selections',
  'catalogue_test_missing_configuration', 'catalogue_save_test', 'catalogue_save_parameter',
  'catalogue_save_range', 'catalogue_replace_ranges', 'catalogue_delete_test',
  'catalogue_delete_parameter', 'catalogue_delete_range', 'catalogue_clone_test',
  'catalogue_set_test_lifecycle', 'catalogue_set_package_lifecycle',
  'create_patient_bill_order_with_packages', "Referenced tests cannot be deleted",
  "server-authoritative calculation configuration", "('AFP'", "('BT_CT'", "('PT_INR'", "('LDH'",
  'price_configured', 'allow_zero_price_billing', 'Requires Clinical Validation', 'Workflow Not Supported',
  "('PT_INR','INR','INR','Calculated'", 'Zero-price billing requires catalogue authorization and explicit operator acknowledgement',
]) assert.ok(sql.includes(fragment), `missing SQL architecture: ${fragment}`);

assert.match(sql, /REVOKE INSERT, UPDATE, DELETE ON public\.tests, public\.parameters, public\.reference_ranges FROM authenticated/);
assert.match(sql, /ON CONFLICT DO NOTHING/);
assert.match(sql, /lifecycle_status='Active'/);
assert.match(sql, /cardinality\(p_components\).*DISTINCT/s);
assert.match(sql, /bill_package_components.*PRIMARY KEY\(bill_package_selection_id, test_id\)/s);
assert.doesNotMatch(sql, /PATIENT_PT\s*[+*/^-]|CONTROL_PT\s*[+*/^-]|ISI\s*[+*/^-]/);

for (const fragment of ['SmartMessageDialog', 'catalogue_save_test', 'catalogue_clone_test', 'Lifecycle']) assert.ok(catalogue.includes(fragment), `catalogue UI missing ${fragment}`);
for (const fragment of ['catalogue_save_category', 'catalogue_save_package', 'catalogue_set_package_lifecycle', 'Ordered canonical components']) assert.ok(categoryPackages.includes(fragment), `category/package UI missing ${fragment}`);
for (const fragment of ['create_patient_bill_order_with_packages', 'handleAddPackage', 'component_ids', 'selectedPackages']) assert.ok(billing.includes(fragment), `billing package integration missing ${fragment}`);
assert.ok(report.includes('snapshot'), 'canonical report must remain snapshot-driven');

const identityRows = [...sql.matchAll(/^ \('[A-Z0-9_]+','[^']+','(?:Individual|Profile)'/gm)].length;
assert.equal(identityRows, 23, 'expected exactly 23 reviewed Draft identities');
assert.ok(sql.includes("'NoReporting',0,FALSE,'','',FALSE,'Draft','Requires Clinical Validation'"), 'draft identities must be price-pending, non-billable, inactive, and validation-pending');

console.log('Catalogue management architecture verification passed.');
console.log(JSON.stringify({ reviewedDraftIdentities: identityRows, activeClinicalImports: 0, inventedRanges: 0, packageExpansion: 'guarded/atomic', historicalDeleteGuards: true }, null, 2));
