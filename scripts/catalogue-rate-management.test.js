import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql=fs.readFileSync('supabase/migrations_legacy_archive/00087_production_catalogue_rate_management.sql','utf8');
const ui=fs.readFileSync('src/features/catalogue/CataloguePriceMasterSection.tsx','utf8');
const billing=fs.readFileSync('supabase/migrations_legacy_archive/00086_repair_panel_billing_authoritative_rate.sql','utf8');

test('migration is forward-only after production head 00086 and has no business seed DML',()=>{
 assert.match(sql,/schema\/code only/i);assert.doesNotMatch(sql,/INSERT INTO public\.tests|UPDATE public\.tests SET price_paisa=[0-9]/);
});
test('manager and technical boundaries require active users and separate permissions',()=>{
 assert.match(sql,/catalogue_require_manager[\s\S]*is_active_user\(\)[\s\S]*can_manage_catalogue/);
 assert.match(sql,/catalogue_require_technical[\s\S]*is_active_user\(\)[\s\S]*can_configure_catalogue_technical/);
 assert.doesNotMatch(sql,/can_configure_catalogue_technical[^$]+catalogue_set_current_rate/);
});
test('atomic rate update uses locking, optimistic versioning, integer paisa and audit reason',()=>{
 const block=sql.slice(sql.indexOf('catalogue_set_current_rate'),sql.indexOf('catalogue_bulk_set_current_rates'));
 for(const token of ['FOR UPDATE','PT409','p_price_paisa BIGINT','CATALOGUE_RATE_CHANGED','p_reason','price_configured=TRUE'])assert.ok(block.includes(token),token);
 assert.match(block,/status='Inactive'[\s\S]*INSERT INTO public\.catalogue_rate_versions[\s\S]*status[\s\S]*'Active'/);
});
test('bulk rates are bounded, duplicate-safe and transactional through nested atomic calls',()=>{
 assert.match(sql,/jsonb_array_length\(p_changes\)>100/);assert.match(sql,/Duplicate entity in bulk rate review/);assert.match(sql,/catalogue_set_current_rate/);
});
test('safe delete checks billing, orders, results, packages, profiles and panels',()=>{
 for(const table of ['bill_items','clinical_order_items','test_results','health_package_components','catalogue_profile_components','catalogue_panel_components','bill_package_components','bill_panel_components'])assert.ok(sql.includes(table),table);
 assert.match(sql,/Referenced tests cannot be deleted\. Archive this test/);
});
test('rate list is server filtered sorted and paginated with required production columns',()=>{
 for(const field of ['p_query','p_category_id','p_lifecycle','p_priced','p_sort','p_offset','p_limit'])assert.ok(sql.includes(field),field);
 for(const label of ['Test Code','Test Name','Category','Current Rate','Status','Last Updated','Actions'])assert.ok(ui.includes(label),label);
 assert.match(ui,/TablePagination/);assert.match(ui,/parseRupeesToPaisa/);assert.match(ui,/Reason for change/);
});
test('panel billing remains bound to bundled authoritative rate version',()=>{
 assert.match(billing,/catalogue_rate_versions/);assert.match(billing,/panel_price_paisa,rate_version_id/);assert.match(billing,/rate\.price_paisa/);
});
test('rate RPC grants only authenticated callers and server function remains authoritative',()=>{
 assert.match(sql,/REVOKE ALL ON FUNCTION public\.catalogue_set_current_rate[\s\S]*PUBLIC,anon,authenticated,service_role/);
 assert.match(sql,/GRANT EXECUTE ON FUNCTION public\.catalogue_set_current_rate[\s\S]*TO authenticated/);
});
