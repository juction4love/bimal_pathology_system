# Authenticated staging browser acceptance

This suite is intentionally fail-closed and read-only. It never defaults to a URL, project, search fixture, result item, or credential. It blocks production, non-staging Supabase projects, the SMS dispatcher, Sparrow, and financial/clinical mutation RPCs at the browser network layer.

Required environment variables:

```text
STAGING_ACCEPTANCE_ENVIRONMENT=isolated-staging
STAGING_ACCEPTANCE_PROJECT_REF=ilcnctiaumrjbnlmnise
STAGING_ACCEPTANCE_CONFIRM=RUN_ISOLATED_STAGING_ilcnctiaumrjbnlmnise
STAGING_ACCEPTANCE_BASE_URL=<loopback or explicitly staging-named frontend URL>
STAGING_ACCEPTANCE_SUPABASE_URL=https://ilcnctiaumrjbnlmnise.supabase.co
STAGING_ACCEPTANCE_ADMIN_EMAIL=<synthetic active staging Admin>
STAGING_ACCEPTANCE_ADMIN_PASSWORD=<secret>
STAGING_ACCEPTANCE_TECHNICIAN_EMAIL=<synthetic active staging Lab Technician>
STAGING_ACCEPTANCE_TECHNICIAN_PASSWORD=<secret>
STAGING_ACCEPTANCE_RESULT_ITEM_ID=<synthetic staging clinical_order_items UUID readable by both roles>
STAGING_ACCEPTANCE_SEARCH_2=<known two-character active catalogue match>
STAGING_ACCEPTANCE_SEARCH_3=<known three-character active catalogue match>
STAGING_ACCEPTANCE_SEARCH_4=<known four-character active catalogue match>
```

Run only after independently confirming that the frontend was built/configured for the isolated staging backend:

```powershell
npx playwright test --config playwright.staging.config.js
```

The run covers authenticated Admin and Lab Technician sessions, the visible navigation permission matrix, all required main workspaces, a synthetic Result Entry fixture, and keyboard-first 2/3/4-character New Bill catalogue selection. It does not finalize a bill, receive a payment, save a clinical result, sign a report, dispatch an SMS, or call Sparrow.
