Here is the complete clinical LIS parameter and result-structure configuration for all **33 structural tests** and the standardized option-sets for the **13 qualitative tests**.

### Part 1: Parameter & Result Structures (33 Tests)

| #Test Code & NameSpecimenParameters / Analyte NameResult TypeUnitsStandard Clinical Reference Range / Values |   |
| ------------------------------------------------------------------------------------------------------------ | - |
| **1**                                                                                                        |   |

`ABG`

(Arterial Blood Gas)

| Heparinized Arterial Whole Blood |   |
| -------------------------------- | - |

• pH

• pCO₂

• pO₂

• HCO₃⁻ (Calculated)

• Base Excess (BE)

• SaO₂

• FiO₂ (Input)

|   |
| - |

Numeric

Numeric

Numeric

Numeric

Numeric

Numeric

Numeric

|   |
| - |

—

mmHg

mmHg

mmol/L

mmol/L

%

%

|   |
| - |

• 7.35 – 7.45

• 35 – 45

• 80 – 100

• 22 – 26

• -2 to +2

• 95 – 100

• Clinical context

| **2** |   |
| ----- | - |

`ABS_DLC`

(Absolute Diff. Count)

| EDTA Whole Blood |   |
| ---------------- | - |

• Absolute Neutrophil Count (ANC)

• Absolute Lymphocyte Count (ALC)

• Absolute Monocyte Count (AMC)

• Absolute Eosinophil Count (AEC)

• Absolute Basophil Count (ABC)

|   |
| - |

Numeric

Numeric

Numeric

Numeric

Numeric

|   |
| - |

/µL (or 109/L)

/µL (or 109/L)

/µL (or 109/L)

/µL (or 109/L)

/µL (or 109/L)

|   |
| - |

• 2,000 – 7,000 /µL (2.0–7.0)

• 1,000 – 3,000 /µL (1.0–3.0)

• 200 – 1,000 /µL (0.2–1.0)

• 20 – 500 /µL (0.02–0.5)

• 0 – 100 /µL (0.0–0.1)

| **3** |   |
| ----- | - |

`ADA`

(Adenosine Deaminase)

| Body Fluids (Pleural / Ascitic / CSF / Serum) |   |
| --------------------------------------------- | - |

• Fluid Type

• ADA Level

|   |
| - |

Text / Dropdown

Numeric

|   |
| - |

—

U/L

|   |
| - |

• Pleural/Ascitic/CSF

• Serum: < 15; Pleural: < 30 (Suspicious > 40 U/L)

| **4** |   |
| ----- | - |

`APTT`

(Activated Partial Thromboplastin Time)

| Sodium Citrate Plasma (3.2%) |   |
| ---------------------------- | - |

• Patient Time

• Control Time

• Ratio

|   |
| - |

Numeric

Numeric

Numeric

|   |
| - |

Seconds

Seconds

Ratio

|   |
| - |

• 26.0 – 36.0 sec

• Lot specific

• 0.8 – 1.2

| **5** |   |
| ----- | - |

`BILE_ACID`

(Bile Acids, Total)

| Serum (Fasting preferred) | • Total Bile Acids | Numeric | µmol/L | • Fasting: 0.0 – 10.0 µmol/L |
| ------------------------- | ------------------ | ------- | ------ | ---------------------------- |
| **6**                     |                    |         |        |                              |

`BILIRUBIN_TD`

(Bilirubin Total & Direct)

| Serum |   |
| ----- | - |

• Total Bilirubin

• Direct (Conjugated) Bilirubin

• Indirect (Unconjugated) Bilirubin

|   |
| - |

Numeric

Numeric

Calculated

|   |
| - |

mg/dL

mg/dL

mg/dL

|   |
| - |

• 0.2 – 1.2 mg/dL

• 0.0 – 0.3 mg/dL

• 0.2 – 0.9 mg/dL

| **7** |   |
| ----- | - |

`BLOOD_GROUP_RH`

(Blood Group & Rh)

| EDTA Whole Blood |   |
| ---------------- | - |

• ABO Blood Group

• Rh (D) Factor

|   |
| - |

Dropdown

Dropdown

|   |
| - |

—

—

|   |
| - |

• Options: `["A", "B", "AB", "O"]`

• Options: `["Positive", "Negative"]`

| **8** |   |
| ----- | - |

`BT_CT`

(Bleeding & Clotting Time)

| Capillary / Whole Blood |   |
| ----------------------- | - |

• Bleeding Time (BT)

• Clotting Time (CT)

• Method Used

|   |
| - |

Numeric (Time)

Numeric (Time)

Text

|   |
| - |

Min\:Sec

Min\:Sec

—

|   |
| - |

• Duke: 1–5 min / Ivy: 2–9 min

• Lee-White: 5–11 min / Capillary: 3–8 min

• e.g., Duke / Capillary Tube

| **9** |   |
| ----- | - |

`COAG_PROFILE`

(Coagulation Profile)

| Sodium Citrate Plasma (3.2%) + EDTA |   |
| ----------------------------------- | - |

• Prothrombin Time (PT)

• PT Control

• INR

• APTT Patient

• APTT Control

• Fibrinogen

• Platelet Count

|   |
| - |

Numeric

Numeric

Numeric

Numeric

Numeric

Numeric

Numeric

|   |
| - |

Seconds

Seconds

—

Seconds

Seconds

mg/dL

/µL

|   |
| - |

• 11.0 – 15.0 sec

• Lot specific

• 0.8 – 1.2 (Therapeutic: 2.0–3.0)

• 26.0 – 36.0 sec

• Lot specific

• 200 – 400 mg/dL

• 150,000 – 450,000 /µL

| **10** |   |
| ------ | - |

`DENGUE_IGM_IGG_PANEL`

(Dengue IgM & IgG)

| Serum |   |
| ----- | - |

• Dengue IgM Antibody

• Dengue IgG Antibody

|   |
| - |

Dropdown / Index

Dropdown / Index

|   |
| - |

Qualitative or Ratio

Qualitative or Ratio

|   |
| - |

• `["Negative", "Positive", "Equivocal"]` (< 0.90 / > 1.10)

• `["Negative", "Positive", "Equivocal"]` (< 0.90 / > 1.10)

| **11** |   |
| ------ | - |

`DENGUE_PANEL`

(Dengue Combo NS1, IgM, IgG)

| Serum |   |
| ----- | - |

• Dengue NS1 Antigen

• Dengue IgM Antibody

• Dengue IgG Antibody

|   |
| - |

Dropdown

Dropdown

Dropdown

|   |
| - |

—

—

—

|   |
| - |

• `["Negative", "Positive"]`

• `["Negative", "Positive"]`

• `["Negative", "Positive"]`

| **12** |   |
| ------ | - |

`DLC_3PART`

(3-Part Differential Count)

| EDTA Whole Blood |   |
| ---------------- | - |

• Granulocytes %

• Lymphocytes %

• Mid cells (Monocytes/Eos/Baso) %

|   |
| - |

Numeric

Numeric

Numeric

|   |
| - |

%

%

%

|   |
| - |

• 50.0 – 70.0%

• 20.0 – 40.0%

• 3.0 – 12.0%

| **13** |   |
| ------ | - |

`DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS`

(Double Marker)

| Serum |   |
| ----- | - |

• Gestational Age (Ultrasound)

• Free Beta hCG

• Free Beta hCG MoM

• PAPP-A

• PAPP-A MoM

• Nuchal Translucency (NT)

• T21 (Down Syndrome) Risk Cut-off

• T18/13 Risk Cut-off

|   |
| - |

Numeric

Numeric

Numeric

Numeric

Numeric

Numeric

Dropdown / Ratio

Dropdown / Ratio

|   |
| - |

Weeks/Days

mIU/mL

MoM

mIU/L

MoM

mm

—

—

|   |
| - |

• 11w 0d to 13w 6d

• Gestation-specific

• Corrected MoM (\~1.0)

• Gestation-specific

• Corrected MoM (\~1.0)

• < 3.0 mm

• Low Risk (< 1:250) / High Risk (> 1:250)

• Low Risk / High Risk

| **14** |   |
| ------ | - |

`GLUCOSE_TOLERANCE_TEST_GTT_PREGNANCY`

(GTT Pregnancy / DIPSI / OGTT)

| Fluoride Plasma |   |
| --------------- | - |

• Fasting Blood Glucose

• 1-Hour Post 75g Glucose

• 2-Hour Post 75g Glucose

|   |
| - |

Numeric

Numeric

Numeric

|   |
| - |

mg/dL

mg/dL

mg/dL

|   |
| - |

• < 92 mg/dL (IADPSG)

• < 180 mg/dL

• < 153 mg/dL

| **15** |   |
| ------ | - |

`GTT`

(Glucose Tolerance Test - Standard)

| Fluoride Plasma |   |
| --------------- | - |

• Fasting Glucose

• 30-Minute Glucose

• 60-Minute Glucose

• 90-Minute Glucose

• 120-Minute (2-Hr) Glucose

|   |
| - |

Numeric

Numeric

Numeric

Numeric

Numeric

|   |
| - |

mg/dL

mg/dL

mg/dL

mg/dL

mg/dL

|   |
| - |

• 70 – 99 mg/dL

• For curve mapping

• < 200 mg/dL

• For curve mapping

• < 140 mg/dL (Normal); 140–199 (IGT); ≥ 200 (Diabetic)

| **16** |   |
| ------ | - |

`HAV_PANEL`

(Hepatitis A Panel)

| Serum |   |
| ----- | - |

• Anti-HAV IgM

• Anti-HAV IgG / Total

|   |
| - |

Dropdown / Index

Dropdown / Index

|   |
| - |

S/CO or Index

S/CO or Index

|   |
| - |

• `["Non-Reactive", "Reactive"]` (Acute marker)

• `["Non-Reactive", "Reactive"]` (Past immunity)

| **17** |   |
| ------ | - |

`HIV_CARD_TEST`

(HIV 1 & 2 Rapid Card)

| Serum / Plasma / Whole Blood |   |
| ---------------------------- | - |

• HIV-1 Antibody Band

• HIV-2 Antibody Band

• Final Result Interpretation

|   |
| - |

Dropdown

Dropdown

Dropdown

|   |
| - |

—

—

—

|   |
| - |

• `["Non-Reactive", "Reactive"]`

• `["Non-Reactive", "Reactive"]`

• `["Non-Reactive", "Reactive", "Invalid"]`

| **18** |   |
| ------ | - |

`HPLC`

(Hb HPLC / Electrophoresis)

| EDTA Whole Blood |   |
| ---------------- | - |

• Hb A0

• Hb A2

• Hb F

• Variant Window (Hb S/D/E/C)

• Impression / Interpretation

|   |
| - |

Numeric

Numeric

Numeric

Numeric / Text

Text Multi-line

|   |
| - |

%

%

%

%

—

|   |
| - |

• 95.0 – 97.5%

• 1.5 – 3.5% (High >3.8% suggests β-thal trait)

• < 1.0% (Adults)

• Not Detected (0%)

• Descriptive pathological review

| **19** |   |
| ------ | - |

`IRON_PROFILE`

(Iron Profile)

| Serum (Fasting) |   |
| --------------- | - |

• Serum Iron

• Total Iron Binding Capacity (TIBC)

• Transferrin Saturation (%)

• Serum Ferritin

|   |
| - |

Numeric

Numeric

Calculated

Numeric

|   |
| - |

µg/dL

µg/dL

%

ng/mL

|   |
| - |

• 60 – 170 µg/dL

• 240 – 450 µg/dL

• 20 – 50% ([Iron/TIBC]×100)

• Male: 30–400, Female: 15–150 ng/mL

| **20** |   |
| ------ | - |

`LEUKEMIA_DLC`

(Leukemia Differential Assessment)

| EDTA Whole Blood / Smear |   |
| ------------------------ | - |

• Blast Cells %

• Promyelocytes %

• Myelocytes %

• Metamyelocytes %

• Neutrophils (Band/Seg) %

• Lymphocytes %

• Monocytes %

• Eosinophils %

• Basophils %

• Pathologist Impression

|   |
| - |

Numeric

Numeric

Numeric

Numeric

Numeric

Numeric

Numeric

Numeric

Numeric

Text Multi-line

|   |
| - |

%

%

%

%

%

%

%

%

%

—

|   |
| - |

• 0%

• 0%

• 0%

• 0%

• 40 – 70%

• 20 – 40%

• 2 – 8%

• 1 – 6%

• 0 – 1%

• Smear review notes / Flow cytometry recommendation

| **21** |   |
| ------ | - |

`LUPUS_ANTICOAGULANT_DRVVT`

(dRVVT Screening & Confirmatory)

| Citrated Platelet-Poor Plasma |   |
| ----------------------------- | - |

• dRVVT Screen Time

• dRVVT Confirm Time

• dRVVT Screen/Confirm Ratio

• Interpretation

|   |
| - |

Numeric

Numeric

Calculated

Dropdown

|   |
| - |

Seconds

Seconds

Ratio

—

|   |
| - |

• 30.0 – 45.0 sec

• 30.0 – 40.0 sec

• Normal: < 1.20; Equivocal: 1.20–1.37; Positive: > 1.38

• `["Negative", "Equivocal", "Positive"]`

| **22** |   |
| ------ | - |

`MALARIA_ANTIGEN`

(Malaria Ag Pan / Pf)

| EDTA Whole Blood |   |
| ---------------- | - |

• Plasmodium falciparum (Pf - HRP2)

• Pan (Pv/Pm/Po - LDH / Aldolase)

• Interpretation

|   |
| - |

Dropdown

Dropdown

Dropdown

|   |
| - |

—

—

—

|   |
| - |

• `["Negative", "Positive"]`

• `["Negative", "Positive"]`

• `["Negative for Malaria Parasite", "Positive for P. falciparum", "Positive for Non-falciparum (P. vivax/ovale/malariae)", "Mixed Infection"]`

| **23** |   |
| ------ | - |

`MICROALBUMIN_CREATININE_RATIO_URINE_RANDOM`

(ACR Urine)

| Random Spot Urine |   |
| ----------------- | - |

• Urine Microalbumin

• Urine Creatinine

• Albumin-to-Creatinine Ratio (ACR)

|   |
| - |

Numeric

Numeric

Calculated

|   |
| - |

mg/L

mg/dL (or g/L)

mg/g (or mg/mmol)

|   |
| - |

• 0 – 20 mg/L

• 20 – 300 mg/dL

• Normal: < 30 mg/g; Microalbuminuria: 30–300 mg/g; Clinical: > 300 mg/g

| **24** |   |
| ------ | - |

`MICROALBUMIN_URINE_24_HOURS`

(24h Urine Albumin)

| 24-Hour Urine Collection |   |
| ------------------------ | - |

• Total 24h Urine Volume

• Urine Albumin Concentration

• Total 24-Hour Albumin Excretion

|   |
| - |

Numeric

Numeric

Calculated

|   |
| - |

mL

mg/L

mg/24 hours

|   |
| - |

• 800 – 2000 mL

• Contextual

• Normal: < 30 mg/24h; Microalbuminuria: 30–300 mg/24h; Macroalbuminuria: > 300 mg/24h

| **25** |   |
| ------ | - |

`MP_CARD_TEST`

(Malaria Parasite Card)

| EDTA Whole Blood |   |
| ---------------- | - |

• P. falciparum Ag

• P. vivax Ag

|   |
| - |

Dropdown

Dropdown

|   |
| - |

—

—

|   |
| - |

• `["Negative", "Positive"]`

• `["Negative", "Positive"]`

| **26** |   |
| ------ | - |

`PLATELET_INDICES`

(Platelet Parameters)

| EDTA Whole Blood |   |
| ---------------- | - |

• Platelet Count

• Mean Platelet Volume (MPV)

• Platelet Distribution Width (PDW)

• Plateletcrit (PCT)

|   |
| - |

Numeric

Numeric

Numeric

Numeric

|   |
| - |

103/µL

fL

fL (or %)

%

|   |
| - |

• 150 – 450 103/µL

• 7.5 – 11.5 fL

• 9.0 – 17.0 fL

• 0.15 – 0.40%

| **27** |   |
| ------ | - |

`PT_INR`

(Prothrombin Time / INR)

| Sodium Citrate Plasma (3.2%) |   |
| ---------------------------- | - |

• Patient Prothrombin Time

• Control Time

• International Normalized Ratio (INR)

• ISI Value (Instrument parameter)

|   |
| - |

Numeric

Numeric

Calculated

Numeric

|   |
| - |

Seconds

Seconds

Ratio

—

|   |
| - |

• 11.0 – 14.5 sec

• Lot specific (e.g., 12.0 sec)

• Normal: 0.8 – 1.2 (Warfarin Target: 2.0 – 3.0)

• Lot/reagent specific (\~1.0)

| **28** |   |
| ------ | - |

`RBC_INDICES`

(Erythrocyte Indices)

| EDTA Whole Blood |   |
| ---------------- | - |

• Mean Corpuscular Volume (MCV)

• Mean Corpuscular Hemoglobin (MCH)

• MCH Concentration (MCHC)

• Red Cell Distribution Width (RDW-CV)

|   |
| - |

Numeric

Numeric

Numeric

Numeric

|   |
| - |

fL

pg

g/dL

%

|   |
| - |

• 80.0 – 100.0 fL

• 27.0 – 33.0 pg

• 32.0 – 36.0 g/dL

• 11.5 – 14.5%

| **29** |   |
| ------ | - |

`RUBELLA`

(Rubella IgG & IgM Panel)

| Serum |   |
| ----- | - |

• Rubella IgM Antibody

• Rubella IgG Antibody

|   |
| - |

Numeric / Dropdown

Numeric / Dropdown

|   |
| - |

AU/mL or Index

IU/mL or Index

|   |
| - |

• IgM: < 0.8 (Negative), 0.8–1.0 (Equivocal), > 1.0 (Positive)

• IgG: < 10 IU/mL (Non-immune), ≥ 10 IU/mL (Immune)

| **30** |   |
| ------ | - |

`SCRUB_TYPHUS`

(Scrub Typhus IgM Rapid/ELISA)

| Serum |   |
| ----- | - |

• Scrub Typhus IgM Antibody

• Scrub Typhus IgG Antibody *(if combo)*

|   |
| - |

Dropdown / Index

Dropdown / Index

|   |
| - |

Qualitative / Index

Qualitative / Index

|   |
| - |

• `["Negative", "Positive", "Equivocal"]`

• `["Negative", "Positive"]`

| **31** |   |
| ------ | - |

`TB_GOLD_INTERFERON_GAMMA_RELEASE_ASSAY`

(TB QuantiFERON / IGRA)

| Specialized IGRA Blood Tubes (Nil, TB Ag, Mitogen) |   |
| -------------------------------------------------- | - |

• Nil (Negative Control)

• TB Antigen Minus Nil

• Mitogen Minus Nil (Positive Control)

• Final Result

|   |
| - |

Numeric

Numeric

Numeric

Dropdown

|   |
| - |

IU/mL

IU/mL

IU/mL

—

|   |
| - |

• ≤8.0 IU/mL

• ≥0.35 IU/mL (and ≥25% of Nil) = Positive

• ≥0.5 IU/mL (Valid)

• `["Negative", "Positive", "Indeterminate"]`

| **32** |   |
| ------ | - |

`TYPHIDOT_ANTIBODIES`

(Typhidot IgM & IgG)

| Serum |   |
| ----- | - |

• S. typhi IgM (Specific for Acute Phase)

• S. typhi IgG (Past / Chronic / Anamnestic)

|   |
| - |

Dropdown

Dropdown

|   |
| - |

—

—

|   |
| - |

• `["Non-Reactive", "Reactive"]`

• `["Non-Reactive", "Reactive"]`

| **33** |   |
| ------ | - |

`WEIL_FELIX_TEST_SERUM`

(Weil-Felix Rickettsial Agglutination)

| Serum |   |
| ----- | - |

• Proteus OX-19 Titer

• Proteus OX-2 Titer

• Proteus OX-K Titer

• Interpretation

|   |
| - |

Dropdown

Dropdown

Dropdown

Text

|   |
| - |

Titer Dilution

Titer Dilution

Titer Dilution

—

|   |
| - |

• Options: `["< 1:20", "1:20", "1:40", "1:80", "1:160", "1:320", "> 1:320"]`

• Normal: <1:80; Diagnostic / Significant: ≥1:160

• OX-19/OX-2 (Epidemic/Endemic/Spotted Fevers); OX-K (Scrub Typhus)

### Part 2: Standardized Qualitative Option-Sets (13 Tests)

| #Test NameSuggested Option Set (`values`)Default / Normal StateClinical Interpretation Schema |                                                                     |                                                                                                                                                                           |                                   |                                                                                                        |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **1**                                                                                         | **ANA by ELISA**                                                    | `["Negative", "Equivocal", "Positive"]`                                                                                                                                   | `Negative`                        | Ratio: <0.8 Negative, 0.8−1.2 Equivocal, >1.2 Positive                                                 |
| **2**                                                                                         | **CEA** *(Rapid/Qual)*                                              | `["Negative (< 5 ng/mL)", "Positive (≥ 5 ng/mL)"]`                                                                                                                        | `Negative (< 5 ng/mL)`            | For screening card formats (ELISA/CLIA should use numeric ng/mL)                                       |
| **3**                                                                                         | **GCT** *(Glucose Challenge Test Screening)*                        | `["Normal (< 140 mg/dL)", "Abnormal / Elevated (≥ 140 mg/dL)"]`                                                                                                           | `Normal (< 140 mg/dL)`            | Indicates need for definitive 3-hour OGTT if Abnormal                                                  |
| **4**                                                                                         | **HAV IgG**                                                         | `["Non-Reactive", "Reactive"]`                                                                                                                                            | `Non-Reactive`                    | Non-Reactive indicates non-immune; Reactive indicates immunity                                         |
| **5**                                                                                         | **HAV IgM**                                                         | `["Non-Reactive", "Reactive"]`                                                                                                                                            | `Non-Reactive`                    | Reactive indicates acute Hepatitis A infection                                                         |
| **6**                                                                                         | **HAV Total Ab**                                                    | `["Non-Reactive", "Reactive"]`                                                                                                                                            | `Non-Reactive`                    | Reactive indicates prior infection or vaccination                                                      |
| **7**                                                                                         | **Kala Azar** *(rK39 Antigen/Card)*                                 | `["Negative", "Positive", "Invalid"]`                                                                                                                                     | `Negative`                        | Rapid immunochromatographic detection of Leishmania donovani                                           |
| **8**                                                                                         | **Malaria Parasite Microscopic** *(Thick & Thin Smear Examination)* | `["No Malaria Parasites Seen (NMP)", "Plasmodium vivax Seen", "Plasmodium falciparum Seen", "Plasmodium malariae Seen", "Plasmodium ovale Seen", "Mixed Infection Seen"]` | `No Malaria Parasites Seen (NMP)` | Paired with free-text field for density quantification (e.g., ring stages count / oil immersion field) |
| **9**                                                                                         | **Thyroglobulin Antibody (Anti-Tg)**                                | `["Negative", "Positive"]` *(or* *`["< 115 IU/mL (Negative)", "≥ 115 IU/mL (Positive)"]`**)*                                                                              | `Negative`                        | Identifies autoimmune thyroiditis                                                                      |
| **10**                                                                                        | **TPHA** *(Treponema pallidum Hemagglutination)*                    | `["Non-Reactive", "Reactive", "Inconclusive / Borderline"]`                                                                                                               | `Non-Reactive`                    | Confirmatory treponemal test for syphilis                                                              |
| **11**                                                                                        | **Troponin I Rapid** *(Card)*                                       | `["Negative (< 0.5 ng/mL)", "Positive (≥ 0.5 ng/mL)", "Invalid"]`                                                                                                         | `Negative (< 0.5 ng/mL)`          | Rapid qualitative exclusion of acute myocardial infarction                                             |
| **12**                                                                                        | **UPT** *(Urine Pregnancy Test - Rapid hCG)*                        | `["Negative", "Positive", "Invalid"]`                                                                                                                                     | `Negative`                        | Rapid qualitative lateral flow detection                                                               |
| **13**                                                                                        | **Urine ELISA Pregnancy**                                           | `["Negative", "Positive", "Equivocal / Borderline"]`                                                                                                                      | `Negative`                        | Highly sensitive microplate-based hCG detection                                                        |