import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_PATH = os.path.join(ROOT, "approved-data", "Bimal_Pathology_Master_Test_Catalogue_1122.csv")

# Section 2: Coagulation (COA-0001 to COA-0030)
coa_rows = """COA-0001,Coagulation,Hemostasis,Prothrombin Time (PT),,Single,Citrated Plasma,Sodium Citrate (Blue),Clot-based,sec,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0002,Coagulation,Hemostasis,INR,,Single,Citrated Plasma,Sodium Citrate (Blue),Calculated from PT,ratio,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0003,Coagulation,Hemostasis,Activated Partial Thromboplastin Time (APTT),,Single,Citrated Plasma,Sodium Citrate (Blue),Clot-based,sec,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0004,Coagulation,Hemostasis,Thrombin Time (TT),,Single,Citrated Plasma,Sodium Citrate (Blue),Clot-based,sec,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0005,Coagulation,Hemostasis,Fibrinogen (Clauss),,Single,Citrated Plasma,Sodium Citrate (Blue),Clauss,mg/dL,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0006,Coagulation,Hemostasis,D-Dimer,,Single,Citrated Plasma,Sodium Citrate (Blue),Immunoturbidimetry/Immunoassay,ng/mL FEU,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0007,Coagulation,Hemostasis,Bleeding Time,,Single,Capillary Blood,None,Ivy/Duke (legacy),min,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0008,Coagulation,Hemostasis,Clotting Time,,Single,Whole Blood,Plain tube,Lee-White (legacy),min,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0009,Coagulation,Hemostasis,Factor VIII Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),One-stage clot assay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0010,Coagulation,Hemostasis,Factor IX Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),One-stage clot assay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0011,Coagulation,Hemostasis,Factor XI Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),Clot assay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0012,Coagulation,Hemostasis,Factor XII Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),Clot assay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0013,Coagulation,Hemostasis,Factor VII Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),Clot assay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0014,Coagulation,Hemostasis,Factor V Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),Clot assay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0015,Coagulation,Hemostasis,Factor X Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),Clot assay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0016,Coagulation,Hemostasis,Factor XIII Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),Functional assay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0017,Coagulation,Hemostasis,Von Willebrand Factor Antigen,,Single,Citrated Plasma,Sodium Citrate (Blue),Immunoassay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0018,Coagulation,Hemostasis,Von Willebrand Factor Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),Activity assay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0019,Coagulation,Hemostasis,Protein C Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),Chromogenic/Clot assay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0020,Coagulation,Hemostasis,Protein S Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),Clot/Immunoassay,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0021,Coagulation,Hemostasis,Antithrombin III Activity,,Single,Citrated Plasma,Sodium Citrate (Blue),Chromogenic,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0022,Coagulation,Hemostasis,Lupus Anticoagulant Screen,,Single,Citrated Plasma,Sodium Citrate (Blue),dRVVT/LA-sensitive APTT,ratio,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0023,Coagulation,Hemostasis,dRVVT Screen,,Single,Citrated Plasma,Sodium Citrate (Blue),dRVVT,ratio,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0024,Coagulation,Hemostasis,dRVVT Confirm,,Single,Citrated Plasma,Sodium Citrate (Blue),dRVVT,ratio,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0025,Coagulation,Hemostasis,Mixing Study PT,,Single,Citrated Plasma,Sodium Citrate (Blue),Mixing study,Interpretive,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0026,Coagulation,Hemostasis,Mixing Study APTT,,Single,Citrated Plasma,Sodium Citrate (Blue),Mixing study,Interpretive,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0027,Coagulation,Hemostasis,Anti-Xa Heparin Assay,,Single,Citrated Plasma,Sodium Citrate (Blue),Chromogenic,IU/mL,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0028,Coagulation,Hemostasis,Fibrin Degradation Products,,Single,Plasma,Citrate,Latex/Immunoassay,µg/mL,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0029,Coagulation,Hemostasis,Platelet Function Screen,,Single,Citrated Whole Blood,Citrate,PFA/aggregation platform,sec,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,
COA-0030,Coagulation,Hemostasis,Platelet Aggregation Studies,,Single,Citrated Platelet Rich Plasma,Citrate,Light transmission aggregometry,%,VALIDATE PER METHOD/AGE/SEX,CONFIGURE PER LAB POLICY,Routine,Numeric,No,No,Yes,,REQUIRES LAB VALIDATION,"""

with open(CSV_PATH, "a", encoding="utf-8") as f:
    f.write(coa_rows.strip() + "\n")
    print("Appended COA section (30 tests).")
