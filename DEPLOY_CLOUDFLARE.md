# Cloudflare Pages — Deployment Guide
## Bimal Pathology & Diagnostic Center — Cloud LIS
**Target URL:** `https://lis.bimalpathology.com.np`

---

## Prerequisites

| Item | Status |
|------|--------|
| Cloudflare account with `bimalpathology.com.np` zone | Required |
| Supabase project `rncjxstujioagcezvfkb` active | Live |
| Production build passing | `npm run build` |
| Release acceptance evidence | Required; use the sealed release identity |

---

## 0. Database migration gate for the next catalogue release

The verified production baseline is `00075`; the reviewed candidate database
head is `00079`. Migrations `00000` through `00075` are immutable.
The only deployable pending chain is `00076` through `00079`. Cloud-SMS
`00070_cloud_sms_dispatch_coordination.sql` remains under
`supabase/deferred_migrations` and is forbidden from this promotion.

Every production migration command must run through the fail-closed guard. It
prints and validates environment, project ref, current head, target head and
the approved migration checksums before any push:

```powershell
$env:PRODUCTION_ENVIRONMENT = 'production'
$env:PRODUCTION_PROJECT_REF = 'rncjxstujioagcezvfkb'
$env:FOUNDATION_PROJECT_REF = 'rncjxstujioagcezvfkb'
$env:FOUNDATION_SUPABASE_URL = 'https://rncjxstujioagcezvfkb.supabase.co/'
$env:FOUNDATION_TARGET_ENVIRONMENT = 'production-cutover'
$env:FOUNDATION_TARGET_CONFIRMATION = 'I_CONFIRM_FOUNDATION_PRODUCTION_rncjxstujioagcezvfkb'

node scripts/production-foundation-cutover-guard.js
```

The guard aborts unless the remote head is exactly `00075`, the local head is
exactly `00079`, every candidate checksum matches, the dry-run pending set is
exactly `00076` through `00079`, and no deferred cloud-SMS object is deployable. This
document does not authorize `--execute`; production application is a separate
operator-approved change after backup, clean-chain, integrity, and runtime
acceptance gates pass.

---

## 1. Cloudflare Pages — Project Setup

### Option A: Direct Upload (Recommended for first deploy)

```
Cloudflare Dashboard
-> Workers & Pages
-> Create
-> Pages
-> Upload assets

Upload the entire contents of: dist/
```

Treat `dist/` as one indivisible deployment artifact. Never copy `index.html`
and `assets/` separately or upload changed files over the active deployment.
Create a new Cloudflare Pages deployment containing the complete freshly built
`dist/`, verify its preview URL, and only then promote that deployment to
production. This keeps the HTML entry graph and its hashed chunks atomic.

The final build also writes a byte-level identity record to
`artifacts/releases/<release-id>.dist-identity.json`. This record contains
sorted relative paths, per-file SHA-256 values and one aggregate dist-tree
SHA-256; it contains no credentials. Run `npm run release:verify` before and
after preview acceptance. Run `npm run release:preview:verify` to serve the
sealed artifact on loopback, byte-check every local asset and render the login
shell in Chromium while all external requests (including Supabase) are blocked
before dispatch. Both checks must pass without rebuilding or changing `dist/`.

For routine releases, deploy a non-production preview branch first:

```
npx wrangler pages deploy dist --project-name bimal-pathology-lis --branch release-<build-id>
```

Run the artifact audit and real-browser module evaluation against the returned
preview URL. This Direct Upload project has no Wrangler command that promotes
the same preview deployment object to production. After preview acceptance,
do not publish new HTML and new chunk URLs to `main` in one step: custom-domain
propagation can expose the HTML before every new chunk is available.

Use a two-stage production release without rebuilding:

1. Create a temporary bridge artifact containing the complete verified new
   `dist`, but replace its `index.html` with the currently deployed production
   `index.html`. Deploy that bridge to `main`.
2. Poll every new hashed asset URL through the custom domain until each returns
   200, JavaScript MIME, the expected digest, and immutable caching. The old UI
   remains active because the bridge still serves the old entry graph.
3. Deploy the untouched verified final `dist` to `main`. This second upload
   changes HTML only from the browser's perspective; all referenced assets are
   already available at the custom domain.
4. Compare production against preview and test old and fresh tabs. Never rebuild
   between bridge, verification, and final deployment.

Record preview, bridge, and final deployment IDs. A direct one-step `--branch
main` release is prohibited whenever the build introduces any new asset URL.

After upload, proceed to Step 3 (Environment Variables).

### Option B: Git Integration

Do not use Git Integration for the already sealed 1.0.0 cutover because it
would perform another build. It is documented only for a future release process
that creates and accepts its artifact within Cloudflare.

```
Cloudflare Dashboard
-> Workers & Pages
-> Create
-> Pages
-> Connect to Git
-> Select repository: bimal_pathology_cloud
```

**Build configuration:**

| Setting | Value |
|---------|-------|
| Framework preset | None |
| Build command | `npm run build` |
| Build output directory | `dist` |
| Root directory | `/` (repository root) |
| Node.js version | 18 or 20 |

---

## 2. Environment Variables

Set in: `Cloudflare Dashboard -> Pages Project -> Settings -> Environment variables`

Apply to **Production** environment:

| Variable | Value |
|----------|-------|
| `VITE_SUPABASE_URL` | `https://rncjxstujioagcezvfkb.supabase.co` |
| `VITE_SUPABASE_ANON_KEY` | `sb_publishable_bP8Ts6veu2lc--86flqL5w_pYaJatuR` |
| `VITE_PUBLIC_APP_URL` | `https://lis.bimalpathology.com.np` |

IMPORTANT: These are the ONLY Vite-prefixed variables.
SUPABASE_SERVICE_ROLE_KEY and SPARROW_SMS_TOKEN must NEVER appear here --
they live only in Supabase Edge Function secrets.

CAUTION: VITE_SUPABASE_ANON_KEY is the publishable (sb_publishable_...) key.
This is safe to expose in frontend bundles. Verify it is NOT the service_role
key before setting.

---

## 3. SPA Routing -- _redirects

`public/_redirects` contains an explicit allowlist of application routes, and
`public/404.html` disables Pages' implicit catch-all SPA behavior. Never use
`/* /index.html 200`: a missing `/assets/*.js` request would otherwise receive
`200 text/html` and inherit the one-year immutable asset cache policy. A browser
can then retain HTML under a JavaScript URL and fail every dynamic import.

The JavaScript filename namespace is derived from the package release version
(for example, version `1.0.0` uses `r1_0_0`) while Rollup content hashes remain
the byte-level cache identity. Bump the package version only for a new release;
never rebuild an already sealed release ID. Never reuse or remove the explicit
404/allowlisted-route protection.

**Routes that must work after hard refresh:**
- `/`                    -> Dashboard (redirects to /login if unauthenticated)
- `/login`
- `/dashboard`
- `/billing/new`
- `/billing`
- `/patients`
- `/samples`
- `/worklist`
- `/worklist/entry/:id`
- `/reports`
- `/catalogue`
- `/personnel/doctors`
- `/personnel/reporting`
- `/admin/users`
- `/admin/roles`
- `/admin/audit`
- `/settings`
- `/r/:token`            -> Public patient report (no login required)

---

## 4. Custom Domain

```
Cloudflare Dashboard
-> Workers & Pages
-> [Your Pages project]
-> Custom domains
-> Add custom domain
-> Enter: lis.bimalpathology.com.np
-> Activate domain
```

Cloudflare will automatically create a CNAME DNS record:

```
Type   Name                       Content
CNAME  lis.bimalpathology.com.np  <pages-project>.pages.dev
```

NOTE: This only creates the `lis` subdomain record. It does NOT touch `www`,
`@` (root), or any other existing DNS records for `bimalpathology.com.np`.

SSL/TLS is provisioned automatically by Cloudflare (Universal SSL).
No certificate management required.

---

## 5. Supabase Auth -- Required URL Configuration

IMPORTANT: Must be done before the first production login attempt.

In Supabase Dashboard -> Authentication -> URL Configuration:

### Site URL
```
https://lis.bimalpathology.com.np
```

### Redirect URLs (Allowed)
```
https://lis.bimalpathology.com.np/**
http://localhost:5173/**
```

These control where Supabase redirects after email confirmation and OAuth flows.

WARNING: If Site URL is still set to http://localhost:5173, password reset
emails will redirect users to localhost. Update this before going live.

---

## 6. Supabase Edge Functions -- CORS

### `public-report` (patient-facing)
Restricted to explicit origins:
```typescript
const ALLOWED_ORIGINS = [
  'https://lis.bimalpathology.com.np',  // production
  'http://localhost:5173',               // local dev
  'http://localhost:4173',               // vite preview
];
```
Dynamic CORS: responds with the exact requesting origin if it matches,
falls back to production domain otherwise. Includes Vary: Origin header.

### `dispatch-sms` (server-side only)
Retains * CORS -- this function is invoked by pg_cron / Supabase Webhooks
(server-to-server), never directly by a browser. Wildcard is harmless here.

### Deploying Edge Functions
```bash
# Install Supabase CLI if not already installed
npm install -g supabase

# Deploy public-report function
supabase functions deploy public-report --project-ref rncjxstujioagcezvfkb

# Deploy dispatch-sms function
supabase functions deploy dispatch-sms --project-ref rncjxstujioagcezvfkb
```

Edge Function secrets (set once, never in frontend):
```bash
supabase secrets set SPARROW_SMS_TOKEN=your-real-token --project-ref rncjxstujioagcezvfkb
supabase secrets set SPARROW_SMS_FROM=TheAlert --project-ref rncjxstujioagcezvfkb
```

---

## 7. Security Checklist

| Check | Result |
|-------|--------|
| `service_role` key in `src/` | CLEAN -- not found |
| `sb_secret` key in `src/` | CLEAN -- not found |
| Known administrator test-password marker in `src/` | CLEAN -- not found |
| Known technician test-password marker in `src/` | CLEAN -- not found |
| `localhost` hardcoded in `src/` | CLEAN -- not found |
| `.env.local` in `.gitignore` | Covered by `*.local` rule |
| `dist/` in `.gitignore` | Present |
| `diagnostic-reports` bucket public | Private (RLS enforced) |
| Mock authentication bypass | None -- Supabase RLS authoritative |
| Supabase anon key in bundle | Expected -- it is a publishable key |
| `public-report` CORS restricted | FIXED -- explicit origin list |
| `dispatch-sms` browser-callable | No -- server-to-server only |

---

## 8. Build Output

```
dist/index.html                   0.47 kB  (gzip: 0.30 kB)
dist/assets/index-*.css           0.79 kB  (gzip: 0.48 kB)
dist/assets/index-*.js        1,094 kB     (gzip: 310 kB)
dist/_redirects                   1 line   SPA catch-all
dist/_headers                     cache policy for HTML and hashed chunks
dist/assets/pathology-logo.png    1.2 MB   (logo asset)
dist/favicon.svg                  copied
```

The JS bundle is large (~1 MB raw / 310 KB gzip) due to MUI.
Cloudflare's CDN edge caching makes this acceptable for a private LIS tool.
Route-based code splitting is active. `index.html` is explicitly served with
`no-cache, no-store`; Cloudflare Pages serves SPA fallback responses with its
default `max-age=0, must-revalidate`; hashed `/assets/*` files are immutable for one year.
The service worker is also `no-cache`. A retained tab that requests a removed
chunk performs at most one automatic refresh per route; a repeated mismatch
shows “New version available — Refresh” without entering a reload loop.

---

## 9. Post-Deployment Acceptance Tests

Run these after DNS propagates (allow 5-10 minutes):

```
[ ] https://lis.bimalpathology.com.np/          -> loads app, redirects to /login
[ ] https://lis.bimalpathology.com.np/login     -> Supabase login form
[ ] Hard refresh /billing/new                   -> no 404 (SPA routing works)
[ ] Hard refresh /worklist                      -> no 404
[ ] Hard refresh /reports                       -> no 404
[ ] Inspect /index.html response                -> Cache-Control: no-cache, no-store, must-revalidate
[ ] Inspect /assets/<hashed-file>.js response   -> Cache-Control: public, max-age=31536000, immutable
[ ] Open every lazy route on deployment preview -> all referenced chunks return 200
[ ] Keep old version tab open, promote preview, navigate -> at most one reload and route recovers
[ ] Admin login -> catalogue visible
[ ] Admin login -> new bill works, Supabase persists
[ ] Lab Technician login -> limited nav (no catalogue, no reports sign-off)
[ ] /r/{valid-token}                            -> public report loads without login
[ ] /r/invalid-token                            -> clean 404/error message
[ ] Print preview -> logo and assets load correctly
[ ] SSL padlock visible (Cloudflare Universal SSL)
```

---

## 10. Files Changed for Deployment

| File | Change |
|------|--------|
| `public/_redirects` | NEW -- Cloudflare Pages SPA catch-all |
| `.env.example` | Updated with VITE_PUBLIC_APP_URL, secrets guidance |
| `index.html` | Updated title, meta description, noindex |
| `supabase/functions/public-report/index.ts` | CORS restricted -- explicit origin list |

---

## 11. What NOT to Do

- Do NOT commit `.env.local` (gitignored by *.local rule)
- Do NOT put SUPABASE_SERVICE_ROLE_KEY in Cloudflare Pages env vars
- Do NOT put SPARROW_SMS_TOKEN in Cloudflare Pages env vars
- Do NOT enable "Public" on the diagnostic-reports Supabase storage bucket
- Do NOT add a Cloudflare Worker / Tunnel as a backend proxy
- Do NOT change the database away from Supabase
- Do NOT enable real Sparrow SMS until production acceptance tests pass
