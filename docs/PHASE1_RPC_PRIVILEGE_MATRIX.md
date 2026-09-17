# Phase 1 RPC privilege matrix

All functions introduced by pending migration `00050` use `SECURITY DEFINER SET search_path=public,pg_temp`. Execution is first revoked from `PUBLIC`, `anon`, and `authenticated`; only the browser-facing entry points are then granted to `authenticated`. Internal helpers receive no client grant.

| Function group | Client role | Server authorization |
|---|---|---|
| `catalogue_actor_name`, `catalogue_require_manager` | None | Internal helper only |
| `catalogue_test_missing_configuration` | `authenticated` | `can_manage_catalogue` through `catalogue_require_manager` |
| Test CRUD/lifecycle/price/clone | `authenticated` | `can_manage_catalogue` |
| Parameter CRUD/lifecycle | `authenticated` | `can_manage_catalogue` |
| Reference-range CRUD/lifecycle/replacement | `authenticated` | `can_manage_catalogue`; approval also requires explicit `ClinicallyValidated` provenance |
| Category save/lifecycle | `authenticated` | `can_manage_catalogue`; row lock and expected `row_version` |
| Package save/lifecycle/delete | `authenticated` | `can_manage_catalogue` |
| `catalogue_expand_package` | `authenticated` | `can_create_bill` |
| `search_billable_catalogue` | `authenticated` | `can_create_bill` |
| `create_patient_bill_order_with_packages` | `authenticated` | `can_create_bill`; delegates the existing atomic bill/order RPC |
| `replace_role_permission_matrix` | `authenticated` | `can_manage_roles`; one transaction, locked roles, fixed permission allowlist, Admin role protected |
| `save_reporting_personnel` | `authenticated` | `can_manage_personnel`; locked update and audit event |
| `save_referring_doctor` | `authenticated` | `can_manage_referring_doctors`; locked update and audit event |

Direct authenticated `INSERT`, `UPDATE`, and `DELETE` are revoked for catalogue tables, `role_permissions`, `reporting_personnel`, and `referring_doctors`. Read policies remain unchanged.
