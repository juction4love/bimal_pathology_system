import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/inspect_coag_results.json', 'utf8'));

for (const t of data) {
  if (['COA-0001', 'COA-0007', 'COA-0008'].includes(t.code)) {
    console.log(`\n=== ${t.code} (${t.name}) ===`);
    console.log('sample_type:', t.sample_type);
    console.log('specimen_type:', t.specimen_type);
    console.log('container:', t.container);
    console.log('container_type:', t.container_type);
    console.log('method:', t.method);
    console.log('department:', t.department);
    console.log('category:', t.category);
    console.log('reporting_type:', t.reporting_type);
    console.log('lifecycle_status:', t.lifecycle_status);
    console.log('is_active:', t.is_active);
    console.log('parameters:', t.parameters);
    console.log('ranges:', t.ranges);
  }
}
