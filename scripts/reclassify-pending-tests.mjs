// scripts/reclassify-pending-tests.mjs
// Read-only high-confidence audit & reclassification of catalogue tests

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';

const outputDir = path.resolve('scripts/output');
mkdirSync(outputDir, { recursive: true });

// Read the previously exported pending tests CSV
const inputCsvPath = path.join(outputDir, 'configuration_pending_tests.csv');
const inputContent = readFileSync(inputCsvPath, 'utf8');

function parseCsv(text) {
    const lines = text.trim().split('\n');
    const header = lines[0].split(',').map(h => h.trim());
    const rows = [];
    
    for (let i = 1; i < lines.length; i++) {
        const line = lines[i];
        if (!line.trim()) continue;
        
        const row = [];
        let inQuotes = false;
        let currentValue = '';
        
        for (let j = 0; j < line.length; j++) {
            const char = line[j];
            if (char === '"') {
                if (inQuotes && line[j + 1] === '"') {
                    currentValue += '"';
                    j++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (char === ',' && !inQuotes) {
                row.push(currentValue);
                currentValue = '';
            } else {
                currentValue += char;
            }
        }
        row.push(currentValue);
        
        const obj = {};
        header.forEach((h, idx) => {
            obj[h] = row[idx] !== undefined ? row[idx] : '';
        });
        rows.push(obj);
    }
    return rows;
}

const pendingTests = parseCsv(inputContent);
console.log(`Auditing ${pendingTests.length} pending tests with high-confidence clinical rules...`);

// Verified analyzer mapped test codes
const verifiedAnalyzerCapableCodes = new Set([
    // CounCell 23 Excel
    'HEM-0001', 'HEM-0002',
    // CORALAB ACE
    'BIO-0021', 'BIO-0020', 'BIO-0022', 'BIO-0017', 'BIO-0018', 'BIO-0013', 'BIO-0014',
    'BIO-0015', 'BIO-0016', 'BIO-0023', 'BIO-0010', 'BIO-0008', 'BIO-0009', 'BIO-0012',
    'BIO-0001', 'BIO-0002', 'BIO-0003', 'BIO-0027', 'BIO-0028', 'BIO-0029', 'BIO-0030',
    'BIO-0031', 'BIO-0032', 'BIO-0041', 'BIO-0043', 'BIO-0044', 'BIO-0037', 'BIO-0038',
    'BIO-0039', 'BIO-0060', 'BIO-0062', 'BIO-0024', 'BIO-0058',
    // FIAcheck
    'END-0001', 'END-0002', 'END-0003', 'END-0004', 'END-0005', 'BIO-0053', 'BIO-0051',
    'BIO-0063', 'BIO-0061', 'BIO-0065', 'BIO-0067', 'COA-0006', 'BIO-0068', 'PCT_SEPSIS',
    'END-0039', 'BIO-0050'
]);

function classifyClinicalType(test) {
    const cat = (test.category || '').toLowerCase();
    const name = (test.name || '').toLowerCase();
    const code = (test.code || '').toUpperCase();
    const method = (test.method || '').toLowerCase();

    if (cat.includes('histopathology') || name.includes('biopsy') || name.includes('histopathology') || name.includes('resection') || name.includes('radical mastectomy') || name.includes('hysterectomy') || name.includes('appendectomy') || name.includes('cholecystectomy')) {
        return 'HISTOPATHOLOGY_NARRATIVE';
    }
    if (cat.includes('cytology') || name.includes('pap smear') || name.includes('fnac') || name.includes('fluid cytology') || name.includes('brush cytology') || name.includes('cell block') || name.includes('fine needle aspiration')) {
        return 'CYTOLOGY_NARRATIVE';
    }
    if (cat.includes('microbiology') && (name.includes('culture') || name.includes('sensitivity') || name.includes('ast') || name.includes('c/s'))) {
        return 'MICROBIOLOGY_CULTURE';
    }
    if (name.includes('gram stain') || name.includes('zn stain') || name.includes('afb stain') || name.includes('wet mount') || name.includes('koh mount') || name.includes('microscopy') || name.includes('peripheral blood smear') || name.includes('malarial parasite') || name.includes('microfilaria')) {
        return 'MANUAL_MICROSCOPY';
    }
    if (cat.includes('genetics') || cat.includes('cytogenetics') || name.includes('karyotyping') || name.includes('fish') || name.includes('chromosomal')) {
        return 'GENETICS_RESULT';
    }
    if (cat.includes('molecular') || name.includes('pcr') || name.includes('rt-pcr') || name.includes('viral load') || name.includes('genotyping') || name.includes('mutation') || name.includes('genexpert') || name.includes('truenat')) {
        return 'MOLECULAR_RESULT';
    }
    if (cat.includes('profile') || cat.includes('package') || code.startsWith('PRO-') || code.startsWith('PKG-') || name.includes('panel') || name.includes('profile')) {
        return 'PROFILE_PANEL';
    }
    if (cat.includes('coagulation') || code.startsWith('COA-') || name.includes('prothrombin') || name.includes('fibrinogen') || name.includes('thrombin') || name.includes('factor')) {
        return 'COAGULATION';
    }
    if (
        (cat.includes('serology') || cat.includes('immunology')) && (
            name.includes('rapid') || name.includes('card') || name.includes('cassette') || name.includes('strip') || name.includes('latex') || name.includes('pregnancy') || name.includes('vdrl') || name.includes('rpr') || name.includes('hiv') || name.includes('hbsag') || name.includes('hcv') || name.includes('blood group')
        )
    ) {
        return 'QUALITATIVE_RESULT';
    }
    if (cat.includes('allergy') || cat.includes('endocrinology') || cat.includes('tumor') || cat.includes('immunology') || method.includes('elisa') || method.includes('clia') || method.includes('fia') || name.includes('ige') || name.includes('antibody') || name.includes('hormone') || name.includes('psa') || name.includes('ca-125')) {
        return 'IMMUNOASSAY';
    }
    if (cat.includes('hematology') || cat.includes('haematology')) {
        return 'ANALYZER_HEMATOLOGY';
    }
    if (cat.includes('biochemistry') || cat.includes('special chemistry') || cat.includes('toxicology') || cat.includes('blood gas') || cat.includes('point of care')) {
        return 'ANALYZER_CHEMISTRY';
    }
    return 'NUMERIC_ANALYTE';
}

function determineActionableClassification(configType, test) {
    const code = (test.code || '').toUpperCase();
    const paramCount = parseInt(test.parameter_count || '0', 10);
    const rrCount = parseInt(test.reference_range_count || '0', 10);
    const hasRate = test.active_rate && test.active_rate !== 'RATE_PENDING';
    const mappingCount = parseInt(test.analyzer_mapping_count || '0', 10);
    const isVerifiedAnalyzer = verifiedAnalyzerCapableCodes.has(code);

    let rrReq = false;
    let qualReq = false;
    let analyzerMappingReq = isVerifiedAnalyzer;
    let narrativeReq = false;
    let astReq = false;

    switch (configType) {
        case 'HISTOPATHOLOGY_NARRATIVE':
        case 'CYTOLOGY_NARRATIVE':
            narrativeReq = true;
            break;
        case 'MICROBIOLOGY_CULTURE':
            astReq = true;
            break;
        case 'MANUAL_MICROSCOPY':
        case 'QUALITATIVE_RESULT':
        case 'MOLECULAR_RESULT':
            qualReq = true;
            break;
        case 'GENETICS_RESULT':
            qualReq = true;
            narrativeReq = true;
            break;
        case 'COAGULATION':
        case 'IMMUNOASSAY':
        case 'ANALYZER_CHEMISTRY':
        case 'ANALYZER_HEMATOLOGY':
        case 'NUMERIC_ANALYTE':
            rrReq = true;
            break;
    }

    const actionReasons = [];
    let priority = 'P2';
    let status = 'PARTIAL';

    if (paramCount === 0) {
        actionReasons.push('NO_PARAMETERS');
        priority = 'P0';
        status = 'ACTION_REQUIRED';
    } else if (narrativeReq) {
        actionReasons.push('NARRATIVE_TEMPLATE_MISSING');
        priority = 'P1';
        status = 'WORKFLOW_REQUIRED';
    } else if (astReq) {
        actionReasons.push('CULTURE_WORKFLOW_MISSING');
        priority = 'P1';
        status = 'WORKFLOW_REQUIRED';
    } else if (rrReq && rrCount === 0) {
        actionReasons.push('NUMERIC_RANGE_MISSING');
        priority = 'P1';
        status = 'LAB_SPECIFICATION_REQUIRED';
    } else if (qualReq && rrCount === 0) {
        actionReasons.push('QUALITATIVE_OPTIONS_MISSING');
        priority = 'P1';
        status = 'LAB_SPECIFICATION_REQUIRED';
    }

    if (analyzerMappingReq && mappingCount === 0) {
        actionReasons.push('REQUIRED_ANALYZER_MAPPING_MISSING');
    }
    if (!hasRate) {
        actionReasons.push('RATE_MISSING');
    }

    return {
        configuration_type: configType,
        status,
        priority,
        reference_range_required: rrReq ? 'TRUE' : 'FALSE',
        qualitative_config_required: qualReq ? 'TRUE' : 'FALSE',
        analyzer_mapping_required: analyzerMappingReq ? 'TRUE' : 'FALSE',
        narrative_template_required: narrativeReq ? 'TRUE' : 'FALSE',
        antibiotic_susceptibility_required: astReq ? 'TRUE' : 'FALSE',
        action_reason: actionReasons.join('; ')
    };
}

const actionableTests = pendingTests.map(t => {
    const configType = classifyClinicalType(t);
    const reqs = determineActionableClassification(configType, t);

    return {
        code: t.code,
        name: t.name,
        category: t.category,
        configuration_type: reqs.configuration_type,
        status: reqs.status,
        priority: reqs.priority,
        parameter_count: t.parameter_count,
        reference_range_required: reqs.reference_range_required,
        reference_range_count: t.reference_range_count,
        qualitative_config_required: reqs.qualitative_config_required,
        analyzer_mapping_required: reqs.analyzer_mapping_required,
        analyzer_mapping_count: t.analyzer_mapping_count,
        method: t.method,
        specimen: t.specimen,
        active_rate: t.active_rate,
        action_reason: reqs.action_reason
    };
});

const priorityWeight = { 'P0': 0, 'P1': 1, 'P2': 2, 'P3': 3 };
actionableTests.sort((a, b) => {
    const pDiff = (priorityWeight[a.priority] ?? 99) - (priorityWeight[b.priority] ?? 99);
    if (pDiff !== 0) return pDiff;
    const catDiff = a.category.localeCompare(b.category);
    if (catDiff !== 0) return catDiff;
    return a.code.localeCompare(b.code);
});

const escapeCsv = (val) => {
    if (val === null || val === undefined) return '""';
    const str = String(val).replace(/"/g, '""');
    return `"${str}"`;
};

// 1. Export configuration_pending_actionable.csv
const actionableCsvHeader = [
    'code',
    'name',
    'category',
    'configuration_type',
    'status',
    'priority',
    'parameter_count',
    'reference_range_required',
    'reference_range_count',
    'qualitative_config_required',
    'analyzer_mapping_required',
    'analyzer_mapping_count',
    'method',
    'specimen',
    'active_rate',
    'action_reason'
].join(',');

const actionableCsvRows = actionableTests.map(t => [
    escapeCsv(t.code),
    escapeCsv(t.name),
    escapeCsv(t.category),
    escapeCsv(t.configuration_type),
    escapeCsv(t.status),
    escapeCsv(t.priority),
    t.parameter_count,
    escapeCsv(t.reference_range_required),
    t.reference_range_count,
    escapeCsv(t.qualitative_config_required),
    escapeCsv(t.analyzer_mapping_required),
    t.analyzer_mapping_count,
    escapeCsv(t.method || ''),
    escapeCsv(t.specimen || ''),
    escapeCsv(t.active_rate),
    escapeCsv(t.action_reason)
].join(','));

const actionableCsvContent = [actionableCsvHeader, ...actionableCsvRows].join('\n');
const actionableCsvPath = path.join(outputDir, 'configuration_pending_actionable.csv');
writeFileSync(actionableCsvPath, actionableCsvContent, 'utf8');

// 2. Export configuration_pending_actionable_summary.csv
const summaryMap = {};
for (const t of actionableTests) {
    const key = `${t.configuration_type}|||${t.status}|||${t.priority}|||${t.category}`;
    if (!summaryMap[key]) {
        summaryMap[key] = {
            configuration_type: t.configuration_type,
            status: t.status,
            priority: t.priority,
            category: t.category,
            count: 0,
            missing_parameters: 0,
            missing_numeric_ranges: 0,
            missing_qualitative_options: 0,
            missing_analyzer_mappings: 0,
            missing_narrative_templates: 0,
            missing_culture_workflows: 0,
            missing_rates: 0
        };
    }
    const item = summaryMap[key];
    item.count++;
    if (t.action_reason.includes('NO_PARAMETERS')) item.missing_parameters++;
    if (t.action_reason.includes('NUMERIC_RANGE_MISSING')) item.missing_numeric_ranges++;
    if (t.action_reason.includes('QUALITATIVE_OPTIONS_MISSING')) item.missing_qualitative_options++;
    if (t.action_reason.includes('REQUIRED_ANALYZER_MAPPING_MISSING')) item.missing_analyzer_mappings++;
    if (t.action_reason.includes('NARRATIVE_TEMPLATE_MISSING')) item.missing_narrative_templates++;
    if (t.action_reason.includes('CULTURE_WORKFLOW_MISSING')) item.missing_culture_workflows++;
    if (t.action_reason.includes('RATE_MISSING')) item.missing_rates++;
}

const summaryRows = Object.values(summaryMap);
summaryRows.sort((a, b) => {
    const pDiff = (priorityWeight[a.priority] ?? 99) - (priorityWeight[b.priority] ?? 99);
    if (pDiff !== 0) return pDiff;
    const typeDiff = a.configuration_type.localeCompare(b.configuration_type);
    if (typeDiff !== 0) return typeDiff;
    return a.category.localeCompare(b.category);
});

const summaryCsvHeader = [
    'configuration_type',
    'status',
    'priority',
    'category',
    'test_count',
    'missing_parameters',
    'missing_numeric_ranges',
    'missing_qualitative_options',
    'missing_analyzer_mappings',
    'missing_narrative_templates',
    'missing_culture_workflows',
    'missing_rates'
].join(',');

const summaryCsvRowsFormatted = summaryRows.map(r => [
    escapeCsv(r.configuration_type),
    escapeCsv(r.status),
    escapeCsv(r.priority),
    escapeCsv(r.category),
    r.count,
    r.missing_parameters,
    r.missing_numeric_ranges,
    r.missing_qualitative_options,
    r.missing_analyzer_mappings,
    r.missing_narrative_templates,
    r.missing_culture_workflows,
    r.missing_rates
].join(','));

const summaryCsvContent = [summaryCsvHeader, ...summaryCsvRowsFormatted].join('\n');
const summaryCsvPath = path.join(outputDir, 'configuration_pending_actionable_summary.csv');
writeFileSync(summaryCsvPath, summaryCsvContent, 'utf8');

// Summary counts
const statusCounts = {};
const priorityCounts = {};
for (const t of actionableTests) {
    statusCounts[t.status] = (statusCounts[t.status] || 0) + 1;
    priorityCounts[t.priority] = (priorityCounts[t.priority] || 0) + 1;
}

console.log('Status Counts:', statusCounts);
console.log('Priority Counts:', priorityCounts);
