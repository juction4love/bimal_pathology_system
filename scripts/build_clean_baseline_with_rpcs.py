"""
Builds the complete single authoritative baseline migration:
supabase/migrations/00001_bimal_pathology_clean_baseline.sql
combining:
1. Extensions
2. Enums / Domains
3. Public tables (Core, Catalogue, Transactions, AST, Storage, Audit, SMS, HMIS)
4. Indexes & Constraints
5. Helper functions & Security Definer RBAC functions
6. Business RPCs & Domain Functions (Accession, Billing, Worklist, Result Entry, Verification, Signoff, Public QR, AST, SMS, Catalogue, HMIS)
7. Triggers
8. RLS Policies & Grants
9. Storage buckets & policies
10. Master Data (Tests, Categories, Parameters, Reference Ranges, Panel Components, Analyzers, Mappings, Rate Versions)
"""

import os
import re
import glob

LEGACY_DIR = 'supabase/migrations_legacy_archive'
CURRENT_BASELINE = 'supabase/migrations/00001_bimal_pathology_clean_baseline.sql'

def read_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()

def write_file(path, content):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

print("Reading baseline and legacy migrations...")
baseline_content = read_file(CURRENT_BASELINE)

# Extract functions from legacy archive
legacy_files = sorted(glob.glob(os.path.join(LEGACY_DIR, '*.sql')))
print(f"Found {len(legacy_files)} legacy migration files.")

# We want all functions from legacy migrations
# Let's parse function blocks
function_blocks = {}
grant_blocks = []

for file in legacy_files:
    content = read_file(file)
    
    # Extract CREATE OR REPLACE FUNCTION blocks
    # Using regex to find CREATE [OR REPLACE] FUNCTION ... $$ LANGUAGE ...;
    # Or $$ ... $$;
    matches = re.finditer(
        r'(CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-zA-Z0-9_]+)\s*\([^)]*?\)\s*RETURNS[\s\S]*?(?:AS\s*\$\$[\s\S]*?\$\$|\$func\$[\s\S]*?\$func\$|\$body\$[\s\S]*?\$body\$)[\s\S]*?;)',
        content,
        re.IGNORECASE
    )
    for m in matches:
        full_sql = m.group(1)
        func_name = m.group(2)
        function_blocks[func_name] = {
            'file': os.path.basename(file),
            'name': func_name,
            'sql': full_sql
        }

print(f"Total unique functions extracted across archive: {len(function_blocks)}")
