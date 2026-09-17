import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const searchTerms = [
  'CBC', 'Hemogram', 'LFT', 'KFT', 'RFT', 'Lipid', 'Cholesterol',
  'TSH', 'FT3', 'FT4', 'T3', 'T4', 'Vitamin D', 'Troponin', 'cTnI',
  'CK-MB', 'NT-proBNP', 'D-Dimer', 'CRP', 'hs-CRP', 'PCT', 'IL-6',
  'Ferritin', 'HbA1c', 'Microalbumin', 'Cystatin C', 'HIV', 'HIV Rapid',
  'HBsAg', 'HBsAg Rapid', 'HCV', 'HCV Rapid', 'Dengue', 'Scrub Typhus',
  'H pylori', 'Anti-CCP', 'ASO', 'RF', 'IgE', 'PSA', 'AFP', 'CEA'
];

const sql = `
WITH search_queries AS (
  SELECT unnest(ARRAY[${searchTerms.map(t => `'${t}'`).join(',')}]) AS term
)
SELECT json_agg(json_build_object(
  'term', q.term,
  'match_count', (
    SELECT count(*) FROM (
      SELECT t.id FROM public.tests t
      WHERE t.lifecycle_status = 'Active'
        AND (t.name ILIKE '%' || q.term || '%' 
             OR t.short_name ILIKE '%' || q.term || '%' 
             OR t.code ILIKE '%' || q.term || '%'
             OR EXISTS (SELECT 1 FROM public.test_aliases a WHERE a.test_id = t.id AND a.alias_name ILIKE '%' || q.term || '%'))
    ) matches
  ),
  'top_matches', (
    SELECT json_agg(json_build_object(
      'code', m.code,
      'name', m.name,
      'short_name', m.short_name,
      'test_type', m.test_type,
      'price_npr', m.price_paisa / 100,
      'specimen', m.specimen_type
    )) FROM (
      SELECT t.code, t.name, t.short_name, t.test_type, t.price_paisa, t.specimen_type
      FROM public.tests t
      WHERE t.lifecycle_status = 'Active'
        AND (t.name ILIKE '%' || q.term || '%' 
             OR t.short_name ILIKE '%' || q.term || '%' 
             OR t.code ILIKE '%' || q.term || '%'
             OR EXISTS (SELECT 1 FROM public.test_aliases a WHERE a.test_id = t.id AND a.alias_name ILIKE '%' || q.term || '%'))
      ORDER BY 
        CASE WHEN t.code ILIKE q.term THEN 1
             WHEN t.short_name ILIKE q.term THEN 2
             WHEN t.name ILIKE q.term THEN 3
             ELSE 4 END,
        t.code
      LIMIT 5
    ) m
  )
)) AS search_results
FROM search_queries q;
`;

async function main() {
  const tmpFile = path.resolve('tmp_search_audit.sql');
  writeFileSync(tmpFile, sql, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
      maxBuffer: 50 * 1024 * 1024,
    });
    const jsonStart = raw.indexOf('[');
    const jsonStartObj = raw.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    const parsed = JSON.parse(raw.slice(start));
    const result = Array.isArray(parsed) ? parsed[0]?.search_results : parsed.rows?.[0]?.search_results;
    
    let allPassed = true;
    for (const r of result) {
      if (!r.match_count || r.match_count === 0) {
        console.error(`FAILED: No match for term "${r.term}"`);
        allPassed = false;
      } else {
        console.log(`PASS: "${r.term}" -> ${r.match_count} matches (Top: ${r.top_matches[0]?.code} - ${r.top_matches[0]?.name})`);
      }
    }
    
    writeFileSync('scripts/search_audit_output.json', JSON.stringify(result, null, 2), 'utf8');
    if (allPassed) {
      console.log('ALL 41 SEARCH TERMS PASSED WITH LIVE MATCHES!');
    }
  } catch (err) {
    console.error('Error during search audit:', err.message, err.stderr);
    process.exit(1);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

main();
