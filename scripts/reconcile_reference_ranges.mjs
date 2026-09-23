import fs from 'node:fs';

const liveRaw = fs.readFileSync('scripts/output/live_reference_ranges.json', 'utf8');
const liveData = JSON.parse(liveRaw.slice(liveRaw.indexOf('{'), liveRaw.lastIndexOf('}') + 1)).rows;

const baselineSql = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

// Let's extract reference_ranges from baseline SQL
// Format: ('id', 'test_code', 'param_code', 'gender', age_min, age_max, normal_min, normal_max, critical_low, critical_high, 'unit', 'text_value', 'range_type', 'reference_range_type')
// or similar INSERT INTO public.reference_ranges ...

console.log(`Live reference ranges count: ${liveData.length}`);

// Let's find the INSERT statement for reference_ranges in baselineSql
const rrInsertMatch = baselineSql.match(/INSERT INTO public\.reference_ranges[\s\S]*?(?=INSERT INTO|COMMIT;|$)/i);
if (!rrInsertMatch) {
  console.log('Could not find reference_ranges INSERT in baselineSql');
} else {
  console.log(`Found reference_ranges insert section length: ${rrInsertMatch[0].length}`);
}
