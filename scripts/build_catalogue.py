import os
import csv
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_PATH = os.path.join(ROOT, "approved-data", "Bimal_Pathology_Master_Test_Catalogue_1122.csv")
SQL_PATH = os.path.join(ROOT, "supabase", "migrations", "00098_master_catalogue_1122_rebuild_and_convergence.sql")

def run():
    print("Writing master catalogue data...")

if __name__ == "__main__":
    run()
