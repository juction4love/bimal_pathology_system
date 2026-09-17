import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/inspect_coag_results.json', 'utf8'));

console.log('=== COA-0001 & COA-0002 ===');
for (const t of data) {
  if (['COA-0001', 'COA-0002'].includes(t.code)) {
    console.log(`- Code: "${t.code}", Name: "${t.name}", Short: "${t.short_name}", Dept: "${t.department}", Specimen: "${t.specimen_type}", Method: "${t.method}", Rates: ${JSON.stringify(t.rates)}`);
    console.log(`  Params: ${JSON.stringify(t.parameters)}`);
    console.log(`  Aliases: ${JSON.stringify(t.aliases)}`);
    console.log(`  Ranges: ${JSON.stringify(t.ranges)}`);
  }
}
