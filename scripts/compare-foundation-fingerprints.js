import assert from 'node:assert/strict';import fs from 'node:fs';
const before=JSON.parse(fs.readFileSync('artifacts/foundation/fingerprint-before-00053.json','utf8'));const after=JSON.parse(fs.readFileSync('artifacts/foundation/fingerprint-after-00055.json','utf8'));
for(const table of Object.keys(before.tables)){assert.deepEqual(after.tables[table],before.tables[table],`${table} changed`);console.log(`PASS ${table} unchanged (${before.tables[table].count})`)}console.log('PASS historical foundation fingerprint');
