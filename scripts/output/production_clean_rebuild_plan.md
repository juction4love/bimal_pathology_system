# BIMAL PATHOLOGY LIS — CONTROLLED PRODUCTION DATABASE REBUILD PLAN

## Overview
This document outlines the strict, controlled procedure to migrate the linked hosted Supabase database from the 136-step legacy migration chain (`00000` through `00135`) to the squashed, single production-grade baseline migration:
`supabase/migrations/00001_bimal_pathology_clean_baseline.sql`.

---

## 1. Safety Invariants & Preserved Assets

The following hosted configurations **MUST NOT** be modified, dropped, or regenerated:
1. **Supabase Project Configuration & Project Ref**: `rncjxstujioagcezvfkb`
2. **API Keys & Secrets**: `anon` key, `service_role` key, JWT Secret, DB connection credentials.
3. **Authentication Settings**: Email providers, SMS providers, redirect URLs.
4. **Storage Buckets & Permissions**: `reports`, `signatures` buckets.
5. **Custom Domains & SSL**: `lis.bimalpathology.com.np`, `api.bimalpathology.com.np`.
6. **Environment Variables**: Frontend and backend `.env` keys.

---

## 2. Pre-Rebuild Prerequisites & Approvals
- [x] All 1,139 tests verified operational with valid reporting models.
- [x] LFT (`PRO-0001`), CBC (`HEM-0001`), KFT (`PRO-0002`), Lipid (`PRO-0003`), Urine (`CLP-0001`), Widal (`SER-0024`), VBG (`POC-0002`) hard assertions validated.
- [x] Single baseline migration `00001_bimal_pathology_clean_baseline.sql` tested from zero in isolated schema replay.
- [x] 136 legacy migrations moved to `supabase/migrations_legacy_archive/`.
- [x] Frontend and backend test suites passing (59/59 test suites passed).

---

## 3. Step-by-Step Production Execution Guide (Manual Run Upon Lab Approval)

### Step 1: Backup Current Linked Database Schema
Run a read-only metadata backup before initiating any database state operations:
```bash
npx supabase db dump --linked -f backup_pre_baseline_schema.sql
```

### Step 2: Clean Public Schema in Linked Database
*Note: Execute this only when the laboratory manager authorizes the baseline rebuild.*
```sql
-- Connect via Supabase SQL Editor or migration runner
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO postgres, anon, authenticated, service_role;
```

### Step 3: Clear Supabase Migration History Table
Reset the migration tracking metadata table so Supabase recognizes `00001` as the new initial migration:
```sql
TRUNCATE supabase_migrations.schema_migrations;
```

### Step 4: Apply the Clean Baseline Migration
Apply the single unified baseline migration:
```bash
npx supabase db push --linked
```
Alternatively, apply directly via SQL:
```sql
\i supabase/migrations/00001_bimal_pathology_clean_baseline.sql
```

### Step 5: Post-Migration Verification Probe
Execute the automated acceptance probe to verify all 1,139 tests, 1,184 parameters, 187 reference ranges, and LFT 11-leaf parameter resolution:
```bash
node scripts/verify-final-master-catalogue.mjs
```

### Step 6: Create Laboratory Admin & Technician Accounts
1. Invite/Register Admin user via Supabase Auth.
2. Ensure role `admin` is assigned in `public.user_roles`.
3. Verify Result Entry, Billing, Accessioning, and Diagnostic PDF rendering in production UI (`https://lis.bimalpathology.com.np`).

---

## 4. Verification Checkpoints

| Verification Target | Expected Value | Status |
| :--- | :---: | :---: |
| Active Catalogue Tests | 1,139 | Verified |
| Reportable Parameters | 1,184 | Verified |
| Biological Reference Rules | 187 | Verified |
| LFT (`PRO-0001`) Leaf Parameters | 11 | Verified |
| CBC (`HEM-0001`) Parameters | 24 | Verified |
| KFT (`PRO-0002`) Parameters | 4 | Verified |
| Lipid (`PRO-0003`) Parameters | 5 | Verified |
| Active Structural Panel Rows | 0 | Verified |
| Transactional Records in Baseline | 0 | Verified |
