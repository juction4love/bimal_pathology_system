import fs from 'node:fs';

const baselineSql = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

function parseInsertStatements(sql, tableName) {
  const regex = new RegExp(`INSERT\\s+INTO\\s+public\\.${tableName}\\s*\\(([^)]+)\\)\\s*VALUES`, 'gi');
  let match;
  const results = [];
  
  while ((match = regex.exec(sql)) !== null) {
    const cols = match[1].split(',').map(c => c.trim());
    let pos = regex.lastIndex;
    
    // Scan until semicolon
    let inString = false;
    let stringChar = '';
    let parenDepth = 0;
    let currentTuple = '';
    
    while (pos < sql.length) {
      const char = sql[pos];
      const nextChar = sql[pos + 1];
      
      if (inString) {
        currentTuple += char;
        if (char === "'" && nextChar === "'") {
          currentTuple += nextChar;
          pos += 2;
          continue;
        } else if (char === "'") {
          inString = false;
        }
      } else {
        if (char === "'") {
          inString = true;
          currentTuple += char;
        } else if (char === '(') {
          parenDepth++;
          if (parenDepth === 1) {
            currentTuple = '';
          } else {
            currentTuple += char;
          }
        } else if (char === ')') {
          parenDepth--;
          if (parenDepth === 0) {
            results.push({ cols, values: currentTuple });
            currentTuple = '';
          } else {
            currentTuple += char;
          }
        } else if (char === ';' && parenDepth === 0) {
          break;
        } else if (parenDepth > 0) {
          currentTuple += char;
        }
      }
      pos++;
    }
  }
  return results;
}

console.log('Parsing baseline SQL data...');
const tests = parseInsertStatements(baselineSql, 'tests');
const params = parseInsertStatements(baselineSql, 'parameters');
const panelComps = parseInsertStatements(baselineSql, 'catalogue_panel_components');
const refRanges = parseInsertStatements(baselineSql, 'reference_ranges');
const analyzers = parseInsertStatements(baselineSql, 'analyzers');
const analyzerMappings = parseInsertStatements(baselineSql, 'analyzer_parameter_mappings');
const rates = parseInsertStatements(baselineSql, 'catalogue_rate_versions');

console.log('--- BASELINE PARSED COUNTS ---');
console.log(`Tests: ${tests.length}`);
console.log(`Parameters: ${params.length}`);
console.log(`Panel Components: ${panelComps.length}`);
console.log(`Reference Ranges: ${refRanges.length}`);
console.log(`Analyzers: ${analyzers.length}`);
console.log(`Analyzer Mappings: ${analyzerMappings.length}`);
console.log(`Rates: ${rates.length}`);
