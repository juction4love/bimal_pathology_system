# BIMAL PATHOLOGY & DIAGNOSTIC CENTER
## Row Level Security (RLS) & Clinical Authorization Architecture

### 1. Security Principles

This is a clinical medical Laboratory Information System. Unrestricted direct database access via Supabase client is strictly prohibited. Security is enforced through multi-layered defense:

1. **PostgreSQL Row Level Security (RLS)**: Every database table has RLS enabled with explicit capability-based policies.
2. **Granular Permission Matrix**: Permissions are discrete capability keys (e.g. `can_sign_reports`, `can_verify_results`, `can_create_bill`).
3. **Database Function / RPC Authorization**: Sensitive multi-entity mutations (e.g. billing, sample rejection, report sign-off) are executed via `SECURITY DEFINER` stored procedures.
4. **Append-Only Auditing**: Every critical mutation is logged into `audit_logs` where `UPDATE` and `DELETE` operations are completely disabled.
5. **Signed Report Immutability**: Once a diagnostic report is signed off (`status = 'SignedOff'`), the row is frozen. Subsequent corrections require an explicit amendment (`version >= 2`) with an audit reason.

---

### 2. Granular Permissions Dictionary

| Permission Key | Description | Applicable Roles |
|---|---|---|
| `can_view_dashboard` | Access live operational dashboard & metrics | Admin, Pathologist, Technologist, Tech, Reception, Staff |
| `can_create_bill` | Create patient bookings, bills, and record payments | Admin, Reception |
| `can_edit_patient` | Modify patient demographic records | Admin, Reception |
| `can_collect_sample` | Mark samples collected and print barcode labels | Admin, Technologist, Tech, Reception |
| `can_receive_sample` | Accession & receive specimens in lab workstation | Admin, Technologist, Tech |
| `can_reject_sample` | Reject specimen and trigger recollection lineage | Admin, Technologist, Tech |
| `can_enter_results` | Enter parameter observations and draft worklists | Admin, Pathologist, Technologist, Tech |
| `can_verify_results` | Perform clinical verification of results | Admin, Pathologist, Technologist |
| `can_acknowledge_critical` | Acknowledge critical pathological value alerts | Admin, Pathologist, Technologist |
| `can_sign_reports` | Authorize and digitally sign final pathology reports | Admin, Pathologist |
| `can_amend_reports` | Issue post-sign-off amendments (v2+) | Admin, Pathologist |
| `can_print_reports` | Print official A4 pathology diagnostic reports | Admin, Pathologist, Technologist, Tech, Reception |
| `can_manage_catalogue` | Configure tests, parameters, formulas, ranges | Admin |
| `can_manage_referring_doctors` | Manage referring clinicians and institutions | Admin |
| `can_manage_personnel` | Manage internal signatories and councils | Admin |
| `can_view_financials` | View revenue, discounts, and ledger reports | Admin |
| `can_manage_users` | Create, invite, and disable staff user accounts | Admin |
| `can_manage_roles` | Configure roles and granular permission matrix | Admin |
| `can_view_audit_logs` | Inspect system-wide tamper-evident audit logs | Admin, Pathologist |

---

### 3. Role-Based Access Matrix

| Role | Billing | Samples | Entry | Verify | Critical Ack | Sign Report | Catalogue | Admin |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Admin** | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| **Pathologist** | View | View | Yes | Yes | Yes | Yes | Read | Audit |
| **Lab Technologist** | View | Yes | Yes | Yes | Yes | No | Read | No |
| **Lab Technician** | View | Yes | Yes | No | No | No | Read | No |
| **Reception** | Yes | Collect | No | No | No | No | Read | No |
| **Other Staff** | View | No | No | No | No | No | Read | No |

---

### 4. Critical Value Acknowledgment Protocol

When a result enters `CriticalLow` or `CriticalHigh` threshold:
1. The parameter is flagged in real time.
2. The worklist displays high-priority visual alerts.
3. Verification and Sign-Off buttons are locked.
4. An authorized personnel (`can_acknowledge_critical`) must open the acknowledgment modal, record communication details (clinician name, method, timestamp), and commit the record.
5. The acknowledgment is written to the audit trail, unlocking verification.
