import React, { useEffect } from 'react';
import { createRoot } from 'react-dom/client';
import { ReportDocument } from '@/features/reports/ReportDocument';
import type { ClinicalSnapshot } from '@/lib/reportRenderer';
import { clonePrintElement } from '@/lib/reportPrint';
import { BIMAL_PRINT_CSS } from '@/lib/printDesign';

const requested = new URLSearchParams(window.location.search).get('pages');
const requestedProfile = new URLSearchParams(window.location.search).get('profile');
const preserveReactSource = new URLSearchParams(window.location.search).get('source') === 'react';
const requestedPages = requested === 'N' ? 8 : Math.min(100, Math.max(1, Number(requested) || 1));
const isCbc = requestedPages === 1 && requestedProfile === 'cbc';
const isDenseOnePage = requestedPages === 1 && requestedProfile === 'dense';
const isBoundaryProfile = requestedProfile === 'boundary';
const isIdentityProfile = requestedProfile === 'identity';
const isRealTwoPageExample = requestedProfile === 'urea-cbc-creatinine';
const isRealClinicalRegression = requestedProfile === 'real-cbc-lft-electrolytes';
const isHistoricalSigned = requestedProfile === 'historical-signed';
const isHistoricalAmended = requestedProfile === 'historical-amended';
const isHistoricalMultipage = requestedProfile === 'historical-multipage';
const isWholeBodyStress = requestedProfile === 'whole-body';
const isSparseSerology = requestedProfile === 'sparse-serology';
const isSerumCreatinine = requestedProfile === 'serum-creatinine';
const rowsByPageCount: Record<number, number> = { 1: 8, 2: 30, 3: 45, 4: 62, 5: 78, 8: 130, 12: 190 };
const rowCount = isDenseOnePage ? 14 : rowsByPageCount[requestedPages];
const cbcNames = ['Hemoglobin', 'Total Leukocyte Count', 'Neutrophils', 'Lymphocytes', 'Platelet Count', 'RBC Count', 'Hematocrit', 'MCV'];
const thyroidNames = ['T3, Total', 'T4, Total', 'TSH', 'Free T4'];
const snapshot: ClinicalSnapshot = {
  organization: {
    name_en: 'BIMAL PATHOLOGY & DIAGNOSTIC CENTER',
    name_ne: 'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर',
    address_en: 'Bharatpur-7, Chitwan, Nepal', address_ne: 'भरतपुर-७, चितवन, नेपाल',
    reg_no: '7-1496', pan_no: '302481477', phone: '056-593288',
  },
  patient: {
    uhid: 'QA-2026-0001',
    full_name: isIdentityProfile ? 'श्रीमती प्रज्ञा कुमारी अधिकारी लामिछाने' : 'PRINT PIPELINE QA PATIENT',
    mobile: '9800000000', gender: 'Female', age_years: 32,
    address: isIdentityProfile ? 'भरतपुर महानगरपालिका–७, चितवन, बागमती प्रदेश, नेपाल' : 'Bharatpur, Chitwan',
  },
  order: {
    order_number: 'LAB-QA-0001', bill_number: 'INV-QA-0001',
    registered_date_ad: '2026-08-20T10:00:00+05:45', registered_date_bs: '2083-05-04 BS',
    collected_at: '2026-08-20T10:10:00+05:45', received_at: '2026-08-20T10:25:00+05:45',
    reported_at: '2026-08-20T11:30:00+05:45',
    referring_doctor_name: isIdentityProfile ? 'Dr. A Very Long Referring Clinician Name, MD (Internal Medicine)' : 'Self',
  },
  signatories: {
    performed_by: { id: 'qa-performer', full_name: 'QA Technologist', qualification: 'BMLT', professional_type: 'Medical Laboratory Technologist', registration_council: 'NHPC', registration_number: 'QA-001' },
    authorized_by: requestedProfile === 'one-signatory' ? null : { id: 'qa-authorizer', full_name: 'QA Pathologist', qualification: 'MD Pathology', professional_type: 'Pathologist', specialization: 'Pathology', registration_council: 'NMC', registration_number: 'QA-002' },
  },
  investigations: [{
    order_item_id: 'qa-order-item', test_id: 'qa-test', test_name: isCbc ? 'Complete Blood Count (CBC)' : requestedPages === 1 ? 'Thyroid Function Panel' : isBoundaryProfile ? 'Extended Print QA Profile with a realistically long investigation name that must wrap without collision' : 'Extended Print QA Profile',
    department: isCbc ? 'Hematology' : requestedPages === 1 ? 'Immunology' : 'Hematology', reporting_type: 'InHouse', method: 'Automated analyzer', specimen_type: isCbc ? 'Whole Blood' : 'Serum', container_type: isCbc ? 'EDTA' : 'SST',
    results: Array.from({ length: rowCount }, (_, i) => ({
      parameter_id: `qa-${i}`, code: `QA${i + 1}`, name: isCbc ? cbcNames[i] : requestedPages === 1 && !isDenseOnePage ? thyroidNames[i] : isBoundaryProfile ? `Quality Parameter ${i + 1} with a deliberately long diagnostic parameter name that wraps safely` : `Quality Parameter ${i + 1}`,
      value_type: 'Numeric', display_value: `${10 + i}.5`, numeric_value: 10 + i + 0.5,
      unit: isBoundaryProfile && i % 3 === 0 ? 'international units per litre (IU/L)' : i % 2 ? 'g/dL' : '10³/µL', flag: i === 2 ? 'High' : i === 3 ? 'CriticalHigh' : 'Normal', is_critical: i === 3,
      reference_range: isBoundaryProfile ? 'Age and sex adjusted reference interval: 5.0 - 20.0; interpret alongside the complete clinical context' : '5.0 - 20.0', normal_min: 5, normal_max: 20,
    })),
    interpretation_template: isBoundaryProfile ? 'Clinical interpretation near the page boundary.\nCorrelate these findings with history, examination, medication exposure, and prior laboratory trends.\nThis deliberately multiline comment must remain immediately above the protected final signatory block.' : null,
  }],
  meta: { version: 1, is_amendment: false, signed_at: '2026-08-20T11:30:00+05:45' },
};

if (isSparseSerology) {
  snapshot.patient.full_name = 'SPARSE SEROLOGY QA PATIENT';
  snapshot.investigations = [{
    order_item_id: 'qa-serology', test_id: 'qa-serology', test_name: 'Serology Screening',
    department: 'Serology', reporting_type: 'InHouse', method: 'Rapid immunochromatography',
    specimen_type: 'Serum', container_type: 'SST', interpretation_template: null,
    results: [
      { parameter_id: 'hiv', code: 'HIV', name: 'HIV I & II', value_type: 'Text', display_value: 'Non-Reactive', unit: '-', flag: 'Normal', is_critical: false, reference_range: 'Non-Reactive' },
      { parameter_id: 'hiv-result', code: 'HIV-RESULT', name: 'HIV I & II Result', value_type: 'Text', display_value: 'Non-Reactive', unit: '-', flag: 'Normal', is_critical: false, reference_range: 'Non-Reactive' },
      { parameter_id: 'hbsag', code: 'HBSAG', name: 'HBsAg', value_type: 'Text', display_value: 'Non-Reactive', unit: '-', flag: 'Normal', is_critical: false, reference_range: 'Non-Reactive' },
      { parameter_id: 'hcv', code: 'HCV', name: 'Anti-HCV', value_type: 'Text', display_value: 'Non-Reactive', unit: '-', flag: 'Normal', is_critical: false, reference_range: 'Non-Reactive' },
    ],
  }];
}

if (isSerumCreatinine) {
  snapshot.patient.full_name = 'SERUM CREATININE PRODUCTION-SHAPE PATIENT';
  snapshot.investigations = [{
    order_item_id: 'qa-serum-creatinine', test_id: 'qa-serum-creatinine', test_name: 'Serum Creatinine',
    department: 'Biochemistry', reporting_type: 'InHouse', method: 'Enzymatic', specimen_type: 'Serum',
    container_type: 'SST', interpretation_template: null,
    results: [{
      parameter_id: 'serum-creatinine', code: 'CREAT', name: 'Serum Creatinine', value_type: 'Numeric',
      display_value: '1.0', numeric_value: 1, unit: 'mg/dL', flag: 'Normal', is_critical: false,
      reference_range: 'Male: 0.7 - 1.3; Female: 0.6 - 1.1', normal_min: 0.6, normal_max: 1.3,
    }],
  }];
}

// Exercise the fixed footer with production-worst-case, non-truncated values
// across every requested page count.
(snapshot.organization as { email?: string }).email = 'laboratory.reporting.office@bimalpathology.com.np';

if (isHistoricalSigned || isHistoricalAmended || isHistoricalMultipage) {
  snapshot.patient.full_name = isHistoricalAmended ? 'HISTORICAL AMENDED PATIENT' : isHistoricalMultipage ? 'HISTORICAL MULTIPAGE PATIENT' : 'HISTORICAL SIGNED PATIENT';
  snapshot.order.order_number = isHistoricalAmended ? 'LAB-2019-AMENDED' : isHistoricalMultipage ? 'LAB-2017-MULTIPAGE' : 'LAB-2018-SIGNED';
  snapshot.order.registered_date_ad = isHistoricalAmended ? '2019-04-10T09:30:00+05:45' : '2018-02-05T08:15:00+05:45';
  snapshot.order.reported_at = isHistoricalAmended ? '2019-04-10T15:45:00+05:45' : '2018-02-05T13:20:00+05:45';
  snapshot.meta = {
    version: isHistoricalAmended ? 3 : 1,
    is_amendment: isHistoricalAmended,
    amendment_reason: isHistoricalAmended ? 'Historical corrected result retained in its frozen version.' : null,
    signed_at: snapshot.order.reported_at,
  };
}

if (isRealTwoPageExample) {
  const result = (id: string, name: string, value: string, unit: string, range: string, flag = 'Normal', critical = false) => ({
    parameter_id: id, code: id.toUpperCase(), name, value_type: 'Numeric', display_value: value,
    numeric_value: Number(value), unit, flag, is_critical: critical, reference_range: range,
  });
  snapshot.investigations = [
    { order_item_id: 'qa-urea', test_id: 'qa-urea', test_name: 'Blood Urea', department: 'Biochemistry', reporting_type: 'InHouse', method: 'Urease', specimen_type: 'Serum', container_type: 'SST', results: [result('urea', 'Blood Urea', '28', 'mg/dL', '15 - 45')], interpretation_template: null },
    { order_item_id: 'qa-cbc', test_id: 'qa-cbc', test_name: 'Complete Blood Count (CBC / Hemogram)', department: 'Hematology', reporting_type: 'InHouse', method: 'Automated hematology analyzer', specimen_type: 'Whole Blood', container_type: 'EDTA', results: [
      result('hb', 'Hemoglobin', '10.8', 'g/dL', '12.0 - 16.0', 'Low'), result('tlc', 'Total Leukocyte Count', '13200', '/µL', '4,000 - 11,000', 'High'),
      result('neut', 'Neutrophils', '78', '%', '40 - 75', 'High'), result('lymph', 'Lymphocytes', '18', '%', '20 - 45', 'Low'),
      result('plt', 'Platelet Count', '92000', '/µL', '150,000 - 450,000', 'CriticalLow', true), result('rbc', 'RBC Count', '4.1', '10⁶/µL', '3.8 - 5.2'),
      result('hct', 'Hematocrit', '34', '%', '36 - 46', 'Low'), result('mcv', 'MCV', '82.9', 'fL', '80 - 100'),
    ], interpretation_template: null },
    { order_item_id: 'qa-creatinine', test_id: 'qa-creatinine', test_name: 'Serum Creatinine', department: 'Biochemistry', reporting_type: 'InHouse', method: 'Enzymatic', specimen_type: 'Serum', container_type: 'SST', results: [result('creatinine', 'Serum Creatinine', '1.0', 'mg/dL', 'Male: 0.7 - 1.3; Female: 0.6 - 1.1')], interpretation_template: null },
  ];
}

if (isRealClinicalRegression) {
  const numeric = (id: string, name: string, value: string, unit: string, range: string, flag = 'Normal') => ({
    parameter_id: id, code: id.toUpperCase(), name, value_type: 'Numeric', display_value: value,
    numeric_value: Number(value), unit, flag, is_critical: flag.startsWith('Critical'), reference_range: range,
  });
  const investigation = (id: string, name: string, department: string, results: ReturnType<typeof numeric>[]) => ({
    order_item_id: `real-${id}`, test_id: `real-${id}`, test_name: name, department, reporting_type: 'InHouse',
    method: 'Automated analyzer', specimen_type: department === 'Hematology' ? 'Whole Blood' : 'Serum',
    container_type: department === 'Hematology' ? 'EDTA' : 'SST', results, interpretation_template: null,
  });
  snapshot.investigations = [
    investigation('cbc', 'Complete Blood Count (CBC / Hemogram)', 'Hematology', [
      numeric('hb', 'Hemoglobin', '8.4', 'g/dL', '13 - 17', 'Low'), numeric('tlc', 'Total Leukocyte Count (TLC / WBC)', '8,300', '/cumm', '4000 - 11000', 'Low'),
      numeric('neut', 'Neutrophils', '68', '%', '40 - 75'), numeric('lymph', 'Lymphocytes', '22', '%', '20 - 45'),
      numeric('eos', 'Eosinophils', '06', '%', '1 - 6'), numeric('mono', 'Monocytes', '04', '%', '2 - 10'), numeric('baso', 'Basophils', '00', '%', '0 - 1'),
      numeric('rbc', 'RBC Count', '—', 'million/cumm', '4.5 - 5.9'), numeric('hct', 'Packed Cell Volume (PCV / Hematocrit)', '—', '%', '40 - 52'),
      numeric('mcv', 'Mean Corpuscular Volume (MCV)', '—', 'fL', '80 - 100'), numeric('mch', 'Mean Corpuscular Hemoglobin (MCH)', '—', 'pg', '27 - 33'),
      numeric('mchc', 'Mean Corpuscular Hb Conc (MCHC)', '—', 'g/dL', '32 - 36'), numeric('rdw', 'Red Cell Distribution Width (RDW)', '—', '%', '11.5 - 14.5'),
      numeric('plt', 'Platelet Count', '1,88,000', '/cumm', '150000 - 450000', 'Low'),
    ]),
    investigation('lft', 'Liver Function Test (LFT)', 'Biochemistry', [
      numeric('bilirubin-total', 'Bilirubin Total', '0.78', 'mg/dL', '0.3 - 1.2'), numeric('bilirubin-direct', 'Bilirubin Direct', '0.11', 'mg/dL', '0 - 0.3'),
      numeric('bilirubin-indirect', 'Bilirubin Indirect', '0.67', 'mg/dL', '0.2 - 0.9'), numeric('ast', 'AST / SGOT', '38.0', 'U/L', '10 - 40'),
      numeric('alt', 'ALT / SGPT', '34.0', 'U/L', '7 - 56'), numeric('alp', 'Alkaline Phosphatase (ALP)', '—', 'U/L', '44 - 147'),
      numeric('protein', 'Total Protein', '—', 'g/dL', '6.4 - 8.3'), numeric('albumin', 'Albumin', '—', 'g/dL', '3.5 - 5'),
      numeric('globulin', 'Globulin', '—', 'g/dL', '2 - 3.5'), numeric('ag-ratio', 'A:G Ratio', '—', 'ratio', '1 - 2.5'),
    ]),
    investigation('creatinine', 'Serum Creatinine', 'Biochemistry', [numeric('creatinine', 'Serum Creatinine', '2.8', 'mg/dL', '0.7 - 1.3', 'High')]),
    investigation('sodium', 'Serum Sodium', 'Biochemistry', [numeric('sodium', 'Serum Sodium (Na+)', '135.4', 'mEq/L', '135 - 145')]),
    investigation('potassium', 'Serum Potassium', 'Biochemistry', [numeric('potassium', 'Serum Potassium (K+)', '3.6', 'mEq/L', '3.5 - 5.1')]),
    investigation('urea', 'Blood Urea', 'Biochemistry', [numeric('urea', 'Blood Urea', '98.0', 'mg/dL', '15 - 45', 'High')]),
  ];
  // Keep this physical regression at two pages while retaining representative
  // CBC, LFT, creatinine, sodium, potassium, and urea sections.
  snapshot.investigations[0].results = snapshot.investigations[0].results.slice(0, 10);
  snapshot.investigations[1].results = snapshot.investigations[1].results.slice(0, 6);
}

if (isWholeBodyStress) {
  const resultsPerInvestigation = requestedPages >= 100 ? 113 : requestedPages >= 50 ? 54 : requestedPages >= 24 ? 25 : 14;
  const departments = [
    ['Hematology', 'Complete Blood Count Profile'],
    ['Biochemistry', 'Comprehensive Metabolic Profile'],
    ['Biochemistry', 'Liver Function Profile'],
    ['Biochemistry', 'Kidney Function Profile'],
    ['Biochemistry', 'Lipid Profile'],
    ['Biochemistry', 'Diabetes / Glucose Profile'],
    ['Biochemistry', 'Electrolyte Profile'],
    ['Immunology', 'Thyroid Function Profile'],
    ['Clinical Pathology', 'Urine Examination Profile'],
    ['Serology', 'Serology Screening Profile'],
    ['Immunology', 'Immunology Profile'],
    ['Clinical Pathology', 'Whole Health Review Profile'],
  ];
  snapshot.investigations = departments.map(([department, testName], investigationIndex) => ({
    order_item_id: `whole-body-${investigationIndex + 1}`,
    test_id: `whole-body-test-${investigationIndex + 1}`,
    test_name: testName,
    department,
    reporting_type: 'InHouse',
    method: 'Snapshot-authoritative method',
    specimen_type: investigationIndex === 0 ? 'Whole Blood' : 'Serum',
    container_type: investigationIndex === 0 ? 'EDTA' : 'SST',
    results: Array.from({ length: resultsPerInvestigation + (requestedPages === 100 && investigationIndex === departments.length - 1 ? 3 : 0) }, (_, resultIndex) => ({
      parameter_id: `whole-${investigationIndex + 1}-${resultIndex + 1}`,
      code: `WB${investigationIndex + 1}-${resultIndex + 1}`,
      name: `${testName} Parameter ${resultIndex + 1}`,
      value_type: 'Numeric',
      display_value: `${10 + investigationIndex}.${resultIndex}`,
      numeric_value: 10 + investigationIndex + resultIndex / 10,
      unit: resultIndex % 3 === 0 ? 'mg/dL' : resultIndex % 3 === 1 ? 'U/L' : 'mmol/L',
      flag: resultIndex === 3 ? 'High' : resultIndex === 7 ? 'Low' : 'Normal',
      is_critical: false,
      reference_range: resultIndex % 4 === 0 ? 'Age/sex adjusted snapshot range: 5.0 - 20.0' : '5.0 - 20.0',
    })),
    interpretation_template: investigationIndex === departments.length - 1
      ? 'Whole health package interpretation retained from the signed clinical snapshot. Correlate all reported findings with history and clinical examination.'
      : null,
  }));
}

// Rendering must be observational only: historical snapshots remain exactly as
// supplied while the current presentation and pagination are calculated.
const snapshotBeforeRender = JSON.stringify(snapshot);

export const PrintQa = () => {
  useEffect(() => {
    const timer = window.setTimeout(() => {
      const report = document.getElementById('printable-report');
      if (!report) return;
      const pages = Array.from(report.querySelectorAll<HTMLElement>('.report-page'));
      const signatures = Array.from(report.querySelectorAll<HTMLElement>('.signature-block'));
      const finalPage = pages.at(-1);
      const finalSignature = finalPage?.querySelector<HTMLElement>('.signature-block');
      const finalFooter = finalPage?.querySelector<HTMLElement>('.bimal-footer-strip');
      const finalClinicalContent = finalPage?.querySelector<HTMLElement>('.clinical-end-marker');
      const signatureRect = finalSignature?.getBoundingClientRect();
      const footerRect = finalFooter?.getBoundingClientRect();
      const clinicalRect = finalClinicalContent?.getBoundingClientRect();
      const pageRect = finalPage?.getBoundingClientRect();
      const intermediateSignatureCount = pages.slice(0, -1).reduce((count, page) => count + page.querySelectorAll('.signature-block').length, 0);
      const allSignaturesClear = pages.every((reportPage) => {
        const workspace = reportPage.querySelector<HTMLElement>('.clinical-workspace');
        const flow = reportPage.querySelector<HTMLElement>('.clinical-flow-region');
        const signature = reportPage.querySelector<HTMLElement>('.signature-block');
        return Boolean(workspace && flow && signature &&
          flow.getBoundingClientRect().bottom <= signature.getBoundingClientRect().top &&
          signature.getBoundingClientRect().bottom <= workspace.getBoundingClientRect().bottom);
      });
      document.body.dataset.qaExpectedPageCount = String(requestedPages);
      document.body.dataset.qaPageCount = String(pages.length);
      document.body.dataset.qaSignatureCount = String(signatures.length);
      document.body.dataset.qaIntermediateSignatureCount = String(intermediateSignatureCount);
      document.body.dataset.qaSignatureOnFinalPage = String(Boolean(finalSignature));
      document.body.dataset.qaSignatureOnEveryPage = String(signatures.length === pages.length && allSignaturesClear);
      document.body.dataset.qaContentBeforeSignature = String(Boolean(clinicalRect && signatureRect && clinicalRect.bottom <= signatureRect.top));
      document.body.dataset.qaSignatureBeforeFooter = String(Boolean(signatureRect && footerRect && signatureRect.bottom <= footerRect.top));
      document.body.dataset.qaFinalPageContained = String(Boolean(pageRect && footerRect && signatureRect && signatureRect.top >= pageRect.top && footerRect.bottom <= pageRect.bottom));
      document.body.dataset.qaSnapshotUnchanged = String(snapshotBeforeRender === JSON.stringify(snapshot));
      document.body.dataset.qaSnapshotInvestigationCount = String(snapshot.investigations.length);
      document.body.dataset.qaSnapshotResultCount = String(snapshot.investigations.reduce((count, investigation) => count + investigation.results.length, 0));
      document.body.dataset.qaRenderedInvestigationCount = String(new Set(Array.from(report.querySelectorAll<HTMLElement>('.investigation-block')).map((block) => block.dataset.investigationId)).size);
      document.body.dataset.qaRenderedResultCount = String(report.querySelectorAll('.clinical-result-row').length);
      document.body.dataset.qaPageGeometry = JSON.stringify(pages.map((page) => {
        const workspace = page.querySelector<HTMLElement>('.clinical-workspace')!;
        const workspaceRect = workspace.getBoundingClientRect();
        const contentNodes = Array.from(workspace.children).filter((node) =>
          !node.classList.contains('bimal-page-watermark') && !node.classList.contains('bimal-workspace-texture'));
        const contentBottom = contentNodes.reduce((bottom, node) => Math.max(bottom, node.getBoundingClientRect().bottom), workspaceRect.top);
        return {
          page: Number(page.dataset.reportPage),
          workspaceHeightMm: 189,
          actualUsedMm: Number(((contentBottom - workspaceRect.top) * 25.4 / 96).toFixed(2)),
          actualRemainingMm: Number(((workspaceRect.bottom - contentBottom) * 25.4 / 96).toFixed(2)),
          modeledUsedMm: Number(page.dataset.paginationUsedMm),
          modeledCapacityMm: Number(page.dataset.paginationCapacityMm),
        };
      }));
      document.body.dataset.qaFinalizationReserveMm = String(finalClinicalContent && finalSignature
        ? Number(((signatureRect!.bottom - clinicalRect!.top) * 25.4 / 96).toFixed(2))
        : 0);
      document.body.dataset.qaSignatureFooterGapMm = String(signatureRect && footerRect
        ? Number(((footerRect.top - signatureRect.bottom) * 25.4 / 96).toFixed(2))
        : 0);
      if (!preserveReactSource) {
        const clone = clonePrintElement(report);
        const style = document.createElement('style');
        style.textContent = BIMAL_PRINT_CSS;
        document.head.appendChild(style);
        document.body.replaceChildren(clone);
      }
      document.body.dataset.printCloneReady = 'true';
    }, 500);
    return () => window.clearTimeout(timer);
  }, []);
  const version = isHistoricalSigned || isHistoricalAmended || isHistoricalMultipage ? snapshot.meta.version : 12;
  return <ReportDocument snapshot={snapshot} reportNumber={isHistoricalAmended ? 'RPT-2019-0042' : isHistoricalMultipage ? 'RPT-2017-0008' : isHistoricalSigned ? 'RPT-2018-0017' : 'REP-2026-00010-WHOLE-BODY-COMPREHENSIVE'} version={version} isAmended={snapshot.meta.is_amendment} amendmentReason={snapshot.meta.amendment_reason} integrityHash={'a'.repeat(64)} publicToken={'q'.repeat(40)} />;
};

document.body.style.margin = '0';
document.body.style.background = '#fff';
createRoot(document.getElementById('root')!).render(<PrintQa />);
