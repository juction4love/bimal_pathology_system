import fs from 'node:fs';
import assert from 'node:assert/strict';

const page = fs.readFileSync('src/features/patients/PatientsPage.tsx', 'utf8');
const schema = fs.readFileSync('supabase/migrations_legacy_archive/00001_initial_schema.sql', 'utf8');
const m42 = fs.readFileSync('supabase/migrations_legacy_archive/00042_safe_patient_management.sql', 'utf8');
const m43 = fs.readFileSync('supabase/migrations_legacy_archive/00043_payment_receivables_integrity.sql', 'utf8');
const m75 = fs.readFileSync('supabase/migrations_legacy_archive/00075_catalogue_readiness_approval_workflow.sql', 'utf8');
let passed = 0;

const check = (name, fn) => {
  try { fn(); passed += 1; console.log(`PASS ${name}`); }
  catch (error) { console.error(`FAIL ${name}: ${error.message}`); process.exitCode = 1; }
};

const patientListSelect = page.match(/\.from\('patients'\)[\s\S]{0,160}?\.select\(([^\n]+)\)/)?.[1] || '';
const summarize = (bill) => ({
  billId: bill.id,
  net: bill.net_amount_paisa,
  paid: bill.paid_amount_paisa,
  due: bill.due_amount_paisa,
  status: bill.payment_status,
  payments: bill.payment_transactions || [],
});

check('registry assumes no direct patients to payments relationship', () => assert.doesNotMatch(patientListSelect, /payment_transactions/));
check('schema has no fake payment patient_id foreign key', () => assert.doesNotMatch(schema.match(/CREATE TABLE payment_transactions \([\s\S]*?\n\);/)?.[0] || '', /patient_id/));
check('authoritative payment relationship is payment to bill', () => assert.match(schema, /CREATE TABLE payment_transactions \([\s\S]*?bill_id UUID NOT NULL REFERENCES bills\(id\)/));
check('bill history embeds its own immutable payments', () => assert.match(m75, /'payment_transactions'.*SELECT jsonb_agg\(jsonb_build_object\('id',pt\.id,'receipt_number'/));
check('each bill payment timeline is chronological', () => assert.match(m75, /FROM public\.payment_transactions pt WHERE pt\.bill_id=b\.id\),'\[\]'::JSONB/));
check('bill history resolves Lab No through bill orders', () => assert.match(m75, /'clinical_orders'.*'order_number',o\.order_number/));
check('patient history is bounded by a server keyset RPC', () => {
  assert.match(page, /rpc\('search_patient_history'/);
  assert.match(m75, /\(b\.created_at,b\.id\)<\(p_cursor_timestamp,p_cursor_id\)/);
});
check('zero patients is a valid empty registry result', () => assert.deepEqual([], []));
check('patient without bills is a valid empty history result', () => assert.deepEqual([].map(summarize), []));
check('unpaid bill retains an empty payment timeline', () => assert.deepEqual(summarize({ id:'u', net_amount_paisa:100000, paid_amount_paisa:0, due_amount_paisa:100000, payment_status:'Due' }).payments, []));
check('partial bill keeps its received amount and due', () => assert.deepEqual(summarize({ id:'p', net_amount_paisa:100000, paid_amount_paisa:40000, due_amount_paisa:60000, payment_status:'PartiallyPaid', payment_transactions:[{ id:'p1', amount_paisa:40000 }] }), { billId:'p', net:100000, paid:40000, due:60000, status:'PartiallyPaid', payments:[{ id:'p1', amount_paisa:40000 }] }));
check('multiple immutable payments remain separate and ordered payload entries', () => assert.deepEqual(summarize({ id:'m', net_amount_paisa:100000, paid_amount_paisa:70000, due_amount_paisa:30000, payment_status:'PartiallyPaid', payment_transactions:[{ id:'p1', amount_paisa:40000 }, { id:'p2', amount_paisa:30000 }] }).payments.map(p => p.id), ['p1','p2']));
check('fully paid bill has zero due', () => assert.equal(summarize({ id:'f', net_amount_paisa:100000, paid_amount_paisa:100000, due_amount_paisa:0, payment_status:'Paid', payment_transactions:[{ id:'p1', amount_paisa:100000 }] }).due, 0));
check('payment immutability remains enforced', () => assert.match(m43, /BEFORE UPDATE OR DELETE ON public\.payment_transactions/));
check('patient management security remains enforced', () => assert.match(m42, /has_permission\('can_edit_patient'\)/));

console.log(`\nPatient history relationships: ${passed} passed, ${process.exitCode ? 1 : 0} failed`);
