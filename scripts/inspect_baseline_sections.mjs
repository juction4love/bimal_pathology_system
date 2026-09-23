import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

// Find all section comments like -- ===
const lines = sql.split('\n');
const sections = [];

lines.forEach((line, idx) => {
  if (line.startsWith('-- ==') || (line.startsWith('-- ') && line.includes('Phase'))) {
    sections.push({ line: idx + 1, text: line });
  }
});

sections.forEach(s => console.log(`Line ${s.line}: ${s.text}`));
