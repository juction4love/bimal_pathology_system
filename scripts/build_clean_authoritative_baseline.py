"""
Builds the pristine single clean production baseline migration:
supabase/migrations/00001_bimal_pathology_clean_baseline.sql
"""

import os
import re
import glob

def extract_functions_from_sql(content):
    funcs = {}
    pattern = re.compile(
        r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-zA-Z0-9_]+)\s*\(',
        re.IGNORECASE
    )
    pos = 0
    while True:
        match = pattern.search(content, pos)
        if not match:
            break
        
        start_idx = match.start()
        func_name = match.group(1)
        
        tag_match = re.search(r'AS\s+(\$[a-zA-Z0-9_]*\$)', content[match.end():], re.IGNORECASE)
        if not tag_match:
            semi_idx = content.find(';', match.end())
            if semi_idx != -1:
                funcs[func_name] = content[start_idx : semi_idx + 1].strip()
                pos = semi_idx + 1
            else:
                pos = match.end()
            continue
        
        tag = tag_match.group(1)
        body_start = match.end() + tag_match.end()
        body_end = content.find(tag, body_start)
        if body_end == -1:
            pos = match.end()
            continue
        
        semi_idx = content.find(';', body_end + len(tag))
        if semi_idx == -1:
            semi_idx = body_end + len(tag)
        
        full_sql = content[start_idx : semi_idx + 1].strip()
        funcs[func_name] = full_sql
        pos = semi_idx + 1
        
    return funcs

print("Extracting clean functions from legacy migrations...")
legacy_files = sorted(glob.glob('supabase/migrations_legacy_archive/*.sql'))
all_funcs = {}
for f in legacy_files:
    c = open(f, 'r', encoding='utf-8').read()
    extracted = extract_functions_from_sql(c)
    for name, sql in extracted.items():
        all_funcs[name] = sql

print(f"Extracted {len(all_funcs)} clean functions.")

# Read pure master seed block from baseline (index 1492564)
cur = open('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'r', encoding='utf-8').read()
seed_start_idx = cur.find("INSERT INTO public.analyzers (code, name, manufacturer, model")
if seed_start_idx == -1:
    seed_start_idx = cur.find("INSERT INTO public.analyzers")

master_seed_clean = cur[seed_start_idx:].strip()
if 'COMMIT;' in master_seed_clean:
    master_seed_clean = master_seed_clean[:master_seed_clean.rfind('COMMIT;')].strip()

# Read pure tables header from start of baseline up to before any functions
hdr_end = cur.find('-- ============================================================================\n-- 5. BUSINESS FUNCTIONS')
if hdr_end == -1:
    hdr_end = cur.find('CREATE OR REPLACE FUNCTION')

base_tables_clean = cur[:hdr_end].strip()

# Format clean functions SQL
functions_sql = "-- ============================================================================\n-- 5. BUSINESS FUNCTIONS & APPLICATION RPCS\n-- ============================================================================\n\n"

for name in sorted(all_funcs.keys()):
    func_code = all_funcs[name]
    # Ensure public. prefix
    if not re.search(r'FUNCTION\s+public\.', func_code, re.IGNORECASE):
        func_code = re.sub(r'FUNCTION\s+([a-zA-Z0-9_]+)', r'FUNCTION public.\1', func_code, count=1, flags=re.IGNORECASE)
    
    # Harden search_path if not present
    if 'SET search_path' not in func_code and 'LANGUAGE plpgsql' in func_code:
        func_code = func_code.replace('LANGUAGE plpgsql', 'LANGUAGE plpgsql\nSET search_path = public, pg_temp')
    elif 'SET search_path' not in func_code and 'LANGUAGE sql' in func_code:
        func_code = func_code.replace('LANGUAGE sql', 'LANGUAGE sql\nSET search_path = public, pg_temp')
        
    functions_sql += f"{func_code}\n\n"
    if 'resolve_public_report' in name or 'get_report_secure_link' in name:
        functions_sql += f"GRANT EXECUTE ON FUNCTION public.{name} TO authenticated, anon, service_role;\n\n"
    else:
        functions_sql += f"GRANT EXECUTE ON FUNCTION public.{name} TO authenticated, service_role;\n\n"

final_sql = f"{base_tables_clean}\n\n{functions_sql}\n\n-- ============================================================================\n-- 6. MASTER SEED DATA\n-- ============================================================================\n\n{master_seed_clean}\n\nCOMMIT;\n"

if not final_sql.startswith('BEGIN;'):
    final_sql = f"BEGIN;\n\n{final_sql}"

open('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'w', encoding='utf-8').write(final_sql)
print("Successfully written pure clean baseline migration!")
