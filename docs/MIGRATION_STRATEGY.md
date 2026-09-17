# BIMAL PATHOLOGY & DIAGNOSTIC CENTER
## Supabase Cloud Migration Strategy (Phase 0)

### 1. Zero-Coupling Frozen Boundary Policy

- **Frozen Reference Directory**: `G:\bimal_pathology\bimal_admin_web` is completely frozen.
- **Rules**:
  - No code or schema migration scripts may connect to or touch the frozen project.
  - No legacy SQLite or ASP.NET artifacts are reused.
  - Cloud database is initialized from a clean, modern PostgreSQL schema exclusively in `G:\bimal_pathology_cloud\supabase\migrations\`.

---

### 2. Migration Execution Order

Migrations are versioned sequentially and intended to be applied via Supabase CLI (`supabase db push` / `supabase migration up`) or the Supabase SQL Editor:

1. **`00001_initial_schema.sql`**:
   - Creates extensions (`uuid-ossp`, `pgcrypto`).
   - Creates custom ENUMs.
   - Creates core tables with integer paisa `BIGINT` constraints, snapshots, and foreign key relationships.
2. **`00002_rls_and_permissions.sql`**:
   - Implements `auth.has_permission(text)` and `auth.is_super_admin()`.
   - Enables Row Level Security on all 19 application tables.
   - Applies discrete SELECT, INSERT, UPDATE, DELETE policies.
3. **`00003_seed_catalogue_and_roles.sql`**:
   - Seeds standard roles (`admin`, `pathologist`, `lab_technologist`, `lab_technician`, `reception`, `other_staff`).
   - Populates complete default permission matrix mappings.
   - Seeds standard pathology test catalogue (CBC, LFT, RFT, Lipid, Thyroid ECLIA) with prices in integer paisa.
4. **`00004_atomic_functions_and_triggers.sql`**:
   - Creates sequences for sequential human-readable codes (`BP-YYYY-NNNNN`, `INV-YYYY-NNNNN`, `LAB-YYYY-NNNNN`, `SMP-YYYY-NNNNN`, `RCP-YYYY-NNNNN`).
   - Installs `create_patient_bill_and_order` atomic procedure.

---

### 3. Environment & Secrets Strategy

- **Development**:
  - Client utilizes `.env.local` containing `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
  - `.env.example` committed with placeholders only.
- **Production**:
  - Cloud hosting environment variables (e.g. Vercel, Netlify, Cloudflare Pages) inject Supabase URL and Anon Key.
  - Service Role Key is NEVER exposed in the frontend bundle.
