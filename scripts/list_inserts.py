import re

content = open('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'r', encoding='utf-8').read()

# Let's find all INSERT statements
inserts = list(re.finditer(r'INSERT INTO public\.([a-zA-Z0-9_]+)', content))
print(f"Found {len(inserts)} INSERT statements in baseline SQL:")
for i, m in enumerate(inserts):
    print(f"{i+1}: INSERT INTO public.{m.group(1)} at index {m.start()}")
