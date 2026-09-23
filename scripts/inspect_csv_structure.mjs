import fs from 'node:fs';

function readCsv(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n').filter(l => l.trim().length > 0);
  const header = parseCsvLine(lines[0]);
  const rows = [];
  for (let i = 1; i < lines.length; i++) {
    const vals = parseCsvLine(lines[i]);
    const obj = {};
    for (let j = 0; j < header.length; j++) {
      obj[header[j]] = vals[j] !== undefined ? vals[j] : '';
    }
    rows.push(obj);
  }
  return rows;
}

function parseCsvLine(line) {
  const result = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      if (inQuotes && line[i + 1] === '"') {
        current += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch === ',' && !inQuotes) {
      result.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  result.push(current.trim());
  return result;
}

const tests = readCsv('scripts/output/final_master_catalogue_after.csv');
const params = readCsv('scripts/output/final_master_parameters.csv');
const rules = readCsv('scripts/output/final_master_reference_rules.csv');
const rates = readCsv('scripts/output/final_master_rates.csv');

console.log(`Loaded from CSV:`);
console.log(`- Tests: ${tests.length}`);
console.log(`- Parameters: ${params.length}`);
console.log(`- Reference Rules: ${rules.length}`);
console.log(`- Rates: ${rates.length}`);

console.log('Sample test row:', tests[0]);
console.log('Sample param row:', params[0]);
console.log('Sample rule row:', rules[0]);
console.log('Sample rate row:', rates[0]);
