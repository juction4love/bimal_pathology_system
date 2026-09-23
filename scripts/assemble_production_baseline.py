import os
import re
import glob

print("Reading baseline and legacy archive...")

legacy_files = sorted(glob.glob('supabase/migrations_legacy_archive/*.sql'))

# Extract functions in order of appearance (later overwrites earlier)
functions_map = {}
for f in legacy_files:
    content = open(f, 'r', encoding='utf-8').read()
    # Match CREATE OR REPLACE FUNCTION public.func_name(...) ... $$ LANGUAGE ...;
    matches = re.finditer(
        r'(CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-zA-Z0-9_]+)\s*\([^)]*?\)\s*RETURNS[\s\S]*?(?:AS\s*\$\$[\s\S]*?\$\$|\$func\$[\s\S]*?\$func\$|\$body\$[\s\S]*?\$body\$)[\s\S]*?;)',
        content,
        re.IGNORECASE
    )
    for m in matches:
        func_sql = m.group(1)
        func_name = m.group(2)
        functions_map[func_name] = func_sql

print(f"Extracted {len(functions_map)} unique functions from legacy migrations.")

# Read current baseline
current_baseline = open('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8').read()

# Let's see what is inside current baseline
# Master data section starts from INSERT INTO public.analyzers or INSERT INTO public.test_categories
seed_idx = current_baseline.find('INSERT INTO public.analyzers')
if seed_idx == -1:
    seed_idx = current_baseline.find('INSERT INTO public.test_categories')

header_and_tables = current_baseline[:seed_idx]
master_seed = current_baseline[seed_idx:]

print(f"Header & Tables length: {len(header_and_tables)} characters.")
print(f"Master Seed length: {len(master_seed)} characters.")

# Let's format all functions as clean SQL
functions_sql = "\n\n-- ============================================================================\n-- 5. BUSINESS FUNCTIONS & APPLICATION RPCS\n-- ============================================================================\n\n"

# Required list of functions to place in baseline
function_names_ordered = sorted(functions_map.keys())

for name in function_names_ordered:
    func_code = functions_map[name]
    functions_sql += f"{func_code}\n\n"
    # Grant execute to authenticated and anon (if public)
    if 'resolve_public_report' in name or 'get_report_secure_link' in name:
        functions_sql += f"GRANT EXECUTE ON FUNCTION public.{name} TO authenticated, anon, service_role;\n\n"
    else:
        functions_sql += f"GRANT EXECUTE ON FUNCTION public.{name} TO authenticated, service_role;\n\n"

print(f"Assembled functions SQL length: {len(functions_sql)} characters.")
