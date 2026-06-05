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

### Audit Trail (Comprehensive Logging)
Every action must be logged with:
- Timestamp (accurate to seconds)
- User ID
- Action type
- Entity affected (Patient ID, Report ID, etc.)
- Old value (if update)
- New value (if update)
- IP/Session info (if applicable)

**Minimum Audit Events**:
- [ ] **Patient Creation**: Who created, when, initial data
- [ ] **Patient Modification**: Who changed what, old vs. new values
- [ ] **Result Entry**: Who entered, test type, values
- [ ] **Result Review**: Who reviewed, approval status, feedback
- [ ] **Result Approval**: Who approved, timestamp, approval comments
- [ ] **Report Generation**: Report number, who generated, timestamp
- [ ] **Report Printing**: Who printed, how many copies, timestamp
- [ ] **Report Delivery**: Delivery method (patient, email, physical), timestamp
- [ ] **User Login/Logout**: All authentication events
- [ ] **User Role Changes**: Admin modified user role
- [ ] **System Configuration Changes**: Backup settings, reference ranges modified
- [ ] **Access Attempts**: Failed access attempts, permission denials

**Audit Log Storage**:
- [ ] Separate table/database from operational data
- [ ] Indexed by timestamp and user_id for fast queries
- [ ] Audit logs immutable (append-only, no deletions)
- [ ] Retention: Minimum 3 years (check local regulations)

---

## 🟡 TIER 2: STRONGLY RECOMMENDED

### Clean Architecture Structure
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
│   │   └── encryption_service.dart
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

**Rationale**:
- [ ] Feature-based structure scales with team size
- [ ] Clear separation: data layer (database/API), domain layer (business logic), presentation (UI)
- [ ] Easy to locate feature code
- [ ] Dependencies point inward (presentation → domain → data)

### Repository Pattern Implementation
- [ ] **Repository Interface**: Abstract interface in `domain/repositories/`
- [ ] **Repository Implementation**: Concrete implementation in `data/repositories/`
- [ ] **Data Source Abstraction**: `LocalDataSource` for SQLite, `RemoteDataSource` for APIs
- [ ] **No Direct Database Access**: All database calls through repository
- [ ] **Error Handling**: Repositories catch exceptions, return Result or Either type
- [ ] **Testing**: Repository logic testable with mock data sources

**Example (Patient Repository)**:
```dart
// domain/repositories/patient_repository.dart
abstract class PatientRepository {
  Future<Either<Failure, List<Patient>>> getPatients({int page = 1});
  Future<Either<Failure, Patient>> getPatientById(String id);
  Future<Either<Failure, Patient>> createPatient(PatientRequest request);
  Future<Either<Failure, Patient>> updatePatient(String id, PatientRequest request);
}

// data/repositories/patient_repository_impl.dart
class PatientRepositoryImpl implements PatientRepository {
  final PatientLocalDataSource _localDataSource;
  final AuditService _auditService;
  
  @override
  Future<Either<Failure, Patient>> createPatient(PatientRequest request) async {
    try {
      final patient = await _localDataSource.createPatient(request);
      await _auditService.log(AuditEvent.patientCreated(patient.id));
      return Right(patient);
    } catch (e) {
      return Left(DatabaseFailure(e.toString()));
    }
  }
}
```

- [ ] **Repositories Tested**: Unit tests for each repository

### Dependency Injection (DI)
- [ ] **get_it or riverpod Used**: NOT ServiceLocator or global singletons
- [ ] **Service Locator Configuration**: Centralized in `core/di/service_locator.dart`
- [ ] **Lazy Loading**: Services created on first use, not all at app startup
- [ ] **Testing Mode**: Ability to register mock implementations for testing
- [ ] **No Service Locator in Business Logic**: Inject dependencies via constructors

**Example (get_it setup)**:
```dart
// core/di/service_locator.dart
final getIt = GetIt.instance;

void setupServiceLocator() {
  // Core Services
  getIt.registerSingleton<AuthService>(AuthServiceImpl());
  getIt.registerSingleton<DatabaseService>(DatabaseServiceImpl());
  getIt.registerSingleton<AuditService>(AuditServiceImpl());
  getIt.registerSingleton<BackupService>(BackupServiceImpl());
  
  // Repositories
  getIt.registerSingleton<PatientRepository>(
    PatientRepositoryImpl(
      localDataSource: getIt<PatientLocalDataSource>(),
      auditService: getIt<AuditService>(),
    ),
  );
  
  // Use Cases
  getIt.registerSingleton<CreatePatientUseCase>(
    CreatePatientUseCase(getIt<PatientRepository>()),
  );
}
```

- [ ] **No Service Locator Leakage**: Business logic doesn't import `service_locator.dart`

### Error Handling & Logging
- [ ] **Custom Exception Hierarchy**:
  ```dart
  abstract class AppException implements Exception {}
  class AuthenticationException extends AppException {}
  class DatabaseException extends AppException {}
  class ValidationException extends AppException {}
  class NetworkException extends AppException {}
  ```
- [ ] **Try-Catch at Boundaries**: Data layer (database, APIs)
- [ ] **Result Type or Either**: Return `Result<T>` or `Either<Failure, T>` from repositories
- [ ] **Centralized Logging**:
  - [ ] Log levels: DEBUG, INFO, WARNING, ERROR, CRITICAL
  - [ ] Structured logs with fields: timestamp, level, logger_name, message, stack_trace
  - [ ] Medical-sensitive data NOT logged (patient names, IDs masked if logged)
- [ ] **Error Display**: User-friendly error messages without technical details
- [ ] **Crash Reporting**: Send critical errors to admin (via email or logging service)

---

## 🟢 TIER 3: PATHOLOGY-SPECIFIC ENHANCEMENTS

### Reference Range Management
- [ ] **Separate Reference Range Table**:
  ```
  TestReferenceRange {
    id
    test_name
    age_group_min (0 for all ages)
    age_group_max (999 for all ages)
    gender ('M', 'F', 'Both')
    min_value
    max_value
    unit
    created_by
    created_at
    modified_by
    modified_at
  }
  ```
- [ ] **Age & Gender-Specific Ranges**: Different ranges for different demographics
  - [ ] Hemoglobin: Male 13-17 g/dL, Female 12-15 g/dL
  - [ ] Pediatric ranges separate from adult
- [ ] **Automatic Abnormality Highlighting**: UI flags values outside range
- [ ] **Reference Range Versioning**: Track changes over time (medical guidelines update)
- [ ] **Critical Value Flags**: Special marker for values requiring immediate attention
- [ ] **Admin Interface**: Easily add/update reference ranges

### Critical Value Alerts
- [ ] **Critical Values Defined** (examples):
  - [ ] Glucose < 40 or > 400 mg/dL
  - [ ] Potassium < 2.5 or > 6.5 mmol/L
  - [ ] Platelet < 20,000/µL
  - [ ] Hemoglobin < 5 g/dL
  - [ ] Calcium < 6.5 mg/dL
  - [ ] Creatinine > 10 mg/dL
- [ ] **Alert Workflow**:
  - [ ] Result entry triggers check against critical values
  - [ ] Modal/popup displays critical value warning
  - [ ] Pathologist must confirm acknowledgment
  - [ ] Confirmation logged in audit trail
  - [ ] Optional: Immediate notification to clinician (email, SMS)
- [ ] **Critical Value Reports**: Generate daily/weekly list for review

### Barcode Support
- [ ] **Barcode Entities**:
  - [ ] Patient ID barcode (on registration card)
  - [ ] Sample barcode (on specimen tube/container)
  - [ ] Report barcode (on printed report)
  - [ ] Invoice barcode (on billing document)
- [ ] **Barcode Format**: Code128 or QR code (QR preferred for density)
- [ ] **Barcode Scanning Integration**:
  - [ ] Barcode scanner device connected to Windows desktop
  - [ ] Scan field auto-populated
  - [ ] Validation on scan (check barcode format)
  - [ ] Reduce manual data entry errors
- [ ] **Barcode Generation**: System generates unique barcodes on entity creation
- [ ] **Barcode Printing**: Barcodes included on reports and labels

### Sample Tracking Workflow
- [ ] **Sample States & Timestamps**:
  ```
  Sample {
    id (unique sample ID / barcode)
    patient_id
    test_type
    collected_at (timestamp)
    received_at (timestamp)
    processing_started_at (timestamp)
    completed_at (timestamp)
    reported_at (timestamp)
    current_status ('Collected', 'Received', 'Processing', 'Completed', 'Reported')
  }
  ```
- [ ] **Status Transitions Logged**: Every status change tracked with timestamp & user
- [ ] **Receptionist Marks as Received**: Confirms sample received from patient
- [ ] **Lab Technician Starts Processing**: Updates status to Processing
- [ ] **Results Completed**: Lab technician marks results complete
- [ ] **Report Generated**: Automatic update to Reported on report generation
- [ ] **Dashboard View**: Visual timeline showing sample journey

### Reference Range Management (Reference Values)
- [ ] **Test Results Display**:
  ```
  Test: Hemoglobin
  Result: 14.2 g/dL
  Reference Range: 13-17 g/dL (Male)  [or 12-15 g/dL (Female)]
  Status: NORMAL ✓
  
  Test: Glucose
  Result: 45 mg/dL
  Reference Range: 70-100 mg/dL
  Status: CRITICAL LOW ⚠️ (Requires confirmation)
  ```
- [ ] **Automatic Flagging**: RED for abnormal, YELLOW for critical, GREEN for normal
- [ ] **Notes on Abnormal Values**: Pathologist can add clinical notes

---

## 📊 REPORTING & PDF GENERATION

### PDF Report Structure
- [ ] **Locked Template**: Report layout fixed, cannot be modified by users
- [ ] **Unique Report Number**: Sequential or UUID (REP-2026-000145)
- [ ] **Header Information**:
  - [ ] Lab name & logo
  - [ ] Unique report number
  - [ ] Issue date & time
  - [ ] Pathologist name & signature
- [ ] **Patient Section**:
  - [ ] Patient name, ID, DOB
  - [ ] Gender, age
  - [ ] Contact information
- [ ] **Sample Information**:
  - [ ] Sample ID / barcode
  - [ ] Collection date/time
  - [ ] Received date/time
- [ ] **Results Section**:
  - [ ] Test name
  - [ ] Result value
  - [ ] Unit
  - [ ] Reference range
  - [ ] Abnormal flag (if applicable)
  - [ ] Notes/comments
- [ ] **Footer**:
  - [ ] Lab address & contact
  - [ ] QR verification code
  - [ ] Confidentiality notice
  - [ ] Disclaimer
- [ ] **QR Verification Code**: Encodes report ID, patient ID, issue date
- [ ] **Digital Signature**: PDF signed with lab private key (optional but recommended)
- [ ] **Watermark**: "DRAFT" on unapproved reports, "FINAL" on approved
- [ ] **Print Date**: Printed-at timestamp on physical copies

### Report Versioning & Amendment
- [ ] **Amendment Reason Visible**: Report shows "Amended - Reference range updated"
- [ ] **Both Versions Available**: Original & amended accessible from report history
- [ ] **Version Number**: Report #123 v1, Report #123 v2, etc.
- [ ] **Amendment Audit**: Amendment reason, date, and approver logged

---

## ⚡ PERFORMANCE REQUIREMENTS

### Database Indexing
- [ ] **Primary Indexes Created**:
  ```sql
  CREATE INDEX idx_patient_id ON results(patient_id);
  CREATE INDEX idx_mobile ON patients(mobile_number);
  CREATE INDEX idx_report_number ON reports(report_number);
  CREATE INDEX idx_sample_date ON samples(collected_at);
  CREATE INDEX idx_created_at ON patients(created_at);
  CREATE INDEX idx_user_id ON audit_logs(user_id);
  CREATE INDEX idx_audit_timestamp ON audit_logs(created_at);
  ```
- [ ] **Query Optimization**: Avoid full table scans
- [ ] **Foreign Key Indexes**: Indexed for join performance

### Pagination & Data Loading
- [ ] **Patient List Pagination**: LIMIT 50 OFFSET 0
  - [ ] Default: 50 items per page
  - [ ] User can configure (25, 50, 100 per page)
- [ ] **Results List**: Paginated by report/date range
- [ ] **Lazy Loading**: Load data on-demand, not all at startup
- [ ] **Caching**: Cache reference ranges, user roles, frequently accessed data
- [ ] **Search Optimization**: Indexed search fields (patient name, phone, ID)

### Memory & UI Responsiveness
- [ ] **Async Operations**: Long-running tasks (PDF generation, backup) off main thread
- [ ] **Progress Indicators**: Show progress on long operations (report generation)
- [ ] **No Freezing UI**: Responsive even with large datasets
- [ ] **Memory Profiling**: Monitor memory usage in long sessions
- [ ] **Database Connection Pooling**: Connection management for concurrent operations

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
| UI/Presentation | 50-60% | Critical flows, user interactions |
| Result Workflow | 90%+ | State transitions, approvals |

### Test Types Recommended
- [ ] **Unit Tests**: Business logic, utilities, validators
- [ ] **Integration Tests**: Repository + database, workflow state machines
- [ ] **Widget Tests**: Form validation, permission-based UI visibility
- [ ] **E2E Tests** (if resources allow): Complete user workflows
  - [ ] Patient registration → result entry → report generation
  - [ ] Approval workflow with multiple users
  - [ ] Amendment process

### Test Data Fixtures
- [ ] **Seeded Test Database**: Consistent test data for all tests
- [ ] **Mock External Services**: Backup service, email service (if used)
- [ ] **Medical Data Samples**: Real-world lab values for testing

---

## 📋 HIGH-RISK AREAS (Priority Review)

These areas warrant extra scrutiny during code reviews:

1. **Patient Data Security** ⚠️
   - [ ] Encryption implementation correct
   - [ ] No plaintext passwords stored
   - [ ] SQL injection prevention

2. **Audit Logging** ⚠️
   - [ ] All required events captured
   - [ ] Logs immutable after writing
   - [ ] Timestamps accurate and consistent

3. **Result Approval Workflow** ⚠️
   - [ ] State machine correctly enforced
   - [ ] No skipped states possible
   - [ ] Approval always by different user than entry

4. **Backup & Recovery** ⚠️
   - [ ] Backup process tested monthly
   - [ ] Restoration verified to work
   - [ ] Backup encryption correct

5. **Report Integrity** ⚠️
   - [ ] Reports become read-only after approval
   - [ ] Amendment process maintains original
   - [ ] Version history complete

6. **Reference Range Management** ⚠️
   - [ ] Age/gender logic correct
   - [ ] Critical values properly flagged
   - [ ] Updates don't affect historical results

7. **Role-Based Access** ⚠️
   - [ ] All sensitive operations check RBAC
   - [ ] No role bypass paths
   - [ ] Permission matrix enforced

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

### Performance
- [ ] Load testing with 10,000+ patient records
- [ ] Report generation time < 5 seconds
- [ ] Patient search response < 2 seconds
- [ ] Concurrent user testing (5+ simultaneous users)

### Operations
- [ ] Backup/restore procedure documented and tested
- [ ] Admin dashboard shows system health
- [ ] Error monitoring in place
- [ ] User manual and admin guide complete

### Compliance
- [ ] HIPAA/local regulations reviewed
- [ ] Data retention policy documented
- [ ] Privacy policy in place
- [ ] Terms of service finalized

---

## 📅 AUDIT CADENCE

### Weekly
- [ ] Code review checklist applied to all PRs
- [ ] Failing tests investigated
- [ ] Performance metrics reviewed

### Monthly
- [ ] Backup restoration test
- [ ] Audit log review (sample check)
- [ ] Database optimization (indexes)
- [ ] Security update checks

### Quarterly
- [ ] Full security audit
- [ ] Test coverage report
- [ ] Reference range review (medical standards)
- [ ] Capacity planning (database size growth)

### Annually
- [ ] Penetration testing
- [ ] Compliance audit
- [ ] Architecture review

---

## 🔗 Related Documentation

- [Clean Architecture Guide](CLEAN_ARCHITECTURE.md) *(to be created)*
- [Database Schema Specification](DATABASE_SCHEMA.md) *(to be created)*
- [API & Repository Interfaces](API_SPECIFICATION.md) *(to be created)*
- [Testing Strategy](TESTING_STRATEGY.md) *(to be created)*
- [Backup & Recovery Procedure](BACKUP_PROCEDURE.md) *(to be created)*
- [Audit Logging Specification](AUDIT_LOGGING.md) *(to be created)*
- [Report Template Design](REPORT_TEMPLATES.md) *(to be created)*

---

**Questions or updates?** File an issue or contact the architecture team.
