# Bimal Pathology LIS — 256-test master reconciliation

Generated from the operator-provided identity reference and a read-only production catalogue export at migration head 00060. Source values are identity/provenance evidence only and do not authorize ranges, units, formulas, methods, analyzers, assays, activation, or reporting.

- Parsed source rows: **256**
- Source departments: Haematology 43; Biochemistry 109; Serology & Immunology 61; Clinical Pathology 21; Cytology 3; Microbiology 6; Endocrinology 11; Others 1; Miscellaneous 1
- Classification totals: AliasExisting 28; ConflictRequiresReview 41; DuplicateCandidate 4; ExactExisting 22; MissingDraftCandidate 134; ProfileComponentExisting 12; SpecialistWorkflowRequired 15

## Hematology reconciliation

| # | Source identity | Alias | Classification | Existing LIS match | Proposed identity | Workflow | Conflict |
|---:|---|---|---|---|---|---|---|
| 1 | Hemoglobin | Hb | AliasExisting | HB — Hemoglobin (Hb) [Active/Routine; clinical=false] | HB — Hemoglobin | RoutineSingleParameter | CBC component versus standalone billable service boundary |
| 2 | Total Leukocyte Count | TLC | AliasExisting | TLC — Total Leukocyte Count (TLC / WBC) [Active/Routine; clinical=false] | TLC — Total Leukocyte Count | RoutineSingleParameter | TLC/WBC/TC equivalence and duplicate billable identity; CBC component versus standalone billable service boundary |
| 3 | Differential Leucocyte Count | DLC | AliasExisting | DLC — Differential Leukocyte Count (DLC) [Active/Routine; clinical=false] | DLC — Differential Leukocyte Count | RoutineMultiParameter/Profile | DLC variant/duplicate and reporting-shape conflict; CBC component versus standalone billable service boundary |
| 4 | Differential Leukocyte Count (Absolute count) | — | ConflictRequiresReview | — | Differential Leukocyte Count (Absolute count) | RoutineMultiParameter/Profile | DLC variant/duplicate and reporting-shape conflict |
| 5 | Erythrocyte sedimentation rate (Westergren) | ESR (Westergren) | ConflictRequiresReview | — | ESR — method-specific Westergren service/configuration | RoutineSingleParameter | Method-specific ESR must not be collapsed into generic ESR without approval |
| 6 | Erythrocyte Sedimentation Rate (Wintrobe) | ESR (Wintrobe) | ConflictRequiresReview | — | ESR — method-specific Wintrobe service/configuration | RoutineSingleParameter | Method-specific ESR must not be collapsed into generic ESR without approval |
| 7 | Platelet Count | — | ExactExisting | PLT — Platelet Count [Active/Routine; clinical=false] | PLT — Platelet Count | RoutineSingleParameter | Platelet count versus platelet indices/profile boundary; CBC component versus standalone billable service boundary |
| 8 | Absolute Eosinophil Count | AEC | ExactExisting | AEC — Absolute Eosinophil Count [Draft/NoClinicalReport; clinical=false] | AEC — Absolute Eosinophil Count | RoutineSingleParameter | — |
| 9 | Blood Group & Rh. | — | MissingDraftCandidate | — | Blood Group & Rh. | RoutineMultiParameter/Profile | — |
| 10 | Bleeding Time | BT | ProfileComponentExisting | BT_CT.BLEEDING_TIME — Bleeding Time | Bleeding Time | RoutineSingleParameter | — |
| 11 | Clotting Time | CT | ProfileComponentExisting | BT_CT.CLOTTING_TIME — Clotting Time | Clotting Time | RoutineSingleParameter | — |
| 12 | Peripheral Blood Smear | PBS / GBP | AliasExisting | PBS — Peripheral Blood Smear Examination (PBS) [Active/Routine; clinical=true] | PBS — Peripheral Blood Smear Examination (PBS) | Document/StructuredNarrativeReview | — |
| 13 | Malaria Parasite (Card Test) | MP (Card Test) | MissingDraftCandidate | — | Malaria Parasite (Card Test) | RoutineMultiParameter/Profile | Source department differs from proposed canonical discipline |
| 14 | Malaria Parasite (Microscopic) | MP (Microscopic) | MissingDraftCandidate | — | Malaria Parasite (Microscopic) | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 15 | Filarial Parasite (Card Test) | MF | MissingDraftCandidate | — | Filarial Parasite (Card Test) | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 16 | Total RBC Count | — | AliasExisting | RBC_COUNT — Red Blood Cell Count (RBC Count) [Active/Routine; clinical=false] | RBC_COUNT — Red Blood Cell Count | RoutineSingleParameter | CBC component versus standalone billable service boundary |
| 17 | Hematocrit Value, Hct | Hct | AliasExisting | PCV — Packed Cell Volume (PCV / Hematocrit) [Active/Routine; clinical=false] | PCV — Packed Cell Volume / Hematocrit | RoutineSingleParameter | CBC component versus standalone billable service boundary |
| 18 | Mean Corpuscular Volume, MCV | MCV | ProfileComponentExisting | CBC.MCV — Mean Corpuscular Volume (MCV) | MCV standalone identity | RoutineSingleParameter | CBC component versus standalone billable service boundary |
| 19 | Mean Cell Haemoglobin, MCH | MCH | ProfileComponentExisting | CBC.MCH — Mean Corpuscular Hemoglobin (MCH) | MCH standalone identity | RoutineSingleParameter | CBC component versus standalone billable service boundary |
| 20 | Mean Cell Haemoglobin CON, MCHC | MCHC | ProfileComponentExisting | CBC.MCHC — Mean Corpuscular Hb Conc (MCHC) | MCHC standalone identity | RoutineSingleParameter | CBC component versus standalone billable service boundary |
| 21 | Mean Platelet Volume, MPV | MPV | MissingDraftCandidate | — | Mean Platelet Volume, MPV | RoutineSingleParameter | Platelet count versus platelet indices/profile boundary |
| 22 | Reticulocyte Count | — | ExactExisting | RETIC_COUNT — Reticulocyte Count [Draft/NoClinicalReport; clinical=false] | RETIC_COUNT — Reticulocyte Count | RoutineSingleParameter | — |
| 23 | Glucose-6-phosphate dehydrogenase | G6PD | MissingDraftCandidate | — | Glucose-6-phosphate dehydrogenase | RoutineSingleParameter | — |
| 24 | Prothrombin time, PT/INR | PT/INR | AliasExisting | PT_INR — Prothrombin Time / International Normalized Ratio (PT / INR) [Draft/NoClinicalReport; clinical=false] | PT_INR — PT/INR (blocked pending authoritative configuration) | RoutineMultiParameter/Profile | — |
| 25 | Activated partial thromboplastin time, APTT | APTT | MissingDraftCandidate | — | APTT — Activated Partial Thromboplastin Time | RoutineMultiParameter/Profile | — |
| 26 | WBC Count | — | ConflictRequiresReview | TLC — Total Leukocyte Count (TLC / WBC) [Active/Routine; clinical=false] | TLC — WBC Count alias candidate | RoutineSingleParameter | TLC/WBC/TC equivalence and duplicate billable identity |
| 27 | P-LCR | — | MissingDraftCandidate | — | P-LCR | RoutineSingleParameter | Platelet count versus platelet indices/profile boundary |
| 28 | R.D.W. - CV | — | MissingDraftCandidate | — | R.D.W. - CV | RoutineSingleParameter | CBC component versus standalone billable service boundary |
| 29 | P.D.W. | — | MissingDraftCandidate | — | P.D.W. | RoutineSingleParameter | Platelet count versus platelet indices/profile boundary |
| 30 | R.D.W. - SD | — | MissingDraftCandidate | — | R.D.W. - SD | RoutineSingleParameter | CBC component versus standalone billable service boundary |
| 31 | Neutrophil Lymphocyte Ratio | NLR | MissingDraftCandidate | — | Neutrophil Lymphocyte Ratio | RoutineSingleParameter | — |
| 32 | Lupus Anticoagulant (DRVVT) | — | MissingDraftCandidate | — | Lupus Anticoagulant (DRVVT) | RoutineMultiParameter/Profile | — |
| 33 | Troponin T | — | MissingDraftCandidate | — | Troponin T | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 34 | HEMOGLOBIN HPLC/ELECTROPHORESIS | HPLC | MissingDraftCandidate | — | HEMOGLOBIN HPLC/ELECTROPHORESIS | RoutineMultiParameter/Profile | — |
| 35 | Leukemia DLC | — | ConflictRequiresReview | — | Leukemia DLC | RoutineMultiParameter/Profile | DLC variant/duplicate and reporting-shape conflict |
| 36 | RBC Indices | — | ConflictRequiresReview | — | RBC Indices | RoutineMultiParameter/Profile | CBC component versus standalone billable service boundary |
| 37 | Platelet Indices | — | ConflictRequiresReview | — | Platelet Indices | RoutineMultiParameter/Profile | Platelet count versus platelet indices/profile boundary; CBC component versus standalone billable service boundary |
| 38 | Morphology | — | ConflictRequiresReview | — | Morphology | RoutineMultiParameter/Profile | CBC component versus standalone billable service boundary |
| 39 | DLC 3 Parts | — | ConflictRequiresReview | — | DLC 3 Parts | RoutineMultiParameter/Profile | DLC variant/duplicate and reporting-shape conflict |
| 40 | DLC Leukemia | — | ConflictRequiresReview | — | DLC Leukemia | RoutineMultiParameter/Profile | DLC variant/duplicate and reporting-shape conflict |
| 41 | Procalcitonin | — | ConflictRequiresReview | — | Procalcitonin | RoutineSingleParameter | Duplicate Procalcitonin source identities across departments; Source department differs from proposed canonical discipline |
| 42 | TC | TC | ConflictRequiresReview | TLC — Total Leukocyte Count (TLC / WBC) [Active/Routine; clinical=false] | TLC — TC alias candidate | RoutineSingleParameter | TLC/WBC/TC equivalence and duplicate billable identity |
| 43 | DLC | DLC | ConflictRequiresReview | DLC — Differential Leukocyte Count (DLC) [Active/Routine; clinical=false] | DLC — duplicate source row requiring type review | RoutineSingleParameter | DLC variant/duplicate and reporting-shape conflict |

## Biochemistry reconciliation

| # | Source identity | Alias | Classification | Existing LIS match | Proposed identity | Workflow | Conflict |
|---:|---|---|---|---|---|---|---|
| 44 | Serum Phosphorus | — | AliasExisting | PHOSPHORUS — Serum Phosphorus (Inorganic) [Active/Routine; clinical=false] | PHOSPHORUS — Serum Phosphorus (Inorganic) | RoutineSingleParameter | — |
| 45 | Serum Creatinine | — | ExactExisting | CREATININE — Serum Creatinine [Active/Routine; clinical=false] | CREATININE — Serum Creatinine | RoutineSingleParameter | — |
| 46 | Serum Urea | — | AliasExisting | UREA — Blood Urea [Active/Routine; clinical=false] | UREA — Blood Urea | RoutineSingleParameter | — |
| 47 | Fasting Blood Sugar | — | AliasExisting | FBS — Fasting Blood Sugar (FBS) [Active/Routine; clinical=false] | FBS — Fasting Blood Sugar (FBS) | RoutineSingleParameter | — |
| 48 | Blood Sugar PP | — | AliasExisting | PPBS — Post Prandial Blood Sugar (PPBS) [Active/Routine; clinical=false] | PPBS — Post Prandial Blood Sugar (PPBS) | RoutineSingleParameter | — |
| 49 | Serum Bilirubin (Total) | — | ProfileComponentExisting | LFT.TBIL — Bilirubin Total | Serum Bilirubin (Total) | RoutineSingleParameter | — |
| 50 | Serum Bilirubin (Direct) | — | ProfileComponentExisting | LFT.DBIL — Bilirubin Direct | Serum Bilirubin (Direct) | RoutineSingleParameter | — |
| 51 | Serum Bilirubin (Indirect) | — | ProfileComponentExisting | LFT.IBIL — Bilirubin Indirect | Serum Bilirubin (Indirect) | RoutineSingleParameter | — |
| 52 | Serum Uric Acid | Uric Acid | ExactExisting | URIC_ACID — Serum Uric Acid [Active/Routine; clinical=false] | URIC_ACID — Serum Uric Acid | RoutineSingleParameter | — |
| 53 | SGPT (ALT) | SGPT | AliasExisting | ALT — ALT / SGPT [Draft/NoClinicalReport; clinical=false] | ALT — ALT / SGPT | RoutineSingleParameter | — |
| 54 | SGOT (AST) | SGOT | AliasExisting | AST — AST / SGOT [Draft/NoClinicalReport; clinical=false] | AST — AST / SGOT | RoutineSingleParameter | — |
| 55 | Serum Protein | — | ProfileComponentExisting | LFT.TP — Total Protein \| URINE_RE.PROTEIN — Protein / Albumin | Serum Protein | RoutineSingleParameter | — |
| 56 | Serum Albumin | — | ProfileComponentExisting | LFT.ALB — Albumin | Serum Albumin | RoutineSingleParameter | — |
| 57 | Serum Alkaline Phosphatase | — | ExactExisting | ALP — Alkaline Phosphatase [Draft/NoClinicalReport; clinical=false] | ALP — Alkaline Phosphatase | RoutineSingleParameter | — |
| 58 | Total Cholesterol | — | ExactExisting | CHOL_TOTAL — Total Cholesterol [Draft/NoClinicalReport; clinical=false] | CHOL_TOTAL — Total Cholesterol | RoutineSingleParameter | — |
| 59 | Triglycerides | — | ExactExisting | TRIGLYCERIDES — Triglycerides [Draft/NoClinicalReport; clinical=false] | TRIGLYCERIDES — Triglycerides | RoutineSingleParameter | — |
| 60 | HDL Cholesterol | HDL Cholesterol | ExactExisting | HDL_CHOL — HDL Cholesterol [Draft/NoClinicalReport; clinical=false] | HDL_CHOL — HDL Cholesterol | RoutineSingleParameter | — |
| 61 | LDL Cholesterol | LDL Cholesterol | ExactExisting | LDL_CHOL — LDL Cholesterol [Draft/NoClinicalReport; clinical=false] | LDL_CHOL — LDL Cholesterol | RoutineSingleParameter | — |
| 62 | VLDL Cholesterol | VLDL Cholesterol | ProfileComponentExisting | LIPID_PROFILE.VLDL — VLDL Cholesterol | VLDL Cholesterol | RoutineSingleParameter | — |
| 63 | LDL / HDL | — | ConflictRequiresReview | — | LDL/HDL ratio — calculation candidate | RoutineSingleParameter | — |
| 64 | Total Cholesterol / HDL | — | ConflictRequiresReview | — | Total Cholesterol/HDL ratio — calculation candidate | RoutineSingleParameter | — |
| 65 | TG / HDL | — | ConflictRequiresReview | — | TG/HDL ratio — calculation candidate | RoutineSingleParameter | — |
| 66 | Total Lipid | — | ConflictRequiresReview | LIPID — Lipid Profile [Active/Routine; clinical=true] \| LIPID_PROFILE — Lipid Profile [Active/Routine; clinical=false] | Total Lipid | RoutineSingleParameter | — |
| 67 | Serum Sodium | — | AliasExisting | SODIUM — Serum Sodium (Na+) [Active/Routine; clinical=false] | SODIUM — Serum Sodium (Na+) | RoutineSingleParameter | — |
| 68 | BUN | — | MissingDraftCandidate | — | BUN | RoutineSingleParameter | — |
| 69 | BUN / Creatinine Ratio | — | ConflictRequiresReview | — | BUN/Creatinine ratio — calculation candidate | RoutineSingleParameter | — |
| 70 | Urea / Creatinine Ratio | — | ConflictRequiresReview | — | Urea/Creatinine ratio — calculation candidate | RoutineSingleParameter | — |
| 71 | Serum Potassium | — | AliasExisting | POTASSIUM — Serum Potassium (K+) [Active/Routine; clinical=false] | POTASSIUM — Serum Potassium (K+) | RoutineSingleParameter | — |
| 72 | iCalcium | — | MissingDraftCandidate | — | iCalcium | RoutineSingleParameter | — |
| 73 | Serum Calcium | — | ConflictRequiresReview | CALCIUM — Serum Calcium (Total) [Active/Routine; clinical=false] | CALCIUM — Serum Calcium (Total) | RoutineSingleParameter | — |
| 74 | Total Calcium | — | ConflictRequiresReview | CALCIUM — Serum Calcium (Total) [Active/Routine; clinical=false] | CALCIUM — Serum Calcium (Total) | RoutineSingleParameter | — |
| 75 | Glucose Tolerance Test, GTT | GTT | MissingDraftCandidate | — | Glucose Tolerance Test, GTT | RoutineMultiParameter/Profile | — |
| 76 | Random Blood Sugar | — | AliasExisting | RBS — Random Blood Sugar (RBS) [Active/Routine; clinical=false] | RBS — Random Blood Sugar (RBS) | RoutineSingleParameter | — |
| 77 | Serum Chloride | — | AliasExisting | CHLORIDE — Serum Chloride (Cl-) [Active/Routine; clinical=false] | CHLORIDE — Serum Chloride (Cl-) | RoutineSingleParameter | — |
| 78 | Serum Amylase | — | ExactExisting | AMYLASE — Amylase [Draft/NoClinicalReport; clinical=false] | AMYLASE — Amylase | RoutineSingleParameter | — |
| 79 | HbA1c (Glycosylated Hemoglobin) | — | AliasExisting | HBA1C — Glycated Hemoglobin (HbA1c) [Active/Routine; clinical=false] | HBA1C — Glycated Hemoglobin (HbA1c) | RoutineMultiParameter/Profile | — |
| 80 | A/G Ratio | — | ConflictRequiresReview | LFT.AG_RATIO — A:G Ratio | Albumin/Globulin ratio — calculation candidate | RoutineSingleParameter | — |
| 81 | Globulin | — | ExactExisting | GLOBULIN — Globulin [Draft/NoClinicalReport; clinical=false] | GLOBULIN — Globulin | RoutineSingleParameter | — |
| 82 | Lipase | — | ExactExisting | LIPASE — Lipase [Draft/NoClinicalReport; clinical=false] | LIPASE — Lipase | RoutineSingleParameter | — |
| 83 | Ferritin | — | ExactExisting | FERRITIN — Serum Ferritin [Active/Routine; clinical=false] | FERRITIN — Serum Ferritin | RoutineSingleParameter | — |
| 84 | Microalbumin Creatinine Ratio, Urine Random | — | MissingDraftCandidate | — | Microalbumin Creatinine Ratio, Urine Random | RoutineMultiParameter/Profile | Source department differs from proposed canonical discipline |
| 85 | CPK-MB | — | ConflictRequiresReview | CK_MB — Creatine Kinase MB [Draft/NoClinicalReport; clinical=false] | CK_MB — CK-MB | RoutineSingleParameter | CPK-MB/CK-MB duplicate candidate |
| 86 | Stool reducing substances | — | MissingDraftCandidate | — | Stool reducing substances | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 87 | 25 Hydroxy (OH) Vitamin D | Vitamin D3 | AliasExisting | VITAMIN_D — 25-Hydroxy Vitamin D (Total) [Active/Routine; clinical=false] | VITAMIN_D — 25-Hydroxy Vitamin D (Total) | RoutineSingleParameter | — |
| 88 | Vitamin B12 | — | AliasExisting | VITAMIN_B12 — Vitamin B12 (Cyanocobalamin) [Active/Routine; clinical=false] | VITAMIN_B12 — Vitamin B12 (Cyanocobalamin) | RoutineSingleParameter | — |
| 89 | Gamma Glutamyl Transferase, GGT | GGT | AliasExisting | GGT — Gamma-Glutamyl Transferase [Draft/NoClinicalReport; clinical=false] | GGT — Gamma-Glutamyl Transferase | RoutineSingleParameter | — |
| 90 | Serum IgE | — | MissingDraftCandidate | — | Serum IgE | RoutineSingleParameter | — |
| 91 | Serum IgG | — | MissingDraftCandidate | — | Serum IgG | RoutineSingleParameter | — |
| 92 | Serum IgM | — | MissingDraftCandidate | — | Serum IgM | RoutineSingleParameter | — |
| 93 | Serum IgA | — | MissingDraftCandidate | — | Serum IgA | RoutineSingleParameter | — |
| 94 | HSV-1/2 IgG | — | MissingDraftCandidate | — | HSV-1/2 IgG | RoutineSingleParameter | — |
| 95 | HSV-1/2 IgM | — | MissingDraftCandidate | — | HSV-1/2 IgM | RoutineSingleParameter | — |
| 96 | HSV-2 IgG | — | MissingDraftCandidate | — | HSV-2 IgG | RoutineSingleParameter | — |
| 97 | CMV IgG | — | MissingDraftCandidate | — | CMV IgG | RoutineSingleParameter | — |
| 98 | CMV IgM | — | MissingDraftCandidate | — | CMV IgM | RoutineSingleParameter | — |
| 99 | Rubella IgG | — | MissingDraftCandidate | — | Rubella IgG | RoutineSingleParameter | — |
| 100 | Rubella IgM | — | MissingDraftCandidate | — | Rubella IgM | RoutineSingleParameter | — |
| 101 | Anti TPO | — | MissingDraftCandidate | — | Anti TPO | RoutineSingleParameter | — |
| 102 | Thyroglobulin (TG) | — | MissingDraftCandidate | — | Thyroglobulin (TG) | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 103 | Thyroglobulin Antibody (TgAb) | — | MissingDraftCandidate | — | Thyroglobulin Antibody (TgAb) | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 104 | Toxo IgG | — | MissingDraftCandidate | — | Toxo IgG | RoutineSingleParameter | — |
| 105 | Toxo IgM | — | MissingDraftCandidate | — | Toxo IgM | RoutineSingleParameter | — |
| 106 | Estradiol | — | MissingDraftCandidate | — | Estradiol | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 107 | DHEA | — | MissingDraftCandidate | — | DHEA | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 108 | Troponin I | — | MissingDraftCandidate | — | Troponin I | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 109 | Creatine Kinase | CPK-Total | ExactExisting | CK_TOTAL — Creatine Kinase Total [Draft/NoClinicalReport; clinical=false] | CK_TOTAL — Creatine Kinase Total | RoutineSingleParameter | — |
| 110 | CK-MB | — | ConflictRequiresReview | CK_MB — Creatine Kinase MB [Draft/NoClinicalReport; clinical=false] | CK_MB — CK-MB | RoutineSingleParameter | CPK-MB/CK-MB duplicate candidate |
| 111 | D-Dimer | — | MissingDraftCandidate | — | D-Dimer | RoutineSingleParameter | — |
| 112 | Calcitonin | — | MissingDraftCandidate | — | Calcitonin | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 113 | Indirect Coomb's Test | — | MissingDraftCandidate | — | Indirect Coomb's Test | RoutineSingleParameter | — |
| 114 | Direct Coomb's Test | — | MissingDraftCandidate | — | Direct Coomb's Test | RoutineSingleParameter | — |
| 115 | CA 125 | — | MissingDraftCandidate | — | CA 125 | RoutineSingleParameter | — |
| 116 | CA 15-3 | — | MissingDraftCandidate | — | CA 15-3 | RoutineSingleParameter | — |
| 117 | CA 19-9 | — | MissingDraftCandidate | — | CA 19-9 | RoutineSingleParameter | — |
| 118 | CA 50 | — | MissingDraftCandidate | — | CA 50 | RoutineSingleParameter | — |
| 119 | CA 242 | — | MissingDraftCandidate | — | CA 242 | RoutineSingleParameter | — |
| 120 | CA 72-4 | — | MissingDraftCandidate | — | CA 72-4 | RoutineSingleParameter | — |
| 121 | H-ALB | — | MissingDraftCandidate | — | H-ALB | RoutineSingleParameter | — |
| 122 | Anti cyclic-citrullinated-peptide | CCP | MissingDraftCandidate | — | Anti cyclic-citrullinated-peptide | RoutineSingleParameter | — |
| 123 | Arterial Blood Gas | ABG | MissingDraftCandidate | — | Arterial Blood Gas | RoutineMultiParameter/Profile | — |
| 124 | Iron | — | ExactExisting | IRON — Serum Iron [Active/Routine; clinical=false] | IRON — Serum Iron | RoutineSingleParameter | — |
| 125 | Total Iron Binding Capacity (TIBC) | — | ExactExisting | TIBC — Total Iron Binding Capacity (TIBC) [Active/Routine; clinical=false] | TIBC — Total Iron Binding Capacity (TIBC) | RoutineSingleParameter | — |
| 126 | Transferrin Saturation | — | ConflictRequiresReview | — | Transferrin Saturation — calculation candidate | RoutineSingleParameter | — |
| 127 | Non-HDL cholesterol | — | ConflictRequiresReview | — | Non-HDL Cholesterol — calculation candidate | RoutineSingleParameter | — |
| 128 | UIBC | — | MissingDraftCandidate | — | UIBC | RoutineSingleParameter | — |
| 129 | eGFR | — | ConflictRequiresReview | EGFR — Estimated Glomerular Filtration Rate [Draft/NoClinicalReport; clinical=false] | EGFR — calculation candidate | RoutineSingleParameter | — |
| 130 | eGFR Category | — | ConflictRequiresReview | — | eGFR Category — derived interpretation | RoutineSingleParameter | — |
| 131 | C3 Complement | C3 | MissingDraftCandidate | — | C3 Complement | RoutineSingleParameter | — |
| 132 | High-Sensitivity C-Reactive Protein | HsCRP | MissingDraftCandidate | — | High-Sensitivity C-Reactive Protein | RoutineSingleParameter | — |
| 133 | ANTI MULLERIAN HORMONE | AMH | MissingDraftCandidate | — | ANTI MULLERIAN HORMONE | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 134 | Ammonia | — | MissingDraftCandidate | — | Ammonia | RoutineSingleParameter | — |
| 135 | Magnesium | — | ExactExisting | MAGNESIUM — Serum Magnesium [Active/Routine; clinical=false] | MAGNESIUM — Serum Magnesium | RoutineSingleParameter | — |
| 136 | Glucose Tolerance Test, GTT (Pregnancy) | — | MissingDraftCandidate | — | Glucose Tolerance Test, GTT (Pregnancy) | RoutineMultiParameter/Profile | — |
| 137 | SGOT/SGPT | — | ConflictRequiresReview | — | AST/ALT ratio — calculation candidate | RoutineSingleParameter | — |
| 138 | NT- ProBNP (N-TERMINAL PRO B TYPE NATRIURETIC PEPTIDE) | NT- ProBNP | MissingDraftCandidate | — | NT- ProBNP (N-TERMINAL PRO B TYPE NATRIURETIC PEPTIDE) | RoutineSingleParameter | — |
| 139 | Glucose Challenge Test (GCT); Pregnancy , 75g Glucose | GCT | MissingDraftCandidate | — | Glucose Challenge Test (GCT); Pregnancy , 75g Glucose | RoutineSingleParameter | — |
| 140 | Serum Procalcitonin | PCT | ConflictRequiresReview | — | Procalcitonin — reconcile with source #41 | RoutineSingleParameter | Duplicate Procalcitonin source identities across departments; Source department differs from proposed canonical discipline |
| 141 | Urine Protein Creatinine Ratio | UPCR | MissingDraftCandidate | — | Urine Protein Creatinine Ratio | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 142 | Serum Cholinesterase | — | MissingDraftCandidate | — | Serum Cholinesterase | RoutineSingleParameter | — |
| 143 | Serum Zinc | — | MissingDraftCandidate | — | Serum Zinc | RoutineSingleParameter | — |
| 144 | Fasting Insulin | — | MissingDraftCandidate | — | Fasting Insulin | RoutineSingleParameter | Source department differs from proposed canonical discipline |
| 145 | Bile Acid | — | MissingDraftCandidate | — | Bile Acid | RoutineMultiParameter/Profile | — |
| 146 | Homocysteine | — | MissingDraftCandidate | — | Homocysteine | RoutineSingleParameter | — |
| 147 | Serum LDH | — | AliasExisting | LDH — Lactate Dehydrogenase (LDH) [Draft/NoClinicalReport; clinical=false] | LDH — Lactate Dehydrogenase (LDH) | RoutineSingleParameter | — |
| 148 | Oral Glucose Challenge Test | OGCT | MissingDraftCandidate | — | Oral Glucose Challenge Test | RoutineSingleParameter | — |
| 149 | DOUBLE MARKER, MATERNAL SCREEN-2 TESTS | — | MissingDraftCandidate | — | DOUBLE MARKER, MATERNAL SCREEN-2 TESTS | RoutineMultiParameter/Profile | — |
| 150 | Adenosine Deaminase | ADA | MissingDraftCandidate | — | Adenosine Deaminase | RoutineMultiParameter/Profile | — |
| 151 | Ascitic Fluid Examination | AFE | SpecialistWorkflowRequired | — | Ascitic Fluid Examination | StructuredClinicalPathology | Source department differs from proposed canonical discipline |
| 152 | ADA (Pleural,Pericardial or Ascitic Fluid) | ADA (Pleural,Pericardial or Ascitic Fluid) | MissingDraftCandidate | — | ADA (Pleural,Pericardial or Ascitic Fluid) | RoutineSingleParameter | — |

## Reporting-type mapping

| Source type | Prospective LIS mapping | Safety boundary |
|---|---|---|
| Single parameter | Routine single typed parameter | Draft until configured and validated |
| Multi parameter | Routine multi-parameter test/profile | Confirm profile-versus-standalone identity and parameter structure |
| Multi parameter nested | Structured Clinical Pathology | Use ordered headings and typed parameters; no forced flat result |
| Document | Document/structured narrative review | Cytology/culture/molecular entries use dedicated workflows |

## Department normalization

The CSV retains the source department and adds a separate proposed canonical department. Hormones/immunoassays are routed by clinical discipline for review; no source department is overwritten.

## Implementation batches

1. Hematology identity decisions and Draft-only additions.
2. Biochemistry identity/profile conflicts and calculation-definition candidates.
3. Endocrinology/Hormone identities.
4. Serology/Immunology assay and qualitative-value governance.
5. Structured Clinical Pathology services.
6. Dedicated Microbiology culture/microscopy workflows.
7. Dedicated Cytology cases and sections.
8. Molecular/Genetics assays and versions.

Every approved new identity must start Draft with billing and clinical reporting disabled. Clinical ranges, critical limits, formulas, methods, analyzers and assay configuration require separate authoritative approval.
