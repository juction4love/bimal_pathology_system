import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_PATH = os.path.join(ROOT, "approved-data", "Bimal_Pathology_Master_Test_Catalogue_1122.csv")

os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)

header = "Test Code,Department,Subdepartment,Test Name,Synonyms,Test Type,Specimen,Container,Method / Platform,Unit,Reference Range,Critical Limits,TAT,Report Data Type,Fasting Required,Outsource,Active,Price NPR,Validation Status,Notes\n"

with open(CSV_PATH, "w", encoding="utf-8") as f:
    f.write(header)
    print("CSV Header written successfully.")
