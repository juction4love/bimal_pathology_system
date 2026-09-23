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

print("Extracting functions from legacy migrations...")
legacy_files = sorted(glob.glob('supabase/migrations_legacy_archive/*.sql'))
all_funcs = {}
for f in legacy_files:
    c = open(f, 'r', encoding='utf-8').read()
    extracted = extract_functions_from_sql(c)
    for name, sql in extracted.items():
        all_funcs[name] = sql

print(f"Extracted {len(all_funcs)} unique functions.")

current_baseline = open('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'r', encoding='utf-8').read()

# Locate seed data
seed_idx = current_baseline.find('INSERT INTO public.analyzers')
if seed_idx == -1:
    seed_idx = current_baseline.find('INSERT INTO public.test_categories')

master_seed = current_baseline[seed_idx:]

# Locate header and base tables (before functions)
func_hdr_idx = current_baseline.find('-- ============================================================================\n-- 5. BUSINESS FUNCTIONS')
if func_hdr_idx != -1:
    header_tables = current_baseline[:func_hdr_idx]
else:
    header_tables = current_baseline[:seed_idx]

# Format all functions
functions_sql = "\n\n-- ============================================================================\n-- 5. BUSINESS FUNCTIONS & APPLICATION RPCS\n-- ============================================================================\n\n"

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

full_sql = f"{header_tables.strip()}\n{functions_sql.strip()}\n\n{master_seed.strip()}"

if not full_sql.startswith('BEGIN;'):
    full_sql = f"BEGIN;\n\n{full_sql}"
if not full_sql.endswith('COMMIT;'):
    full_sql = f"{full_sql}\n\nCOMMIT;\n"

open('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'w', encoding='utf-8').write(full_sql)
print("Saved clean 00001_bimal_pathology_clean_baseline.sql successfully!")
