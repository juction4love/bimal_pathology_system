import fs from 'node:fs';

const content = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');
const lines = content.split('\n');

for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes("p_analyzer->>'code'")) {
    console.log(`Found around line ${i + 1}:`);
    for (let j = Math.max(0, i - 10); j <= Math.min(lines.length - 1, i + 10); j++) {
      console.log(`${j + 1}: ${lines[j]}`);
    }
  }
}
