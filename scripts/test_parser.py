import os
import re
import glob

def extract_functions_from_sql(content):
    """
    Robustly extracts all CREATE [OR REPLACE] FUNCTION blocks from SQL content.
    Handles any dollar-quote tag like $$, $func$, $body$, $trg$, etc.
    """
    funcs = {}
    
    # Match the start of a function definition
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
        
        # Now find the dollar quote tag after RETURNS
        # e.g. AS $$ or AS $func$ or AS $body$ or AS $trg$
        tag_match = re.search(r'AS\s+(\$[a-zA-Z0-9_]*\$)', content[match.end():], re.IGNORECASE)
        if not tag_match:
            # might be LANGUAGE sql without AS $$ (e.g. inline) or AS '...'
            # let's look for semicolon
            semi_idx = content.find(';', match.end())
            if semi_idx != -1:
                funcs[func_name] = content[start_idx : semi_idx + 1].strip()
                pos = semi_idx + 1
            else:
                pos = match.end()
            continue
        
        tag = tag_match.group(1)
        body_start = match.end() + tag_match.end()
        # Find the matching closing tag
        body_end = content.find(tag, body_start)
        if body_end == -1:
            pos = match.end()
            continue
        
        # Find the ending semicolon
        semi_idx = content.find(';', body_end + len(tag))
        if semi_idx == -1:
            semi_idx = body_end + len(tag)
        
        full_sql = content[start_idx : semi_idx + 1].strip()
        funcs[func_name] = full_sql
        pos = semi_idx + 1
        
    return funcs

# Test parser on legacy migrations
legacy_files = sorted(glob.glob('supabase/migrations_legacy_archive/*.sql'))
all_funcs = {}
for f in legacy_files:
    c = open(f, 'r', encoding='utf-8').read()
    extracted = extract_functions_from_sql(c)
    for name, sql in extracted.items():
        all_funcs[name] = sql

print(f"Robustly extracted {len(all_funcs)} functions from legacy archive.")
for name in ['catalogue_save_analyzer', 'provision_historical_report_secure_link', 'resolve_public_report_by_token', 'save_test_results', 'create_patient_bill_order_with_packages']:
    if name in all_funcs:
        print(f"  [OK] {name}: length {len(all_funcs[name])}")
        print("  " + all_funcs[name][:120].replace('\n', ' '))
    else:
        print(f"  [FAIL] Missing {name}")
