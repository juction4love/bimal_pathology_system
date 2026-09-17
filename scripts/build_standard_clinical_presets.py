#!/usr/bin/env python3
"""
scripts/build_standard_clinical_presets.py
Generates migration 00103: Standard Clinical Presets Library for all 1,122 canonical tests.
Strictly adheres to clinical safety, zero fabricated approval evidence, and fail-closed governance.
"""

import os
import csv
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_FILE = os.path.join(ROOT, "approved-data", "Bimal_Pathology_Master_Test_Catalogue_1122.csv")
SQL_OUT = os.path.join(ROOT, "supabase", "migrations", "00103_standard_clinical_presets_library.sql")

with open(CSV_FILE, "r", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

print(f"Loaded {len(rows)} canonical test records from master catalogue.")

# Specific clinical reference intervals and critical limits for routine and specialized pathology parameters
CLINICAL_PRESETS = {
    # --- Hematology ---
    "HEM-0002": { # Hemoglobin
        "method": "SLS-Hemoglobin / Photometric",
        "ranges": [
            {"gender": "Male", "min": 13.0, "max": 17.0, "crit_low": 7.0, "crit_high": 20.0, "text": "13.0 - 17.0 g/dL"},
            {"gender": "Female", "min": 12.0, "max": 15.5, "crit_low": 7.0, "crit_high": 20.0, "text": "12.0 - 15.5 g/dL"},
        ],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "HEM-0003": { # Hematocrit / PCV
        "method": "Calculated (RBC x MCV / 10) / Centrifugation",
        "ranges": [
            {"gender": "Male", "min": 40.0, "max": 50.0, "crit_low": 20.0, "crit_high": 60.0, "text": "40.0 - 50.0 %"},
            {"gender": "Female", "min": 36.0, "max": 46.0, "crit_low": 20.0, "crit_high": 60.0, "text": "36.0 - 46.0 %"},
        ],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "HEM-0004": { # RBC Count
        "method": "Automated Electrical Impedance",
        "ranges": [
            {"gender": "Male", "min": 4.5, "max": 5.9, "text": "4.5 - 5.9 x10^6/µL"},
            {"gender": "Female", "min": 4.0, "max": 5.2, "text": "4.0 - 5.2 x10^6/µL"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0005": { # WBC Count / TLC
        "method": "Automated Flow Cytometry / Impedance",
        "ranges": [
            {"gender": "All", "min": 4.0, "max": 10.5, "crit_low": 1.5, "crit_high": 30.0, "text": "4.0 - 10.5 x10^3/µL"},
        ],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "HEM-0006": { # Platelet Count
        "method": "Automated Electrical Impedance / Optical",
        "ranges": [
            {"gender": "All", "min": 150.0, "max": 450.0, "crit_low": 20.0, "crit_high": 1000.0, "text": "150 - 450 x10^3/µL"},
        ],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "HEM-0007": { # MCV
        "method": "Calculated (HCT x 10 / RBC)",
        "ranges": [{"gender": "All", "min": 80.0, "max": 98.0, "text": "80.0 - 98.0 fL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0008": { # MCH
        "method": "Calculated (Hb x 10 / RBC)",
        "ranges": [{"gender": "All", "min": 27.0, "max": 33.0, "text": "27.0 - 33.0 pg"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0009": { # MCHC
        "method": "Calculated (Hb x 100 / HCT)",
        "ranges": [{"gender": "All", "min": 32.0, "max": 36.0, "text": "32.0 - 36.0 g/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0010": { # RDW-CV
        "method": "Automated Impedance / Optical",
        "ranges": [{"gender": "All", "min": 11.5, "max": 14.5, "text": "11.5 - 14.5 %"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0015": { # Neutrophil %
        "method": "Automated Flow Cytometry / Manual Differential",
        "ranges": [{"gender": "All", "min": 40.0, "max": 75.0, "text": "40.0 - 75.0 %"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0016": { # Lymphocyte %
        "method": "Automated Flow Cytometry / Manual Differential",
        "ranges": [{"gender": "All", "min": 20.0, "max": 45.0, "text": "20.0 - 45.0 %"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0017": { # Monocyte %
        "method": "Automated Flow Cytometry / Manual Differential",
        "ranges": [{"gender": "All", "min": 2.0, "max": 10.0, "text": "2.0 - 10.0 %"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0018": { # Eosinophil %
        "method": "Automated Flow Cytometry / Manual Differential",
        "ranges": [{"gender": "All", "min": 1.0, "max": 6.0, "text": "1.0 - 6.0 %"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0019": { # Basophil %
        "method": "Automated Flow Cytometry / Manual Differential",
        "ranges": [{"gender": "All", "min": 0.0, "max": 1.5, "text": "0.0 - 1.5 %"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0020": { # Absolute Neutrophil Count (ANC)
        "method": "Calculated (WBC x Neutrophil% / 100)",
        "ranges": [{"gender": "All", "min": 1.8, "max": 7.5, "crit_low": 0.5, "crit_high": None, "text": "1.8 - 7.5 x10^3/µL"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "HEM-0021": { # Absolute Lymphocyte Count
        "method": "Calculated (WBC x Lymphocyte% / 100)",
        "ranges": [{"gender": "All", "min": 1.0, "max": 4.0, "text": "1.0 - 4.0 x10^3/µL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0022": { # Absolute Eosinophil Count
        "method": "Calculated (WBC x Eosinophil% / 100) / Direct Chamber",
        "ranges": [{"gender": "All", "min": 40.0, "max": 450.0, "text": "40 - 450 cells/µL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "HEM-0027": { # ESR
        "method": "Westergren Method",
        "ranges": [
            {"gender": "Male", "min": 0.0, "max": 15.0, "text": "0 - 15 mm/hr"},
            {"gender": "Female", "min": 0.0, "max": 20.0, "text": "0 - 20 mm/hr"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },

    # --- Biochemistry ---
    "BIO-0001": { # Fasting Glucose
        "method": "Hexokinase / GOD-POD",
        "ranges": [{"gender": "All", "min": 70.0, "max": 99.0, "crit_low": 50.0, "crit_high": 400.0, "text": "70 - 99 mg/dL (Normal Fasting), 100 - 125 mg/dL (Impaired Fasting)"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0002": { # Random Blood Sugar
        "method": "Hexokinase / GOD-POD",
        "ranges": [{"gender": "All", "min": 70.0, "max": 140.0, "crit_low": 50.0, "crit_high": 400.0, "text": "70 - 140 mg/dL"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0003": { # Postprandial Glucose (PP 2 hr)
        "method": "Hexokinase / GOD-POD",
        "ranges": [{"gender": "All", "min": 70.0, "max": 140.0, "crit_low": 50.0, "crit_high": 400.0, "text": "< 140 mg/dL (Normal), 140 - 199 mg/dL (Impaired Glucose Tolerance)"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0006": { # HbA1c
        "method": "HPLC / Enzymatic / Immunoturbidimetry (NGSP/IFCC Certified)",
        "ranges": [{"gender": "All", "min": 4.0, "max": 5.6, "crit_low": None, "crit_high": 12.0, "text": "< 5.7 % (Normal), 5.7 - 6.4 % (Prediabetes), >= 6.5 % (Diabetes)"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0008": { # Blood Urea
        "method": "Urease - GLDH Enzymatic",
        "ranges": [{"gender": "All", "min": 15.0, "max": 45.0, "text": "15 - 45 mg/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0009": { # Blood Urea Nitrogen (BUN)
        "method": "Calculated (Urea / 2.14) / Enzymatic",
        "ranges": [{"gender": "All", "min": 7.0, "max": 20.0, "text": "7 - 20 mg/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0010": { # Serum Creatinine
        "method": "Enzymatic / Modified Jaffe (IDMS Traceable)",
        "ranges": [
            {"gender": "Male", "min": 0.7, "max": 1.3, "crit_low": None, "crit_high": 5.0, "text": "0.7 - 1.3 mg/dL"},
            {"gender": "Female", "min": 0.6, "max": 1.1, "crit_low": None, "crit_high": 5.0, "text": "0.6 - 1.1 mg/dL"},
        ],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0011": { # eGFR
        "method": "CKD-EPI 2021 Equation",
        "ranges": [{"gender": "All", "min": 90.0, "max": 120.0, "text": ">= 90 mL/min/1.73m² (Normal), 60-89 (Mild decrease), 30-59 (Moderate), 15-29 (Severe), < 15 (Kidney failure)"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0012": { # Uric Acid
        "method": "Uricase - PAP Enzymatic",
        "ranges": [
            {"gender": "Male", "min": 3.5, "max": 7.2, "text": "3.5 - 7.2 mg/dL"},
            {"gender": "Female", "min": 2.6, "max": 6.0, "text": "2.6 - 6.0 mg/dL"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0013": { # Total Protein
        "method": "Biuret Method",
        "ranges": [{"gender": "All", "min": 6.4, "max": 8.3, "text": "6.4 - 8.3 g/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0014": { # Albumin
        "method": "Bromocresol Green (BCG)",
        "ranges": [{"gender": "All", "min": 3.5, "max": 5.2, "text": "3.5 - 5.2 g/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0015": { # Globulin
        "method": "Calculated (Total Protein - Albumin)",
        "ranges": [{"gender": "All", "min": 2.0, "max": 3.5, "text": "2.0 - 3.5 g/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0016": { # A/G Ratio
        "method": "Calculated (Albumin / Globulin)",
        "ranges": [{"gender": "All", "min": 1.1, "max": 2.2, "text": "1.1 - 2.2"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0017": { # Sodium (Na+)
        "method": "Direct / Indirect Ion Selective Electrode (ISE)",
        "ranges": [{"gender": "All", "min": 136.0, "max": 145.0, "crit_low": 120.0, "crit_high": 160.0, "text": "136 - 145 mmol/L"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0018": { # Potassium (K+)
        "method": "Direct / Indirect Ion Selective Electrode (ISE)",
        "ranges": [{"gender": "All", "min": 3.5, "max": 5.1, "crit_low": 2.5, "crit_high": 6.2, "text": "3.5 - 5.1 mmol/L"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0019": { # Chloride (Cl-)
        "method": "Ion Selective Electrode (ISE) / Colorimetric",
        "ranges": [{"gender": "All", "min": 98.0, "max": 107.0, "crit_low": 80.0, "crit_high": 120.0, "text": "98 - 107 mmol/L"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0020": { # Calcium, Total
        "method": "Arsenazo III / O-CPC Photometric",
        "ranges": [{"gender": "All", "min": 8.6, "max": 10.2, "crit_low": 6.0, "crit_high": 13.0, "text": "8.6 - 10.2 mg/dL"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0021": { # Calcium, Ionized
        "method": "Direct Ion Selective Electrode (ISE)",
        "ranges": [{"gender": "All", "min": 1.15, "max": 1.33, "crit_low": 0.80, "crit_high": 1.60, "text": "1.15 - 1.33 mmol/L"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0022": { # Magnesium
        "method": "Calmagite / Xylidyl Blue Photometric",
        "ranges": [{"gender": "All", "min": 1.7, "max": 2.4, "crit_low": 1.0, "crit_high": 4.5, "text": "1.7 - 2.4 mg/dL"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0023": { # Phosphorus (Inorganic)
        "method": "Phosphomolybdate UV",
        "ranges": [{"gender": "All", "min": 2.5, "max": 4.5, "crit_low": 1.0, "crit_high": None, "text": "2.5 - 4.5 mg/dL"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0024": { # Bilirubin, Total
        "method": "Diazo / DCA Photometric",
        "ranges": [{"gender": "All", "min": 0.2, "max": 1.2, "crit_low": None, "crit_high": 15.0, "text": "0.2 - 1.2 mg/dL"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0025": { # Bilirubin, Direct
        "method": "Diazo Photometric",
        "ranges": [{"gender": "All", "min": 0.0, "max": 0.3, "text": "0.0 - 0.3 mg/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0026": { # Bilirubin, Indirect
        "method": "Calculated (Total Bilirubin - Direct Bilirubin)",
        "ranges": [{"gender": "All", "min": 0.1, "max": 0.9, "text": "0.1 - 0.9 mg/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0027": { # SGOT / AST
        "method": "IFCC without Pyridoxal Phosphate (UV Enzymatic)",
        "ranges": [
            {"gender": "Male", "min": 0.0, "max": 40.0, "text": "< 40 U/L"},
            {"gender": "Female", "min": 0.0, "max": 32.0, "text": "< 32 U/L"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0028": { # SGPT / ALT
        "method": "IFCC without Pyridoxal Phosphate (UV Enzymatic)",
        "ranges": [
            {"gender": "Male", "min": 0.0, "max": 41.0, "text": "< 41 U/L"},
            {"gender": "Female", "min": 0.0, "max": 33.0, "text": "< 33 U/L"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0029": { # Alkaline Phosphatase (ALP)
        "method": "IFCC / p-NPP Kinetic Colorimetric",
        "ranges": [{"gender": "All", "min": 44.0, "max": 147.0, "text": "44 - 147 U/L"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0030": { # Gamma-GT (GGT)
        "method": "Szasz / Persijn Method (Enzymatic)",
        "ranges": [
            {"gender": "Male", "min": 8.0, "max": 61.0, "text": "8 - 61 U/L"},
            {"gender": "Female", "min": 5.0, "max": 36.0, "text": "5 - 36 U/L"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0031": { # Total Cholesterol
        "method": "CHOD-PAP Enzymatic Colorimetric",
        "ranges": [{"gender": "All", "min": 0.0, "max": 200.0, "text": "< 200 mg/dL (Desirable), 200-239 (Borderline), >= 240 (High)"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0032": { # Triglycerides
        "method": "GPO-PAP Enzymatic Colorimetric",
        "ranges": [{"gender": "All", "min": 0.0, "max": 150.0, "crit_low": None, "crit_high": 1000.0, "text": "< 150 mg/dL (Normal), 150-199 (Borderline), 200-499 (High), >= 500 (Very High)"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "BIO-0033": { # HDL Cholesterol
        "method": "Direct Clearance / Enzymatic Immunoinhibition",
        "ranges": [
            {"gender": "Male", "min": 40.0, "max": 60.0, "text": "> 40 mg/dL"},
            {"gender": "Female", "min": 50.0, "max": 60.0, "text": "> 50 mg/dL"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0034": { # LDL Cholesterol (Direct / Calc)
        "method": "Direct Enzymatic / Friedewald Calculation",
        "ranges": [{"gender": "All", "min": 0.0, "max": 100.0, "text": "< 100 mg/dL (Optimal), 100-129 (Near Optimal), 130-159 (Borderline), 160-189 (High), >= 190 (Very High)"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0035": { # VLDL Cholesterol
        "method": "Calculated (Triglycerides / 5)",
        "ranges": [{"gender": "All", "min": 5.0, "max": 30.0, "text": "5 - 30 mg/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0036": { # Serum Amylase
        "method": "CNPG3 / IFCC Kinetic Photometric",
        "ranges": [{"gender": "All", "min": 28.0, "max": 100.0, "text": "28 - 100 U/L"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0037": { # Serum Lipase
        "method": "Enzymatic Colorimetric",
        "ranges": [{"gender": "All", "min": 13.0, "max": 60.0, "text": "13 - 60 U/L"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "BIO-0060": { # Troponin I
        "method": "Chemiluminescent Microparticle Immunoassay (CMIA / High Sensitivity)",
        "ranges": [{"gender": "All", "min": 0.0, "max": 0.04, "crit_low": None, "crit_high": 0.05, "text": "< 0.04 ng/mL (Normal Reference Limit)"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },

    # --- Endocrinology ---
    "END-0001": { # TSH (Ultrasensitive)
        "method": "Chemiluminescent Immunoassay (CLIA / 3rd Gen)",
        "ranges": [{"gender": "All", "min": 0.45, "max": 4.5, "text": "0.45 - 4.50 µIU/mL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "END-0002": { # Free T3 (FT3)
        "method": "Chemiluminescent Immunoassay (CLIA)",
        "ranges": [{"gender": "All", "min": 2.0, "max": 4.4, "text": "2.0 - 4.4 pg/mL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "END-0003": { # Free T4 (FT4)
        "method": "Chemiluminescent Immunoassay (CLIA)",
        "ranges": [{"gender": "All", "min": 0.82, "max": 1.77, "text": "0.82 - 1.77 ng/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "END-0004": { # Total T3
        "method": "Chemiluminescent Immunoassay (CLIA)",
        "ranges": [{"gender": "All", "min": 0.8, "max": 2.0, "text": "0.8 - 2.0 ng/mL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "END-0005": { # Total T4
        "method": "Chemiluminescent Immunoassay (CLIA)",
        "ranges": [{"gender": "All", "min": 5.1, "max": 14.1, "text": "5.1 - 14.1 µg/dL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "END-0006": { # Prolactin
        "method": "Chemiluminescent Immunoassay (CLIA)",
        "ranges": [
            {"gender": "Male", "min": 4.0, "max": 15.2, "text": "4.0 - 15.2 ng/mL"},
            {"gender": "Female", "min": 4.8, "max": 23.3, "text": "Non-pregnant: 4.8 - 23.3 ng/mL; Post-menopausal: 3.0 - 18.0 ng/mL"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "END-0007": { # LH (Luteinizing Hormone)
        "method": "Chemiluminescent Immunoassay (CLIA)",
        "ranges": [
            {"gender": "Male", "min": 1.7, "max": 8.6, "text": "1.7 - 8.6 mIU/mL"},
            {"gender": "Female", "min": 2.4, "max": 12.6, "text": "Follicular: 2.4 - 12.6, Mid-cycle: 14.0 - 95.6, Luteal: 1.0 - 11.4, Postmenopausal: 7.7 - 58.5 mIU/mL"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "END-0008": { # FSH (Follicle Stimulating Hormone)
        "method": "Chemiluminescent Immunoassay (CLIA)",
        "ranges": [
            {"gender": "Male", "min": 1.5, "max": 12.4, "text": "1.5 - 12.4 mIU/mL"},
            {"gender": "Female", "min": 3.5, "max": 12.5, "text": "Follicular: 3.5 - 12.5, Mid-cycle: 4.7 - 21.5, Luteal: 1.7 - 7.7, Postmenopausal: 25.8 - 134.8 mIU/mL"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "END-0009": { # Beta-hCG (Quantitative)
        "method": "Chemiluminescent Immunoassay (CLIA)",
        "ranges": [
            {"gender": "Male", "min": 0.0, "max": 5.0, "text": "< 5.0 mIU/mL"},
            {"gender": "Female", "min": 0.0, "max": 5.0, "text": "Non-pregnant: < 5.0 mIU/mL; Pregnancy 3-4 wk: 9-130, 4-5 wk: 75-2600, 5-6 wk: 850-20800 mIU/mL"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "END-0010": { # Testosterone, Total
        "method": "Chemiluminescent Immunoassay (CLIA / LC-MS)",
        "ranges": [
            {"gender": "Male", "min": 240.0, "max": 870.0, "text": "240 - 870 ng/dL"},
            {"gender": "Female", "min": 8.0, "max": 60.0, "text": "8 - 60 ng/dL"},
        ],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "END-0011": { # Intact PTH
        "method": "Chemiluminescent Immunoassay (CLIA)",
        "ranges": [{"gender": "All", "min": 15.0, "max": 65.0, "text": "15 - 65 pg/mL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },

    # --- Coagulation ---
    "COA-0001": { # Prothrombin Time (PT)
        "method": "Electromechanical / Photo-optical Clot Detection",
        "ranges": [{"gender": "All", "min": 11.0, "max": 14.5, "text": "11.0 - 14.5 seconds"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "COA-0002": { # INR
        "method": "Calculated ((Patient PT / MNPT) ^ ISI)",
        "ranges": [{"gender": "All", "min": 0.8, "max": 1.2, "crit_low": None, "crit_high": 4.5, "text": "0.8 - 1.2 (Normal), 2.0 - 3.0 (Standard Oral Anticoagulant Therapy)"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "COA-0003": { # APTT
        "method": "Photo-optical Clot Detection",
        "ranges": [{"gender": "All", "min": 25.0, "max": 38.0, "crit_low": None, "crit_high": 100.0, "text": "25.0 - 38.0 seconds"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "COA-0004": { # Fibrinogen
        "method": "Clauss Method",
        "ranges": [{"gender": "All", "min": 200.0, "max": 400.0, "crit_low": 100.0, "crit_high": None, "text": "200 - 400 mg/dL"}],
        "crit_policy": "DEFENSIBLE_STANDARD_PRESET"
    },
    "COA-0005": { # D-Dimer
        "method": "Quantitative Immunoturbidimetry",
        "ranges": [{"gender": "All", "min": 0.0, "max": 0.5, "text": "< 0.50 µg/mL FEU"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },

    # --- Serology & Immunology ---
    "SER-0001": { # HIV 1 & 2 Rapid Antibody / Ag
        "method": "4th Generation Rapid Immunochromatography (Ag/Ab)",
        "qualitative": "Non-Reactive",
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "SER-0002": { # HBsAg Rapid Screen
        "method": "Rapid Immunochromatography / ELISA",
        "qualitative": "Non-Reactive",
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "SER-0003": { # Anti-HCV Rapid Screen
        "method": "Rapid Immunochromatography / ELISA",
        "qualitative": "Non-Reactive",
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "SER-0004": { # VDRL / RPR
        "method": "Flocculation / Carbon Particle Agglutination",
        "qualitative": "Non-Reactive",
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "SER-0005": { # Widal Test
        "method": "Slide & Tube Agglutination",
        "qualitative": "S. Typhi O & H Titre < 1:80",
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "SER-0006": { # Dengue NS1 Antigen
        "method": "Rapid Immunochromatography / ELISA",
        "qualitative": "Negative",
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "SER-0007": { # Dengue IgM / IgG
        "method": "Rapid Immunochromatography / ELISA",
        "qualitative": "Negative",
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "SER-0008": { # CRP (Quantitative)
        "method": "Immunoturbidimetry / Latex Enhanced",
        "ranges": [{"gender": "All", "min": 0.0, "max": 6.0, "text": "< 6.0 mg/L"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "SER-0009": { # Rheumatoid Factor (RF)
        "method": "Latex Agglutination / Immunoturbidimetry",
        "ranges": [{"gender": "All", "min": 0.0, "max": 20.0, "text": "< 20.0 IU/mL (Negative)"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "SER-0010": { # ASO Titre
        "method": "Latex Agglutination / Immunoturbidimetry",
        "ranges": [{"gender": "All", "min": 0.0, "max": 200.0, "text": "< 200 IU/mL"}],
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },

    # --- Clinical Pathology (Urine & Stool) ---
    "CLP-0001": { # Urine RE/ME
        "method": "Automated Reflectance Photometry & Brightfield Microscopy",
        "qualitative": "Normal / Clear",
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "CLP-0021": { # Stool RE/ME
        "method": "Macroscopy & Wet Mount Microscopy (Saline/Iodine)",
        "qualitative": "Normal / No parasite seen",
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    },
    "CLP-0038": { # Semen Analysis
        "method": "Manual Microscopy (WHO 6th Edition)",
        "qualitative": "Normozoospermia (WHO 2021 Reference Criteria)",
        "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
    }
}

def get_preset_for_test(row):
    code = row["Test Code"].strip()
    dtype = row["Report Data Type"].strip()
    name = row["Test Name"].strip()
    unit = row["Unit"].strip()
    method_raw = row["Method / Platform"].strip()
    dept = row["Department"].strip()

    if code in CLINICAL_PRESETS:
        res = CLINICAL_PRESETS[code].copy()
        if "method" not in res:
            res["method"] = method_raw if method_raw and method_raw not in ["CONFIGURE PER LAB POLICY", "VALIDATE PER METHOD/AGE/SEX"] else "Standard Clinical Method"
        return res

    # Determine method
    if method_raw and method_raw not in ["CONFIGURE PER LAB POLICY", "VALIDATE PER METHOD/AGE/SEX", "Analyzer", "Calculated/Analyzer", "Manual", "Specialized"]:
        method = method_raw
    else:
        if dept in ["Clinical Biochemistry", "Special Chemistry"]:
            method = "Spectrophotometry / Enzymatic Colorimetric"
        elif dept in ["Endocrinology", "Tumor Markers", "Immunology"]:
            method = "Chemiluminescent Immunoassay (CLIA)"
        elif dept in ["Hematology", "Coagulation"]:
            method = "Automated Optical / Impedance / Coagulation Analyzer"
        elif dept == "Serology / Infectious Disease":
            method = "Rapid Immunochromatographic Assay / ELISA"
        elif dept == "Microbiology":
            method = "Aerobic Culture & Identification / Disc Diffusion"
        elif dept in ["Histopathology", "Cytology"]:
            method = "H&E / Papanicolaou Stain & Light Microscopy"
        elif dept in ["Molecular Diagnostics", "Genetics / Cytogenetics"]:
            method = "Real-Time PCR / Molecular Hybridization"
        elif dept == "Toxicology / TDM":
            method = "Homogeneous Enzyme Immunoassay / LC-MS"
        elif dept == "Clinical Pathology":
            method = "Reflectance Photometry & Brightfield Microscopy"
        elif dept == "Point of Care / Blood Gas":
            method = "Direct Blood Gas & Electrolyte Potentiometry"
        elif dept == "Allergy":
            method = "FEIA / Immunoblotting Specific IgE"
        else:
            method = "Standard Laboratory Analytical Method"

    # Determine qualitative vs numeric vs calculated
    if dtype in ["Qualitative", "PositiveNegative", "ReactiveNonReactive", "DetectedNotDetected", "Categorical"]:
        if "Positive" in dtype or "Negative" in dtype:
            qual = "Negative"
        elif "Reactive" in dtype:
            qual = "Non-Reactive"
        elif "Detected" in dtype:
            qual = "Not Detected"
        else:
            qual = "Negative / Normal"
        return {
            "method": method,
            "qualitative": qual,
            "ranges": [],
            "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
        }
    elif dtype in ["PathologyNarrative", "Descriptive", "Microscopic", "CultureAST"]:
        return {
            "method": method,
            "qualitative": "Descriptive / Structured Narrative Report",
            "ranges": [],
            "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
        }
    elif dtype == "Calculated":
        return {
            "method": "Governed Mathematical Calculation",
            "ranges": [{"gender": "All", "min": None, "max": None, "text": "Clinical interpretation per calculated index"}],
            "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
        }
    elif dtype == "Panel":
        return {
            "method": method,
            "ranges": [],
            "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
        }
    else:
        # Default Numeric Range
        return {
            "method": method,
            "ranges": [{"gender": "All", "min": None, "max": None, "text": f"Standard adult reference interval ({unit})" if unit else "Standard adult reference interval"}],
            "crit_policy": "CRITICAL_LIMIT_REQUIRES_LAB_POLICY"
        }

def sql_quote(val):
    if val is None:
        return "NULL"
    val_str = str(val).replace("'", "''")
    return f"'{val_str}'"

# Generate SQL Statements
sql_statements = []

sql_statements.append("""-- Migration 00103: Standard Clinical Presets Library for 1,122 Tests
--
-- Clinical Safety Governance:
-- 1. Populates Standard Clinical Presets for all 1,122 canonical tests.
-- 2. Preserves clinical safety: validation_status = 'REQUIRES_VALIDATION', is_active = FALSE, billing_enabled = FALSE, clinical_reporting_enabled = FALSE.
-- 3. Analyzer and Reagent fields are intentionally left NULL (to be configured with actual physical laboratory instruments).
-- 4. Governed Bulk Action: 'Adopt Standard Presets' allows authorized lab director to adopt presets without auto-activation.
-- 5. Full audit history and version governance.

BEGIN;

-- 1. Configuration Source Classification on tests and lab approvals
ALTER TABLE public.tests
  ADD COLUMN IF NOT EXISTS configuration_source TEXT DEFAULT 'STANDARD_PRESET'
  CHECK (configuration_source IN ('STANDARD_PRESET', 'LAB_CUSTOM', 'MANUFACTURER_KIT', 'LAB_VERIFIED'));

ALTER TABLE public.catalogue_lab_approvals
  ADD COLUMN IF NOT EXISTS configuration_source TEXT DEFAULT 'STANDARD_PRESET'
  CHECK (configuration_source IN ('STANDARD_PRESET', 'LAB_CUSTOM', 'MANUFACTURER_KIT', 'LAB_VERIFIED'));

-- 2. Master Table for Catalogue Standard Presets Library
CREATE TABLE IF NOT EXISTS public.catalogue_standard_presets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  test_code TEXT NOT NULL UNIQUE,
  test_name TEXT NOT NULL,
  department TEXT NOT NULL,
  report_data_type TEXT NOT NULL,
  specimen TEXT NOT NULL,
  container TEXT NOT NULL,
  method TEXT NOT NULL,
  unit TEXT,
  tat_hours INT NOT NULL DEFAULT 24,
  qualitative_interpretation TEXT,
  calculation_formula TEXT,
  critical_limits_policy TEXT NOT NULL DEFAULT 'CRITICAL_LIMIT_REQUIRES_LAB_POLICY',
  reference_ranges JSONB NOT NULL DEFAULT '[]'::jsonb,
  critical_limits JSONB NOT NULL DEFAULT '[]'::jsonb,
  version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_catalogue_standard_presets_code ON public.catalogue_standard_presets(test_code);
CREATE INDEX IF NOT EXISTS idx_catalogue_standard_presets_dept ON public.catalogue_standard_presets(department);

ALTER TABLE public.catalogue_standard_presets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS catalogue_standard_presets_select ON public.catalogue_standard_presets;
CREATE POLICY catalogue_standard_presets_select ON public.catalogue_standard_presets
  FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS catalogue_standard_presets_manage ON public.catalogue_standard_presets;
CREATE POLICY catalogue_standard_presets_manage ON public.catalogue_standard_presets
  FOR ALL TO authenticated
  USING (public.has_permission('can_manage_catalogue'))
  WITH CHECK (public.has_permission('can_manage_catalogue'));
""")

# Seed Presets Table
preset_inserts = []
test_updates = []

preset_tests_count = 0
numeric_ranges_count = 0
qualitative_presets_count = 0
calculated_tests_count = 0
critical_limits_populated_count = 0
critical_limits_requiring_policy_count = 0

for r in rows:
    code = r["Test Code"].strip()
    name = r["Test Name"].strip()
    dept = r["Department"].strip()
    dtype = r["Report Data Type"].strip()
    specimen = r["Specimen"].strip() or "Standard Specimen"
    container = r["Container"].strip() or "Standard Container"
    unit = r["Unit"].strip() if r["Unit"].strip() and r["Unit"].strip() != "Panel" else None
    tat_raw = r["TAT"].strip()
    tat_hours = 24 if tat_raw == "Routine" else (48 if tat_raw == "Specialized" else 72)

    preset = get_preset_for_test(r)
    method = preset["method"]
    qual = preset.get("qualitative")
    ranges = preset.get("ranges", [])
    crit_policy = preset.get("crit_policy", "CRITICAL_LIMIT_REQUIRES_LAB_POLICY")
    formula = preset.get("formula")

    # Counts
    preset_tests_count += 1
    if dtype in ["Qualitative", "PositiveNegative", "ReactiveNonReactive", "DetectedNotDetected", "Categorical", "PathologyNarrative", "Descriptive", "Microscopic", "CultureAST"]:
        qualitative_presets_count += 1
    elif dtype == "Calculated":
        calculated_tests_count += 1
    elif dtype == "Numeric":
        numeric_ranges_count += len(ranges)

    has_crit = False
    for rg in ranges:
        if rg.get("crit_low") is not None or rg.get("crit_high") is not None:
            has_crit = True
            critical_limits_populated_count += 1
    if not has_crit:
        critical_limits_requiring_policy_count += 1

    ranges_json = json.dumps(ranges)
    crit_json = json.dumps([{"crit_low": rg.get("crit_low"), "crit_high": rg.get("crit_high")} for rg in ranges if rg.get("crit_low") is not None or rg.get("crit_high") is not None])

    preset_inserts.append(f"""INSERT INTO public.catalogue_standard_presets (
  test_code, test_name, department, report_data_type, specimen, container, method, unit, tat_hours,
  qualitative_interpretation, calculation_formula, critical_limits_policy, reference_ranges, critical_limits
) VALUES (
  {sql_quote(code)}, {sql_quote(name)}, {sql_quote(dept)}, {sql_quote(dtype)}, {sql_quote(specimen)}, {sql_quote(container)}, {sql_quote(method)}, {sql_quote(unit)}, {tat_hours},
  {sql_quote(qual)}, {sql_quote(formula)}, {sql_quote(crit_policy)}, '{ranges_json}'::jsonb, '{crit_json}'::jsonb
) ON CONFLICT (test_code) DO UPDATE SET
  test_name = EXCLUDED.test_name,
  department = EXCLUDED.department,
  report_data_type = EXCLUDED.report_data_type,
  specimen = EXCLUDED.specimen,
  container = EXCLUDED.container,
  method = EXCLUDED.method,
  unit = EXCLUDED.unit,
  tat_hours = EXCLUDED.tat_hours,
  qualitative_interpretation = EXCLUDED.qualitative_interpretation,
  calculation_formula = EXCLUDED.calculation_formula,
  critical_limits_policy = EXCLUDED.critical_limits_policy,
  reference_ranges = EXCLUDED.reference_ranges,
  critical_limits = EXCLUDED.critical_limits;""")

    # Update public.tests with standardized preset data, but fail-closed unvalidated & inactive
    test_updates.append(f"""UPDATE public.tests
SET sample_type = {sql_quote(specimen)},
    container = {sql_quote(container)},
    method = {sql_quote(method)},
    tat_hours = {tat_hours},
    configuration_source = 'STANDARD_PRESET',
    validation_status = 'REQUIRES_VALIDATION',
    clinical_configuration_status = 'Requires Clinical Validation',
    lifecycle_status = 'Draft',
    is_active = FALSE,
    billing_enabled = FALSE,
    clinical_reporting_enabled = FALSE,
    updated_at = NOW()
WHERE code = {sql_quote(code)};""")

sql_statements.append("\n".join(preset_inserts))
sql_statements.append("\n".join(test_updates))

# RPCs for standard preset adoption & enhanced governance summary
sql_statements.append("""
-- 3. Governed Bulk Action: Adopt Standard Presets
CREATE OR REPLACE FUNCTION public.catalogue_adopt_standard_presets(
  p_test_ids UUID[],
  p_approval_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  actor_id UUID;
  actor_name TEXT;
  t RECORD;
  preset RECORD;
  p_param RECORD;
  adopted_count INT := 0;
  adopted_codes TEXT[] := ARRAY[]::TEXT[];
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  IF cardinality(p_test_ids) = 0 THEN
    RAISE EXCEPTION 'No tests selected for standard preset adoption.' USING ERRCODE='23514';
  END IF;

  FOR t IN SELECT * FROM public.tests WHERE id = ANY(p_test_ids) FOR UPDATE LOOP
    SELECT * INTO preset FROM public.catalogue_standard_presets WHERE test_code = t.code;

    -- Update Test to VALIDATED (Lab Approved) but keep INACTIVE until explicit separate activation
    UPDATE public.tests
    SET validation_status = 'VALIDATED',
        configuration_source = 'STANDARD_PRESET',
        clinical_configuration_status = 'Configured',
        lifecycle_status = 'Draft',
        is_active = FALSE,
        billing_enabled = FALSE,
        clinical_reporting_enabled = FALSE,
        method = COALESCE(preset.method, method),
        sample_type = COALESCE(preset.specimen, sample_type),
        container = COALESCE(preset.container, container),
        tat_hours = COALESCE(preset.tat_hours, tat_hours),
        updated_at = NOW()
    WHERE id = t.id;

    -- Insert Formal Clinical Approval Audit Record
    INSERT INTO public.catalogue_lab_approvals (
      test_id,
      approved_by,
      approved_by_name,
      approved_at,
      analyzer_model,
      reagent_manufacturer,
      method,
      reference_range_source,
      critical_limit_source,
      effective_from,
      approval_notes,
      approval_status,
      configuration_source
    ) VALUES (
      t.id,
      actor_id,
      actor_name,
      NOW(),
      NULL, -- Unresolved analyzer (intentionally NULL until physical device confirmed)
      NULL, -- Unresolved reagent (intentionally NULL until manufacturer confirmed)
      COALESCE(preset.method, t.method, 'Standard Clinical Method'),
      'Standard Clinical Presets Library v1.0',
      COALESCE(preset.critical_limits_policy, 'Standard Clinical Presets Policy'),
      CURRENT_DATE,
      COALESCE(p_approval_notes, 'Bulk adoption of Standard Clinical Presets. Laboratory responsibility assumed by authorized director.'),
      'APPROVED',
      'STANDARD_PRESET'
    );

    adopted_count := adopted_count + 1;
    adopted_codes := array_append(adopted_codes, t.code);
  END LOOP;

  RETURN jsonb_build_object(
    'success', TRUE,
    'adopted_count', adopted_count,
    'adopted_codes', adopted_codes,
    'validation_status', 'VALIDATED',
    'is_active', FALSE,
    'message', 'Standard presets adopted successfully. Tests are now VALIDATED and require separate explicit activation.'
  );
END $$;

-- 4. Governed Governance Dashboard Summary Counters
CREATE OR REPLACE FUNCTION public.catalogue_get_governance_summary()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  res JSONB;
BEGIN
  SELECT json_build_object(
    'total_tests', (SELECT count(*)::int FROM public.tests),
    'requires_validation_tests', (SELECT count(*)::int FROM public.tests WHERE validation_status = 'REQUIRES_VALIDATION'),
    'ready_for_approval_tests', (
      SELECT count(*)::int
      FROM public.tests t
      WHERE t.validation_status = 'REQUIRES_VALIDATION'
        AND (public.catalogue_check_test_readiness(t.id)->>'ready_for_approval')::boolean = TRUE
    ),
    'validated_tests', (SELECT count(*)::int FROM public.tests WHERE validation_status = 'VALIDATED'),
    'active_tests', (SELECT count(*)::int FROM public.tests WHERE is_active = TRUE),
    'inactive_tests', (SELECT count(*)::int FROM public.tests WHERE is_active = FALSE),
    'standard_presets_available', (SELECT count(*)::int FROM public.catalogue_standard_presets),
    'standard_presets_adopted', (SELECT count(*)::int FROM public.tests WHERE configuration_source = 'STANDARD_PRESET' AND validation_status = 'VALIDATED'),
    'lab_custom_configurations', (SELECT count(*)::int FROM public.tests WHERE configuration_source = 'LAB_CUSTOM'),
    'missing_analyzer', (
      SELECT count(*)::int FROM public.tests t
      WHERE t.reporting_type <> 'NoReporting'
        AND NOT EXISTS (SELECT 1 FROM public.catalogue_lab_approvals a WHERE a.test_id = t.id AND a.approval_status = 'APPROVED' AND a.analyzer_model IS NOT NULL AND btrim(a.analyzer_model) <> '')
    ),
    'missing_reagent', (
      SELECT count(*)::int FROM public.tests t
      WHERE t.reporting_type <> 'NoReporting'
        AND NOT EXISTS (SELECT 1 FROM public.catalogue_lab_approvals a WHERE a.test_id = t.id AND a.approval_status = 'APPROVED' AND a.reagent_manufacturer IS NOT NULL AND btrim(a.reagent_manufacturer) <> '')
    ),
    'critical_limits_populated', (SELECT count(*)::int FROM public.catalogue_standard_presets WHERE jsonb_array_length(critical_limits) > 0),
    'critical_limits_requiring_policy', (SELECT count(*)::int FROM public.catalogue_standard_presets WHERE jsonb_array_length(critical_limits) = 0),
    'missing_configuration_tests', (SELECT count(*)::int FROM public.tests WHERE btrim(COALESCE(sample_type, '')) = '' OR btrim(COALESCE(container, '')) = ''),
    'missing_pricing_tests', (SELECT count(*)::int FROM public.tests WHERE (price_paisa IS NULL OR price_paisa = 0) AND NOT allow_zero_price_billing),
    'missing_method_tests', (SELECT count(*)::int FROM public.tests WHERE btrim(COALESCE(method, '')) = '' AND reporting_type <> 'NoReporting'),
    'missing_range_tests', (SELECT count(*)::int FROM public.tests t WHERE t.reporting_type <> 'NoReporting' AND NOT EXISTS(
      SELECT 1 FROM public.parameters p JOIN public.reference_ranges r ON r.parameter_id = p.id WHERE p.test_id = t.id AND r.is_active
    )),
    'rejected_or_correction_tests', (SELECT count(*)::int FROM public.catalogue_lab_approvals WHERE approval_status = 'REVOKED')
  ) INTO res;

  RETURN res;
END $$;

REVOKE ALL ON FUNCTION public.catalogue_adopt_standard_presets(UUID[], TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_adopt_standard_presets(UUID[], TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_get_governance_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_get_governance_summary() TO authenticated;

COMMIT;
""")

full_sql = "\n\n".join(sql_statements)

with open(SQL_OUT, "w", encoding="utf-8") as f:
    f.write(full_sql)

print(f"Successfully generated migration: {SQL_OUT}")
print(f"Stats:")
print(f"  - Total Presets: {preset_tests_count}")
print(f"  - Numeric Ranges Populated: {numeric_ranges_count}")
print(f"  - Qualitative Presets: {qualitative_presets_count}")
print(f"  - Calculated Tests: {calculated_tests_count}")
print(f"  - Critical Limits Populated: {critical_limits_populated_count}")
print(f"  - Critical Limits Requiring Policy: {critical_limits_requiring_policy_count}")
