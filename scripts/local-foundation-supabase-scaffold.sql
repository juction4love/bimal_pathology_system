-- Local PostgreSQL-only acceptance scaffold for Supabase-owned primitives.
-- Never deploy this file. Supabase owns these roles, schemas and tables.
DO $$ BEGIN
  CREATE ROLE anon NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE ROLE authenticated NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE ROLE service_role NOLOGIN BYPASSRLS;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- Supabase installs pgcrypto objects in the extensions schema. Native Windows
-- PostgreSQL installs them in public by default, so expose the compatible name.
CREATE OR REPLACE FUNCTION extensions.gen_random_bytes(integer)
RETURNS bytea LANGUAGE sql VOLATILE PARALLEL SAFE
AS 'SELECT public.gen_random_bytes($1)';
CREATE OR REPLACE FUNCTION extensions.digest(bytea,text)
RETURNS bytea LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS 'SELECT public.digest($1,$2)';
CREATE OR REPLACE FUNCTION extensions.digest(text,text)
RETURNS bytea LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS 'SELECT public.digest($1,$2)';

CREATE TABLE IF NOT EXISTS auth.users (
  id UUID PRIMARY KEY,
  email TEXT,
  phone TEXT,
  phone_confirmed_at TIMESTAMPTZ,
  raw_app_meta_data JSONB NOT NULL DEFAULT '{}'::JSONB,
  raw_user_meta_data JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS JSONB
LANGUAGE sql STABLE AS $
  SELECT jsonb_build_object(
    'sub', current_setting('request.jwt.claim.sub', true),
    'phone', current_setting('request.jwt.claim.phone', true),
    'email', current_setting('request.jwt.claim.email', true),
    'role', current_setting('role', true)
  );
$;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', TRUE), '')::UUID
$$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.role', TRUE), '')
$$;

CREATE TABLE IF NOT EXISTS storage.buckets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  public BOOLEAN NOT NULL DEFAULT FALSE,
  file_size_limit BIGINT,
  allowed_mime_types TEXT[]
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id TEXT NOT NULL REFERENCES storage.buckets(id),
  name TEXT NOT NULL,
  owner UUID,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA auth, storage TO anon, authenticated, service_role;
GRANT SELECT ON auth.users TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.buckets, storage.objects TO service_role;
