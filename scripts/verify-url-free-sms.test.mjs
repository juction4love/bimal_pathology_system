import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const read = path => fs.readFileSync(path, 'utf8');
const migration = read('supabase/migrations/00122_url_free_sms_notifications.sql');
const message = 'Bimal Pathology: Your laboratory report is ready. Please collect it from the lab or contact 056-593288. Thank you.';
const definitions = text => [...text.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)\([\s\S]*?\bAS\s+(\$\w*\$)[\s\S]*?\2\s*;/gi)];
const before = new Map();
for (const file of fs.readdirSync('supabase/migrations').filter(x => x.endsWith('.sql') && x < '00122').sort()) {
 for (const m of definitions(read('supabase/migrations/' + file))) before.set(m[1], m[0]);
}
test('all three live report SMS construction paths use the neutral template; token and URL operations unchanged', () => {
 const changes = definitions(migration).filter(m => m[1] !== 'reject_sms_gateway_v2_local_validation');
 assert.deepEqual(changes.map(m => m[1]).sort(), ['complete_report_pdf_artifact_v2', 'create_public_report_token', 'notify_updated_order_reports']);
 for (const m of changes) {
  const expected = before.get(m[1]).replace(/'Bimal Pathology: (?:Your report is ready|Updated reports are available)\. Lab No: '\s*\|\|\s*ordering.order_number\s*\|\|\s*'\. View reports?: '\s*\|\|\s*(?:intent.public_url|i.public_url|p_public_url_base)/g, "'" + message + "'");
  assert.equal(m[0], expected);
  assert.ok(m[0].includes(message));
 }
 assert.doesNotMatch(migration, /(?:ALTER|DROP|CREATE) TABLE/i);
});
test('effective report-ready templates have no dynamic URL or clinical interpolation', () => {
 const effective = new Map(before);
 for (const m of definitions(migration)) effective.set(m[1], m[0]);
 for (const body of effective.values()) {
  for (const literal of body.matchAll(/'Bimal Pathology: ([^']*)'/g)) {
   assert.doesNotMatch(literal[1], /https?:|www\.|bimalpathology\.|View report/i);
  }
 }
 assert.doesNotMatch(message, /https?:|www\.|bimalpathology\.|\/(r|o)\//i);
});
test('public URL and printed QR consumers remain present', () => {
 assert.match(read('src/features/reports/ReportDocument.tsx'), /qr|QRCode/i);
 assert.match(before.get('report_artifact_public_url'), /intent.public_url/);
 assert.match(before.get('report_artifact_public_url'), /report_secure_link_presentations/);
});

test('URL rejection is accepted by the database and records a safe permanent audit', () => {
 const body = definitions(migration).find(m => m[1] === 'reject_sms_gateway_v2_local_validation')[0];
 assert.equal(body, before.get('reject_sms_gateway_v2_local_validation').replace("'SEGMENT_LIMIT_EXCEEDED')", "'SEGMENT_LIMIT_EXCEEDED','SMS_URL_BLOCKED')"));
 assert.match(body, /status='DeadLetter'/);
 assert.match(body, /'error_code',p_error_code/);
 assert.doesNotMatch(body, /message_body/);
});
