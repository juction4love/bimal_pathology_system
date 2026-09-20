// scripts/verify-p0-form-cleanliness.mjs
// Audit P0 CSV and Markdown forms for zero unapproved prefilled values

import { readFileSync } from 'node:fs';
import path from 'node:path';

const csvPath = path.resolve('scripts/output/p0_lab_specification_form.csv');
const mdPath = path.resolve('scripts/output/p0_lab_specification_form.md');

const csvContent = readFileSync(csvPath, 'utf8');
const mdContent = readFileSync(mdPath, 'utf8');

// Parse CSV
const lines = csvContent.trim().split('\n');
const _header = lines[0].split(',').map(h => h.trim());
const rows = lines.slice(1);

console.log(`Auditing CSV: ${rows.length} rows across 15 P0 investigations...`);

const forbiddenKeywords = [
    '<140', '<1.8', '>50%', '<1.0', 'Synacthen', 'Clonidine', 'Glucagon',
    'L-Dopa', 'DDAVP', 'Cosyntropin', '0 min', '30 min', '60 min', '120 min',
    'mg/dL', 'mg/L', 'µg/dL', 'ng/mL', 'pg/mL', 'mOsm/kg'
];

let unapprovedPrefilledCount = 0;
const unapprovedItems = [];

// Audit CSV rows
for (let i = 0; i < rows.length; i++) {
    const cols = [];
    let inQuotes = false;
    let cur = '';
    const line = rows[i];
    for (let j = 0; j < line.length; j++) {
        const c = line[j];
        if (c === '"') {
            if (inQuotes && line[j + 1] === '"') {
                cur += '"';
                j++;
            } else {
                inQuotes = !inQuotes;
            }
        } else if (c === ',' && !inQuotes) {
            cols.push(cur);
            cur = '';
        } else {
            cur += c;
        }
    }
    cols.push(cur);

    // Columns:
    // 0: code, 1: test_name, 2: category, 3: parameter_name, 4: result_type, 5: unit,
    // 6: specimen, 7: method, 8: time_point, 9: reference_low, 10: reference_high,
    // 11: qualitative_options, 12: cutoff, 13: calculation_formula, 14: configured_source,
    // 15: analyzer_name, 16: report_note, 17: lab_approval_status, 18: lab_comments

    const clinicalFieldsToCheck = [
        { name: 'parameter_name', val: cols[3] },
        { name: 'result_type', val: cols[4] },
        { name: 'unit', val: cols[5] },
        { name: 'time_point', val: cols[8] },
        { name: 'reference_low', val: cols[9] },
        { name: 'reference_high', val: cols[10] },
        { name: 'qualitative_options', val: cols[11] },
        { name: 'cutoff', val: cols[12] },
        { name: 'calculation_formula', val: cols[13] },
        { name: 'configured_source', val: cols[14] },
        { name: 'analyzer_name', val: cols[15] },
        { name: 'report_note', val: cols[16] },
        { name: 'lab_comments', val: cols[18] }
    ];

    for (const f of clinicalFieldsToCheck) {
        if (f.val && f.val.trim().length > 0) {
            unapprovedPrefilledCount++;
            unapprovedItems.push(`Row ${i + 1} (${cols[0]} ${cols[1]}): Field '${f.name}' has prefilled value '${f.val}'`);
        }
    }

    // Check for forbidden keywords in entire row
    for (const kw of forbiddenKeywords) {
        if (line.includes(kw)) {
            unapprovedPrefilledCount++;
            unapprovedItems.push(`Row ${i + 1} contains forbidden keyword '${kw}'`);
        }
    }
}

// Audit Markdown tables
const mdTableRows = mdContent.split('\n').filter(l => l.startsWith('|') && !l.includes('---') && !l.includes('Parameter Name'));
for (let i = 0; i < mdTableRows.length; i++) {
    const cells = mdTableRows[i].split('|').map(c => c.trim()).slice(1, -1);
    // cells: [ #, Parameter Name, Sample/Time Point, Result Type, Unit, Ref Low, Ref High, Qualitative Options, Source ]
    // Check cells 1 through 8
    for (let cIdx = 1; cIdx < cells.length; cIdx++) {
        if (cells[cIdx] && cells[cIdx].length > 0) {
            unapprovedPrefilledCount++;
            unapprovedItems.push(`Markdown Table row ${i + 1}: Cell index ${cIdx} has prefilled value '${cells[cIdx]}'`);
        }
    }
}

console.log(`\n========================================`);
console.log(`P0_COUNT: 15`);
console.log(`WORKSHEET_ROWS: ${rows.length}`);
console.log(`UNAPPROVED_PREFILLED_COUNT: ${unapprovedPrefilledCount}`);
console.log(`CSV_CLINICAL_FIELDS_CLEAN: ${unapprovedPrefilledCount === 0 ? 'YES' : 'NO'}`);
console.log(`MARKDOWN_CLINICAL_FIELDS_CLEAN: ${unapprovedPrefilledCount === 0 ? 'YES' : 'NO'}`);
console.log(`READY_FOR_LAB_DIRECTOR_INPUT: ${unapprovedPrefilledCount === 0 ? 'YES' : 'NO'}`);
console.log(`========================================\n`);

if (unapprovedItems.length > 0) {
    console.log('Unapproved items found:');
    unapprovedItems.forEach(item => console.log(' - ' + item));
} else {
    console.log('CONFIRMED: All clinical specification fields across both CSV and Markdown are 100% clean and blank.');
}
