// scripts/generate-p0-forms.mjs
// Generate clean Lab Director specification worksheet for the 15 P0 tests
// Absolute zero unapproved clinical values prefilled.

import { writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';

const outputDir = path.resolve('scripts/output');
mkdirSync(outputDir, { recursive: true });

// Authoritative test metadata directly from production database
const p0Tests = [
    {
        code: 'BIO-0141',
        name: 'Cystatin C',
        category: 'Clinical Biochemistry',
        specimen: '',
        method: '',
        why_blocked: 'Zero reportable parameters configured. Result entry is blocked because no parameter exists in database.',
        known_data: 'Test registered in catalogue with active code BIO-0141.',
        rows: [
            { row_label: 'Sample 1' }
        ]
    },
    {
        code: 'END-0056',
        name: 'Oral Glucose Tolerance Test (75 g)',
        category: 'Endocrinology',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        why_blocked: 'Dynamic endocrine protocol with zero configured sample interval parameters.',
        known_data: 'Multi-timed glucose tolerance protocol with 75g oral glucose load.',
        rows: [
            { row_label: 'Sample 1' },
            { row_label: 'Sample 2' },
            { row_label: 'Sample 3' },
            { row_label: 'Sample 4' }
        ]
    },
    {
        code: 'END-0057',
        name: 'Gestational OGTT 75 g',
        category: 'Endocrinology',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        why_blocked: 'Gestational diabetes dynamic protocol with zero configured sample interval parameters.',
        known_data: 'Multi-timed gestational protocol with 75g oral glucose load.',
        rows: [
            { row_label: 'Sample 1' },
            { row_label: 'Sample 2' },
            { row_label: 'Sample 3' }
        ]
    },
    {
        code: 'END-0058',
        name: 'Glucose Challenge Test 50 g',
        category: 'Endocrinology',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        why_blocked: 'Gestational screening protocol with zero configured sample interval parameters.',
        known_data: '50g non-fasting glucose challenge screening test.',
        rows: [
            { row_label: 'Sample 1' }
        ]
    },
    {
        code: 'END-0059',
        name: 'Dexamethasone Suppression Test - Overnight',
        category: 'Endocrinology',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        why_blocked: 'Suppression protocol with zero configured cortisol interval parameters.',
        known_data: 'Overnight 1mg dexamethasone suppression protocol.',
        rows: [
            { row_label: 'Sample 1' },
            { row_label: 'Sample 2' }
        ]
    },
    {
        code: 'END-0060',
        name: 'Low Dose Dexamethasone Suppression Test',
        category: 'Endocrinology',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        why_blocked: 'Multi-day low dose suppression protocol with zero configured sample parameters.',
        known_data: 'Multi-day low-dose dexamethasone suppression protocol.',
        rows: [
            { row_label: 'Sample 1' },
            { row_label: 'Sample 2' },
            { row_label: 'Sample 3' }
        ]
    },
    {
        code: 'END-0061',
        name: 'High Dose Dexamethasone Suppression Test',
        category: 'Endocrinology',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        why_blocked: 'High dose suppression protocol with zero configured sample parameters.',
        known_data: 'High-dose dexamethasone suppression protocol.',
        rows: [
            { row_label: 'Sample 1' },
            { row_label: 'Sample 2' }
        ]
    },
    {
        code: 'END-0062',
        name: 'ACTH Stimulation Test',
        category: 'Endocrinology',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        why_blocked: 'Stimulation protocol with zero configured sample interval parameters.',
        known_data: 'Adrenocortical stimulation protocol.',
        rows: [
            { row_label: 'Sample 1' },
            { row_label: 'Sample 2' },
            { row_label: 'Sample 3' }
        ]
    },
    {
        code: 'END-0063',
        name: 'Growth Hormone Suppression Test',
        category: 'Endocrinology',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        why_blocked: 'GH suppression protocol with zero configured sample interval parameters.',
        known_data: 'Growth hormone suppression protocol.',
        rows: [
            { row_label: 'Sample 1' },
            { row_label: 'Sample 2' },
            { row_label: 'Sample 3' },
            { row_label: 'Sample 4' },
            { row_label: 'Sample 5' }
        ]
    },
    {
        code: 'END-0064',
        name: 'Growth Hormone Stimulation Test',
        category: 'Endocrinology',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        why_blocked: 'GH stimulation protocol with zero configured sample interval parameters.',
        known_data: 'Growth hormone stimulation protocol.',
        rows: [
            { row_label: 'Sample 1' },
            { row_label: 'Sample 2' },
            { row_label: 'Sample 3' },
            { row_label: 'Sample 4' }
        ]
    },
    {
        code: 'END-0065',
        name: 'Water Deprivation Test',
        category: 'Endocrinology',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        why_blocked: 'Multi-analyte deprivation protocol with zero configured sample parameters.',
        known_data: 'Diagnostic water deprivation and response protocol.',
        rows: [
            { row_label: 'Sample 1' },
            { row_label: 'Sample 2' },
            { row_label: 'Sample 3' },
            { row_label: 'Sample 4' }
        ]
    },
    {
        code: 'IMM-0093',
        name: 'Interleukin-6 (IL-6)',
        category: 'Serology & Immunology',
        specimen: '',
        method: '',
        why_blocked: 'Zero reportable parameters configured. Result entry is blocked because no parameter exists in database.',
        known_data: 'Cytokine immunoassay test registered with active code IMM-0093.',
        rows: [
            { row_label: 'Sample 1' }
        ]
    },
    {
        code: 'POC-0002',
        name: 'Venous Blood Gas (VBG)',
        category: 'Point of Care / Blood Gas',
        specimen: 'Heparinized arterial/venous whole blood',
        method: 'Blood gas analyzer',
        why_blocked: 'Panel container with zero configured parameters and zero linked component tests.',
        known_data: 'Venous blood gas panel test registered in Point of Care / Blood Gas category.',
        rows: [
            { row_label: 'Parameter 1' },
            { row_label: 'Parameter 2' },
            { row_label: 'Parameter 3' },
            { row_label: 'Parameter 4' },
            { row_label: 'Parameter 5' },
            { row_label: 'Parameter 6' },
            { row_label: 'Parameter 7' }
        ]
    },
    {
        code: 'SER-0089',
        name: 'Scrub Typhus (FIA IgM/IgG)',
        category: 'Serology & Immunology',
        specimen: '',
        method: 'Fluorescence Immunoassay (FIA)',
        why_blocked: 'Zero reportable parameters configured. Result entry is blocked because no parameter exists in database.',
        known_data: 'Fluorescence Immunoassay for Scrub Typhus antibody detection.',
        rows: [
            { row_label: 'Parameter 1' },
            { row_label: 'Parameter 2' }
        ]
    },
    {
        code: 'SPC-0007',
        name: 'Organic Acids, Urine',
        category: 'Special Chemistry',
        specimen: 'Blood/DBS/Urine/Sweat as specified',
        method: 'Validated screening/LC-MS/MS method',
        why_blocked: 'Zero reportable parameters configured. Result entry is blocked because no parameter exists in database.',
        known_data: 'Specialized metabolic screening test.',
        rows: [
            { row_label: 'Parameter 1' }
        ]
    }
];

const escapeCsv = (val) => {
    if (val === null || val === undefined) return '""';
    const str = String(val).replace(/"/g, '""');
    return `"${str}"`;
};

// 1. Generate CSV Form with strictly blank unapproved clinical fields
const csvHeader = [
    'code',
    'test_name',
    'category',
    'parameter_name',
    'result_type',
    'unit',
    'specimen',
    'method',
    'time_point',
    'reference_low',
    'reference_high',
    'qualitative_options',
    'cutoff',
    'calculation_formula',
    'configured_source',
    'analyzer_name',
    'report_note',
    'lab_approval_status',
    'lab_comments'
].join(',');

const csvRows = [];
for (const test of p0Tests) {
    for (const _r of test.rows) {
        csvRows.push([
            escapeCsv(test.code),
            escapeCsv(test.name),
            escapeCsv(test.category),
            escapeCsv(''), // parameter_name: BLANK
            escapeCsv(''), // result_type: BLANK
            escapeCsv(''), // unit: BLANK
            escapeCsv(test.specimen), // specimen: authoritative DB value or blank
            escapeCsv(test.method),   // method: authoritative DB value or blank
            escapeCsv(''), // time_point: BLANK (no unapproved minutes or schedules)
            escapeCsv(''), // reference_low: BLANK
            escapeCsv(''), // reference_high: BLANK
            escapeCsv(''), // qualitative_options: BLANK
            escapeCsv(''), // cutoff: BLANK
            escapeCsv(''), // calculation_formula: BLANK
            escapeCsv(''), // configured_source: BLANK
            escapeCsv(''), // analyzer_name: BLANK
            escapeCsv(''), // report_note: BLANK
            escapeCsv('PENDING_LAB_APPROVAL'),
            escapeCsv('')  // lab_comments: BLANK
        ].join(','));
    }
}

const csvContent = [csvHeader, ...csvRows].join('\n');
const csvPath = path.join(outputDir, 'p0_lab_specification_form.csv');
writeFileSync(csvPath, csvContent, 'utf8');

// 2. Generate Markdown Form with strictly blank input cells
let mdContent = `# BIMAL PATHOLOGY LIS — LAB DIRECTOR SPECIFICATION WORKSHEET
## High-Priority (P0) Unconfigured Investigations Form

> **Instructions for Laboratory Director / Pathologist:**  
> The following **15 active investigations** currently have zero reportable parameters or component links in the LIS database, preventing result entry.  
> Please review each test section, define the required clinical parameters, reference intervals, units, methodologies, and qualitative options, and approve them for LIS configuration.  
> **Governance Notice:** All clinical fields below are strictly unpopulated for authoritative laboratory specification.

---

`;

p0Tests.forEach((t, idx) => {
    mdContent += `### ${idx + 1}. [${t.code}] ${t.name}\n\n`;
    mdContent += `- **Category:** \`${t.category}\`\n`;
    mdContent += `- **Why Blocked:** ${t.why_blocked}\n`;
    mdContent += `- **Current Authoritative Data Known:** ${t.known_data}\n`;
    mdContent += `- **Current Database Specimen:** \`${t.specimen || 'Pending Validation'}\`\n`;
    mdContent += `- **Current Database Method:** \`${t.method || 'Pending Validation'}\`\n\n`;
    mdContent += `#### Clinical Specification Input Table\n\n`;
    mdContent += `| # | Parameter Name | Sample / Time Point | Result Type (Numeric/Text/Calc) | Unit | Reference Low | Reference High | Qualitative Options / Cutoff | Source (Manual/Analyzer) |\n`;
    mdContent += `| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |\n`;

    t.rows.forEach((r, rIdx) => {
        mdContent += `| ${rIdx + 1} | | | | | | | | |\n`;
    });

    mdContent += `\n- **Validated Analytical Method:** \`____________________________________\`\n`;
    mdContent += `- **Validated Specimen Type:** \`____________________________________\`\n`;
    mdContent += `- **Interpretation / Diagnostic Note Template:**\n`;
    mdContent += `  \`\`\`\n  \n  \`\`\`\n`;
    mdContent += `- **Approval Signature / Date:** \`____________________________________\`\n\n`;
    mdContent += `---\n\n`;
});

const mdPath = path.join(outputDir, 'p0_lab_specification_form.md');
writeFileSync(mdPath, mdContent, 'utf8');
console.log(`Generated completely clean ${csvPath} (${csvRows.length} rows) and ${mdPath}`);
