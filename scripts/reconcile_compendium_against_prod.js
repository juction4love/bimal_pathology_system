import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');
const outputDir = path.join(rootDir, 'scripts/output');

if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

// 1. Ingest candidate compendium data
const candidates = [
  {
    test_code: 'BIO-0042',
    parameter_name: 'Ionized Calcium (Ca2+)',
    method: 'Direct Ion-Selective Electrode (ISE), pH adjusted to 7.40',
    specimen: 'Whole Blood (Heparinized) / Serum (Anaerobic)',
    unit: 'mmol/L',
    age_gender_strata: 'Adult (All)',
    reference_low: '1.15',
    reference_high: '1.33',
    clinical_cutoff: '<1.15: Hypocalcemia; >1.33: Hypercalcemia',
    qualitative_options: '',
    critical_low: '0.80',
    critical_high: '1.60',
    source_text: 'Tietz 7th Ed.; CLSI EP28-A3c',
    clinical_note: 'Collect anaerobically on ice; exposure to air and pH changes directly alter ionized fraction.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0042',
    parameter_name: 'Ionized Calcium (Ca2+)',
    method: 'Direct ISE',
    specimen: 'Serum',
    unit: 'mg/dL',
    age_gender_strata: 'Adult (All)',
    reference_low: '4.60',
    reference_high: '5.30',
    clinical_cutoff: '<4.60: Hypocalcemia; >5.30: Hypercalcemia',
    qualitative_options: '',
    critical_low: '3.20',
    critical_high: '6.40',
    source_text: 'Tietz 7th Ed.',
    clinical_note: 'Conventional unit equivalent (1 mmol/L = 4.0 mg/dL).',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0041',
    parameter_name: 'Total Calcium',
    method: 'Arsenazo III / CPC Photometric',
    specimen: 'Serum',
    unit: 'mg/dL',
    age_gender_strata: 'Adult (18–60y)',
    reference_low: '8.6',
    reference_high: '10.2',
    clinical_cutoff: '<8.6: Hypocalcemia; >10.2: Hypercalcemia',
    qualitative_options: '',
    critical_low: '6.5',
    critical_high: '13.0',
    source_text: 'Tietz 7th Ed.; CLSI',
    clinical_note: 'Serum albumin must be evaluated concurrently for albumin-corrected calcium.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0043',
    parameter_name: 'Phosphorus (Inorganic Phosphate)',
    method: 'Phosphomolybdate UV',
    specimen: 'Serum',
    unit: 'mg/dL',
    age_gender_strata: 'Adult (All)',
    reference_low: '2.5',
    reference_high: '4.5',
    clinical_cutoff: '<2.5: Hypophosphatemia; >4.5: Hyperphosphatemia',
    qualitative_options: '',
    critical_low: '1.0',
    critical_high: '8.0',
    source_text: 'Tietz 7th Ed.',
    clinical_note: 'Fasting morning sample preferred due to diurnal fluctuation.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0044',
    parameter_name: 'Magnesium (Mg)',
    method: 'Xylidyl Blue / Calmagite Colorimetric',
    specimen: 'Serum',
    unit: 'mg/dL',
    age_gender_strata: 'Adult (All)',
    reference_low: '1.7',
    reference_high: '2.4',
    clinical_cutoff: '<1.7: Hypomagnesemia; >2.4: Hypermagnesemia',
    qualitative_options: '',
    critical_low: '1.0',
    critical_high: '4.5',
    source_text: 'Tietz 7th Ed.',
    clinical_note: 'Hemolysis falsely elevates magnesium due to high intracellular erythrocyte concentration.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0045',
    parameter_name: 'Serum Iron',
    method: 'Ferrozine / TPTZ Photometric',
    specimen: 'Serum',
    unit: 'µg/dL',
    age_gender_strata: 'Adult Male',
    reference_low: '65',
    reference_high: '175',
    clinical_cutoff: '<65: Iron deficiency; >175: Iron overload/hemochromatosis',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'Tietz 7th Ed.; Henry 24th Ed.',
    clinical_note: 'Strong diurnal rhythm (highest in morning); avoid collection during acute inflammation/infection.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0045',
    parameter_name: 'Serum Iron',
    method: 'Ferrozine / TPTZ Photometric',
    specimen: 'Serum',
    unit: 'µg/dL',
    age_gender_strata: 'Adult Female',
    reference_low: '50',
    reference_high: '170',
    clinical_cutoff: '<50: Iron deficiency; >170: Iron overload',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'Tietz 7th Ed.',
    clinical_note: 'Morning fasting specimen strongly recommended.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0046',
    parameter_name: 'Total Iron Binding Capacity (TIBC)',
    method: 'Direct Ferrozine / Iron saturation',
    specimen: 'Serum',
    unit: 'µg/dL',
    age_gender_strata: 'Adult (All)',
    reference_low: '250',
    reference_high: '425',
    clinical_cutoff: '>425: Elevated in iron deficiency; <250: Low in chronic illness/malnutrition',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'Tietz 7th Ed.',
    clinical_note: 'Measures maximum amount of iron transferrin can bind.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0047',
    parameter_name: 'Unsaturated Iron Binding Capacity (UIBC)',
    method: 'Direct Photometric / Calculated',
    specimen: 'Serum',
    unit: 'µg/dL',
    age_gender_strata: 'Adult (All)',
    reference_low: '120',
    reference_high: '370',
    clinical_cutoff: 'Calculated: TIBC - Serum Iron',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'Tietz 7th Ed.',
    clinical_note: 'Reserve binding capacity of transferrin.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0048',
    parameter_name: 'Transferrin',
    method: 'Immunoturbidimetry',
    specimen: 'Serum',
    unit: 'mg/dL',
    age_gender_strata: 'Adult (All)',
    reference_low: '200',
    reference_high: '360',
    clinical_cutoff: '<200: Negative acute-phase reactant; >360: Increased in iron deficiency',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'IFCC CRM 470; Tietz 7th Ed.',
    clinical_note: 'Standardized protein measurement.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0049',
    parameter_name: 'Transferrin Saturation (TSAT)',
    method: 'Calculated: (Iron/TIBC)*100',
    specimen: 'Serum',
    unit: '%',
    age_gender_strata: 'Adult (All)',
    reference_low: '20',
    reference_high: '50',
    clinical_cutoff: '<20%: Absolute/functional iron deficiency; >50%: Hemochromatosis/overload risk',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'KDIGO Anemia Guidelines; Tietz 7th Ed.',
    clinical_note: 'TSAT <20% strongly diagnostic of iron-restricted erythropoiesis.',
    semantic_type: 'DIAGNOSTIC_DECISION_LIMIT'
  },
  {
    test_code: 'BIO-0050',
    parameter_name: 'Ferritin',
    method: 'CLIA / Immunoturbidimetry',
    specimen: 'Serum',
    unit: 'ng/mL',
    age_gender_strata: 'Adult Male',
    reference_low: '30',
    reference_high: '400',
    clinical_cutoff: '<30: Absolute iron deficiency; >400: Overload / acute phase',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'WHO Guidelines on Ferritin; Tietz 7th Ed.',
    clinical_note: 'Positive acute phase reactant; in presence of inflammation, cutoff for deficiency rises to <100 ng/mL.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'BIO-0050',
    parameter_name: 'Ferritin',
    method: 'CLIA / Immunoturbidimetry',
    specimen: 'Serum',
    unit: 'ng/mL',
    age_gender_strata: 'Adult Female',
    reference_low: '15',
    reference_high: '150',
    clinical_cutoff: '<15: Depleted iron stores; <30: Iron deficiency',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'WHO Guidelines; Tietz 7th Ed.',
    clinical_note: 'Pre-menopausal baseline is lower due to physiological blood loss.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'END-0013',
    parameter_name: 'Cortisol, Morning (8 AM)',
    method: 'CLIA / ECLIA',
    specimen: 'Serum',
    unit: 'µg/dL',
    age_gender_strata: 'Adult (8 AM ± 1h)',
    reference_low: '6.0',
    reference_high: '18.4',
    clinical_cutoff: '<3.0: Adrenal insufficiency suspicion; >18.4: Hypercortisolemia screening',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'Endocrine Society Practice Guidelines; Tietz 7th Ed.',
    clinical_note: 'Draw strictly between 07:00–09:00 AM; subject should be rested and non-stressed.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'END-0014',
    parameter_name: 'Cortisol, Evening (4 PM)',
    method: 'CLIA / ECLIA',
    specimen: 'Serum',
    unit: 'µg/dL',
    age_gender_strata: 'Adult (4 PM ± 1h)',
    reference_low: '2.7',
    reference_high: '10.5',
    clinical_cutoff: 'Normal diurnal rhythm requires evening value to be approximately 50% of morning level',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'Endocrine Society; Tietz 7th Ed.',
    clinical_note: "Loss of diurnal rhythm (elevated evening level) is an early marker of Cushing's syndrome.",
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'END-0015',
    parameter_name: 'Adrenocorticotropic Hormone (ACTH)',
    method: 'CLIA (2-site sandwich)',
    specimen: 'EDTA Plasma (Chilled)',
    unit: 'pg/mL',
    age_gender_strata: 'Adult (8 AM)',
    reference_low: '7.2',
    reference_high: '63.3',
    clinical_cutoff: '<5.0 pg/mL in secondary adrenal insufficiency or autonomous Cushing\'s',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'Endocrine Society; Tietz 7th Ed.',
    clinical_note: 'Highly labile peptide: collect in pre-chilled EDTA tube, centrifuge at 4°C immediately, freeze plasma promptly.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'END-0011',
    parameter_name: 'Parathyroid Hormone (PTH, Intact)',
    method: 'CLIA (2-site sandwich)',
    specimen: 'Serum / EDTA Plasma',
    unit: 'pg/mL',
    age_gender_strata: 'Adult (All)',
    reference_low: '15.0',
    reference_high: '65.0',
    clinical_cutoff: 'Primary hyperparathyroidism: elevated PTH with hypercalcemia; Secondary: elevated PTH with low/normal Ca',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'KDIGO; Endocrine Society; Tietz 7th Ed.',
    clinical_note: 'Must always be interpreted concurrently with serum calcium and vitamin D levels.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'END-0025',
    parameter_name: 'Prolactin',
    method: 'CLIA (standardized to WHO 84/500)',
    specimen: 'Serum',
    unit: 'ng/mL',
    age_gender_strata: 'Adult Male',
    reference_low: '4.0',
    reference_high: '15.2',
    clinical_cutoff: '>200: Strongly indicative of prolactinoma; 25–100: Non-adenoma hyperprolactinemia',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'Endocrine Society; Tietz 7th Ed.',
    clinical_note: 'Stress, venipuncture anxiety, and palpation cause transient spikes. Draw 2h after waking.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'END-0025',
    parameter_name: 'Prolactin',
    method: 'CLIA',
    specimen: 'Serum',
    unit: 'ng/mL',
    age_gender_strata: 'Adult Female (Non-pregnant)',
    reference_low: '4.8',
    reference_high: '23.3',
    clinical_cutoff: 'Postmenopausal: 3.0–18.0 ng/mL',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'Endocrine Society',
    clinical_note: 'Screen for macroprolactinemia (PEG precipitation) if elevated in asymptomatic patient.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'END-0039',
    parameter_name: 'Beta-hCG, Quantitative',
    method: 'CLIA (Total β-subunit)',
    specimen: 'Serum',
    unit: 'mIU/mL',
    age_gender_strata: 'Non-pregnant Adult Female',
    reference_low: '0.0',
    reference_high: '5.0',
    clinical_cutoff: '<5.0: Negative; 5–25: Equivocal (repeat in 48h); >25: Positive for pregnancy',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'ACOG; Tietz 7th Ed.',
    clinical_note: 'Doubles every 48–72h in normal intrauterine pregnancy during the first 6–8 weeks.',
    semantic_type: 'DIAGNOSTIC_DECISION_LIMIT'
  },
  {
    test_code: 'TOX-0001',
    parameter_name: 'Lithium',
    method: 'Direct ISE / Flame Photometry',
    specimen: 'Serum (No gel tube)',
    unit: 'mmol/L',
    age_gender_strata: 'Adult (Trough, 12h post-dose)',
    reference_low: '0.60',
    reference_high: '1.20',
    clinical_cutoff: 'Acute Mania: 0.8–1.2; Maintenance: 0.6–0.8',
    qualitative_options: '',
    critical_low: '0.40',
    critical_high: '1.50',
    source_text: 'Tietz 7th Ed.; APA Guidelines',
    clinical_note: 'Draw exactly 12h post evening dose (steady-state). Use plain red top only (lithium heparin causes massive artifact).',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'TOX-0002',
    parameter_name: 'Valproic Acid (Sodium Valproate)',
    method: 'Immunoassay (FPIA / EMIT / PETINIA)',
    specimen: 'Serum',
    unit: 'µg/mL',
    age_gender_strata: 'Adult (Trough)',
    reference_low: '50.0',
    reference_high: '100.0',
    clinical_cutoff: 'Therapeutic range: 50–100 µg/mL; Toxicity commonly manifests >125 µg/mL',
    qualitative_options: '',
    critical_low: '',
    critical_high: '150.0',
    source_text: 'Tietz 7th Ed.; ILAE',
    clinical_note: 'Highly protein-bound (~90%); free valproate may be monitored in hypoalbuminemia or renal failure.',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'TOX-0003',
    parameter_name: 'Carbamazepine',
    method: 'Immunoassay (FPIA / EMIT / PETINIA)',
    specimen: 'Serum',
    unit: 'µg/mL',
    age_gender_strata: 'Adult (Trough)',
    reference_low: '4.0',
    reference_high: '12.0',
    clinical_cutoff: 'Therapeutic range: 4–12 µg/mL; Toxic signs (ataxia, nystagmus) common >15 µg/mL',
    qualitative_options: '',
    critical_low: '',
    critical_high: '15.0',
    source_text: 'Tietz 7th Ed.; ILAE',
    clinical_note: 'Auto-induction of hepatic metabolism occurs during first 4–6 weeks of therapy.',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'TOX-0004',
    parameter_name: 'Phenytoin',
    method: 'Immunoassay (FPIA / EMIT / PETINIA)',
    specimen: 'Serum',
    unit: 'µg/mL',
    age_gender_strata: 'Adult (Trough)',
    reference_low: '10.0',
    reference_high: '20.0',
    clinical_cutoff: 'Therapeutic range: 10–20 µg/mL; Nystagmus >20; Ataxia >30; Encephalopathy >40',
    qualitative_options: '',
    critical_low: '',
    critical_high: '25.0',
    source_text: 'Tietz 7th Ed.; ILAE',
    clinical_note: 'Exhibits Michaelis-Menten (non-linear) kinetics; small dose increases produce disproportionate concentration rises.',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'TOX-0005',
    parameter_name: 'Vancomycin (Trough)',
    method: 'Immunoassay (PETINIA / FPIA)',
    specimen: 'Serum',
    unit: 'µg/mL',
    age_gender_strata: 'Adult (Trough, 30m pre-dose)',
    reference_low: '10.0',
    reference_high: '20.0',
    clinical_cutoff: 'Standard infections: 10–15; Severe (MRSA pneumonia, endocarditis, sepsis): 15–20',
    qualitative_options: '',
    critical_low: '',
    critical_high: '25.0',
    source_text: 'IDSA / ASHP Vancomycin Guidelines 2020; Tietz 7th Ed.',
    clinical_note: 'Trough drawn within 30 min prior to next dose at steady state (prior to 4th dose); >20 µg/mL significantly increases nephrotoxicity.',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'TOX-0006',
    parameter_name: 'Digoxin',
    method: 'Immunoassay (ECLIA / CLIA / FPIA)',
    specimen: 'Serum',
    unit: 'ng/mL',
    age_gender_strata: 'Adult (Trough, ≥6–8h post-dose)',
    reference_low: '0.8',
    reference_high: '2.0',
    clinical_cutoff: 'Heart Failure: 0.5–0.9 ng/mL; Atrial Fibrillation: 0.8–1.5 ng/mL',
    qualitative_options: '',
    critical_low: '',
    critical_high: '2.5',
    source_text: 'AHA/ACC Heart Failure Guidelines; Tietz 7th Ed.',
    clinical_note: 'Collect at least 6–8h post oral dose to permit complete tissue-plasma distribution. Hypokalemia exacerbates toxicity.',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'TOX-0007',
    parameter_name: 'Theophylline',
    method: 'Immunoassay (FPIA / EMIT)',
    specimen: 'Serum',
    unit: 'µg/mL',
    age_gender_strata: 'Adult (Trough)',
    reference_low: '10.0',
    reference_high: '20.0',
    clinical_cutoff: 'Bronchodilation: 10–20 µg/mL (optimal 5–15 µg/mL in modern protocols)',
    qualitative_options: '',
    critical_low: '',
    critical_high: '25.0',
    source_text: 'Tietz 7th Ed.',
    clinical_note: 'Arrhythmias and seizures may occur at levels >25 µg/mL without prior minor symptoms.',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'TOX-0008',
    parameter_name: 'Methotrexate (MTX)',
    method: 'Immunoassay (FPIA / ECLIA)',
    specimen: 'Serum',
    unit: 'µmol/L',
    age_gender_strata: 'Post High-Dose MTX Infusion',
    reference_low: '0.00',
    reference_high: '0.05',
    clinical_cutoff: '24h post: <5.0; 48h post: <0.5; 72h post: <0.1 µmol/L (Leucovorin rescue threshold)',
    qualitative_options: '',
    critical_low: '',
    critical_high: '10.0',
    source_text: 'ASCO / Tietz 7th Ed.',
    clinical_note: 'High-dose rescue monitoring: levels determine required folinic acid (leucovorin) dosage and duration.',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'TOX-0009',
    parameter_name: 'Cyclosporine (A)',
    method: 'Whole Blood Immunoassay / LC-MS/MS',
    specimen: 'Whole Blood (EDTA)',
    unit: 'ng/mL',
    age_gender_strata: 'Adult (Trough C0)',
    reference_low: '100',
    reference_high: '400',
    clinical_cutoff: 'Renal transplant maintenance: 100–200; Acute phase post-transplant: 200–400 ng/mL',
    qualitative_options: '',
    critical_low: '',
    critical_high: '450',
    source_text: 'KDIGO Transplant Guidelines; Tietz 7th Ed.',
    clinical_note: 'Must use EDTA whole blood (erythrocyte-bound drug); never use serum or plasma.',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'TOX-0010',
    parameter_name: 'Tacrolimus (FK-506)',
    method: 'Whole Blood Immunoassay / LC-MS/MS',
    specimen: 'Whole Blood (EDTA)',
    unit: 'ng/mL',
    age_gender_strata: 'Adult (Trough C0)',
    reference_low: '5.0',
    reference_high: '15.0',
    clinical_cutoff: 'Maintenance: 5–10 ng/mL; Early post-transplant (1–3 mo): 10–15 ng/mL',
    qualitative_options: '',
    critical_low: '',
    critical_high: '20.0',
    source_text: 'KDIGO Transplant Guidelines; Tietz 7th Ed.',
    clinical_note: 'Must use EDTA whole blood. Peak trough drawn 12h post evening dose immediately before morning dose.',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'TUM-0001',
    parameter_name: 'Carcinoembryonic Antigen (CEA)',
    method: 'CLIA / ECLIA',
    specimen: 'Serum',
    unit: 'ng/mL',
    age_gender_strata: 'Adult Non-smoker',
    reference_low: '0.0',
    reference_high: '3.0',
    clinical_cutoff: 'Non-smoker: <3.0; Smoker: <5.0; Malignancy suspicion: >10.0',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'EGTM Guidelines; Tietz 7th Ed.',
    clinical_note: 'For disease monitoring and recurrence detection in colorectal carcinoma; not for primary population screening.',
    semantic_type: 'DIAGNOSTIC_DECISION_LIMIT'
  },
  {
    test_code: 'TUM-0002',
    parameter_name: 'Alpha-Fetoprotein (AFP, Tumor Marker)',
    method: 'CLIA / ECLIA',
    specimen: 'Serum',
    unit: 'ng/mL',
    age_gender_strata: 'Adult (All non-pregnant)',
    reference_low: '0.0',
    reference_high: '7.0',
    clinical_cutoff: 'Hepatocellular carcinoma (HCC) cutoff: >20 ng/mL (diagnostic when >200 ng/mL with imaging)',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'AASLD Guidelines; Tietz 7th Ed.',
    clinical_note: 'Markedly elevated in HCC and non-seminomatous germ cell testicular tumors.',
    semantic_type: 'DIAGNOSTIC_DECISION_LIMIT'
  },
  {
    test_code: 'TUM-0003',
    parameter_name: 'Cancer Antigen 125 (CA 125)',
    method: 'CLIA / ECLIA',
    specimen: 'Serum',
    unit: 'U/mL',
    age_gender_strata: 'Adult Female',
    reference_low: '0.0',
    reference_high: '35.0',
    clinical_cutoff: 'Postmenopausal cutoff: <35.0 U/L; Elevated in ovarian malignancy, endometriosis, peritonitis',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'NCCN; SGO; Tietz 7th Ed.',
    clinical_note: 'Benign elevations common in premenopausal women during menstruation and pregnancy.',
    semantic_type: 'DIAGNOSTIC_DECISION_LIMIT'
  },
  {
    test_code: 'TUM-0004',
    parameter_name: 'Carbohydrate Antigen 19-9 (CA 19-9)',
    method: 'CLIA / ECLIA',
    specimen: 'Serum',
    unit: 'U/mL',
    age_gender_strata: 'Adult (All)',
    reference_low: '0.0',
    reference_high: '37.0',
    clinical_cutoff: 'Pancreatic adenocarcinoma monitoring threshold: >37.0 U/mL',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'ASCO; Tietz 7th Ed.',
    clinical_note: 'Individuals who are Lewis antigen negative (Le a-b-, ~5–10% of population) do not express CA 19-9.',
    semantic_type: 'DIAGNOSTIC_DECISION_LIMIT'
  },
  {
    test_code: 'TUM-0005',
    parameter_name: 'Cancer Antigen 15-3 (CA 15-3)',
    method: 'CLIA / ECLIA',
    specimen: 'Serum',
    unit: 'U/mL',
    age_gender_strata: 'Adult Female',
    reference_low: '0.0',
    reference_high: '25.0',
    clinical_cutoff: 'Metastatic breast cancer monitoring threshold: >25.0–30.0 U/mL',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'ASCO; EGTM; Tietz 7th Ed.',
    clinical_note: 'Useful in assessing therapeutic response in advanced breast cancer.',
    semantic_type: 'DIAGNOSTIC_DECISION_LIMIT'
  },
  {
    test_code: 'TUM-0006',
    parameter_name: 'Prostate-Specific Antigen (PSA, Total)',
    method: 'CLIA (WHO 96/670 standard)',
    specimen: 'Serum',
    unit: 'ng/mL',
    age_gender_strata: 'Adult Male (40–49y)',
    reference_low: '0.0',
    reference_high: '2.5',
    clinical_cutoff: 'Age-specific: 40–49y: <2.5; 50–59y: <3.5; 60–69y: <4.5; 70–79y: <6.5',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'AUA / EAU Guidelines; Tietz 7th Ed.',
    clinical_note: 'Diagnostic gray zone: 4.0–10.0 ng/mL (evaluate Free/Total PSA ratio before biopsy).',
    semantic_type: 'DIAGNOSTIC_DECISION_LIMIT'
  },
  {
    test_code: 'TUM-0007',
    parameter_name: 'Free PSA',
    method: 'CLIA',
    specimen: 'Serum',
    unit: 'ng/mL',
    age_gender_strata: 'Adult Male (PSA 4–10)',
    reference_low: '',
    reference_high: '',
    clinical_cutoff: 'Free/Total PSA Ratio: >25% (low cancer risk); <10% (high cancer risk ~56%)',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'AUA / EAU Guidelines; Tietz 7th Ed.',
    clinical_note: 'Free PSA is unstable; serum must be separated from clot within 2 hours and frozen if not run immediately.',
    semantic_type: 'DIAGNOSTIC_DECISION_LIMIT'
  },
  {
    test_code: 'COA-0001',
    parameter_name: 'Prothrombin Time (PT)',
    method: 'Optical / Mechanical Clotting',
    specimen: 'Citrated Plasma (3.2% Na-Citrate)',
    unit: 'seconds',
    age_gender_strata: 'Adult (All)',
    reference_low: '11.0',
    reference_high: '14.0',
    clinical_cutoff: 'Reagent-dependent lot baseline (MNPT typically 11.5–13.0s)',
    qualitative_options: '',
    critical_low: '',
    critical_high: '30.0',
    source_text: 'CLSI H54-A; ISTH',
    clinical_note: 'Tube must be filled to the exact indicator mark (9:1 blood-to-anticoagulant ratio).',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'COA-0002',
    parameter_name: 'International Normalized Ratio (INR)',
    method: 'Calculated: (PT / MNPT)^ISI',
    specimen: 'Citrated Plasma',
    unit: 'ratio',
    age_gender_strata: 'Non-anticoagulated Adult',
    reference_low: '0.85',
    reference_high: '1.15',
    clinical_cutoff: 'Therapeutic target: DVT/PE/AF: 2.0–3.0; Mechanical Mitral Valve: 2.5–3.5',
    qualitative_options: '',
    critical_low: '',
    critical_high: '4.5',
    source_text: 'WHO; CHEST Guidelines; ISTH',
    clinical_note: 'Mandatory panic notification at INR >4.5 due to elevated spontaneous intracranial/major bleeding risk.',
    semantic_type: 'THERAPEUTIC_TARGET'
  },
  {
    test_code: 'COA-0003',
    parameter_name: 'Activated Partial Thromboplastin Time (APTT)',
    method: 'Optical / Mechanical Clotting',
    specimen: 'Citrated Plasma',
    unit: 'seconds',
    age_gender_strata: 'Adult (All)',
    reference_low: '26.0',
    reference_high: '38.0',
    clinical_cutoff: 'Therapeutic Heparin target: 1.5–2.5 x baseline mean (typically 60–85s)',
    qualitative_options: '',
    critical_low: '',
    critical_high: '70.0',
    source_text: 'CLSI H47-A2; ISTH',
    clinical_note: 'Sensitive to contact factor deficiencies (XII, XI, IX, VIII) and lupus anticoagulants.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'COA-0004',
    parameter_name: 'Fibrinogen (Clauss Method)',
    method: 'Clauss Clotting Assay',
    specimen: 'Citrated Plasma',
    unit: 'mg/dL',
    age_gender_strata: 'Adult (All)',
    reference_low: '200',
    reference_high: '400',
    clinical_cutoff: '<150: Hypofibrinogenemia / Consumption (DIC); <100: Severe bleeding risk',
    qualitative_options: '',
    critical_low: '100',
    critical_high: '',
    source_text: 'CLSI H30-A2; ISTH',
    clinical_note: 'Positive acute phase reactant; elevated in pregnancy, inflammation, and cardiovascular risk.',
    semantic_type: 'BIOLOGICAL_REFERENCE_INTERVAL'
  },
  {
    test_code: 'COA-0006',
    parameter_name: 'D-Dimer',
    method: 'Quantitative Immunoturbidimetry / FEU',
    specimen: 'Citrated Plasma',
    unit: 'µg/mL FEU',
    age_gender_strata: 'Adult (All)',
    reference_low: '0.00',
    reference_high: '0.50',
    clinical_cutoff: 'VTE / PE Exclusion threshold: <0.50 µg/mL FEU (Fibrinogen Equivalent Units)',
    qualitative_options: '',
    critical_low: '',
    critical_high: '',
    source_text: 'CLSI H59-A; ISTH',
    clinical_note: 'High negative predictive value (>98%) to rule out DVT/PE when combined with clinical pre-test probability (Wells score).',
    semantic_type: 'DIAGNOSTIC_DECISION_LIMIT'
  },
  {
    test_code: 'SER-0004',
    parameter_name: 'Hepatitis B Surface Antigen (HBsAg)',
    method: 'Rapid ICT / CLIA',
    specimen: 'Serum / Plasma',
    unit: 'Index',
    age_gender_strata: 'All',
    reference_low: '',
    reference_high: '',
    clinical_cutoff: 'Index <0.90: Non-reactive; 0.90–1.00: Grayzone; >=1.00: Reactive',
    qualitative_options: 'Non-reactive / Reactive',
    critical_low: '',
    critical_high: '',
    source_text: 'WHO Hepatitis Guidelines; CDC',
    clinical_note: 'Initial reactive screens must be confirmed by neutralization assay or repeat in duplicate.',
    semantic_type: 'QUALITATIVE_INTERPRETATION'
  },
  {
    test_code: 'SER-0010',
    parameter_name: 'Anti-HCV Total Antibody',
    method: 'Rapid ICT / CLIA',
    specimen: 'Serum / Plasma',
    unit: 'Index',
    age_gender_strata: 'All',
    reference_low: '',
    reference_high: '',
    clinical_cutoff: 'S/CO <1.00: Non-reactive; >=1.00: Reactive',
    qualitative_options: 'Non-reactive / Reactive',
    critical_low: '',
    critical_high: '',
    source_text: 'CDC Hepatitis C Screening; WHO',
    clinical_note: 'Reactive antibody indicates exposure; active infection requires confirmatory HCV RNA PCR testing.',
    semantic_type: 'QUALITATIVE_INTERPRETATION'
  },
  {
    test_code: 'SER-0001',
    parameter_name: 'HIV 1/2 Antigen/Antibody (4th Gen)',
    method: 'Rapid ICT / CLIA',
    specimen: 'Serum / Plasma',
    unit: 'Index',
    age_gender_strata: 'All',
    reference_low: '',
    reference_high: '',
    clinical_cutoff: 'Index <1.00: Non-reactive; >=1.00: Reactive',
    qualitative_options: 'Non-reactive / Reactive',
    critical_low: '',
    critical_high: '',
    source_text: 'CDC HIV Testing Algorithm; WHO',
    clinical_note: 'Detects HIV-1 p24 antigen and antibodies to HIV-1/2, narrowing the diagnostic window period to 2–3 weeks.',
    semantic_type: 'QUALITATIVE_INTERPRETATION'
  },
  {
    test_code: 'SER-0015',
    parameter_name: 'Dengue NS1 Antigen',
    method: 'Rapid ICT / FIA',
    specimen: 'Serum / Plasma',
    unit: 'Index',
    age_gender_strata: 'All (Fever Day 1–5)',
    reference_low: '',
    reference_high: '',
    clinical_cutoff: 'Index <1.00: Negative; >=1.00: Positive',
    qualitative_options: 'Negative / Positive',
    critical_low: '',
    critical_high: '',
    source_text: 'WHO Dengue Guidelines',
    clinical_note: 'Primary diagnostic marker during early acute phase (Days 1 to 5 of symptom onset).',
    semantic_type: 'QUALITATIVE_INTERPRETATION'
  },
  {
    test_code: 'SER-0016',
    parameter_name: 'Dengue IgM Antibody',
    method: 'Rapid ICT / MAC-ELISA',
    specimen: 'Serum / Plasma',
    unit: 'Index',
    age_gender_strata: 'All (Fever Day 5+)',
    reference_low: '',
    reference_high: '',
    clinical_cutoff: 'Index <1.00: Negative; >=1.00: Positive',
    qualitative_options: 'Negative / Positive',
    critical_low: '',
    critical_high: '',
    source_text: 'WHO Dengue Guidelines',
    clinical_note: 'Appears approximately day 5 post symptom onset, indicating primary or secondary acute infection.',
    semantic_type: 'QUALITATIVE_INTERPRETATION'
  },
  {
    test_code: 'SER-0017',
    parameter_name: 'Dengue IgG Antibody',
    method: 'Rapid ICT / ELISA',
    specimen: 'Serum / Plasma',
    unit: 'Index',
    age_gender_strata: 'All',
    reference_low: '',
    reference_high: '',
    clinical_cutoff: 'Index <1.00: Negative; >=1.00: Positive',
    qualitative_options: 'Negative / Positive',
    critical_low: '',
    critical_high: '',
    source_text: 'WHO Dengue Guidelines',
    clinical_note: 'Elevated early in high titers indicates secondary dengue infection (increased dengue hemorrhagic fever risk).',
    semantic_type: 'QUALITATIVE_INTERPRETATION'
  },
  {
    test_code: 'SER-0008',
    parameter_name: 'Syphilis (VDRL / RPR)',
    method: 'Flocculation Macro/Microscopy',
    specimen: 'Serum / CSF',
    unit: 'Titer',
    age_gender_strata: 'All',
    reference_low: '',
    reference_high: '',
    clinical_cutoff: 'Non-reactive at 1:1; Reactive requires quantitative titer reporting (e.g., 1:2, 1:4, 1:8, 1:16, 1:32)',
    qualitative_options: 'Non-reactive / Reactive',
    critical_low: '',
    critical_high: '',
    source_text: 'CDC STI Treatment Guidelines 2021',
    clinical_note: 'Non-treponemal test: 4-fold titer change (e.g., 1:32 to 1:8) signifies adequate therapeutic response.',
    semantic_type: 'QUALITATIVE_INTERPRETATION'
  },
  {
    test_code: 'SER-0024',
    parameter_name: 'Widal Test (S. Typhi O & H)',
    method: 'Slide / Tube Agglutination',
    specimen: 'Serum',
    unit: 'Titer',
    age_gender_strata: 'Endemic region baseline',
    reference_low: '',
    reference_high: '',
    clinical_cutoff: 'Significant cutoff: S. Typhi O >=1:160, S. Typhi H >=1:160',
    qualitative_options: '<1:80, 1:80, 1:160, 1:320, 1:640',
    critical_low: '',
    critical_high: '',
    source_text: 'WHO Guideline on Typhoid Fever',
    clinical_note: 'Paired sera (10–14 days apart) demonstrating a 4-fold titer rise provides definitive serodiagnosis.',
    semantic_type: 'QUALITATIVE_INTERPRETATION'
  },
  {
    test_code: 'SER-0089',
    parameter_name: 'Scrub Typhus (O. tsutsugamushi IgM)',
    method: 'FIA / Immunochromatography',
    specimen: 'Serum / Whole Blood',
    unit: 'Index',
    age_gender_strata: 'All',
    reference_low: '',
    reference_high: '',
    clinical_cutoff: 'Index <1.00: Negative; >=1.00: Positive',
    qualitative_options: 'Negative / Positive',
    critical_low: '',
    critical_high: '',
    source_text: 'WHO; CDC Rickettsial Guidelines',
    clinical_note: 'Key diagnostic test in acute febrile illness with suspected vector (chigger mite) exposure.',
    semantic_type: 'QUALITATIVE_INTERPRETATION'
  }
];

// Helper to escape CSV fields
function csvEscape(val) {
  if (val === null || val === undefined) return '""';
  const str = String(val);
  if (str.includes(',') || str.includes('"') || str.includes('\n')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return `"${str}"`;
}

// 1. Output reference_compendium_candidates.csv
const candidatesHeaders = [
  'test_code', 'parameter_name', 'method', 'specimen', 'unit',
  'age_gender_strata', 'reference_low', 'reference_high', 'clinical_cutoff',
  'qualitative_options', 'critical_low', 'critical_high', 'source_text',
  'clinical_note', 'semantic_type', 'candidate_status'
];

const candidateRows = candidates.map(c => [
  c.test_code, c.parameter_name, c.method, c.specimen, c.unit,
  c.age_gender_strata, c.reference_low, c.reference_high, c.clinical_cutoff,
  c.qualitative_options, c.critical_low, c.critical_high, c.source_text,
  c.clinical_note, c.semantic_type, 'RESEARCH_DRAFT'
].map(csvEscape).join(','));

fs.writeFileSync(
  path.join(outputDir, 'reference_compendium_candidates.csv'),
  [candidatesHeaders.map(csvEscape).join(','), ...candidateRows].join('\n'),
  'utf8'
);

// 2. Perform reconciliation against approved LIS configuration
// Existing DB configuration metadata (from migrations 00103, 00119, 00127, 00130, 00133, 00134)
const existingApprovedMap = {
  'SER-0024': {
    name: 'Widal Test',
    param_count: 4,
    params: ['Salmonella Typhi O', 'Salmonella Typhi H', 'Salmonella Paratyphi AH', 'Salmonella Paratyphi BH'],
    allowed_titers: ['<1:20', '1:20', '1:40', '1:80', '1:160', '1:320'],
    cutoffs: 'O >=1:160, H >=1:160, AH >=1:80, BH >=1:80',
    method: 'Tube Agglutination',
    status: 'APPROVED_LOCKED'
  },
  'SER-0089': {
    name: 'Scrub Typhus (FIA IgM/IgG)',
    param_count: 2,
    params: ['Scrub Typhus IgM', 'Scrub Typhus IgG'],
    cutoffs: 'Index <1.0: Negative; Index >=1.0: Positive',
    method: 'Fluorescence Immunoassay (FIA)',
    status: 'APPROVED_LOCKED'
  },
  'BIO-0050': {
    name: 'Ferritin',
    approved_ranges: 'Male: 30–400 ng/mL; Female: 15–150 ng/mL',
    method: 'CLIA / Immunoturbidimetry',
    status: 'APPROVED_LOCKED'
  },
  'SER-0004': { name: 'HBsAg', status: 'APPROVED_LOCKED', method: 'Rapid Immunochromatography (ICT)' },
  'SER-0010': { name: 'Anti-HCV', status: 'APPROVED_LOCKED', method: 'Rapid Immunochromatography (ICT)' },
  'SER-0001': { name: 'HIV 1/2', status: 'APPROVED_LOCKED', method: 'Rapid Immunochromatography (ICT)' },
  'SER-0015': { name: 'Dengue NS1', status: 'APPROVED_LOCKED', method: 'Rapid Immunochromatography (ICT)' },
  'SER-0016': { name: 'Dengue IgM', status: 'APPROVED_LOCKED', method: 'Rapid Immunochromatography (ICT)' },
  'SER-0017': { name: 'Dengue IgG', status: 'APPROVED_LOCKED', method: 'Rapid Immunochromatography (ICT)' },
  'COA-0001': { name: 'Prothrombin Time', method: 'Optical / Mechanical Clotting', status: 'APPROVED_LOCKED' },
  'COA-0002': { name: 'INR', method: 'Calculated (MNPT & ISI Governed)', status: 'APPROVED_LOCKED' },
  'COA-0003': { name: 'APTT', method: 'Optical / Mechanical Clotting', status: 'APPROVED_LOCKED' },
  'COA-0006': { name: 'D-Dimer', method: 'Quantitative Immunoturbidimetry', cutoff: '<0.50 µg/mL FEU', status: 'APPROVED_LOCKED' }
};

const reconciliationRecords = [];
const conflictRecords = [];
const labReviewRecords = [];

let matchesCount = 0;
let conflictsCount = 0;
let newCandidatesCount = 0;
let methodDependentCount = 0;
let labPolicyCount = 0;
let sourceVerificationCount = 0;

for (const c of candidates) {
  let comparison_classification = 'NEW_CANDIDATE';
  let conflict_reason = '';
  let requires_assay_verification = false;
  let source_traceability = 'SOURCE_VERIFICATION_REQUIRED';
  let lab_policy_required = false;
  let production_action = 'HOLD_PENDING_LAB_REVIEW';

  // Check method dependency
  if (['END-0013', 'END-0014', 'END-0015', 'END-0011', 'END-0025', 'END-0039',
       'TUM-0001', 'TUM-0002', 'TUM-0003', 'TUM-0004', 'TUM-0005', 'TUM-0006', 'TUM-0007',
       'TOX-0001', 'TOX-0002', 'TOX-0003', 'TOX-0004', 'TOX-0005', 'TOX-0006', 'TOX-0007', 'TOX-0008', 'TOX-0009', 'TOX-0010'].includes(c.test_code)) {
    requires_assay_verification = true;
    methodDependentCount++;
  }

  // Check critical values
  if (c.critical_low || c.critical_high) {
    lab_policy_required = true;
    labPolicyCount++;
  }

  // Check specific hard conflicts
  if (c.test_code === 'SER-0024') {
    // WIDAL CHECK
    comparison_classification = 'CONFLICTS_WITH_EXISTING_APPROVED';
    conflict_reason = 'HARD CONFLICT: Research draft specifies 2 antigens (Typhi O/H) with 1:80 baseline. Approved LIS strictly enforces 4 antigens (Typhi O, Typhi H, Paratyphi AH, Paratyphi BH) with 6 discrete titers (<1:20 to 1:320) and AH/BH >=1:80 cutoffs.';
    conflictsCount++;
    conflictRecords.push({
      test_code: c.test_code,
      parameter_name: c.parameter_name,
      candidate_value: c.clinical_cutoff,
      current_production_value: existingApprovedMap['SER-0024'].cutoffs,
      conflict_type: 'STRUCTURE_AND_CUTOFF_MISMATCH',
      conflict_resolution: 'PRESERVE_EXISTING_APPROVED_LOCKED',
      notes: 'Salmonella Paratyphi AH and BH are mandatory clinical parameters in Nepal endemic fever diagnostics.'
    });
  } else if (c.test_code === 'SER-0089') {
    // SCRUB TYPHUS CHECK
    if (c.parameter_name.includes('IgM') && !c.parameter_name.includes('IgG')) {
      comparison_classification = 'CONFLICTS_WITH_EXISTING_APPROVED';
      conflict_reason = 'HARD CONFLICT: Research draft is IgM-only. Approved LIS (00134) strictly configures dual IgM + IgG panel on FIAcheck.';
      conflictsCount++;
      conflictRecords.push({
        test_code: c.test_code,
        parameter_name: c.parameter_name,
        candidate_value: 'IgM single analyte',
        current_production_value: 'Dual Scrub Typhus IgM + IgG (SER-0089-01, SER-0089-02)',
        conflict_type: 'PANEL_STRUCTURE_REGRESSION',
        conflict_resolution: 'PRESERVE_EXISTING_APPROVED_LOCKED',
        notes: 'Do not collapse dual IgM/IgG FIA configuration to IgM single.'
      });
    }
  } else if (existingApprovedMap[c.test_code]) {
    comparison_classification = 'MATCHES_EXISTING_APPROVED';
    matchesCount++;
  } else {
    comparison_classification = 'NEW_CANDIDATE';
    newCandidatesCount++;
  }

  // Source quality evaluation
  if (c.source_text.includes(';') || c.source_text.includes('Guidelines')) {
    source_traceability = 'SOURCE_VERIFICATION_REQUIRED (Requires specific chapter/table citation and assay package insert)';
    sourceVerificationCount++;
  }

  const rec = {
    test_code: c.test_code,
    parameter_name: c.parameter_name,
    semantic_type: c.semantic_type,
    comparison_classification,
    existing_lis_status: existingApprovedMap[c.test_code] ? 'CONFIGURED_IN_PROD' : 'PENDING_CONFIG',
    method_dependent: requires_assay_verification ? 'YES (METHOD_DEPENDENT_REQUIRES_ASSAY)' : 'NO',
    lab_policy_required: lab_policy_required ? 'YES (PANIC_VALUE_POLICY_REQUIRED)' : 'NO',
    source_traceability,
    conflict_notes: conflict_reason || 'None',
    candidate_status: 'RESEARCH_DRAFT',
    production_approved: 'NO',
    production_action
  };

  reconciliationRecords.push(rec);

  if (lab_policy_required || requires_assay_verification || comparison_classification === 'NEW_CANDIDATE') {
    labReviewRecords.push({
      test_code: c.test_code,
      parameter_name: c.parameter_name,
      review_category: requires_assay_verification ? 'ASSAY_PACKAGE_INSERT_VERIFICATION' : lab_policy_required ? 'CRITICAL_PANIC_VALUE_GOVERNANCE' : 'GENERAL_CLINICAL_VALIDATION',
      proposed_range_or_cutoff: `${c.reference_low || ''} - ${c.reference_high || ''} ${c.unit} | ${c.clinical_cutoff || ''}`,
      proposed_critical_panic: c.critical_low || c.critical_high ? `Low: ${c.critical_low || '—'} | High: ${c.critical_high || '—'}` : 'None',
      action_needed: requires_assay_verification ? 'Confirm on-site analyzer reagent lot & package insert' : 'Medical Director sign-off on panic notification thresholds',
      current_decision: 'HOLD_DO_NOT_MIGRATE'
    });
  }
}

// Write reference_compendium_reconciliation.csv
const reconHeaders = Object.keys(reconciliationRecords[0]);
fs.writeFileSync(
  path.join(outputDir, 'reference_compendium_reconciliation.csv'),
  [
    reconHeaders.map(csvEscape).join(','),
    ...reconciliationRecords.map(r => reconHeaders.map(h => csvEscape(r[h])).join(','))
  ].join('\n'),
  'utf8'
);

// Write reference_compendium_conflicts.csv
const conflictHeaders = ['test_code', 'parameter_name', 'candidate_value', 'current_production_value', 'conflict_type', 'conflict_resolution', 'notes'];
fs.writeFileSync(
  path.join(outputDir, 'reference_compendium_conflicts.csv'),
  [
    conflictHeaders.map(csvEscape).join(','),
    ...conflictRecords.map(r => conflictHeaders.map(h => csvEscape(r[h])).join(','))
  ].join('\n'),
  'utf8'
);

// Write reference_compendium_lab_review.csv
const reviewHeaders = Object.keys(labReviewRecords[0]);
fs.writeFileSync(
  path.join(outputDir, 'reference_compendium_lab_review.csv'),
  [
    reviewHeaders.map(csvEscape).join(','),
    ...labReviewRecords.map(r => reviewHeaders.map(h => csvEscape(r[h])).join(','))
  ].join('\n'),
  'utf8'
);

// Write reference_compendium_summary.csv
const summaryData = [
  { metric: 'TOTAL_CANDIDATES', value: candidates.length },
  { metric: 'MATCHES_EXISTING_APPROVED', value: matchesCount },
  { metric: 'CONFLICTS_WITH_EXISTING_APPROVED', value: conflictsCount },
  { metric: 'NEW_CANDIDATES', value: newCandidatesCount },
  { metric: 'METHOD_DEPENDENT', value: methodDependentCount },
  { metric: 'LAB_POLICY_REQUIRED', value: labPolicyCount },
  { metric: 'SOURCE_VERIFICATION_REQUIRED', value: sourceVerificationCount },
  { metric: 'WIDAL_REGRESSION', value: 'NO' },
  { metric: 'SCRUB_TYPHUS_REGRESSION', value: 'NO' },
  { metric: 'EXISTING_APPROVED_VALUES_OVERWRITTEN', value: 0 },
  { metric: 'CRITICAL_VALUES_AUTO_APPROVED', value: 0 },
  { metric: 'DB_CHANGES', value: 'NONE' },
  { metric: 'MIGRATION_CREATED', value: 'NONE' },
  { metric: 'SAFE_TO_MIGRATE', value: 'NO' }
];

const summaryHeaders = ['metric', 'value'];
fs.writeFileSync(
  path.join(outputDir, 'reference_compendium_summary.csv'),
  [
    summaryHeaders.map(csvEscape).join(','),
    ...summaryData.map(r => summaryHeaders.map(h => csvEscape(r[h])).join(','))
  ].join('\n'),
  'utf8'
);

console.log('Successfully generated all 5 reconciliation CSV reports:');
console.log('  1. scripts/output/reference_compendium_candidates.csv');
console.log('  2. scripts/output/reference_compendium_reconciliation.csv');
console.log('  3. scripts/output/reference_compendium_conflicts.csv');
console.log('  4. scripts/output/reference_compendium_lab_review.csv');
console.log('  5. scripts/output/reference_compendium_summary.csv');
console.log(JSON.stringify(summaryData, null, 2));
