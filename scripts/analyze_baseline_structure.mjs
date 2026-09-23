import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

// Find all CREATE TABLE statements and their line numbers
const lines = sql.split('\n');
console.log(`Total lines: ${lines.length}`);

const tables = [];
const functions = [];

lines.forEach((line, idx) => {
  const tMatch = line.match(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([^\s(]+)/i);
  if (tMatch) {
    tables.push({ line: idx + 1, name: tMatch[1] });
  }
  const fMatch = line.match(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([^\s(]+)/i);
  if (fMatch) {
    functions.push({ line: idx + 1, name: fMatch[1] });
  }
});

console.log(`\nFound ${tables.length} tables:`);
tables.forEach(t => console.log(`  Line ${t.line}: ${t.name}`));

console.log(`\nFound ${functions.length} functions:`);
functions.slice(0, 20).forEach(f => console.log(`  Line ${f.line}: ${f.name}`));
if (functions.length > 20) {
  console.log(`  ... and ${functions.length - 20} more functions`);
}
