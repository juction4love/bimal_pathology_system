// scripts/export-p0-specifications.mjs
// Export the exact 15 P0 tests requiring lab director input

import { writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';

const outputDir = path.resolve('scripts/output');
mkdirSync(outputDir, { recursive: true });

const p0Data = [
    {
        code: 'BIO-0141',
        name: 'Cystatin C',
        category: 'Clinical Biochemistry',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Specimen Pending Validation',
        method: 'Method Pending Clinical Validation',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Result entry blocked because no reportable parameter exists.',
        required_lab_input: 'Single analyte definition (Cystatin C); measurement unit (mg/L); age/sex-specific reference intervals; analytical method (e.g. PETIA/Turbidimetry); primary specimen (Serum); analyzer/manual entry source.'
    },
    {
        code: 'END-0056',
        name: 'Oral Glucose Tolerance Test (75 g)',
        category: 'Endocrinology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Timed dynamic endocrine protocol with 0 configured sample interval parameters.',
        required_lab_input: 'Timed sampling parameter names (e.g., Fasting Glucose, 1-Hour Glucose, 2-Hour Glucose); unit (mg/dL); diagnostic cutoff thresholds for normal/impaired/diabetes; protocol administration notes.'
    },
    {
        code: 'END-0057',
        name: 'Gestational OGTT 75 g',
        category: 'Endocrinology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Timed dynamic gestational protocol with 0 configured sample interval parameters.',
        required_lab_input: 'Timed sampling parameter names (e.g., Fasting Glucose, 1-Hour Glucose, 2-Hour Glucose per DIPSI/IADPSG standard); unit (mg/dL); gestational diagnostic cutoffs; protocol instructions.'
    },
    {
        code: 'END-0058',
        name: 'Glucose Challenge Test 50 g',
        category: 'Endocrinology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Screening protocol with 0 configured sample interval parameters.',
        required_lab_input: 'Timed post-load parameter name (e.g., 1-Hour Post-50g Glucose Load); unit (mg/dL); screening cutoff threshold (e.g. <140 mg/dL); patient preparation protocol.'
    },
    {
        code: 'END-0059',
        name: 'Dexamethasone Suppression Test - Overnight',
        category: 'Endocrinology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Timed suppression protocol with 0 configured sample parameters.',
        required_lab_input: 'Sampling parameter names (e.g., Baseline 8 AM Cortisol, Post-Overnight 1mg Dexamethasone 8 AM Cortisol); unit (µg/dL or nmol/L); normal suppression cutoff threshold (e.g. <1.8 µg/dL); analytical method.'
    },
    {
        code: 'END-0060',
        name: 'Low Dose Dexamethasone Suppression Test',
        category: 'Endocrinology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Multi-day timed suppression protocol with 0 configured sample parameters.',
        required_lab_input: 'Multi-point sampling parameter names (e.g., Day 0 Baseline Cortisol, Day 2 Post-0.5mg q6h Cortisol); unit (µg/dL); diagnostic suppression threshold; sampling schedule protocol.'
    },
    {
        code: 'END-0061',
        name: 'High Dose Dexamethasone Suppression Test',
        category: 'Endocrinology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Multi-point suppression protocol with 0 configured sample parameters.',
        required_lab_input: 'Sampling parameter names (e.g., Baseline Cortisol, Post-8mg Dexamethasone Cortisol); unit (µg/dL); suppression percentage criteria (>50% suppression for Cushing disease); protocol schedule.'
    },
    {
        code: 'END-0062',
        name: 'ACTH Stimulation Test',
        category: 'Endocrinology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Timed stimulation protocol with 0 configured sample parameters.',
        required_lab_input: 'Timed sampling parameter names (e.g., Baseline Cortisol [0 min], Post-Synacthen Cortisol [30 min], Post-Synacthen Cortisol [60 min]); unit (µg/dL); normal peak response threshold.'
    },
    {
        code: 'END-0063',
        name: 'Growth Hormone Suppression Test',
        category: 'Endocrinology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Timed GH suppression protocol with 0 configured sample parameters.',
        required_lab_input: 'Timed sampling parameter names (e.g., Baseline GH [0 min], GH [30 min], GH [60 min], GH [90 min], GH [120 min Post-Glucose]); unit (ng/mL); nadir suppression threshold (e.g. <1.0 ng/mL).'
    },
    {
        code: 'END-0064',
        name: 'Growth Hormone Stimulation Test',
        category: 'Endocrinology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Timed GH stimulation protocol with 0 configured sample parameters.',
        required_lab_input: 'Timed sampling parameter names (e.g., Baseline GH, GH [30 min], GH [60 min], GH [90 min Post-Stimulation]); stimulating agent used (Clonidine/Glucagon/L-Dopa/Insulin); unit (ng/mL); peak normal cutoff.'
    },
    {
        code: 'END-0065',
        name: 'Water Deprivation Test',
        category: 'Endocrinology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Serum/Plasma at timed intervals',
        method: 'Protocol-based timed testing',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Complex multi-analyte protocol with 0 configured sample parameters.',
        required_lab_input: 'Protocol parameters list (e.g., Baseline Urine Osmolality, Timed Urine Osmolality, Hourly Body Weight, Plasma Osmolality, Serum Sodium, Post-Desmopressin Urine Osmolality); units (mOsm/kg, mmol/L); differential diagnosis criteria.'
    },
    {
        code: 'IMM-0093',
        name: 'Interleukin-6 (IL-6)',
        category: 'Serology & Immunology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Specimen Pending Validation',
        method: 'Method Pending Clinical Validation',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Single cytokine analyte without reportable parameter.',
        required_lab_input: 'Single parameter definition (Interleukin-6); unit (pg/mL); normal reference interval and acute inflammatory cutoff (e.g. <7.0 pg/mL); analytical method (FIA/CLIA/ELISA); primary specimen (Serum/EDTA Plasma).'
    },
    {
        code: 'POC-0002',
        name: 'Venous Blood Gas (VBG)',
        category: 'Point of Care / Blood Gas',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Heparinized arterial/venous whole blood',
        method: 'Blood gas analyzer',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Panel container with 0 configured parameters and 0 linked component tests.',
        required_lab_input: 'Reportable parameters list (e.g., pH, pvCO2, pvO2, HCO3-, Base Excess, Venous O2 Saturation, Lactate); venous-specific reference intervals (distinct from arterial ABG); analyzer channel mapping.'
    },
    {
        code: 'SER-0089',
        name: 'Scrub Typhus (FIA IgM/IgG)',
        category: 'Serology & Immunology',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Specimen Pending Validation',
        method: 'Fluorescence Immunoassay (FIA)',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Rapid FIA serology test without reportable parameter.',
        required_lab_input: 'Reporting parameters (single overall result or separate Scrub Typhus IgM & Scrub Typhus IgG); result format (Qualitative Negative/Positive or Semi-quantitative Index/Cutoff ratio); specimen type (Serum/Whole Blood); kit method.'
    },
    {
        code: 'SPC-0007',
        name: 'Organic Acids, Urine',
        category: 'Special Chemistry',
        current_parameters: '0',
        current_components: '0',
        specimen: 'Blood/DBS/Urine/Sweat as specified',
        method: 'Validated screening/LC-MS/MS method',
        source: 'Unknown',
        reason_blocked: 'NO_PARAMETERS; Metabolic chromatography assay without reportable parameters.',
        required_lab_input: 'Reporting model (Structured Narrative Interpretation vs Specific Metabolite Panel: Methylmalonic, Glutaric, Orotic acids, etc.); qualitative/quantitative format; reference guidelines; send-out / in-house workflow.'
    }
];

const escapeCsv = (val) => {
    if (val === null || val === undefined) return '""';
    const str = String(val).replace(/"/g, '""');
    return `"${str}"`;
};

const header = [
    'code',
    'name',
    'category',
    'current_parameters',
    'current_components',
    'specimen',
    'method',
    'source',
    'reason_blocked',
    'required_lab_input'
].join(',');

const rows = p0Data.map(d => [
    escapeCsv(d.code),
    escapeCsv(d.name),
    escapeCsv(d.category),
    d.current_parameters,
    d.current_components,
    escapeCsv(d.specimen),
    escapeCsv(d.method),
    escapeCsv(d.source),
    escapeCsv(d.reason_blocked),
    escapeCsv(d.required_lab_input)
].join(','));

const csvContent = [header, ...rows].join('\n');
const csvPath = path.join(outputDir, 'p0_lab_specification_required.csv');
writeFileSync(csvPath, csvContent, 'utf8');
console.log(`Saved exact ${p0Data.length} P0 tests to ${csvPath}`);
