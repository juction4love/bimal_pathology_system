import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const acl=fs.readFileSync('supabase/migrations/00078_two_role_authorization_and_catalogue_access.sql','utf8');
const billingPage=fs.readFileSync('src/features/billing/NewBillPage.tsx','utf8');
const finalModel=fs.readFileSync('supabase/migrations/00087_production_catalogue_rate_management.sql','utf8');

test('billing UI uses guarded RPC then RLS-preserving follow-up reads',()=>{
 assert.match(billingPage,/rpc\('search_billable_catalogue'/);
 assert.match(billingPage,/from\('tests'\)/);
 assert.match(billingPage,/from\('catalogue_test_operational_state'\)/);
});

test('operational-state view is invoker-secured with narrow ACL',()=>{
 assert.match(acl,/WITH \(security_invoker=true\)/);
 assert.match(acl,/GRANT SELECT ON public\.catalogue_test_operational_state TO authenticated/);
 assert.match(acl,/REVOKE ALL ON public\.catalogue_test_operational_state FROM PUBLIC,anon/);
 assert.doesNotMatch(acl,/DISABLE ROW LEVEL SECURITY/i);
});

test('final Technician role has full laboratory operations but not system-owner administration',()=>{
 const target=finalModel.match(/operational_permissions CONSTANT TEXT\[\]:=ARRAY\[[\s\S]*?\];/)?.[0]??'';
 for(const key of ['can_create_bill','can_edit_patient','can_verify_results','can_sign_reports','can_amend_reports','can_manage_catalogue','can_view_financials','can_view_audit_logs']) assert.ok(target.includes(`'${key}'`),key);
 for(const key of ['can_manage_users','can_manage_roles']) assert.ok(!target.includes(`'${key}'`),key);
 assert.match(finalModel,/r\.code='lab_technician'/);
});

test('all bill prices are editable agreed rates and unconfigured tests remain billable with a valid rate',()=>{
 assert.match(billingPage,/allowManualPrice: true/);
 assert.match(billingPage,/Catalogue default — editable agreed rate/);
 assert.match(finalModel,/Every item requires a valid agreed rate/);
 assert.doesNotMatch(finalModel,/Fixed catalogue prices cannot be overridden during billing/);
});
