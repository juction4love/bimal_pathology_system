-- Supabase-managed projects install uuid-ossp in the extensions schema, while
-- migration sessions do not consistently include that schema in search_path.
-- This pre-schema compatibility layer lets the immutable historical 00001
-- migration resolve its original unqualified uuid_generate_v4() defaults.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.uuid_generate_v4()
RETURNS UUID
LANGUAGE sql
VOLATILE
SET search_path = extensions, pg_temp
AS $$ SELECT extensions.uuid_generate_v4() $$;

COMMENT ON FUNCTION public.uuid_generate_v4() IS
    'Compatibility wrapper for historical unqualified UUID defaults on Supabase-managed PostgreSQL.';
