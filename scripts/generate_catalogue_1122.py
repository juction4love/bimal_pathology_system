# Python script to build the normalized Master Test Catalogue (1,122 test items)
# Emits:
#  1. approved-data/Bimal_Pathology_Master_Test_Catalogue_1122.csv
#  2. supabase/migrations/00098_master_catalogue_1122_rebuild_and_convergence.sql

import os
import csv
import json
import re

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_OUT = os.path.join(ROOT_DIR, "approved-data", "Bimal_Pathology_Master_Test_Catalogue_1122.csv")
SQL_OUT = os.path.join(ROOT_DIR, "supabase", "migrations", "00098_master_catalogue_1122_rebuild_and_convergence.sql")

os.makedirs(os.path.dirname(CSV_OUT), exist_ok=True)
os.makedirs(os.path.dirname(SQL_OUT), exist_ok=True)

print("Starting generation of 1122 Master Catalogue...")
