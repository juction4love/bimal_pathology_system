# 🧪 Bimal Pathology System - Architecture & Audit Checklist

> **Purpose**: Quick reference for code reviews, sprint planning, and production readiness checks.
> **Last Updated**: 2026-06-05  
> **Scope**: Windows Desktop Suite for Patient Registration, Result Entry & PDF Reporting
> **Medical Context**: HIPAA/Privacy compliance, Audit trails, Report immutability

---

## 🔴 TIER 1: MANDATORY (Before Production)

### 1️⃣ Patient Data Protection & Compliance

#### Password Security
- [ ] **Password Hashing**: Implemented with Argon2, bcrypt, or PBKDF2 (NOT MD5/SHA1)
  - [ ] Salt used consistently
  - [ ] Work factor/iterations appropriate for Windows desktop
  - [ ] Hashing algorithm documented in `docs/SECURITY.md`
- [ ] **Password Policy**:
  - [ ] Minimum 8 characters
  - [ ] Uppercase, lowercase, numbers, symbols required
  - [ ] Change password every 90 days (configurable)
  - [ ] Cannot reuse last 5 passwords
  - [ ] Password history maintained securely

#### Data Encryption at Rest
- [ ] **SQLite Database Encryption**: Patient data encrypted using SQLite encryption extension (SQLCipher recommended)
  - [ ] Encryption key management documented
  - [ ] Encryption key NOT hardcoded in source
  - [ ] Encryption key stored in OS secure storage (Windows Credential Manager or equivalent)
  - [ ] Different encryption keys per installation (not global)
- [ ] **Backup Encryption**: All backups encrypted before storage
  - [ ] Encryption key for backups managed separately
  - [ ] Backup encryption verified in tests

#### Data Exposure Prevention
- [ ] **Patient PII Masking**: In logs and error messages
  - [ ] Patient IDs masked (show last 4 digits only)
  - [ ] Phone numbers masked (show last 4 digits only)
  - [ ] Email addresses masked (show domain only)
  - [ ] No full SSN/Insurance numbers in logs
- [ ] **Error Messages**: Never expose sensitive data
  - [ ] Generic error messages to UI
  - [ ] Full error details logged securely for admins only
  - [ ] Stack traces never shown to end users

#### HIPAA/Compliance Framework
- [ ] **Privacy Notice**: Displayed at login (user must acknowledge)
- [ ] **Audit Logging**: Every user action logged with timestamp
- [ ] **Data Retention Policy**: Documented (when data can be purged)
- [ ] **Breach Notification**: Process documented
- [ ] **Compliance Testing**: Regular audit of log files for suspicious activity

---

### 2️⃣ Role-Based Access Control (RBAC)

#### Role Definitions
- [ ] **Four Core Roles Implemented**:
  - [ ] `Receptionist` 
    - [ ] Can create new patients
    - [ ] Can view patient demographics
    - [ ] Can log sample collection info
    - [ ] CANNOT view results or reports
  - [ ] `Lab Technician`
    - [ ] Can track samples
    - [ ] Can enter test results
    - [ ] Can view pending approvals
    - [ ] CANNOT approve reports
  - [ ] `Pathologist`
    - [ ] Can review results
    - [ ] Can approve/reject results
    - [ ] Can generate reports
    - [ ] Can amend approved reports (with reason)
  - [ ] `Administrator`
    - [ ] User management (create, disable, reset password)
    - [ ] System configuration
    - [ ] Access to audit logs
    - [ ] Can perform backups

#### Permission Enforcement
- [ ] **Default Deny**: Users have no permissions until explicitly granted
- [ ] **Permission Matrix**: Documented and reviewed quarterly
  - [ ] Create patient: `Receptionist` only
  - [ ] Enter results: `Lab Technician` only
  - [ ] Approve results: `Pathologist` only
  - [ ] Print reports: `Lab Technician`, `Pathologist`, `Administrator`
  - [ ] Access audit logs: `Administrator` only
  - [ ] Delete patient: NONE (never allowed, only archive)
- [ ] **Permission Checks**: Enforced at TWO levels
  - [ ] UI level (buttons hidden for unauthorized users)
  - [ ] Business logic level (all database operations checked)
- [ ] **Role Assignment**: Each user has exactly ONE primary role
  - [ ] No role inheritance/escalation
  - [ ] Role changes logged with timestamp
  - [ ] Old role revoked immediately

---

### 3️⃣ Session Management & Authentication

#### Login & Session Control
- [ ] **Login Screen**: Displays version, build number, security notice
- [ ] **Session Timeout**: Configurable (default 20 minutes for medical data)
  - [ ] Inactivity timer implemented
  - [ ] Warning shown 2 minutes before logout
  - [ ] User must re-authenticate after timeout
  - [ ] Session data cleared from memory
- [ ] **Automatic Logout**: Enforced on timeout or manual logout
  - [ ] All session tokens invalidated
  - [ ] Open dialogs closed gracefully
  - [ ] Unsaved data warning before logout

#### Session Security
- [ ] **Session Storage**: Session tokens stored securely (NOT in plain text)
  - [ ] Tokens use secure random generation (not simple UUIDs)
  - [ ] Token expiration enforced
  - [ ] Token rotation on privilege escalation
- [ ] **Session Isolation**: Each user's session independent
  - [ ] No cross-user data leakage possible
  - [ ] Concurrent sessions logged

#### Login Audit Trail
- [ ] **Login Logging**: Every login/logout recorded
  - [ ] Timestamp of login
  - [ ] User ID and username
  - [ ] IP address (if applicable)
  - [ ] Success/failure indicator
- [ ] **Failed Login Attempts**: Tracked and limited
  - [ ] After 5 failed attempts, account locked for 15 minutes
  - [ ] Failed login attempts logged
  - [ ] Administrator notified of repeated failures
  - [ ] Password reset required after lock

---

### 4️⃣ Laboratory Result Workflow (State Machine)

#### Workflow Definition
```
Sample Collected 
    ↓
Result Entered (by Lab Technician)
    ↓
Result Reviewed (by Pathologist)
    ↓
Pathologist Approved
    ↓
Report Generated
    ↓
Report Delivered (Print/Export)
```

#### State Enforcement
- [ ] **Workflow States Defined**: Each state has allowed transitions documented in code comments
  - [ ] No skipping of states allowed
  - [ ] No backward transitions (e.g., cannot go from Approved → Entered)
  - [ ] Only forward or stay-same transitions allowed
- [ ] **State Validation**: Before every transition
  - [ ] Current state verified in database
  - [ ] User has permission for transition
  - [ ] Required data fields populated
  - [ ] No concurrent modifications (pessimistic locking or version checking)

#### State Transition Audit Logging
- [ ] **Every transition logged with**:
  - [ ] Timestamp (millisecond precision)
  - [ ] User ID (who made transition)
  - [ ] Previous state
  - [ ] New state
  - [ ] Reason/comments (if applicable)
  - [ ] Sample ID/Patient ID for audit trail
- [ ] **Transition Log Immutable**: Once written, cannot be modified or deleted
- [ ] **Transition Log Accessible**: Via audit report (admin only)

#### Role Separation & Approval
- [ ] **Review Separation**: Result reviewer ≠ Result entrant
  - [ ] System prevents same person from entering AND approving same result
  - [ ] If only one pathologist, logs warning
- [ ] **Approval Requirement**: 
  - [ ] Pathologist MUST explicitly approve before report generation
  - [ ] Approval includes sign-off by pathologist name/credentials
  - [ ] Approval timestamp recorded
- [ ] **Rejection Option**: Pathologist can reject results
  - [ ] Result returns to "Entered" state
  - [ ] Rejection reason recorded
  - [ ] Lab technician notified

#### Sample Tracking
- [ ] **Sample Unique ID**: Each sample has barcode or system-generated ID
  - [ ] Format: YYMMDDxxx (e.g., 260605001)
  - [ ] Cannot be changed or reused
  - [ ] Linked to patient (but can be referenced independently)
- [ ] **Sample Timeline Tracked**:
  - [ ] Collected timestamp (when sample taken)
  - [ ] Received timestamp (when arrived at lab)
  - [ ] Processing timestamp (when testing began)
  - [ ] Completed timestamp (when testing finished)
  - [ ] Reported timestamp (when delivered to pathologist)
- [ ] **Sample Status Dashboard**: Real-time visibility
  - [ ] Samples in each stage counted
  - [ ] TAT (turnaround time) per sample tracked
  - [ ] Overdue samples highlighted

---

### 5️⃣ Report Immutability & Amendment Process

#### Report Read-Only After Approval
- [ ] **Approved Reports**: Locked from direct editing
  - [ ] UI disables all edit buttons after approval
  - [ ] Database has `is_locked` flag set to true
  - [ ] Attempt to edit locked report generates audit log entry
- [ ] **Report Data Frozen**: No fields can be modified
  - [ ] Test values locked
  - [ ] Reference ranges locked
  - [ ] Normal/Abnormal flags locked
  - [ ] Comments locked

#### Amendment Workflow
- [ ] **Amendment Creation** (not overwrite):
  - [ ] Create NEW amendment record (not modify original report)
  - [ ] Link amendment to original report via `report_id`
  - [ ] Mark original report as `has_amendments: true`
- [ ] **Amendment Data Required**:
  - [ ] Amendment reason (dropdown + free text)
  - [ ] Changed field names
  - [ ] Original value (before change)
  - [ ] New value (after change)
  - [ ] Amended by (user ID)
  - [ ] Amended timestamp
- [ ] **Re-Approval Required**:
  - [ ] Amended report sent back to "Approved" state (awaiting re-approval)
  - [ ] Pathologist must review amendment and re-approve
  - [ ] Cannot approve amendment without reviewing
- [ ] **Both Versions Accessible**:
  - [ ] Original report still viewable (marked as "Superseded")
  - [ ] Amendment viewable (marked as "Current")
  - [ ] User can see both versions side-by-side

#### Report Versioning
- [ ] **Version Numbering**:
  - [ ] Report #123 - Version 1 (Approved on 2026-06-05 by Dr. XYZ)
  - [ ] Report #123 - Version 2 (Amended on 2026-06-06 by Dr. ABC)
- [ ] **Version History**: Complete audit trail stored
  - [ ] Accessible to authorized users (pathologist, admin)
  - [ ] Shows all amendments and timestamps

#### Amendment Audit Trail
- [ ] **Amendment Record Contains**:
  - [ ] Original value stored (encrypted if sensitive)
  - [ ] New value stored (encrypted if sensitive)
  - [ ] Amendment reason recorded and categorized
  - [ ] Amendment timestamp & user recorded
  - [ ] Amendment approval timestamp & user recorded
- [ ] **Amendment Audit Log**: Searchable and exportable
- [ ] **Reason Categories**: Predefined list (e.g., "Reference range updated", "Data entry error", "Test re-run", "Transcription error")

#### Archive & Deletion Policy
- [ ] **Archive Original**: Original report never deleted, marked as superseded
  - [ ] `is_superseded: true` flag set
  - [ ] Superseded date recorded
  - [ ] Original still accessible via "View History"
- [ ] **No Hard Deletes**: Patient records never permanently deleted
  - [ ] Archived records kept for minimum 7 years (per regulations)
  - [ ] Archive can only be accessed by admin

---

### 6️⃣ Database Backup Strategy

#### Automated Backups
- [ ] **Daily Automatic Backup**: Scheduled backup (recommend 11 PM or off-hours)
  - [ ] Backup runs without user intervention
  - [ ] Configurable backup time
  - [ ] Success/failure logged
  - [ ] Admin email notification on failure
  - [ ] Backup file named with timestamp: `backup_2026-06-05_23-00.sqlite3.enc`
- [ ] **Weekly Full Backup**: Complete database copy (separate from daily incremental)
  - [ ] Full copy preserved separately
  - [ ] Not overwritten by daily backups
  - [ ] Stored on separate drive or USB
- [ ] **Manual Backup Option**: Users can trigger backup anytime
  - [ ] "Backup Now" button in Admin Settings
  - [ ] Success message with backup location
  - [ ] Backup starts immediately, no user data loss during backup

#### Backup Verification & Testing
- [ ] **Backup Integrity Check**:
  - [ ] Checksum/hash verification after backup completes
  - [ ] File size compared to baseline (alert if too small)
  - [ ] File not corrupted (sqlite integrity check if possible)
- [ ] **Backup Encryption**:
  - [ ] Backup encrypted with same key as database
  - [ ] Backup key managed securely
  - [ ] Backup files NOT readable without key
- [ ] **Backup Storage**:
  - [ ] Backup location documented
  - [ ] Backup media (local drive, USB, cloud) accessible
  - [ ] Multiple backup copies maintained (weekly rotation: W1, W2, W3, W4)
- [ ] **Restoration Testing** (monthly minimum):
  - [ ] Monthly test restore of backup to test machine
  - [ ] Restored database verified against original
  - [ ] Test results logged

#### Backup Recovery Procedure
- [ ] **Restore Documentation**: Step-by-step restore guide available
- [ ] **Restore Process**:
  - [ ] Admin can restore from backup via UI (with confirmation)
  - [ ] Restore requires password confirmation
  - [ ] Restore triggers audit log entry
  - [ ] All users logged out during restore
- [ ] **Data Rollback**: After restore, data is as of backup time
  - [ ] Users notified of rollback date
  - [ ] "Redo" of manual entries since backup required
- [ ] **Recovery SLA**: Backup restore completes within 15 minutes

---

### 7️⃣ Audit Logging & Compliance

#### Comprehensive Audit Log
- [ ] **All Sensitive Operations Logged**:
  - [ ] User login/logout (with timestamp)
  - [ ] Failed login attempts
  - [ ] Permission changes
  - [ ] Patient record creation/modification/view
  - [ ] Result entry/modification/approval
  - [ ] Report generation/printing/export
  - [ ] Backup creation/restore
  - [ ] User account changes
  - [ ] Configuration changes

#### Audit Log Format
- [ ] **Log Entry Contains**:
  - [ ] Timestamp (millisecond precision)
  - [ ] User ID & username (or "SYSTEM" for automated)
  - [ ] Action type (e.g., "RESULT_APPROVED")
  - [ ] Resource ID (e.g., patient_id, result_id, report_id)
  - [ ] Before state (if applicable)
  - [ ] After state (if applicable)
  - [ ] Status (SUCCESS/FAILURE)
  - [ ] Error message (if failure)

#### Audit Log Security
- [ ] **Audit Log Immutable**: Once written, cannot be modified or deleted
  - [ ] Implemented with append-only file or separate secure table
  - [ ] Deletion attempts logged as SECURITY_ALERT
- [ ] **Audit Log Encryption**: Encrypted at rest
- [ ] **Audit Log Retention**: Minimum 7 years (per healthcare regulations)
  - [ ] Archive old logs to separate storage
  - [ ] Retention policy documented

#### Audit Log Access Control
- [ ] **Audit Log Visibility**: Admin & Pathologist only
  - [ ] Receptionist and Lab Technician cannot access
  - [ ] Access to audit logs is itself logged (meta-audit)
- [ ] **Audit Log Search**: Filterable by date, user, action type, resource ID
- [ ] **Audit Log Export**: 
  - [ ] Can export to CSV for compliance review
  - [ ] Export requires password confirmation
  - [ ] Export logged as audit event

#### Security Event Detection
- [ ] **Suspicious Activity Alerts**:
  - [ ] 5+ failed login attempts → account locked
  - [ ] Access to unauthorized resources → logged as SECURITY_ALERT
  - [ ] Attempt to modify audit log → logged as CRITICAL_ALERT
  - [ ] Bulk data access → logged as SECURITY_ALERT
- [ ] **Alert Notifications**: Admins notified of CRITICAL_ALERTs
- [ ] **Incident Response**: Process documented for responding to security alerts

---

## 🟡 TIER 2: STRONGLY RECOMMENDED (Before GA Release)

### Architecture & Code Quality
- [ ] **Separation of Concerns**: Business logic separated from UI
  - [ ] Service layer for all patient/result operations
  - [ ] ViewModel layer for UI state management
  - [ ] Repository pattern for data access
- [ ] **Error Handling**: Consistent error handling throughout
  - [ ] Custom exceptions for different error types
  - [ ] Graceful degradation (app doesn't crash)
  - [ ] User-friendly error messages
- [ ] **Logging Framework**: Consistent logging across app
  - [ ] Log levels (DEBUG, INFO, WARN, ERROR, CRITICAL)
  - [ ] Contextual logging (include relevant IDs/data)
  - [ ] Log rotation (old logs archived)
- [ ] **Unit Test Coverage**: Critical paths tested
  - [ ] RBAC logic tested (all role + permission combinations)
  - [ ] State machine transitions tested
  - [ ] Encryption/decryption tested
  - [ ] Backup/restore tested
  - [ ] Target: >80% code coverage for business logic

### Infrastructure & Deployment
- [ ] **Version Management**: Clear versioning scheme
  - [ ] Semantic versioning (e.g., 1.2.3)
  - [ ] Version displayed in app title bar
  - [ ] Release notes document security patches
- [ ] **Update Mechanism**: Secure updates
  - [ ] Signed updates (prevent tampering)
  - [ ] Update notification system
  - [ ] Rollback capability if update fails
  - [ ] Update log entry in audit trail
- [ ] **Installation**: Secure & user-friendly
  - [ ] Windows installer with digital signature
  - [ ] Admin rights required (for database folder)
  - [ ] Installation log recorded
  - [ ] First-run configuration wizard

### Performance & Reliability
- [ ] **Database Optimization**: Queries optimized for local SQLite
  - [ ] Indexes on frequently searched fields (patient_id, result_id)
  - [ ] Query performance tested
  - [ ] Large dataset tested (1M+ patients)
- [ ] **Concurrency**: Handles multiple users on same PC
  - [ ] File locking prevents concurrent writes
  - [ ] Transactions prevent partial updates
  - [ ] Deadlock scenarios prevented/handled
- [ ] **Resource Usage**: App doesn't consume excessive resources
  - [ ] Memory leaks tested
  - [ ] CPU usage reasonable
  - [ ] Disk I/O optimized

---

## 🟢 TIER 3: NICE-TO-HAVE (Long-term)

- [ ] **Internationalization**: Support for multiple languages
- [ ] **Accessibility**: WCAG compliance for accessibility
- [ ] **Mobile Companion**: Mobile app for pathologist report approval
- [ ] **Network Sync**: Multi-location sync with central server
- [ ] **Advanced Analytics**: Dashboard for lab metrics (TAT, volume, trends)
- [ ] **Integration**: HL7 integration with hospital systems
- [ ] **Two-Factor Authentication**: SMS or app-based 2FA option

---

## 📋 Quick Review Checklist (Use Before Code Review)

**Security First:**
- [ ] No hardcoded secrets (API keys, encryption keys, passwords)?
- [ ] All user input validated (SQL injection, XSS prevention)?
- [ ] No unencrypted patient data in logs?
- [ ] All sensitive operations permission-checked?
- [ ] Audit log entries created for all actions?

**Medical Domain:**
- [ ] State machine correctly enforces workflow?
- [ ] Role separation enforced (different users for entry/approval)?
- [ ] Amendment process creates new records (not overwrites)?
- [ ] Original reports archived, never deleted?
- [ ] Backups tested and restorable?

**Code Quality:**
- [ ] Code follows project style guide?
- [ ] No magic numbers or strings (use constants)?
- [ ] Functions have single responsibility?
- [ ] Error handling present for all database operations?
- [ ] Unit tests pass locally?

---

## 📚 Related Documentation
- **SECURITY.md** - Detailed security architecture
- **BACKUP_RECOVERY.md** - Backup & recovery procedures
- **RBAC_MATRIX.md** - Role & permission matrix
- **API_AUDIT_LOG.md** - Audit logging API reference
- **AMENDMENT_WORKFLOW.md** - Report amendment procedure
