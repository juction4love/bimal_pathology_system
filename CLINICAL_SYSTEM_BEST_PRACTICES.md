# 🔄 Clinical System - Result Versioning & Data Governance

> **भाषा / Language**: Nepali (नेपाली) + English  
> **Purpose**: Pathology System मा सही तरिका से Version Management  
> **Last Updated**: 2026-06-05

---

## 🔄 २. Result Versioning (रिपोर्ट संस्करण व्यवस्थापन)

### समस्या - गलत तरिका (❌ Wrong Way)

```
पुरानो रिपोर्ट सिधै परिवर्तन गरिन्छ
↓
मूल डेटा हराउँछ
↓
Compliance समस्या
↓
अडिट ट्रेल खोजिन्छ
```

**उदाहरण - गलत तरिका**:
```
REP-2026-000145
Hemoglobin: 14.2 g/dL  [v1]

अब Pathologist ले सुधार गर्छन्:
DELETE मूल डेटा
INSERT नयाँ डेटा

Hemoglobin: 14.5 g/dL  [अब कुनै proof छैन कि यो कहिले सुधारिएको हो]
```

❌ समस्या:
- पुरानो value खोजिन्छ
- कसले सुधार गर्यो भन्ने प्रमाण नाइ
- रिपोर्ट चेन्ज गरिएको मामिला छुप्य हुन्छ

---

### समाधान - सही तरिका (✅ Right Way)

```
REP-2026-000145
├── Version 1 (Approved)
│   ├── Date: 2026-06-05 09:00 AM
│   ├── By: Dr. Ramesh Kumar
│   ├── Hemoglobin: 14.2 g/dL
│   └── Status: FINAL
│
├── Version 2 (Corrected)
│   ├── Date: 2026-06-05 14:30 PM
│   ├── By: Dr. Anita Singh
│   ├── Reason: "Reference range को आधारमा सुधार"
│   ├── Hemoglobin: 14.5 g/dL
│   └── Status: FINAL
│
└── Version 3 (Amended)
    ├── Date: 2026-06-06 10:15 AM
    ├── By: Dr. Priya Sharma
    ├── Reason: "Patient DOB error - manually corrected"
    ├── Hemoglobin: 14.2 g/dL (मूल value फिर्ता)
    └── Status: FINAL
```

✅ लाभ:
- सबै versions सुरक्षित रहे
- कसले, कहिले, किन परिवर्तन गर्यो भन्ने पूर्ण trail छ
- पुरानो डेटा कहिल्यै हराउँदैन
- Compliance requirement पूरा हुन्छ

---

### Database Schema - Version Management

```sql
-- मूल Result Table
CREATE TABLE results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sample_id INTEGER NOT NULL,
  test_id INTEGER NOT NULL,
  value DECIMAL(10, 2),
  unit VARCHAR(20),
  status VARCHAR(20),                -- 'Draft', 'Approved'
  entered_by INTEGER,
  approved_by INTEGER,
  approved_at DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  
  FOREIGN KEY (sample_id) REFERENCES samples(id),
  FOREIGN KEY (test_id) REFERENCES test_definitions(id),
  FOREIGN KEY (entered_by) REFERENCES users(id),
  FOREIGN KEY (approved_by) REFERENCES users(id)
);

-- Amendment History Table
CREATE TABLE result_amendments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  original_result_id INTEGER NOT NULL,    -- पुरानो result को ID
  amended_result_id INTEGER NOT NULL,     -- नयाँ result को ID
  amendment_reason TEXT,                  -- किन सुधार गरिएको
  amended_by INTEGER NOT NULL,            -- कसले सुधार गर्यो
  amended_at DATETIME DEFAULT CURRENT_TIMESTAMP,  -- कहिले सुधार गर्यो
  amendment_approved_by INTEGER,          -- Pathologist को approval
  amendment_approved_at DATETIME,
  
  FOREIGN KEY (original_result_id) REFERENCES results(id),
  FOREIGN KEY (amended_result_id) REFERENCES results(id),
  FOREIGN KEY (amended_by) REFERENCES users(id),
  FOREIGN KEY (amendment_approved_by) REFERENCES users(id)
);

-- Report Versioning
CREATE TABLE reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  report_number VARCHAR(50) UNIQUE,       -- REP-2026-000145
  sample_id INTEGER NOT NULL,
  version INTEGER DEFAULT 1,              -- Version 1, 2, 3...
  status VARCHAR(20),                     -- 'Draft', 'Final', 'Amended'
  generated_by INTEGER,
  generated_at DATETIME,
  approved_by INTEGER,
  approved_at DATETIME,
  pdf_file_path TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  
  FOREIGN KEY (sample_id) REFERENCES samples(id),
  FOREIGN KEY (generated_by) REFERENCES users(id),
  FOREIGN KEY (approved_by) REFERENCES users(id),
  
  INDEX idx_report_number (report_number),
  INDEX idx_version (version)
);

-- Report Amendment History
CREATE TABLE report_amendments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  original_report_id INTEGER NOT NULL,    -- पहिलो report
  amended_report_id INTEGER NOT NULL,     -- नयाँ (amended) report
  amendment_reason TEXT,                  -- किन सुधार गरिएको
  amended_by INTEGER NOT NULL,            -- कसले सुधार गर्यो
  amended_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  
  FOREIGN KEY (original_report_id) REFERENCES reports(id),
  FOREIGN KEY (amended_report_id) REFERENCES reports(id),
  FOREIGN KEY (amended_by) REFERENCES users(id)
);
```

---

### Implementation - Dart/Flutter Example

```dart
// ✅ Correct Way - Never Modify Original

class ResultRepository {
  final AuditService _auditService;
  final DatabaseService _database;

  // Original result approved
  Future<Result<TestResult>> approveResult(int resultId, int pathologistId) async {
    try {
      return await _database.transaction((txn) async {
        // Update original result to 'Approved' (allow only once)
        await txn.update(
          'results',
          {'status': 'Approved', 'approved_by': pathologistId, 'approved_at': DateTime.now()},
          where: 'id = ?',
          whereArgs: [resultId],
        );

        // Log to audit
        await _auditService.log(AuditEvent(
          action: 'RESULT_APPROVED',
          entityType: 'Result',
          entityId: resultId,
          userId: pathologistId,
          timestamp: DateTime.now(),
        ));

        return Right(result);
      });
    } catch (e) {
      return Left(DatabaseFailure(e.toString()));
    }
  }

  // नयाँ Amendment बनाउनु - Original परिवर्तन नगरी
  Future<Result<TestResult>> amendResult({
    required int originalResultId,
    required DECIMAL newValue,
    required String reason,
    required int amendedByUserId,
  }) async {
    try {
      return await _database.transaction((txn) async {
        // 1. नयाँ result record बनाउनु (original को copy)
        final originalResult = await txn.query(
          'results',
          where: 'id = ?',
          whereArgs: [originalResultId],
        );

        final newResultData = originalResult.first;
        newResultData['value'] = newValue;
        newResultData['status'] = 'Approved';
        newResultData['approved_by'] = amendedByUserId;
        newResultData['approved_at'] = DateTime.now();

        // 2. नयाँ result insert गर्नु
        final newResultId = await txn.insert('results', newResultData);

        // 3. Amendment trail बनाउनु (audit)
        await txn.insert('result_amendments', {
          'original_result_id': originalResultId,
          'amended_result_id': newResultId,
          'amendment_reason': reason,
          'amended_by': amendedByUserId,
          'amended_at': DateTime.now(),
        });

        // 4. Audit log मा दर्ता गर्नु
        await _auditService.log(AuditEvent(
          action: 'RESULT_AMENDED',
          entityType: 'Result',
          entityId: originalResultId,
          userId: amendedByUserId,
          oldValue: jsonEncode({'value': originalResult.first['value']}),
          newValue: jsonEncode({'value': newValue}),
          metadata: {'reason': reason},
          timestamp: DateTime.now(),
        ));

        return Right(amendedResult);
      });
    } catch (e) {
      return Left(DatabaseFailure(e.toString()));
    }
  }

  // ❌ यस्तो method कहिल्यै नहुनुपर्छ:
  // Future<void> updateApprovedResult() {} // DON'T ADD THIS
  // Future<void> deleteResult() {}         // DON'T ADD THIS
}

// Usage Example
void main() async {
  final resultRepo = ResultRepository();

  // 1. नयाँ result approve गर्नु
  await resultRepo.approveResult(resultId: 123, pathologistId: 5);

  // 2. Later, amendment गर्नु (original परिवर्तन हुँदैन)
  await resultRepo.amendResult(
    originalResultId: 123,
    newValue: 14.5,
    reason: 'Reference range को आधारमा सुधार गरिएको',
    amendedByUserId: 6,
  );
  
  // Database मा दुबै values सुरक्षित रहे
  // Result #123 - Version 1: 14.2 g/dL (Original)
  // Result #123 - Version 2: 14.5 g/dL (Amended)
}
```

---

### Version Display - UI

```
चिकित्सा रिपोर्ट (Medical Report)
════════════════════════════════════════

रिपोर्ट क्रमांक: REP-2026-000145
रोगी: राज कुमार शर्मा
परीक्षण: Hemoglobin

📋 संस्करण इतिहास (Version History)
────────────────────────────────────

✅ Version 1 - मूल (Original)
   तारिख: 2026-06-05 09:00 AM
   परीक्षक: Dr. Ramesh Kumar
   मान: 14.2 g/dL
   स्थिति: अनुमोदित (Approved)
   
   
✏️ Version 2 - सुधारिएको (Corrected)
   तारिख: 2026-06-05 14:30 PM
   परीक्षक: Dr. Anita Singh
   कारण: "Reference range अपडेट"
   मान: 14.5 g/dL
   स्थिति: अनुमोदित
   
   
📝 Version 3 - संशोधित (Amended)
   तारिख: 2026-06-06 10:15 AM
   परीक्षक: Dr. Priya Sharma
   कारण: "रोगी DOB सुधार गरिएको"
   मान: 14.2 g/dL
   स्थिति: अनुमोदित
```

---

## 🏛️ ३. Master Data Governance (मास्टर डेटा व्यवस्थापन)

### समस्या - गलत तरिका (❌ Wrong Way)

```
पहिले:
Reference Range - Hemoglobin: 12-16 g/dL

अब सिधै परिवर्तन:
Reference Range - Hemoglobin: 11.5-15.5 g/dL

समस्या:
- पुरानो value खोजिन्छ
- कसले परिवर्तन गर्यो भन्ने खबर नै नाइ
- पुरानो डेटा को आधारमा approve गरिएको reports अब गलत हुन्छ
```

### समाधान - सही तरिका (✅ Right Way)

```
Master Data Changes को पूर्ण History रखनु

Hemoglobin Reference Range
════════════════════════════════════════

पहिले: 12-16 g/dL
परिवर्तन: 2026-06-05 10:00 AM
परिवर्तन गर्ने: Admin (admin@lab.com)
कारण: "WHO 2024 guidelines अनुसार"
प्रभाव: 2026-06-10 देखि लागू

अब: 11.5-15.5 g/dL
════════════════════════════════════════

पुरानो Reports मा कोनै प्रभाव नपर्छ।
नयाँ Reports को लागि नयाँ reference range लागू हुन्छ।
```

---

### Master Data Types

```
१. Test Definitions
   - Hemoglobin
   - Red Blood Cell Count
   - White Blood Cell Count
   - Glucose
   
२. Reference Ranges
   - Age-wise ranges
   - Gender-wise ranges
   - Critical value thresholds
   
३. Departments
   - Laboratory
   - Pathology
   - Radiology
   
४. Instruments
   - Blood analyzer
   - Microscope
   - Calibration dates
   
५. Doctors
   - Registration Number
   - Specialization
   - Department
```

---

### Database Schema - Master Data History

```sql
-- Test Definition
CREATE TABLE test_definitions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  test_code VARCHAR(20) UNIQUE,       -- 'HB', 'RBC'
  test_name VARCHAR(100) NOT NULL,    -- 'Hemoglobin'
  unit VARCHAR(20),                   -- 'g/dL'
  is_active BOOLEAN DEFAULT 1,
  created_at DATETIME,
  updated_at DATETIME,
  updated_by INTEGER,
  
  FOREIGN KEY (updated_by) REFERENCES users(id)
);

-- Test Definition Change History (Insert-Only)
CREATE TABLE test_definitions_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  test_id INTEGER NOT NULL,
  old_value TEXT,                     -- JSON
  new_value TEXT,                     -- JSON
  changed_by INTEGER NOT NULL,        -- कसले परिवर्तन गर्यो
  changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  change_reason TEXT,                 -- किन परिवर्तन गर्यो
  
  FOREIGN KEY (test_id) REFERENCES test_definitions(id),
  FOREIGN KEY (changed_by) REFERENCES users(id),
  INDEX idx_test_id (test_id),
  INDEX idx_changed_at (changed_at)
);

-- Reference Range
CREATE TABLE reference_ranges (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  test_id INTEGER NOT NULL,
  age_group_min INTEGER DEFAULT 0,    -- age in years
  age_group_max INTEGER DEFAULT 999,
  gender CHAR(1),                     -- 'M', 'F', 'B'
  min_value DECIMAL(10, 4),           -- 11.5
  max_value DECIMAL(10, 4),           -- 15.5
  critical_low DECIMAL(10, 4),        -- Alert if below
  critical_high DECIMAL(10, 4),       -- Alert if above
  version_number INTEGER DEFAULT 1,
  effective_date DATE,                -- कहिले लागू हुन्छ
  is_active BOOLEAN DEFAULT 1,
  created_by INTEGER,
  updated_by INTEGER,
  created_at DATETIME,
  updated_at DATETIME,
  
  FOREIGN KEY (test_id) REFERENCES test_definitions(id),
  FOREIGN KEY (created_by) REFERENCES users(id),
  FOREIGN KEY (updated_by) REFERENCES users(id),
  INDEX idx_test_id (test_id),
  INDEX idx_effective_date (effective_date)
);

-- Reference Range History (Insert-Only)
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
  change_reason TEXT,                 -- किन परिवर्तन गर्यो
  changed_by INTEGER NOT NULL,        -- कसले परिवर्तन गर्यो
  changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,  -- कहिले
  
  FOREIGN KEY (reference_range_id) REFERENCES reference_ranges(id),
  FOREIGN KEY (changed_by) REFERENCES users(id),
  INDEX idx_reference_range_id (reference_range_id),
  INDEX idx_changed_at (changed_at)
);
```

---

### Implementation - Master Data Changes

```dart
// Master Data Change Management

class MasterDataService {
  final AuditService _auditService;
  final DatabaseService _database;

  // Reference Range को परिवर्तन (नयाँ version create गर्नु)
  Future<Result<void>> updateReferenceRange({
    required int referenceRangeId,
    required double newMin,
    required double newMax,
    required String changeReason,
    required int changedByUserId,
    required DateTime effectiveDate,
  }) async {
    try {
      return await _database.transaction((txn) async {
        // 1. पुरानो data fetch गर्नु
        final oldData = await txn.query(
          'reference_ranges',
          where: 'id = ?',
          whereArgs: [referenceRangeId],
        );

        final oldRecord = oldData.first;

        // 2. नयाँ version insert गर्नु
        await txn.insert('reference_ranges', {
          'test_id': oldRecord['test_id'],
          'age_group_min': oldRecord['age_group_min'],
          'age_group_max': oldRecord['age_group_max'],
          'gender': oldRecord['gender'],
          'min_value': newMin,
          'max_value': newMax,
          'version_number': (oldRecord['version_number'] ?? 0) + 1,
          'effective_date': effectiveDate.toIso8601String(),
          'is_active': true,
          'created_by': changedByUserId,
          'updated_by': changedByUserId,
          'created_at': DateTime.now().toIso8601String(),
        });

        // 3. History मा दर्ता गर्नु
        await txn.insert('reference_ranges_history', {
          'reference_range_id': referenceRangeId,
          'old_min': oldRecord['min_value'],
          'old_max': oldRecord['max_value'],
          'new_min': newMin,
          'new_max': newMax,
          'change_reason': changeReason,
          'changed_by': changedByUserId,
          'changed_at': DateTime.now().toIso8601String(),
        });

        // 4. Audit log मा दर्ता गर्नु
        await _auditService.log(AuditEvent(
          action: 'REFERENCE_RANGE_UPDATED',
          entityType: 'ReferenceRange',
          entityId: referenceRangeId,
          userId: changedByUserId,
          oldValue: jsonEncode({
            'min': oldRecord['min_value'],
            'max': oldRecord['max_value'],
          }),
          newValue: jsonEncode({
            'min': newMin,
            'max': newMax,
          }),
          metadata: {
            'reason': changeReason,
            'effectiveDate': effectiveDate.toString(),
          },
          timestamp: DateTime.now(),
        ));

        return Right(null);
      });
    } catch (e) {
      return Left(DatabaseFailure(e.toString()));
    }
  }

  // Master Data का सबै परिवर्तन को history देखनु
  Future<List<MasterDataChange>> getMasterDataChangeHistory({
    required String entityType,  // 'ReferenceRange', 'TestDefinition'
    required int days,
  }) async {
    final historyTable = entityType == 'ReferenceRange'
        ? 'reference_ranges_history'
        : 'test_definitions_history';

    final query = '''
      SELECT 
        *
      FROM $historyTable
      WHERE changed_at >= datetime('now', '-$days days')
      ORDER BY changed_at DESC
    ''';

    final results = await _database.rawQuery(query);
    return results.map((e) => MasterDataChange.fromMap(e)).toList();
  }
}

// Usage Example
void main() async {
  final masterDataService = MasterDataService();

  // Reference Range परिवर्तन गर्नु
  await masterDataService.updateReferenceRange(
    referenceRangeId: 42,
    newMin: 11.5,
    newMax: 15.5,
    changeReason: 'WHO 2024 guidelines अनुसार अपडेट',
    changedByUserId: 1,  // Admin
    effectiveDate: DateTime(2026, 6, 10),
  );

  // सबै परिवर्तन को history देखनु
  final changes = await masterDataService.getMasterDataChangeHistory(
    entityType: 'ReferenceRange',
    days: 30,
  );

  for (final change in changes) {
    print('${change.changedBy} ले ${change.changeReason} - ${change.changedAt}');
  }
}
```

---

## 🔧 ४. Database Recovery Testing (डेटाबेस रिकभरी परीक्षण)

### समस्या - गलत तरिका (❌ Wrong Way)

```
✅ हरेक दिन Backup बनाउँछौं
❌ कहिल्यै Restore test गर्दैनौं

नतिजा:
Backup existing छ
लेकिन काम गर्दैन
```

### समाधान - सही तरिका (✅ Right Way)

```
✅ हरेक दिन Backup बनाउँछौं
✅ हरेक ३ महिनामा Restore test गर्छौं
��� Restore काम गर्छ भन्ने documented छ
```

---

### Quarterly Testing Schedule

```
Q1 (Jan-Mar)
════════════════════════════════════
□ अक्टोबर को Backup restore गर्नु (3 महिना पुरानो)
□ सबै tables present छन् कि छैनन् भन्ने verify गर्नु
□ Data integrity check गर्नु (row counts, checksums)
□ कल को latest backup restore गर्नु
□ Smoke tests चलाउनु (patient search, report generation)
□ परीक्षण results दर्ता गर्नु

Q2 (Apr-Jun)
════════════════════════════════════
□ डिसेम्बर को Backup restore गर्नु (6 महिना पुरानो)
□ Audit logs intact छन् भन्ने verify गर्नु
□ 1 हप्ता पुरानो backup restore गर्नु
□ Reference ranges सही छन् भन्ने verify गर्नु
□ परीक्षण results दर्ता गर्नु

Q3 (Jul-Sep)
════════════════════════════════════
□ सेप्टेम्बर को Backup restore गर्नु (9 महिना पुरानो)
□ Encryption/Decryption verify गर्नु
□ Data corruption recovery simulate गर्नु
□ परीक्षण results दर्ता गर्नु

Q4 (Oct-Dec)
════════════════════════════════════
□ पछिलो बर्षको डिसेम्बर को Backup restore गर्नु (12 महिना)
□ Full end-to-end recovery drill गर्नु
□ Backup database मा failover test गर्नु
□ परीक्षण results दर्ता गर्नु
```

---

### Recovery Testing Checklist

```
RTO र RPO परिभाषित गर्नु:
────────────────────────────

RTO (Recovery Time Objective)
सिस्टम बिग्रियो भने कति समयमा पुनः सञ्चालनमा ल्याउनुपर्छ?

उदाहरण:
❌ गलत: "छिटो गर्नुपर्छ"
✅ सही: "६० मिनेट भन्दा कम"


RPO (Recovery Point Objective)
कति डेटा हराउन स्वीकार्य छ?

उदाहरण:
❌ गलत: "कुनै डेटा हराउन हुँदैन"
✅ सही: "अधिकतम २४ घण्टा को डेटा हराउन स्वीकार्य"
```

---

### Recovery Testing Implementation - Dart

```dart
// Recovery Testing Service

class BackupRecoveryService {
  final DatabaseService _database;
  final AuditService _auditService;

  // Backup बनाउनु
  Future<String> createBackup() async {
    try {
      final timestamp = DateTime.now().toIso8601String();
      final backupPath = '/backups/backup_$timestamp.db';

      // Database को copy बनाउनु
      await _database.backup(backupPath);

      // Audit log मा दर्ता गर्नु
      await _auditService.log(AuditEvent(
        action: 'BACKUP_CREATED',
        entityType: 'Backup',
        userId: 0,  // System
        metadata: {'backupPath': backupPath},
      ));

      return backupPath;
    } catch (e) {
      throw BackupException('Backup creation failed: $e');
    }
  }

  // Backup integrity verify गर्नु
  Future<bool> verifyBackupIntegrity(String backupPath) async {
    try {
      // Checksum verify गर्नु
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        return false;
      }

      // Database को sanity check गर्नु
      final tempDb = await _database.openCopy(backupPath);
      final result = await tempDb.rawQuery('PRAGMA integrity_check');

      await tempDb.close();

      if (result.isNotEmpty && result.first['integrity_check'] == 'ok') {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Backup restore गर्नु
  Future<bool> restoreFromBackup(String backupPath) async {
    try {
      // Backup की integrity check गर्नु
      final isValid = await verifyBackupIntegrity(backupPath);
      if (!isValid) {
        throw RecoveryException('Backup integrity check failed');
      }

      // Original database backup गर्नु
      final originalBackupPath = '/backups/pre_recovery_backup.db';
      await _database.backup(originalBackupPath);

      // Restore गर्नु
      await _database.restore(backupPath);

      // Audit log मा दर्ता गर्नु
      await _auditService.log(AuditEvent(
        action: 'DATABASE_RESTORED',
        entityType: 'Database',
        userId: 0,  // System
        metadata: {
          'restoredFrom': backupPath,
          'originalBackup': originalBackupPath,
        },
      ));

      return true;
    } catch (e) {
      throw RecoveryException('Restore failed: $e');
    }
  }

  // Quarterly recovery test गर्नु
  Future<RecoveryTestResult> runQuarterlyRecoveryTest({
    required String backupPath,
    required int quarter,
  }) async {
    final startTime = DateTime.now();

    try {
      // 1. Backup integrity check
      final isIntegrityOk = await verifyBackupIntegrity(backupPath);
      if (!isIntegrityOk) {
        return RecoveryTestResult(
          quarter: quarter,
          status: 'FAILED',
          reason: 'Backup integrity check failed',
          duration: DateTime.now().difference(startTime),
        );
      }

      // 2. Restore test
      await restoreFromBackup(backupPath);

      // 3. Data integrity verification
      final patientCount = await _database.query('SELECT COUNT(*) FROM patients');
      final resultCount = await _database.query('SELECT COUNT(*) FROM results');
      final auditLogCount = await _database.query('SELECT COUNT(*) FROM audit_logs');

      // 4. Smoke tests
      final smokeTestsPassed = await _runSmokeTests();

      final result = RecoveryTestResult(
        quarter: quarter,
        status: smokeTestsPassed ? 'PASSED' : 'FAILED',
        duration: DateTime.now().difference(startTime),
        dataVerification: {
          'patientCount': patientCount,
          'resultCount': resultCount,
          'auditLogCount': auditLogCount,
        },
      );

      // Audit log मा दर्ता गर्नु
      await _auditService.log(AuditEvent(
        action: 'RECOVERY_TEST_COMPLETED',
        entityType: 'RecoveryTest',
        userId: 0,
        metadata: {
          'quarter': quarter,
          'status': result.status,
          'duration': result.duration.toString(),
        },
      ));

      return result;
    } catch (e) {
      return RecoveryTestResult(
        quarter: quarter,
        status: 'ERROR',
        reason: e.toString(),
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  Future<bool> _runSmokeTests() async {
    try {
      // Patient search test
      final patients = await _database.query(
        'SELECT * FROM patients LIMIT 1',
      );

      // Report generation test
      final reports = await _database.query(
        'SELECT * FROM reports LIMIT 1',
      );

      return patients.isNotEmpty || reports.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}

// Test Execution
void main() async {
  final recoveryService = BackupRecoveryService();

  // Q1 Test
  final backupPath = '/backups/backup_2025_10_15.db';  // 3 months old

  final result = await recoveryService.runQuarterlyRecoveryTest(
    backupPath: backupPath,
    quarter: 1,
  );

  print('Q1 Recovery Test Result:');
  print('Status: ${result.status}');
  print('Duration: ${result.duration}');
  print('Data: ${result.dataVerification}');
}
```

---

## 💾 ५. Offline Resilience (अफलाइन रेजिलिन्स)

### समस्या - गलत तरिका (❌ Wrong Way)

```
Diagnostic Center मा:
- Internet समस्या हुन्छ
- Power failure हुन्छ
- Windows crash हुन्छ

नतिजा:
- डेटा हराउँछ
- Inconsistency बढ्छ
- Manual recovery सजिलो हुँदैन
```

### समाधान - सही तरिका (✅ Right Way)

```
Auto Backup
Transaction Safety
Corruption Detection
Automatic Recovery Mode
```

---

### Offline Resilience Features

```sql
-- Transaction Safety

BEGIN TRANSACTION;
  UPDATE results SET status = 'Approved' WHERE id = 123;
  INSERT INTO audit_logs (action, entity_type, ...) 
    VALUES ('RESULT_APPROVED', 'Result', ...);
COMMIT;

-- सबै गर्छ वा कुनै गर्दैन (All or Nothing)
-- अगर कुनै error हुयो भने सबै rollback हुन्छ
```

---

### Implementation

```dart
// Offline Resilience Service

class OfflineResilienceService {
  final DatabaseService _database;

  // Auto backup - App startup मा
  Future<void> autoBackupOnStartup() async {
    try {
      final timestamp = DateTime.now().toIso8601String();
      await _database.backup('/auto_backups/startup_$timestamp.db');
    } catch (e) {
      Logger.error('Startup backup failed: $e');
    }
  }

  // Database integrity check
  Future<bool> checkDatabaseIntegrity() async {
    try {
      final result = await _database.rawQuery('PRAGMA integrity_check');
      if (result.isNotEmpty && result.first['integrity_check'] == 'ok') {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Corruption handling - Auto recovery
  Future<void> handleDatabaseCorruption() async {
    try {
      Logger.error('Database corruption detected!');

      // Latest backup खोजनु
      final backupFile = await _getLatestBackup();
      if (backupFile == null) {
        throw RecoveryException('No backup available');
      }

      // Restore गर्नु
      await _database.restore(backupFile.path);

      Logger.info('Database recovered from backup');

      // User notification
      // showRecoveryDialog('Database was corrupted and has been recovered');
    } catch (e) {
      Logger.error('Recovery failed: $e');
      // Manual admin intervention required
    }
  }

  // Transaction with rollback
  Future<T> executeWithTransaction<T>(
    Future<T> Function() operation,
  ) async {
    try {
      return await _database.transaction((_) async {
        return await operation();
      });
    } catch (e) {
      // Automatically rolled back
      throw TransactionException('Operation failed: $e');
    }
  }

  Future<File?> _getLatestBackup() async {
    final backupDir = Directory('/auto_backups');
    final files = backupDir.listSync().whereType<File>();
    
    if (files.isEmpty) return null;

    return files.reduce((a, b) =>
      a.statSync().modified.isAfter(b.statSync().modified) ? a : b
    );
  }
}

// Usage
void main() async {
  final resilienceService = OfflineResilienceService();

  // App startup
  await resilienceService.autoBackupOnStartup();

  // Database integrity check
  final isHealthy = await resilienceService.checkDatabaseIntegrity();

  if (!isHealthy) {
    await resilienceService.handleDatabaseCorruption();
  }

  // Safe operation with transaction
  try {
    await resilienceService.executeWithTransaction(() async {
      // Result approve गर्नु + Audit log
      // दुवै साथ हुन्छ वा कुनै हुँदैन
    });
  } catch (e) {
    print('Operation failed, database unchanged');
  }
}
```

---

## ⚡ ६. Performance SLA (प्रदर्शन लक्ष्य)

### समस्या - गलत तरिका (❌ Wrong Way)

```
❌ "सिस्टम छिटो हुनुपर्छ"
❌ "Report जलदी खुल्नुपर्छ"
❌ "Dashboard भरिलो आउनुपर्छ"

समस्या:
- स्पष्ट परिभाषा छैन
- परीक्षण कसरी गर्ने भन्ने स्पष्ट नाइ
- Improvement measure गर्न सकिन्दैन
```

### समाधान - सही तरिका (✅ Right Way)

```
✅ Patient Search: १ सेकेन्ड भन्दा कम
✅ Report Open: २ सेकेन्ड भन्दा कम
✅ PDF Generation: ५ सेकेन्ड भन्दा कम
✅ Dashboard Load: ३ सेकेन्ड भन्दा कम

लाभ:
- স्पष्ट लक्ष्य छ
- परीक्षण गर्न सकिन्छ
- Improvement measure गर्न सकिन्छ
```

---

### Performance SLA Table

```
┌─────────────────────────────────┬──────────────┬────────────┐
│ काम (Operation)                 │ लक्ष्य (Target) │ थ्रेसहोल्ड    │
├─────────────────────────────────┼──────────────┼────────────┤
│ Patient Search (नाम से)          │ < 1 second   │ p95: 1.5s  │
│ Patient Search (फोन से)          │ < 1 second   │ p95: 1.5s  │
│ Patient List Load (50 items)    │ < 2 seconds  │ p95: 3s    │
│ Open Patient Record             │ < 1 second   │ p95: 1.5s  │
│ Report Open (PDF)               │ < 2 seconds  │ p95: 3s    │
│ PDF Generation                  │ < 5 seconds  │ p95: 8s    │
│ Sample Tracking Display         │ < 2 seconds  │ p95: 3s    │
│ Dashboard Load                  │ < 3 seconds  │ p95: 5s    │
│ Result Entry Save               │ < 500ms      │ p95: 1s    │
│ Result Search (date range)      │ < 2 seconds  │ p95: 3s    │
│ Backup Operation                │ < 30 seconds │ p95: 60s   │
│ System Startup                  │ < 5 seconds  │ p95: 10s   │
└─────────────────────────────────┴──────────────┴────────────┘
```

---

### Performance Testing Implementation

```dart
// Performance Testing

class PerformanceTestingService {
  final DatabaseService _database;
  final Stopwatch _stopwatch = Stopwatch();

  // Patient search performance
  Future<PerformanceResult> testPatientSearch(String query) async {
    _stopwatch.reset();
    _stopwatch.start();

    final results = await _database.query(
      'SELECT * FROM patients WHERE name LIKE ? LIMIT 50',
      whereArgs: ['%$query%'],
    );

    _stopwatch.stop();

    return PerformanceResult(
      operation: 'Patient Search',
      duration: _stopwatch.elapsedMilliseconds,
      expected: 1000,  // 1 second
      passed: _stopwatch.elapsedMilliseconds < 1000,
      resultCount: results.length,
    );
  }

  // Report generation performance
  Future<PerformanceResult> testReportGeneration(int reportId) async {
    _stopwatch.reset();
    _stopwatch.start();

    final report = await _database.query(
      'SELECT * FROM reports WHERE id = ?',
      whereArgs: [reportId],
    );

    final results = await _database.query(
      'SELECT * FROM results WHERE sample_id = ?',
      whereArgs: [report.first['sample_id']],
    );

    // PDF generation simulation
    // final pdfBytes = await generatePdf(report.first, results);

    _stopwatch.stop();

    return PerformanceResult(
      operation: 'Report Generation',
      duration: _stopwatch.elapsedMilliseconds,
      expected: 5000,  // 5 seconds
      passed: _stopwatch.elapsedMilliseconds < 5000,
    );
  }

  // Dashboard load performance
  Future<PerformanceResult> testDashboardLoad() async {
    _stopwatch.reset();
    _stopwatch.start();

    // Dashboard data collect गर्नु
    final totalPatients = await _database.rawQuery(
      'SELECT COUNT(*) as count FROM patients',
    );

    final todayResults = await _database.rawQuery(
      'SELECT COUNT(*) as count FROM results WHERE DATE(created_at) = DATE("now")',
    );

    final pendingApprovals = await _database.rawQuery(
      'SELECT COUNT(*) as count FROM results WHERE status = "Reviewed"',
    );

    _stopwatch.stop();

    return PerformanceResult(
      operation: 'Dashboard Load',
      duration: _stopwatch.elapsedMilliseconds,
      expected: 3000,  // 3 seconds
      passed: _stopwatch.elapsedMilliseconds < 3000,
    );
  }

  // Run all performance tests
  Future<List<PerformanceResult>> runAllPerformanceTests() async {
    final results = <PerformanceResult>[];

    results.add(await testPatientSearch('John'));
    results.add(await testReportGeneration(1));
    results.add(await testDashboardLoad());

    // Print results
    for (final result in results) {
      print('''
        Operation: ${result.operation}
        Duration: ${result.duration}ms
        Expected: ${result.expected}ms
        Status: ${result.passed ? '✅ PASS' : '❌ FAIL'}
      ''');
    }

    return results;
  }
}

// Performance Result Model
class PerformanceResult {
  final String operation;
  final int duration;
  final int expected;
  final bool passed;
  final int? resultCount;

  PerformanceResult({
    required this.operation,
    required this.duration,
    required this.expected,
    required this.passed,
    this.resultCount,
  });
}

// Usage
void main() async {
  final perfService = PerformanceTestingService();

  // Run baseline performance tests with 10,000 patient records
  final results = await perfService.runAllPerformanceTests();

  // Generate report
  generatePerformanceReport(results);
}
```

---

## 📋 Summary Checklist

```
२. Result Versioning
────────────────────
✅ Version history table बनाउनु
✅ Amendment table बनाउनु
✅ Original data कहिल्यै परिवर्तन नगर्नु
✅ सबै versions accessible हुनु

३. Master Data Governance
─────────────────────────
✅ Test definitions history रखनु
✅ Reference range changes track गर्नु
✅ Effective dates manage गर्नु
✅ पुरानो डेटा archive गर्नु

४. Database Recovery Testing
────────────────────────────
✅ RTO/RPO परिभाषित गर्नु
✅ हरेक 3 महिना Restore test गर्नु
✅ परीक्षण results documented गर्नु
✅ Recovery runbook तयार गर्नु

५. Offline Resilience
─────────────────────
✅ Auto backup implement गर्नु
✅ Transaction safety ensure गर्नु
✅ Corruption detection सेटअप गर्नु
✅ Automatic recovery system बनाउनु

६. Performance SLA
──────────────────
✅ सबै operations को लागि लक्ष्य निर्धारण गर्नु
✅ Performance tests automation गर्नु
✅ Baseline measurements दर्ता गर्नु
✅ Regular monitoring सेटअप गर्नु
```
