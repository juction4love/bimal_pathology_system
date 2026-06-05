# 🧪 Bimal Pathology System - Architecture & Audit Checklist

> **Purpose**: Quick reference for code reviews, sprint planning, and production readiness checks.
> **Last Updated**: 2026-06-05  
> **Scope**: Windows Desktop Suite for Patient Registration, Result Entry & PDF Reporting

---

## 🔴 TIER 1: MANDATORY (Before Production)

### Patient Data Protection & Compliance
- [ ] **Password Hashing**: Implemented with Argon2, bcrypt, or PBKDF2 (NOT MD5/SHA1)
  - [ ] Salt used consistently
  - [ ] Work factor/iterations appropriate for Windows desktop
- [ ] **Data Encryption at Rest**: Patient data encrypted in local SQLite database
  - [ ] Encryption key management documented
  - [ ] Encryption key NOT hardcoded
- [ ] **Backup Encryption**: All backups encrypted before storage
- [ ] **HIPAA/Local Compliance**: If applicable, compliance framework implemented
- [ ] **Patient PII Masking**: In logs and error messages, never expose full IDs

### Role-Based Access Control (RBAC)
- [ ] **Four Core Roles Defined**:
  - [ ] `Receptionist` - Patient registration, sample collection info
  - [ ] `Lab Technician` - Sample tracking, result entry
  - [ ] `Pathologist` - Result review, approval, report generation
  - [ ] `Administrator` - User management, system configuration, audit logs
- [ ] **Role Assignment**: Each user has exactly one role (or role + sub-permissions)
- [ ] **Permission Matrix**: Documented mapping of roles to features
  - [ ] Patient creation: Receptionist ✓
  - [ ] Result entry: Lab Technician ✓
  - [ ] Result approval: Pathologist ✓
  - [ ] Report printing: All except receptionist (configurable)
- [ ] **Default Deny**: Users have no permissions until explicitly granted
- [ ] **Permission Checks**: On every sensitive operation (entry point + business logic)

### Session Management & Authentication
- [ ] **Session Timeout**: Configurable (recommend 15-30 minutes for medical data)
  - [ ] Inactivity timer implemented
  - [ ] Warning before automatic logout
  - [ ] User notified on re-login
- [ ] **Automatic Logout**: Enforced on timeout or user logout
- [ ] **Session Storage**: Session tokens stored securely (NOT in plain text)
- [ ] **Login Audit Log**: Every login/logout recorded with timestamp and user ID
- [ ] **Failed Login Attempts**: Track and potentially lock account after N attempts
- [ ] **Password Policy**: 
  - [ ] Minimum 8 characters
  - [ ] Uppercase, lowercase, numbers, symbols required
  - [ ] Change password every 90 days (configurable)
  - [ ] Cannot reuse last 5 passwords

### Laboratory Result Workflow (State Machine)
```
Sample Collected → Result Entered → Result Reviewed → Pathologist Approved → Report Generated → Report Delivered
```

- [ ] **Workflow States Defined**: Each state has allowed transitions documented
- [ ] **State Transition Logging**: Every transition logged with:
  - [ ] Timestamp
  - [ ] User ID (who made transition)
  - [ ] Previous state
  - [ ] New state
  - [ ] Reason/comments (if applicable)
- [ ] **No Direct Transitions**: Results cannot skip states (e.g., entry → approved)
- [ ] **Review Separation**: Result reviewer ≠ Result entrant (different users)
- [ ] **Approval Requirement**: Pathologist must approve before report generation
- [ ] **Sample Tracking**: Each sample has unique ID (barcode or system ID)
  - [ ] Collected timestamp
  - [ ] Received timestamp
  - [ ] Processing timestamp
  - [ ] Completed timestamp
  - [ ] Reported timestamp

### Report Immutability & Amendment Process
- [ ] **Approved Reports**: Read-only after approval (no direct editing)
- [ ] **Amendment Workflow**:
  - [ ] Create amendment record (NOT overwrite original)
  - [ ] Link amendment to original report
  - [ ] New approval required
  - [ ] Both versions accessible in system
- [ ] **Report Versioning**:
  - [ ] Report #123 - Version 1 (Approved on 2026-06-05 by Dr. XYZ)
  - [ ] Report #123 - Version 2 (Amended on 2026-06-06 by Dr. ABC - Reason: Reference range updated)
- [ ] **Amendment Audit Trail**:
  - [ ] Original value stored
  - [ ] New value stored
  - [ ] Amendment reason recorded
  - [ ] Amendment timestamp & user recorded
- [ ] **Archive Original**: Original report never deleted, marked as superseded

### Database Backup Strategy
- [ ] **Daily Automatic Backup**: Scheduled backup (recommend 11 PM or off-hours)
  - [ ] Backup runs without user intervention
  - [ ] Success/failure logged
  - [ ] Admin notified on failure
- [ ] **Weekly Full Backup**: Complete database copy (separate from daily incremental)
- [ ] **Manual Backup Option**: Users can trigger backup anytime
- [ ] **Backup Verification**:
  - [ ] Backup integrity check (checksum/hash verification)
  - [ ] Backup restoration test (monthly minimum)
  - [ ] Backup size logged
- [ ] **Backup Storage**:
  - [ ] Separate physical location from application data
  - [ ] Encrypted backups
  - [ ] Retention policy: Keep last 30 days of daily backups + all weekly backups
  - [ ] Offsite backup recommended (USB drive, network storage, or cloud)
- [ ] **Recovery Plan**: Documented and tested procedure to restore from backup

### Comprehensive Audit Trail & Logging

#### ⭐ Audit Log Schema - INSERT ONLY (Append-Only)

**महत्वपूर्ण (Important)**: Audit Log को **INSERT मात्र** गर्न दिनु, UPDATE र DELETE गर्न दिँदैन।  
यसले प्रमाण (Evidence) सुरक्षित राख्छ। यो compliance को लागि आवश्यक छ।

```sql
-- Audit Log Table (Append-Only)
CREATE TABLE audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  user_name TEXT,
  action VARCHAR(50) NOT NULL,        -- 'CREATE', 'UPDATE', 'DELETE', 'APPROVE', 'PRINT', etc.
  entity_type VARCHAR(50) NOT NULL,   -- 'Patient', 'Result', 'Report', 'User', 'ReferenceRange'
  entity_id INTEGER NOT NULL,         -- FK to the affected entity
  entity_name TEXT,                   -- Human-readable identifier (Patient name, Report #)
  old_value TEXT,                     -- JSON of previous state (for updates)
  new_value TEXT,                     -- JSON of new state (for updates)
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  ip_address TEXT,
  session_id TEXT,
  status VARCHAR(20),                 -- 'SUCCESS', 'FAILURE'
  error_message TEXT,                 -- If failed, capture error details
  metadata JSON,                       -- Additional context (change reason, comments, etc.)
  
  FOREIGN KEY (user_id) REFERENCES users(id),
  INDEX idx_user_id (user_id),
  INDEX idx_entity_type (entity_type),
  INDEX idx_entity_id (entity_id),
  INDEX idx_timestamp (timestamp),
  INDEX idx_action (action)
);

-- IMMUTABILITY ENFORCEMENT
-- ═════════════════════════════════════════════════════════════

-- 1️⃣ No UPDATE allowed on audit_logs
-- 2️⃣ No DELETE allowed on audit_logs
-- 3️⃣ INSERT ONLY - Application enforces this at code level

-- SQLITE: Prevent DELETE
CREATE TRIGGER prevent_audit_delete BEFORE DELETE ON audit_logs
BEGIN
  SELECT RAISE(FAIL, 'Audit logs cannot be deleted');
END;

-- SQLITE: Prevent UPDATE
CREATE TRIGGER prevent_audit_update BEFORE UPDATE ON audit_logs
BEGIN
  SELECT RAISE(FAIL, 'Audit logs cannot be updated');
END;

-- Application-level enforcement (Dart/Flutter):
-- - AuditService.log() → INSERT only
-- - No updateAuditLog() method exists
-- - No deleteAuditLog() method exists
```

**Database Level Protection**:
- [ ] **SQLite Triggers**: DELETE और UPDATE triggers implement (see SQL above)
- [ ] **No UPDATE Permission**: Database user (application user) को UPDATE permission नदिनु
- [ ] **No DELETE Permission**: Database user को DELETE permission नदिनु
- [ ] **INSERT Only**: Application user को INSERT permission मात्र दिनु

**Application Level Protection**:
- [ ] **No Update Method**: `AuditService` मा updateAuditLog() method छैन
- [ ] **No Delete Method**: `AuditService` मा deleteAuditLog() method छैन
- [ ] **Insert Only**: `AuditService.log(event)` मा INSERT मात्र हुन्छ

```dart
// ✅ Correct Implementation
class AuditService {
  // INSERT ONLY - No delete or update methods!
  
  Future<void> log(AuditEvent event) async {
    // Only INSERT into audit_logs
    await database.insert(
      'audit_logs',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.fail, // Fail on conflict
    );
  }
  
  // ❌ These methods should NOT exist:
  // Future<void> updateAuditLog(int id, ...) {}  // DON'T ADD THIS
  // Future<void> deleteAuditLog(int id) {}      // DON'T ADD THIS
  
  // ✅ Read-only methods are OK:
  Future<List<AuditEvent>> getAuditLog({
    required int days,
    String? userFilter,
    String? entityTypeFilter,
  }) async {
    final sql = '''
      SELECT * FROM audit_logs 
      WHERE timestamp >= datetime('now', '-$days days')
    ''';
    // ... query implementation
  }
}

// Implementation Example
void main() async {
  final auditService = AuditService();
  
  // ✅ This works - log is created
  await auditService.log(AuditEvent(
    action: 'RESULT_APPROVED',
    entityType: 'Result',
    entityId: 123,
    userId: 5,
    timestamp: DateTime.now(),
  ));
  
  // ❌ These should NOT compile:
  // await auditService.updateAuditLog(1, ...);  // Error: No such method
  // await auditService.deleteAuditLog(1);       // Error: No such method
}
```

**Why INSERT-Only?**
```
Audit Log समस्या (Problem):
─────────────────────────
Bad Admin:  "मेरो गलतीको प्रमाण छिपाउँ!"
Bad Admin:  DELETE FROM audit_logs WHERE user_id = bad_admin_id;
Result:     गलतीको कुनै प्रमाण नै नरहे।
            → Compliance violation
            → Evidence destroyed

Audit Log समाधान (Solution):
─────────────────────────
INSERT-Only Audit Log:
  ✅ Bad Admin: DELETE चलाउँ। → DENIED (Trigger blocks it)
  ✅ Bad Admin: UPDATE चलाउँ। → DENIED (Trigger blocks it)
  ✅ सबै प्रमाण सुरक्षित रहे।
  ✅ Compliance maintained
```

**Audit Events to Log**:
- [ ] **Patient Management**:
  - [ ] `CREATE` - New patient registered
  - [ ] `UPDATE` - Patient details modified
  - [ ] `DELETE` - Patient record marked inactive (soft delete)
- [ ] **Result Entry**:
  - [ ] `RESULT_ENTERED` - Lab technician enters test result
  - [ ] `RESULT_REVIEWED` - Pathologist reviews result
  - [ ] `RESULT_APPROVED` - Pathologist approves result
  - [ ] `RESULT_AMENDED` - Result corrected (with amendment reason)
- [ ] **Report Generation**:
  - [ ] `REPORT_GENERATED` - Report created from approved results
  - [ ] `REPORT_PRINTED` - Report printed to paper/file
  - [ ] `REPORT_DELIVERED` - Report delivered to patient/clinic
- [ ] **User Management**:
  - [ ] `USER_CREATED` - New user account created
  - [ ] `USER_ROLE_CHANGED` - User role modified
  - [ ] `USER_DISABLED` - User account disabled
- [ ] **System Configuration**:
  - [ ] `REFERENCE_RANGE_UPDATED` - Reference range changed
  - [ ] `CRITICAL_VALUE_UPDATED` - Critical value alert threshold changed
  - [ ] `CONFIG_CHANGED` - System settings modified
- [ ] **Authentication**:
  - [ ] `LOGIN_SUCCESS` - User logged in
  - [ ] `LOGIN_FAILED` - Failed login attempt
  - [ ] `LOGOUT` - User logged out
  - [ ] `PERMISSION_DENIED` - Access attempt denied

**Audit Log Verification Checklist**:
- [ ] **Append-Only**: INSERT मात्र, UPDATE/DELETE छैन
- [ ] **Immutable After Creation**: Triggers implement गरिएको छ
- [ ] **Retention Policy**: Minimum 3 years
- [ ] **Searchable**: user, timestamp, entity_type, action by indexed
- [ ] **Regular Audit Reports**: Weekly/monthly reports generate हुन्छ
- [ ] **No Bulk Delete**: नियमित cleanup policies छैन (सबै logs retain हुन्छ)

---

## 🟡 TIER 2: RESULT VERSIONING & MASTER DATA GOVERNANCE

### Result Versioning Schema
Never overwrite approved results. Store every version.

```sql
CREATE TABLE results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sample_id INTEGER NOT NULL,
  test_id INTEGER NOT NULL,
  value DECIMAL(10, 2),
  unit VARCHAR(20),
  reference_range_id INTEGER,
  status VARCHAR(20),               -- 'Draft', 'Entered', 'Reviewed', 'Approved'
  entered_by INTEGER,
  entered_at DATETIME,
  reviewed_by INTEGER,
  reviewed_at DATETIME,
  approved_by INTEGER,
  approved_at DATETIME,
  is_abnormal BOOLEAN,
  abnormal_flag VARCHAR(20),        -- 'Normal', 'Low', 'High', 'Critical'
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME,
  
  FOREIGN KEY (sample_id) REFERENCES samples(id),
  FOREIGN KEY (test_id) REFERENCES test_definitions(id),
  FOREIGN KEY (entered_by) REFERENCES users(id),
  FOREIGN KEY (reviewed_by) REFERENCES users(id),
  FOREIGN KEY (approved_by) REFERENCES users(id)
);

CREATE TABLE result_amendments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  original_result_id INTEGER NOT NULL,
  amended_result_id INTEGER NOT NULL,
  amendment_reason TEXT,
  old_value DECIMAL(10, 2),
  new_value DECIMAL(10, 2),
  amended_by INTEGER NOT NULL,
  amended_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  amendment_approved_by INTEGER,
  amendment_approved_at DATETIME,
  
  FOREIGN KEY (original_result_id) REFERENCES results(id),
  FOREIGN KEY (amended_result_id) REFERENCES results(id),
  FOREIGN KEY (amended_by) REFERENCES users(id),
  FOREIGN KEY (amendment_approved_by) REFERENCES users(id)
);

CREATE TABLE reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  report_number VARCHAR(50) UNIQUE,         -- REP-2026-000145
  sample_id INTEGER NOT NULL,
  version INTEGER DEFAULT 1,
  status VARCHAR(20),                       -- 'Draft', 'Final', 'Amended'
  generated_by INTEGER,
  generated_at DATETIME,
  approved_by INTEGER,
  approved_at DATETIME,
  printed_count INTEGER DEFAULT 0,
  pdf_file_path TEXT,
  qr_code TEXT,                             -- QR verification data
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  
  FOREIGN KEY (sample_id) REFERENCES samples(id),
  FOREIGN KEY (generated_by) REFERENCES users(id),
  FOREIGN KEY (approved_by) REFERENCES users(id)
);

CREATE TABLE report_amendments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  original_report_id INTEGER NOT NULL,
  amended_report_id INTEGER NOT NULL,
  amendment_reason TEXT,
  amended_by INTEGER NOT NULL,
  amended_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  previous_report_number VARCHAR(50),
  new_report_number VARCHAR(50),
  
  FOREIGN KEY (original_report_id) REFERENCES reports(id),
  FOREIGN KEY (amended_report_id) REFERENCES reports(id),
  FOREIGN KEY (amended_by) REFERENCES users(id)
);
```

**Report Versioning Example**:
```
Report #REP-2026-000145
├── Version 1 (Approved) - 2026-06-05 09:00 by Dr. XYZ
├── Version 2 (Amended) - 2026-06-05 14:30 by Dr. ABC
│   └── Reason: Reference range updated for Hemoglobin
├── Version 3 (Amended) - 2026-06-06 10:15 by Dr. ABC
│   └── Reason: Corrected patient DOB (data entry error)
```

- [ ] **Version History Accessible**: Users can view all report versions
- [ ] **Reason Tracking**: Amendment reason documented
- [ ] **Approval Chain**: Each version has approval metadata
- [ ] **Report Archive**: Original report never deleted

---

### Master Data Governance

Pathology systems contain critical master data that affects all operations. Changes must be audited and versioned.

```sql
CREATE TABLE test_definitions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  test_code VARCHAR(20) UNIQUE,      -- 'HB', 'RBC', 'WBC', etc.
  test_name VARCHAR(100) NOT NULL,   -- 'Hemoglobin', 'Red Blood Cell Count'
  description TEXT,
  unit VARCHAR(20),
  specimen_type VARCHAR(50),         -- 'Blood', 'Urine', 'Serum'
  method VARCHAR(100),
  is_active BOOLEAN DEFAULT 1,
  created_at DATETIME,
  updated_at DATETIME,
  updated_by INTEGER,
  
  FOREIGN KEY (updated_by) REFERENCES users(id)
);

CREATE TABLE test_definitions_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  test_id INTEGER NOT NULL,
  old_value TEXT,                    -- JSON of previous state
  new_value TEXT,                    -- JSON of new state
  changed_by INTEGER NOT NULL,
  changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  change_reason TEXT,
  
  FOREIGN KEY (test_id) REFERENCES test_definitions(id),
  FOREIGN KEY (changed_by) REFERENCES users(id),
  INDEX idx_test_id (test_id),
  INDEX idx_changed_at (changed_at)
);

CREATE TABLE reference_ranges (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  test_id INTEGER NOT NULL,
  age_group_min INTEGER DEFAULT 0,   -- Age in years (0 = all ages)
  age_group_max INTEGER DEFAULT 999,
  gender CHAR(1),                    -- 'M', 'F', 'B' (both)
  min_value DECIMAL(10, 4),
  max_value DECIMAL(10, 4),
  critical_low DECIMAL(10, 4),       -- Alert if below this
  critical_high DECIMAL(10, 4),      -- Alert if above this
  unit VARCHAR(20),
  notes TEXT,
  version_number INTEGER DEFAULT 1,
  effective_date DATE,
  is_active BOOLEAN DEFAULT 1,
  created_by INTEGER,
  created_at DATETIME,
  updated_by INTEGER,
  updated_at DATETIME,
  
  FOREIGN KEY (test_id) REFERENCES test_definitions(id),
  FOREIGN KEY (created_by) REFERENCES users(id),
  FOREIGN KEY (updated_by) REFERENCES users(id),
  INDEX idx_test_id (test_id),
  INDEX idx_gender (gender),
  INDEX idx_age (age_group_min, age_group_max)
);

CREATE TABLE reference_ranges_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  reference_range_id INTEGER NOT NULL,
  old_min DECIMAL(10, 4),
  old_max DECIMAL(10, 4),
  new_min DECIMAL(10, 4),
  new_max DECIMAL(10, 4),
  old_critical_low DECIMAL(10, 4),
  new_critical_low DECIMAL(10, 4),
  old_critical_high DECIMAL(10, 4),
  new_critical_high DECIMAL(10, 4),
  change_reason TEXT,
  changed_by INTEGER NOT NULL,
  changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  
  FOREIGN KEY (reference_range_id) REFERENCES reference_ranges(id),
  FOREIGN KEY (changed_by) REFERENCES users(id),
  INDEX idx_reference_range_id (reference_range_id),
  INDEX idx_changed_at (changed_at)
);

CREATE TABLE departments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  department_code VARCHAR(20) UNIQUE,
  department_name VARCHAR(100) NOT NULL,
  head_doctor_id INTEGER,
  contact_phone TEXT,
  location TEXT,
  is_active BOOLEAN DEFAULT 1,
  created_at DATETIME,
  updated_at DATETIME,
  
  FOREIGN KEY (head_doctor_id) REFERENCES users(id)
);

CREATE TABLE instruments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  instrument_code VARCHAR(20) UNIQUE,
  instrument_name VARCHAR(100) NOT NULL,
  manufacturer VARCHAR(100),
  model VARCHAR(50),
  serial_number VARCHAR(100),
  department_id INTEGER NOT NULL,
  installation_date DATE,
  last_calibration_date DATE,
  next_calibration_due DATE,
  status VARCHAR(20),                -- 'Active', 'Maintenance', 'Retired'
  created_at DATETIME,
  updated_at DATETIME,
  
  FOREIGN KEY (department_id) REFERENCES departments(id)
);

CREATE TABLE doctors (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  registration_number VARCHAR(50),
  specialization VARCHAR(100),
  department_id INTEGER,
  clinic_name TEXT,
  clinic_address TEXT,
  is_active BOOLEAN DEFAULT 1,
  
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (department_id) REFERENCES departments(id)
);
```

**Master Data Change Governance**:
- [ ] **Change Request Process**: Admin submits change, documents reason
- [ ] **Approval Required**: Changes approved by authorized users before applying
- [ ] **Effective Date**: Changes don't apply retroactively (set effective date)
- [ ] **Version Tracking**: Every version of master data tracked
- [ ] **History Retention**: Never delete master data history
- [ ] **Impact Analysis**: Understand which results/reports affected by change
- [ ] **Audit Trail**: All changes logged to audit_logs table

**Example - Reference Range Change**:
```
Reference Range: Hemoglobin (Male)
Changed by: Admin (admin@lab.com)
Change Date: 2026-06-05 10:00 AM

Old Range: 13.0 - 17.0 g/dL
New Range: 11.5 - 15.5 g/dL

Effective Date: 2026-06-10 (gives time to communicate)
Change Reason: Updated per WHO 2024 guidelines

Audit Entry:
Action: REFERENCE_RANGE_UPDATED
Entity: reference_ranges
Old Value: {"min": 13.0, "max": 17.0}
New Value: {"min": 11.5, "max": 15.5}
Timestamp: 2026-06-05 10:00 AM
User: admin@lab.com
```

---

## 🟢 TIER 3: RECOVERY TESTING, OFFLINE RESILIENCE & PERFORMANCE

### Database Recovery Testing

A backup is only useful if it can be restored. Implement a **quarterly testing schedule**.

```
Recovery Testing Checklist
─────────────────────────

□ Q1 (Jan-Mar)
  □ Restore backup from 3 months ago (Oct)
  □ Verify all tables present
  □ Verify data integrity (row counts, checksums)
  □ Restore latest daily backup from yesterday
  □ Perform smoke tests (patient search, report generation)
  □ Document test results
  
□ Q2 (Apr-Jun)
  □ Restore backup from 6 months ago (Dec)
  □ Verify audit logs intact (immutability check)
  □ Restore 1-week-old backup
  □ Verify reference ranges restored correctly
  □ Document test results

□ Q3 (Jul-Sep)
  □ Restore backup from 9 months ago (Sep)
  □ Verify encryption/decryption
  □ Simulate data corruption recovery
  □ Document test results

□ Q4 (Oct-Dec)
  □ Restore backup from 12 months ago (Dec previous year)
  □ Full end-to-end recovery drill
  □ Test failover to backup database
  □ Document test results
```

- [ ] **Quarterly Restore Test**: Documented and scheduled
- [ ] **Test Evidence**: Screenshot/log of successful restore
- [ ] **Restore Time Measured**: Document how long restore takes
- [ ] **Data Verification**: Checksums or row counts compared before/after
- [ ] **Recovery Runbook**: Step-by-step restore procedure documented
- [ ] **Recovery Time Objective (RTO)**: Target restore time defined (e.g., < 2 hours)
- [ ] **Recovery Point Objective (RPO)**: Maximum data loss acceptable (e.g., < 24 hours)

**Recovery Testing Automation**:
```dart
// test/integration/backup_recovery_test.dart
void main() {
  group('Backup & Recovery', () {
    test('Weekly backup can be restored successfully', () async {
      // Create backup
      final backup = await BackupService.createBackup();
      expect(backup.success, true);
      
      // Verify backup integrity
      final integrity = await BackupService.verifyBackup(backup.path);
      expect(integrity.valid, true);
      
      // Restore from backup
      final restore = await BackupService.restoreFromBackup(backup.path);
      expect(restore.success, true);
      
      // Verify restored data
      final patientCount = await PatientRepository.countAll();
      expect(patientCount, equals(originalCount));
    });
  });
}
```

---

### Offline Resilience for Windows Desktop

Since this is a **local Windows desktop application**, database corruption and network issues are real concerns.

```sql
-- Transaction safety
BEGIN TRANSACTION;
  UPDATE results SET status = 'Approved' WHERE id = 123;
  INSERT INTO audit_logs (action, entity_type, ...) VALUES ('RESULT_APPROVED', 'Result', ...);
COMMIT;  -- All or nothing

-- Rollback on error
BEGIN TRANSACTION;
  UPDATE results SET status = 'Approved' WHERE id = 123;
  -- Error occurs during insert
  INSERT INTO audit_logs ...;  -- FAILS
ROLLBACK;  -- Results update also rolled back
```

**Offline Resilience Checklist**:
- [ ] **Transaction Management**: All critical operations wrapped in transactions
  - [ ] ACID properties enforced
  - [ ] Rollback tested on failure
- [ ] **Database Corruption Handling**:
  - [ ] SQLite integrity check: `PRAGMA integrity_check`
  - [ ] Recovery procedure if corruption detected
  - [ ] Automatic recovery attempt before manual intervention
  - [ ] User notification if database corrupted
- [ ] **Automatic Local Backups**:
  - [ ] Backup on app startup
  - [ ] Backup before major operations (report generation, result approval)
  - [ ] Backup after successful result entry
  - [ ] Last 7 days of hourly backups retained
- [ ] **Recovery Mode**:
  - [ ] Detect corruption on app start
  - [ ] Offer recovery option (restore from latest backup)
  - [ ] Guided recovery process for non-technical users
  - [ ] Fall-back to manual administrator recovery if auto-recovery fails
- [ ] **Transaction Rollback**:
  - [ ] Explicit rollback on exception
  - [ ] No partial updates in database
  - [ ] Clear user feedback: "Operation failed, database unchanged"
- [ ] **Data Consistency Checks**:
  - [ ] Foreign key constraints enforced
  - [ ] Orphaned records check on startup
  - [ ] Data validation on every insert/update

**Implementation Example**:
```dart
// core/database/database_recovery.dart
class DatabaseRecoveryService {
  Future<void> checkDatabaseIntegrity() async {
    try {
      final result = await database.rawQuery('PRAGMA integrity_check');
      if (result.isNotEmpty && result.first['integrity_check'] != 'ok') {
        throw DatabaseCorruptionException('Database integrity check failed');
      }
    } on DatabaseCorruptionException {
      await _handleCorruption();
    }
  }
  
  Future<void> _handleCorruption() async {
    // Log corruption event
    await AuditService.log(AuditEvent(
      action: 'DATABASE_CORRUPTION_DETECTED',
      timestamp: DateTime.now(),
    ));
    
    // Attempt auto-recovery
    final backup = await BackupService.getLatestBackup();
    if (backup != null) {
      await BackupService.restoreFromBackup(backup.path);
      Logger.info('Database recovered from backup');
    } else {
      // Notify user and administrator
      throw RecoveryFailedException('No backup available for recovery');
    }
  }
  
  Future<void> executeWithTransaction(Future Function() operation) async {
    await database.transaction((txn) async {
      try {
        await operation();
      } catch (e) {
        // Transaction automatically rolled back on exception
        throw OperationFailedException('Operation failed: $e');
      }
    });
  }
}

// Usage in repository
Future<Result<Patient>> createPatient(PatientRequest request) async {
  try {
    return await databaseRecoveryService.executeWithTransaction(() async {
      final patient = await _localDataSource.createPatient(request);
      await _auditService.log(AuditEvent.patientCreated(patient.id));
      return patient;
    });
  } catch (e) {
    return Failure(e.toString());
  }
}
```

---

### Large Dataset Performance Targets

Define **measurable, objective performance goals**. These become your performance audit criteria.

```
Performance SLA
═══════════════════════════════════════════════════════════

Operation                     Target        Threshold    Notes
──────────────────────────────────────────────────────────
Patient Search (by name)      < 1 second    p95: 1.5s    Indexed on name field
Patient Search (by phone)     < 1 second    p95: 1.5s    Indexed on phone field
Patient List Load (50 items)  < 2 seconds   p95: 3s      Paginated
Open Patient Record           < 1 second    p95: 1.5s    Including history
Report Open (PDF)             < 2 seconds   p95: 3s      Cached, indexed access
PDF Generation                < 5 seconds   p95: 8s      Depends on complexity
Sample Tracking Display       < 2 seconds   p95: 3s      Real-time updates
Dashboard Load                < 3 seconds   p95: 5s      Multiple widgets
Result Entry Save             < 500ms       p95: 1s      Including audit log
Result Search (date range)    < 2 seconds   p95: 3s      Indexed on date fields
Backup Operation              < 30 seconds  p95: 60s     Depends on DB size
System Startup                < 5 seconds   p95: 10s     Database initialization
```

**Performance Verification Checklist**:
- [ ] **Baseline Measurements**: Performance tests run with 10,000+ patient records
- [ ] **Query Plan Analysis**: EXPLAIN QUERY PLAN reviewed for all queries
  - [ ] Full table scans eliminated where possible
  - [ ] Indexes used for WHERE clauses
  - [ ] JOIN operations optimized
- [ ] **Concurrent User Testing**: 5+ simultaneous users tested
  - [ ] No performance degradation
  - [ ] Database connections managed
- [ ] **Memory Profiling**: Long-running sessions (8+ hours) monitored
  - [ ] No memory leaks detected
  - [ ] Memory stable over time
- [ ] **Load Testing**: Simulate peak usage
  - [ ] High-volume result entry (100+ entries/minute)
  - [ ] Multiple concurrent report generations
  - [ ] Report printing stress test
- [ ] **Performance Monitoring**: Production metrics tracked
  - [ ] Slow query logging enabled
  - [ ] Performance metrics exported (Prometheus/OpenTelemetry)
  - [ ] Alerts on performance degradation

**Performance Test Implementation**:
```dart
// test/performance/patient_search_performance_test.dart
void main() {
  group('Performance Tests', () {
    test('Patient search by name with 10k records < 1 second', () async {
      // Setup: Create 10,000 patient records
      await _seedPatients(10000);
      
      // Measure search performance
      final stopwatch = Stopwatch()..start();
      final results = await patientRepository.searchByName('John');
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      expect(results, isNotEmpty);
    });
    
    test('Report PDF generation < 5 seconds', () async {
      final report = await reportRepository.getReport(reportId);
      
      final stopwatch = Stopwatch()..start();
      final pdfBytes = await reportGenerator.generatePdf(report);
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      expect(pdfBytes.isNotEmpty, true);
    });
  });
}
```

**Performance Optimization Priorities**:
1. **Indexing**: Add indexes to frequently queried fields
2. **Pagination**: Never load all records at once
3. **Caching**: Cache reference ranges, user data, master data
4. **Query Optimization**: Use EXPLAIN QUERY PLAN to optimize SQLite queries
5. **Lazy Loading**: Load data on-demand, not at startup

---

## Clean Architecture Structure
```
lib/
│
├── core/
│   ├── database/
│   │   ├── app_database.dart          # SQLite setup
│   │   ├── migrations/
│   │   └── schemas/
│   ├── services/
│   │   ├── audit_service.dart
│   │   ├── auth_service.dart
│   │   ├── backup_service.dart
│   │   ├── encryption_service.dart
│   │   └── database_recovery_service.dart
│   ├── utils/
│   │   ├── constants.dart
│   │   ├── validators.dart
│   │   └── logger.dart
│   └── di/
│       └── service_locator.dart       # get_it configuration
│
├── features/
│   ├── authentication/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   ├── models/
│   │   │   └── repositories/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   ├── repositories/
│   │   │   └── usecases/
│   │   └── presentation/
│   │       ├── bloc/ or controller/
│   │       ├── pages/
│   │       └── widgets/
│   │
│   ├── patients/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── laboratory/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── reports/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── users/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── dashboard/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   └── settings/
│       ├── data/
│       ├── domain/
│       └── presentation/
│
├── shared/
│   ├── models/
│   │   ├── error_model.dart
│   │   └── api_response.dart
│   ├── widgets/
│   │   ├── custom_dialogs.dart
│   │   ├── loading_indicators.dart
│   │   └── form_widgets.dart
│   └── themes/
│       └── app_theme.dart
│
└── main.dart
```

---

## Repository Pattern Implementation
- [ ] **Repository Interface**: Abstract interface in `domain/repositories/`
- [ ] **Repository Implementation**: Concrete implementation in `data/repositories/`
- [ ] **Data Source Abstraction**: `LocalDataSource` for SQLite, `RemoteDataSource` for APIs
- [ ] **No Direct Database Access**: All database calls through repository
- [ ] **Error Handling**: Repositories catch exceptions, return Result or Either type
- [ ] **Testing**: Repository logic testable with mock data sources

---

## Dependency Injection (DI)
- [ ] **get_it or riverpod Used**: NOT ServiceLocator or global singletons
- [ ] **Service Locator Configuration**: Centralized in `core/di/service_locator.dart`
- [ ] **Lazy Loading**: Services created on first use, not all at app startup
- [ ] **Testing Mode**: Ability to register mock implementations for testing

---

## Error Handling & Logging
- [ ] **Custom Exception Hierarchy**:
  ```dart
  abstract class AppException implements Exception {}
  class AuthenticationException extends AppException {}
  class DatabaseException extends AppException {}
  class ValidationException extends AppException {}
  ```
- [ ] **Try-Catch at Boundaries**: Data layer (database, APIs)
- [ ] **Result Type or Either**: Return `Result<T>` or `Either<Failure, T>` from repositories
- [ ] **Centralized Logging**: Structured logs with levels (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- [ ] **Medical-Sensitive Data NOT Logged**: Patient names, IDs masked if logged
- [ ] **Error Display**: User-friendly messages without technical details

---

## 🧪 PATHOLOGY-SPECIFIC FEATURES

### Reference Range Management
- [ ] **Age & Gender-Specific Ranges**: Different ranges for different demographics
- [ ] **Automatic Abnormality Highlighting**: UI flags values outside range
- [ ] **Reference Range Versioning**: Track changes over time
- [ ] **Critical Value Flags**: Special marker for values requiring immediate attention
- [ ] **Admin Interface**: Easily add/update reference ranges

### Critical Value Alerts
- [ ] **Critical Values Defined** (examples):
  - [ ] Glucose < 40 or > 400 mg/dL
  - [ ] Potassium < 2.5 or > 6.5 mmol/L
  - [ ] Platelet < 20,000/µL
- [ ] **Alert Workflow**:
  - [ ] Modal/popup displays critical value warning
  - [ ] Pathologist must confirm acknowledgment
  - [ ] Confirmation logged in audit trail
- [ ] **Critical Value Reports**: Generate daily/weekly list for review

### Barcode Support
- [ ] **Barcode Entities**: Patient ID, Sample, Report, Invoice
- [ ] **Barcode Format**: Code128 or QR code (QR preferred)
- [ ] **Barcode Scanning Integration**: Reduces manual data entry errors
- [ ] **Barcode Generation**: System generates unique barcodes on entity creation

### Sample Tracking
- [ ] **Sample States**: Collected → Received → Processing → Completed → Reported
- [ ] **Timestamps**: Each state transition timestamped and logged
- [ ] **Status Dashboard**: Visual timeline of sample journey

---

## 📊 REPORTING & PDF GENERATION

### PDF Report Features
- [ ] **Locked Template**: Report layout fixed
- [ ] **Unique Report Number**: REP-2026-000145
- [ ] **QR Verification Code**: Encodes report ID, patient ID, issue date
- [ ] **Digital Signature**: PDF signed with lab private key (optional)
- [ ] **Watermark**: "DRAFT" on unapproved, "FINAL" on approved
- [ ] **Print Date**: Printed-at timestamp on physical copies

---

## 🧪 TESTING TARGETS

| Module | Coverage | Notes |
|--------|----------|-------|
| Business Logic (Use Cases) | 90%+ | Core calculation, validations |
| Repository Layer | 80%+ | Data source interactions |
| Database Layer | 80%+ | SQL queries, migrations |
| Report Generation | 90%+ | PDF templates, formatting |
| RBAC/Authorization | 90%+ | Permission checks, role transitions |
| Audit Service | 90%+ | All audit events logged |
| Result Workflow | 90%+ | State transitions, approvals |
| UI/Presentation | 50-60% | Critical flows, user interactions |

---

## 📋 HIGH-RISK AREAS (Priority Review)

These areas warrant extra scrutiny during code reviews:

1. **Patient Data Security** ⚠️
   - Encryption implementation
   - No plaintext passwords
   - SQL injection prevention

2. **Audit Logging (INSERT-ONLY)** ⚠️
   - All required events captured
   - **Audit logs immutable (no UPDATE/DELETE)**
   - Triggers prevent modification
   - Timestamps accurate

3. **Result Approval Workflow** ⚠️
   - State machine correctly enforced
   - No skipped states possible
   - Approval always by different user

4. **Backup & Recovery** ⚠️
   - Backup process tested quarterly
   - Restoration verified
   - Encryption correct

5. **Report Integrity** ⚠️
   - Reports read-only after approval
   - Amendment process maintains original
   - Version history complete

6. **Master Data Governance** ⚠️
   - Reference range changes tracked
   - Effective dates managed
   - History retained

7. **Role-Based Access** ⚠️
   - All sensitive operations check RBAC
   - No role bypass paths
   - Permission matrix enforced

8. **Database Recovery** ⚠️
   - Recovery testing quarterly documented
   - RTO/RPO defined and tested
   - Runbook available

9. **Offline Resilience** ⚠️
   - Transaction management tested
   - Database corruption handling
   - Auto-backup functional

10. **Performance** ⚠️
    - Query plans optimized
    - Indexes used correctly
    - Performance baselines established

---

## 🚀 PRODUCTION READINESS CHECKLIST

Before going live:

### Security
- [ ] All Tier 1 security measures implemented
- [ ] Penetration testing completed (if resources available)
- [ ] Password policy enforced
- [ ] Session timeout tested
- [ ] Backup encryption verified

### Data Integrity
- [ ] Workflow state machine tested end-to-end
- [ ] Amendment process verified
- [ ] Audit logs comprehensive and immutable
- [ ] Database constraints enforced
- [ ] Result versioning functional

### Performance
- [ ] Load testing with 10,000+ patient records
- [ ] Report generation time < 5 seconds
- [ ] Patient search response < 1 second
- [ ] Concurrent user testing (5+ simultaneous users)
- [ ] Memory profiling complete (no leaks)

### Backup & Recovery
- [ ] Daily automatic backup functional
- [ ] Weekly full backup verified
- [ ] **Quarterly restore test completed** ✅
- [ ] Recovery time measured and acceptable
- [ ] Backup encryption verified

### Operations
- [ ] Admin dashboard shows system health
- [ ] Error monitoring in place
- [ ] User manual and admin guide complete
- [ ] Recovery runbook documented
- [ ] Support contact information visible

### Compliance
- [ ] HIPAA/local regulations reviewed
- [ ] Data retention policy documented
- [ ] Privacy policy in place
- [ ] Terms of service finalized
- [ ] Audit log retention policy enforced

---

## 📅 AUDIT CADENCE

### Weekly
- [ ] Code review checklist applied to all PRs
- [ ] Failing tests investigated
- [ ] Performance metrics reviewed

### Monthly
- [ ] Audit log review (sample check for integrity)
- [ ] Database optimization (indexes, statistics)
- [ ] Security update checks
- [ ] Critical value thresholds reviewed

### Quarterly
- [ ] **Database backup restoration test** ✅
- [ ] Full security audit
- [ ] Test coverage report
- [ ] Capacity planning (database size growth)
- [ ] Performance baseline comparison

### Annually
- [ ] Penetration testing
- [ ] Compliance audit (HIPAA/regulations)
- [ ] Architecture review
- [ ] Master data governance review

---

## 🔗 Related Documentation

- [Database Schema Specification](DATABASE_SCHEMA.md) *(to be created)*
- [Audit Logging Specification](AUDIT_LOGGING.md) *(to be created)*
- [Recovery Procedures](RECOVERY_PROCEDURES.md) *(to be created)*
- [Performance Testing Guide](PERFORMANCE_TESTING.md) *(to be created)*
- [Backup Strategy](BACKUP_STRATEGY.md) *(to be created)*
- [Report Template Design](REPORT_TEMPLATES.md) *(to be created)*
- [API & Repository Interfaces](API_SPECIFICATION.md) *(to be created)*
- [Testing Strategy](TESTING_STRATEGY.md) *(to be created)*

---

## 📌 CRITICAL SUCCESS FACTORS

For a real-world pathology system, focus on these areas first:

1. ✅ **Audit Logging (INSERT-ONLY)** - Foundation for compliance and troubleshooting
2. ✅ **Result Approval Workflow** - Prevents erroneous reports
3. ✅ **Report Immutability** - Protects data integrity
4. ✅ **Backup/Recovery** - Business continuity essential
5. ✅ **Role-Based Permissions** - Data access control
6. ✅ **Database Recovery** - Tested and verified
7. ✅ **Master Data Governance** - Ensures consistent reference ranges

If these seven areas are implemented rigorously, your system will be **significantly more reliable and suitable for real-world laboratory operations**.

---

**Questions or updates?** File an issue or contact the architecture team.
