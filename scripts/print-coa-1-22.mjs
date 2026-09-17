import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/inspect_coag_results.json', 'utf8'));

console.log('=== ALL COAGULATION TESTS ===');
for (const t of data) {
  if (t.code?.startsWith('COA-')) {
    console.log(`- Code: "${t.code}", Name: "${t.name}", Specimen: "${t.specimen_type}", Method: "${t.method}", Rates: ${JSON.stringify(t.rates)}`);
    console.log(`  Params: ${JSON.stringify(t.parameters?.map(p => ({ id: p.id, name: p.name, code: p.code, unit: p.unit, type: p.value_type })))}`);
    console.log(`  Aliases: ${JSON.stringify(t.aliases?.map(a => a.alias_name))}`);
    console.log(`  Ranges: ${JSON.stringify(t.ranges?.map(r => ({ min: r.normal_min, max: r.normal_max, text: r.textual_range })))}`);
  }
}
