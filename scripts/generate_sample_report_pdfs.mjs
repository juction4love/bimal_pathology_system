import fs from 'node:fs';
import path from 'node:path';
import { renderFrozenSnapshotPdf } from '../cloudflare/report-artifacts/src/pdf.ts';
import { assets, baseSnapshot } from '../cloudflare/report-artifacts/test/fixtures.mjs';
import { renderPages } from '../cloudflare/report-artifacts/test/pdf-tools.mjs';

const outDir = path.resolve(process.cwd(), 'artifacts/sample_reports');
fs.mkdirSync(outDir, { recursive: true });

const cbc24Results = [
  { parameter_id: 'p-wbc', code: 'WBC', name: 'White Blood Cell Count (TLC)', unit: '10^9/L', display_value: '7.5', reference_range: '4.0 - 11.0', flag: 'Normal' },
  { parameter_id: 'p-lym-abs', code: 'LYM_ABS', name: 'Absolute Lymphocyte Count', unit: '10^9/L', display_value: '2.1', reference_range: '1.0 - 3.0', flag: 'Normal' },
  { parameter_id: 'p-mid-abs', code: 'MID_ABS', name: 'Absolute Mid-Range Cell Count', unit: '10^9/L', display_value: '0.5', reference_range: '0.2 - 1.0', flag: 'Normal' },
  { parameter_id: 'p-gran-abs', code: 'GRAN_ABS', name: 'Absolute Granulocyte Count', unit: '10^9/L', display_value: '4.9', reference_range: '2.0 - 7.0', flag: 'Normal' },
  { parameter_id: 'p-lym-pct', code: 'LYM_PERCENT', name: 'Lymphocyte Percentage', unit: '%', display_value: '28.0', reference_range: '20.0 - 40.0', flag: 'Normal' },
  { parameter_id: 'p-mid-pct', code: 'MID_PERCENT', name: 'Mid-Range Cell Percentage', unit: '%', display_value: '6.7', reference_range: '3.0 - 10.0', flag: 'Normal' },
  { parameter_id: 'p-gran-pct', code: 'GRAN_PERCENT', name: 'Granulocyte Percentage', unit: '%', display_value: '65.3', reference_range: '50.0 - 70.0', flag: 'Normal' },
  { parameter_id: 'p-nlr', code: 'NLR', name: 'Neutrophil-to-Lymphocyte Ratio (NLR)', unit: '-', display_value: '2.33', reference_range: '1.0 - 3.0', flag: 'Normal' },
  { parameter_id: 'p-plr', code: 'PLR', name: 'Platelet-to-Lymphocyte Ratio (PLR)', unit: '-', display_value: '119.0', reference_range: '100 - 200', flag: 'Normal' },
  { parameter_id: 'p-rbc', code: 'RBC', name: 'Red Blood Cell Count (RBC)', unit: '10^12/L', display_value: '4.85', reference_range: '4.5 - 5.9', flag: 'Normal' },
  { parameter_id: 'p-hgb', code: 'HGB', name: 'Hemoglobin Concentration', unit: 'g/dL', display_value: '14.2', reference_range: '13.0 - 17.0', flag: 'Normal' },
  { parameter_id: 'p-hct', code: 'HCT', name: 'Hematocrit / Packed Cell Volume (PCV)', unit: '%', display_value: '42.5', reference_range: '40.0 - 50.0', flag: 'Normal' },
  { parameter_id: 'p-mcv', code: 'MCV', name: 'Mean Corpuscular Volume (MCV)', unit: 'fL', display_value: '87.6', reference_range: '80.0 - 100.0', flag: 'Normal' },
  { parameter_id: 'p-mch', code: 'MCH', name: 'Mean Corpuscular Hemoglobin (MCH)', unit: 'pg', display_value: '29.3', reference_range: '27.0 - 32.0', flag: 'Normal' },
  { parameter_id: 'p-mchc', code: 'MCHC', name: 'Mean Corpuscular Hemoglobin Concentration (MCHC)', unit: 'g/dL', display_value: '33.4', reference_range: '32.0 - 36.0', flag: 'Normal' },
  { parameter_id: 'p-rdw-cv', code: 'RDW_CV', name: 'Red Cell Distribution Width - CV (RDW-CV)', unit: '%', display_value: '12.8', reference_range: '11.5 - 14.5', flag: 'Normal' },
  { parameter_id: 'p-rdw-sd', code: 'RDW_SD', name: 'Red Cell Distribution Width - SD (RDW-SD)', unit: 'fL', display_value: '42.1', reference_range: '37.0 - 54.0', flag: 'Normal' },
  { parameter_id: 'p-plt', code: 'PLT', name: 'Platelet Count (PLT)', unit: '10^9/L', display_value: '250', reference_range: '150 - 450', flag: 'Normal' },
  { parameter_id: 'p-mpv', code: 'MPV', name: 'Mean Platelet Volume (MPV)', unit: 'fL', display_value: '8.9', reference_range: '7.4 - 10.4', flag: 'Normal' },
  { parameter_id: 'p-pdw-cv', code: 'PDW_CV', name: 'Platelet Distribution Width - CV (PDW-CV)', unit: '%', display_value: '12.3', reference_range: '9.0 - 17.0', flag: 'Normal' },
  { parameter_id: 'p-pdw-sd', code: 'PDW_SD', name: 'Platelet Distribution Width - SD (PDW-SD)', unit: 'fL', display_value: '11.8', reference_range: '9.0 - 17.0', flag: 'Normal' },
  { parameter_id: 'p-pct', code: 'PCT', name: 'Plateletcrit (PCT)', unit: '%', display_value: '0.22', reference_range: '0.15 - 0.40', flag: 'Normal' },
  { parameter_id: 'p-plcc', code: 'P_LCC', name: 'Platelet Large Cell Count (P-LCC)', unit: '10^9/L', display_value: '55', reference_range: '30 - 90', flag: 'Normal' },
  { parameter_id: 'p-plcr', code: 'P_LCR', name: 'Platelet Large Cell Ratio (P-LCR)', unit: '%', display_value: '22.0', reference_range: '15.0 - 35.0', flag: 'Normal' },
];

const lftResults = [
  { parameter_id: 'p-tb', code: 'TBIL', name: 'Bilirubin, Total', unit: 'mg/dL', display_value: '0.8', reference_range: '0.2 - 1.2', flag: 'Normal' },
  { parameter_id: 'p-db', code: 'DBIL', name: 'Bilirubin, Direct', unit: 'mg/dL', display_value: '0.2', reference_range: '0.0 - 0.3', flag: 'Normal' },
  { parameter_id: 'p-ib', code: 'IBIL', name: 'Bilirubin, Indirect', unit: 'mg/dL', display_value: '0.6', reference_range: '0.2 - 0.9', flag: 'Normal' },
  { parameter_id: 'p-ast', code: 'SGOT', name: 'SGOT / AST', unit: 'U/L', display_value: '28', reference_range: '10 - 40', flag: 'Normal' },
  { parameter_id: 'p-alt', code: 'SGPT', name: 'SGPT / ALT', unit: 'U/L', display_value: '32', reference_range: '10 - 45', flag: 'Normal' },
  { parameter_id: 'p-alp', code: 'ALP', name: 'Alkaline Phosphatase (ALP)', unit: 'U/L', display_value: '85', reference_range: '44 - 147', flag: 'Normal' },
  { parameter_id: 'p-tp', code: 'TP', name: 'Total Protein', unit: 'g/dL', display_value: '7.2', reference_range: '6.4 - 8.3', flag: 'Normal' },
  { parameter_id: 'p-alb', code: 'ALB', name: 'Serum Albumin', unit: 'g/dL', display_value: '4.3', reference_range: '3.5 - 5.0', flag: 'Normal' },
  { parameter_id: 'p-glob', code: 'GLOB', name: 'Serum Globulin', unit: 'g/dL', display_value: '2.9', reference_range: '2.0 - 3.5', flag: 'Normal' },
  { parameter_id: 'p-ag', code: 'AGR', name: 'A:G Ratio', unit: '-', display_value: '1.48', reference_range: '1.2 - 2.2', flag: 'Normal' },
];

async function generateSample(name, invs, patientInfo = {}) {
  const snapshot = structuredClone(baseSnapshot);
  snapshot.patient = { ...snapshot.patient, ...patientInfo };
  snapshot.investigations = invs;
  snapshot.meta.report_number = `REP-2026-${name.toUpperCase()}`;

  const integrity = 'b'.repeat(64);
  const pdfBytes = await renderFrozenSnapshotPdf(snapshot, integrity, { ...assets, reportNumber: snapshot.meta.report_number });
  
  const pdfPath = path.join(outDir, `${name}.pdf`);
  fs.writeFileSync(pdfPath, pdfBytes);

  const canvases = await renderPages(pdfBytes, 1.5);
  for (let i = 0; i < canvases.length; i++) {
    const pngPath = path.join(outDir, `${name}_p${i + 1}.png`);
    fs.writeFileSync(pngPath, canvases[i].toBuffer('image/png'));
  }

  console.log(`[Sample Report] ${name}: Pages = ${canvases.length}, PDF = ${pdfPath}`);
  return { name, pageCount: canvases.length, pdfPath };
}

async function main() {
  console.log('Generating representative sample PDFs...');

  // A. CBC only — exactly 24 parameters
  const cbcReport = await generateSample('A_CBC_Only_24_Params', [{
    order_item_id: 'item-cbc',
    test_id: 'test-cbc',
    test_name: 'Complete Blood Count (CBC / Hemogram)',
    department: 'Hematology',
    reporting_type: 'InHouse',
    method: 'Automated Impedance / Colorimetry',
    specimen_type: 'Whole Blood (EDTA)',
    container_type: 'EDTA Vacutainer',
    results: cbc24Results,
  }], { full_name: 'Ram Bahadur Thapa', title: 'Mr.', gender: 'Male', age_years: 32 });

  // B. CBC + LFT
  const cbcLftReport = await generateSample('B_CBC_Plus_LFT', [
    {
      order_item_id: 'item-cbc',
      test_id: 'test-cbc',
      test_name: 'Complete Blood Count (CBC)',
      department: 'Hematology',
      reporting_type: 'InHouse',
      method: 'Automated Impedance / Colorimetry',
      specimen_type: 'Whole Blood (EDTA)',
      container_type: 'EDTA Vacutainer',
      results: cbc24Results,
    },
    {
      order_item_id: 'item-lft',
      test_id: 'test-lft',
      test_name: 'Liver Function Test (LFT Profile)',
      department: 'Biochemistry',
      reporting_type: 'InHouse',
      method: 'Fully Automated Chemistry Analyzer',
      specimen_type: 'Serum',
      container_type: 'Clot Activator (Gel)',
      results: lftResults,
    }
  ], { full_name: 'Sita Kumari Sharma', title: 'Mrs.', gender: 'Female', age_years: 45 });

  // C. LFT only
  const lftReport = await generateSample('C_LFT_Only', [{
    order_item_id: 'item-lft',
    test_id: 'test-lft',
    test_name: 'Liver Function Test (LFT Profile)',
    department: 'Biochemistry',
    reporting_type: 'InHouse',
    method: 'Fully Automated Chemistry Analyzer',
    specimen_type: 'Serum',
    container_type: 'Clot Activator (Gel)',
    results: lftResults,
  }], { full_name: 'Kabita Subedi', title: null, gender: 'Female', age_years: 28 });

  // D. Multi-page report
  const multiReport = await generateSample('D_Multi_Page_Comprehensive', [
    {
      order_item_id: 'item-cbc',
      test_id: 'test-cbc',
      test_name: 'Complete Blood Count (CBC)',
      department: 'Hematology',
      reporting_type: 'InHouse',
      method: 'Automated Impedance / Colorimetry',
      specimen_type: 'Whole Blood (EDTA)',
      container_type: 'EDTA Vacutainer',
      results: cbc24Results,
    },
    {
      order_item_id: 'item-lft',
      test_id: 'test-lft',
      test_name: 'Liver Function Test (LFT Profile)',
      department: 'Biochemistry',
      reporting_type: 'InHouse',
      method: 'Fully Automated Chemistry Analyzer',
      specimen_type: 'Serum',
      container_type: 'Clot Activator (Gel)',
      results: lftResults,
    },
    {
      order_item_id: 'item-lipid',
      test_id: 'test-lipid',
      test_name: 'Lipid Profile Extended',
      department: 'Biochemistry',
      reporting_type: 'InHouse',
      method: 'Enzymatic Colorimetric',
      specimen_type: 'Serum',
      container_type: 'Clot Activator (Gel)',
      results: [
        { parameter_id: 'p-tc', code: 'CHOL', name: 'Cholesterol, Total', unit: 'mg/dL', display_value: '185', reference_range: '< 200', flag: 'Normal' },
        { parameter_id: 'p-tg', code: 'TRIG', name: 'Triglycerides', unit: 'mg/dL', display_value: '140', reference_range: '< 150', flag: 'Normal' },
        { parameter_id: 'p-hdl', code: 'HDL', name: 'HDL Cholesterol', unit: 'mg/dL', display_value: '48', reference_range: '> 40', flag: 'Normal' },
        { parameter_id: 'p-ldl', code: 'LDL', name: 'LDL Cholesterol (Direct)', unit: 'mg/dL', display_value: '109', reference_range: '< 100', flag: 'Normal' },
        { parameter_id: 'p-vldl', code: 'VLDL', name: 'VLDL Cholesterol', unit: 'mg/dL', display_value: '28', reference_range: '< 30', flag: 'Normal' },
      ],
    }
  ], { full_name: 'Dr. Hari Prasad Adhikari', title: 'Dr.', gender: 'Male', age_years: 58 });

  console.log('\n--- VERIFICATION SUMMARY ---');
  console.log(`CBC_ONLY_PAGE_COUNT: ${cbcReport.pageCount}`);
  console.log(`CBC_PLUS_LFT_PAGE_COUNT: ${cbcLftReport.pageCount}`);
  console.log(`LFT_ONLY_PAGE_COUNT: ${lftReport.pageCount}`);
  console.log(`MULTI_PAGE_COUNT: ${multiReport.pageCount}`);
}

main().catch((err) => {
  console.error('Sample generation failed:', err);
  process.exit(1);
});
