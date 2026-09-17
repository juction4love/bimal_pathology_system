import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const catalogue = fs.readFileSync(path.join(root, 'supabase/migrations/00008_default_pathology_catalogue.sql'), 'utf8');
const ranges = fs.readFileSync(path.join(root, 'supabase/migrations/00011_default_reference_ranges.sql'), 'utf8');

const testNames = new Map();
const parameterMeta = new Map();
let currentTest = null;
for (const line of catalogue.split(/\r?\n/)) {
  const test = line.match(/seed_test\(\s*'([^']+)'\s*,\s*'([^']+)'/);
  if (test) {
    currentTest = test[1];
    testNames.set(test[1], test[2].replace(/''/g, "'"));
  }
  const parameter = line.match(/seed_param\(v_id,\s*'([^']+)',\s*'([^']+)',\s*'[^']+',\s*(NULL|'(?:[^']|'')*')/);
  if (currentTest && parameter) {
    const unit = parameter[3] === 'NULL' ? '' : parameter[3].slice(1, -1).replace(/''/g, "'");
    parameterMeta.set(`${currentTest}:${parameter[1]}`, { name: parameter[2].replace(/''/g, "'"), unit });
  }
}

function splitSqlArgs(value) {
  const args = [];
  let token = '';
  let quoted = false;
  for (let i = 0; i < value.length; i += 1) {
    const ch = value[i];
    if (ch === "'" && value[i + 1] === "'") { token += "''"; i += 1; continue; }
    if (ch === "'") quoted = !quoted;
    if (ch === ',' && !quoted) { args.push(token.trim()); token = ''; } else token += ch;
  }
  args.push(token.trim());
  return args;
}

function sqlValue(value) {
  if (!value || value === 'NULL') return '';
  if (value.startsWith("'") && value.endsWith("'")) return value.slice(1, -1).replace(/''/g, "'");
  if (value === 'v_adult_age_min') return '6570 days (18 years)';
  if (value === 'v_adult_age_max') return '43800 days (120 years)';
  return value;
}

function csv(value) { return `"${String(value ?? '').replace(/"/g, '""')}"`; }

const rows = [];
for (const line of ranges.split(/\r?\n/)) {
  const call = line.match(/PERFORM\s+pg_temp\.seed_ref_range\((.*)\);/);
  if (!call) continue;
  const [testCodeRaw, parameterCodeRaw, sexRaw, minRaw, maxRaw, lowRaw, highRaw, textRaw, referenceRaw] = splitSqlArgs(call[1]);
  const testCode = sqlValue(testCodeRaw);
  const parameterCode = sqlValue(parameterCodeRaw);
  const meta = parameterMeta.get(`${testCode}:${parameterCode}`) || { name: parameterCode, unit: '' };
  const lower = sqlValue(lowRaw);
  const upper = sqlValue(highRaw);
  const normalText = sqlValue(textRaw);
  const reference = sqlValue(referenceRaw);
  rows.push({
    test: `${testNames.get(testCode) || testCode} [${testCode}]`,
    parameter: `${meta.name} [${parameterCode}]`,
    sexAge: `${sqlValue(sexRaw)}; ${sqlValue(minRaw)} to ${sqlValue(maxRaw)}`,
    unit: meta.unit,
    currentRange: reference || normalText || [lower, upper].filter(Boolean).join(' - '),
    sourceState: 'Approved/active by migration 00011; practical/default analyzer template',
    validationRequired: 'Yes — Bimal clinical lead must verify analyzer, reagent, method, unit and population applicability',
  });
}

const header = ['Test', 'Parameter', 'Sex/Age', 'Unit', 'Current Range', 'Source State', 'Validation Required'];
const output = [header.map(csv).join(','), ...rows.map((row) => [row.test, row.parameter, row.sexAge, row.unit, row.currentRange, row.sourceState, row.validationRequired].map(csv).join(','))].join('\n') + '\n';
const target = path.join(root, 'docs/REFERENCE_RANGE_VALIDATION_INVENTORY_00011.csv');
fs.writeFileSync(target, output, 'utf8');
console.log(`Wrote ${rows.length} review rows to ${path.relative(root, target)}`);
if (rows.length !== 105) throw new Error(`Expected 105 seeded ranges, found ${rows.length}`);
