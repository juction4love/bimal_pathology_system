import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderFrozenSnapshotPdf } from '../cloudflare/report-artifacts/src/pdf.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const latinFont = fs.readFileSync(path.resolve(__dirname, '../cloudflare/report-artifacts/src/assets/noto-sans-latin.ttf'));
const devanagariFont = fs.readFileSync(path.resolve(__dirname, '../cloudflare/report-artifacts/src/assets/noto-sans-devanagari.ttf'));
const logoPng = fs.readFileSync(path.resolve(__dirname, '../cloudflare/report-artifacts/src/assets/pathology-logo.png'));

const snapshot = {
  "meta": { "version": 1, "signed_at": "2026-09-02T10:23:54.658067+00:00", "is_amendment": false, "signed_by_user_id": "b4022a73-39d0-4501-8262-566776b830f9" },
  "order": { "bill_number": "INV-2026-00049", "reported_at": "2026-09-02T10:23:54.658067+00:00", "order_number": "BPDC-66113930", "registered_date_ad": "2026-09-02", "registered_date_bs": "2083-05-17 BS", "referring_doctor_name": "Self / Walk-in" },
  "patient": { "uhid": "2608296576", "title": "Mr.", "gender": "Male", "mobile": "9855065327", "address": "Bharatpur, Chitwan", "age_years": 52, "full_name": "Bimal Lamichhane" },
  "report_group": { "id": "d2bdb536-e018-4c6f-8ce3-c4122cd5a385", "key": "biochemistry", "title": "Biochemistry", "clinical_section": "Clinical Biochemistry", "configuration_version": 5 },
  "signatories": {
    "performed_by": { "id": "7113fb4b-d852-4f4b-86be-16e1f95809d2", "full_name": "Aliza Thapa Magar", "qualification": "CMLT", "professional_type": "Lab Technician", "registration_number": "B-5963 MLT", "registration_council": "NHPC" },
    "authorized_by": { "id": "c39556d5-d2c3-4281-9c23-d7c1ef886f3d", "full_name": "Dipak Subedi", "qualification": "B.Sc.MLT", "professional_type": "Lab Technologist", "registration_number": "A-909MLT", "registration_council": "NHPC" }
  },
  "organization": { "pan_no": "302481477", "phone": "056-593288", "reg_no": "7-1496", "name_en": "BIMAL PATHOLOGY & DIAGNOSTIC CENTER", "name_ne": "बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर", "address_en": "Bharatpur-7, Chitwan, Nepal" },
  "investigations": [
    {
      "method": "Automated Clinical Chemistry Analyzer",
      "results": [
        { "code": "TBIL", "name": "Bilirubin Total", "unit": "mg/dL", "flag": "Normal", "display_value": "2.2", "numeric_value": 2.2, "parameter_id": "45d166da-9828-4c9f-8ea8-971c22119ce0", "reference_range": "0.200 - 1.200" },
        { "code": "DBIL", "name": "Bilirubin Direct", "unit": "mg/dL", "flag": "Normal", "display_value": "0.5", "numeric_value": 0.5, "parameter_id": "673f8e56-11f8-45e0-82d7-b89bc7e954c2", "reference_range": "0.000 - 0.300" },
        { "code": "SGOT", "name": "SGOT / AST", "unit": "U/L", "flag": "Normal", "display_value": "45", "numeric_value": 45, "parameter_id": "c7aa7c30-4e00-4b68-8093-a9d20c572c41", "reference_range": "5.000 - 40.000" },
        { "code": "SGPT", "name": "SGPT / ALT", "unit": "U/L", "flag": "Normal", "display_value": "32", "numeric_value": 32, "parameter_id": "2783ee85-1d44-4b55-a0cf-6ea65f3f0ae6", "reference_range": "5.000 - 41.000" },
        { "code": "ALP", "name": "Alkaline Phosphatase (ALP)", "unit": "U/L", "flag": "Normal", "display_value": "44", "numeric_value": 44, "parameter_id": "4034ab62-1c6d-46ca-9ef2-1528af29e317", "reference_range": "44.000 - 147.000" },
        { "code": "TP", "name": "Total Protein", "unit": "g/dL", "flag": "Low", "display_value": "6", "numeric_value": 6, "parameter_id": "f3238dd1-bd14-4ed8-8fd4-c54abf13ec03", "reference_range": "6.400 - 8.300" },
        { "code": "ALB", "name": "Albumin", "unit": "g/dL", "flag": "Normal", "display_value": "4", "numeric_value": 4, "parameter_id": "c6655ccd-872d-4066-a975-d5f0995af38f", "reference_range": "3.500 - 5.000" },
        { "code": "GLOB", "name": "Globulin", "unit": "g/dL", "flag": "Normal", "display_value": "2.00", "numeric_value": 2, "parameter_id": "bce6ad4f-7515-416e-94b3-6902c6b9ffea", "reference_range": "Standard", "value_type": "Calculated" },
        { "code": "AG_RATIO", "name": "A:G Ratio", "unit": "ratio", "flag": "Normal", "display_value": "2.00", "numeric_value": 2, "parameter_id": "235aa7bb-80dd-4a50-a23a-70ea72c62500", "reference_range": "Standard", "value_type": "Calculated" }
      ],
      "test_id": "10000000-0000-0000-0000-000000000002",
      "test_code": "LFT",
      "test_name": "Liver Function Test (LFT)",
      "specimen_type": "Serum"
    }
  ]
};

const integrityHash = '3e54127621435d38ff9ca73531057a7f0ddd81be6c6813f439650aaf21c29c97';
const publicUrl = 'https://dashboard.bimalpathology.com.np/o/a9e4bf6e6123c01412472d7ba8660580bc4e03fdb4fe2ae7711f6af6abba0f52';

const t0 = performance.now();
const pdfBytes = await renderFrozenSnapshotPdf(snapshot, integrityHash, {
  latinFont: new Uint8Array(latinFont),
  devanagariFont: new Uint8Array(devanagariFont),
  logoPng: new Uint8Array(logoPng),
  publicUrl,
  reportNumber: 'REP-2026-00043'
});
const t1 = performance.now();
console.log(`Render time: ${(t1 - t0).toFixed(2)} ms, bytes: ${pdfBytes.byteLength}`);
