/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Complete Database Schema TypeScript Interfaces
 * All financial amounts are in PAISA (integer / bigint).
 */

import { ReportingType, SampleStatus, ResultStatus, ResultFlag, PaymentMode, ProfessionalType } from '../config/constants';
import { PermissionKey } from './permissions';

export interface UserProfile {
  id: string; // references auth.users
  email: string;
  fullName: string;
  phone?: string | null;
  isActive: boolean;
  isSuperAdmin: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface Role {
  id: string;
  code: string;
  name: string;
  description: string;
  isSystem: boolean;
  createdAt: string;
}

export interface RolePermission {
  roleId: string;
  permissionKey: PermissionKey;
}

export interface UserRole {
  userId: string;
  roleId: string;
}

export interface UserDirectPermission {
  userId: string;
  permissionKey: PermissionKey;
  isGranted: boolean; // true = grant, false = revoke override
}

export interface ReferringDoctor {
  id: string;
  fullName: string;
  code?: string | null;
  degree?: string | null;
  institution?: string | null;
  phone?: string | null;
  email?: string | null;
  address?: string | null;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface ReportingPersonnel {
  id: string;
  userId?: string | null; // optional link to auth.users
  fullName: string;
  professionalType: ProfessionalType;
  qualification: string;
  registrationCouncil: string; // e.g. "Nepal Medical Council (NMC)", "NHPC"
  registrationNumber: string;
  specialization?: string | null;
  phone?: string | null;
  email?: string | null;
  signatureUrl?: string | null;
  canEnterResults: boolean;
  canVerifyResults: boolean;
  canAcknowledgeCritical: boolean;
  canSignReports: boolean;
  isActive: boolean;
  displayOrder: number;
  createdAt: string;
  updatedAt: string;
}

export interface Patient {
  id: string;
  uhid: string; // Immutable identifier: historical formats or new YYMMDDXXXX
  mobile: string; // Mandatory lookup key
  title?: string | null; // Mr., Mrs., Ms., Master, Dr.
  fullName: string;
  gender: 'Male' | 'Female' | 'Other';
  dob?: string | null;
  ageYears?: number | null;
  ageMonths?: number | null;
  ageDays?: number | null;
  address: string;
  email?: string | null;
  identificationNo?: string | null; // Citizenship, Passport, etc.
  createdAt: string;
  updatedAt: string;
}

export interface Bill {
  id: string;
  billNumber: string; // e.g. INV-2026-00001
  patientId: string;
  patientUhid: string; // Snapshot
  patientName: string; // Snapshot
  patientMobile: string; // Snapshot
  patientAgeGender: string; // Snapshot
  referringDoctorId?: string | null;
  referringDoctorName?: string | null; // Snapshot
  
  // Financial amounts in PAISA (1 NPR = 100 Paisa)
  grossAmountPaisa: number;
  discountAmountPaisa: number;
  discountReason?: string | null;
  netAmountPaisa: number;
  paidAmountPaisa: number;
  dueAmountPaisa: number;
  
  paymentStatus: 'Paid' | 'Partial' | 'Due';
  remarks?: string | null;
  createdBy: string;
  createdAt: string;
  updatedAt: string;
}

export interface BillItem {
  id: string;
  billId: string;
  testId: string;
  testCode: string;
  testName: string;
  reportingType: ReportingType;
  outsourceLabName?: string | null;
  unitPricePaisa: number;
  discountPaisa: number;
  netPricePaisa: number;
  createdAt: string;
}

export interface PaymentTransaction {
  id: string;
  billId: string;
  receiptNumber: string;
  amountPaisa: number;
  paymentMode: PaymentMode;
  transactionReference?: string | null;
  remarks?: string | null;
  receivedBy: string;
  receivedByName: string;
  createdAt: string;
}

export interface ClinicalOrder {
  id: string;
  billId: string;
  patientId: string;
  orderNumber: string; // Lab No. e.g. LAB-2026-00001
  orderDate: string; // Registered date AD
  orderDateBs: string; // Registered date BS
  status: 'Registered' | 'InLab' | 'PartiallyCompleted' | 'Completed' | 'SignedOff';
  createdAt: string;
  updatedAt: string;
}

export interface ClinicalOrderItem {
  id: string;
  orderId: string;
  billItemId: string;
  testId: string;
  testName: string;
  department: string;
  reportingType: ReportingType; // InHouse or OutsourceWithBimalReport only
  outsourceLabName?: string | null;
  specimenType: string;
  containerType: string;
  status: 'Pending' | 'SampleCollected' | 'SampleReceived' | 'ResultDrafted' | 'Verified' | 'SignedOff';
  sampleId?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface Sample {
  id: string;
  barcode: string; // e.g. SMP-2026-00001
  orderId: string;
  patientId: string;
  specimenType: string;
  containerType: string;
  status: SampleStatus;
  
  collectedAt?: string | null;
  collectedBy?: string | null;
  collectedByName?: string | null;
  
  receivedAt?: string | null;
  receivedBy?: string | null;
  receivedByName?: string | null;
  
  rejectedAt?: string | null;
  rejectedBy?: string | null;
  rejectedByName?: string | null;
  rejectionReason?: string | null;
  
  recollectedFromSampleId?: string | null; // Lineage link
  createdAt: string;
  updatedAt: string;
}

export interface SampleLifecycleEvent {
  id: string;
  sampleId: string;
  fromStatus: SampleStatus;
  toStatus: SampleStatus;
  reason?: string | null;
  performedBy: string;
  performedByName: string;
  timestamp: string;
}

export type ReportDataType =
  | 'Numeric'
  | 'Text'
  | 'PositiveNegative'
  | 'ReactiveNonReactive'
  | 'DetectedNotDetected'
  | 'Categorical'
  | 'Multiline'
  | 'Microscopic'
  | 'CultureAST'
  | 'Susceptibility'
  | 'Calculated'
  | 'PathologyNarrative'
  | 'Panel';

export type CatalogueValidationStatus =
  | 'DRAFT'
  | 'REQUIRES_VALIDATION'
  | 'VALIDATED'
  | 'ACTIVE'
  | 'INACTIVE';

export interface TestAlias {
  id: string;
  test_id: string;
  alias_name: string;
  alias_type: 'Synonym' | 'Acronym' | 'LegacyCode' | 'AlternativeName' | 'ShortName';
  is_primary: boolean;
  created_at?: string;
}

export interface CataloguePanelComponent {
  id?: string;
  panel_id: string;
  panel_test_id?: string;
  component_test_id: string;
  component_parameter_id?: string | null;
  component_role: 'Measured' | 'Calculated' | 'Qualitative' | 'ComponentService' | 'Narrative';
  display_order: number;
  is_required: boolean;
  created_at?: string;
  component_test?: TestMaster;
}

export interface TestMaster {
  id: string;
  code: string;
  name: string;
  shortName?: string | null;
  short_name?: string | null;
  department: string;
  subdepartment?: string | null;
  category: string;
  test_type?: 'Single' | 'Panel';
  reportingType: ReportingType;
  reporting_type?: ReportingType;
  outsourceLabName?: string | null;
  outsource_lab_name?: string | null;
  pricePaisa: number;
  price_paisa?: number;
  priceConfigured?: boolean;
  allowZeroPriceBilling?: boolean;
  clinicalReportingEnabled?: boolean;
  collectionRequired?: boolean;
  workflowType?: string;
  workflow_type?: string;
  clinicalConfigurationStatus?: 'Configured' | 'Requires Clinical Validation' | 'Ready for Activation' | 'Workflow Not Supported';
  validation_status?: CatalogueValidationStatus;
  pricingPolicy?: 'Fixed' | 'Negotiable' | 'PricePending' | 'Manual';
  sampleType: string;
  sample_type?: string;
  specimen_type?: string;
  container: string;
  container_type?: string;
  method?: string | null;
  unit?: string | null;
  tatHours?: number | null;
  tat_description?: string | null;
  report_data_type?: ReportDataType;
  fasting_required?: boolean;
  is_outsource?: boolean;
  interpretationTemplate?: string | null;
  interpretation_template?: string | null;
  notes?: string | null;
  allowManualPrice?: boolean;
  requiresSampleTracking?: boolean;
  isActive: boolean;
  is_active?: boolean;
  displayOrder: number;
  display_order?: number;
  createdAt: string;
  updatedAt: string;
  aliases?: TestAlias[];
}

export type OutsourceSampleStatus =
  | 'ReceivedAtBimal'
  | 'PreparedForDispatch'
  | 'DispatchedToReferenceLab'
  | 'ReceivedByReferenceLab'
  | 'ProcessingAtReferenceLab'
  | 'ResultReceived'
  | 'MaterialReturned'
  | 'Completed'
  | 'Rejected'
  | 'Cancelled'
  | 'LostInTransit';

export interface OutsourceSample {
  id: string;
  tracking_number: string;
  bill_id: string;
  bill_item_id: string;
  order_item_id?: string | null;
  reference_laboratory_id?: string | null;
  recollects_outsource_sample_id?: string | null;
  patient_id: string;
  test_id: string;
  service_description: string;
  specimen_type: string;
  specimen_description?: string | null;
  quantity_received: string;
  reference_lab_name: string;
  status: OutsourceSampleStatus;
  received_at: string;
  received_by?: string | null;
  received_by_name?: string | null;
  dispatched_at?: string | null;
  dispatched_by?: string | null;
  dispatched_by_name?: string | null;
  courier_name?: string | null;
  courier_tracking_no?: string | null;
  items_sent_count?: string | null;
  dispatch_notes?: string | null;
  external_report_received: boolean;
  external_report_date?: string | null;
  reference_lab_report_no?: string | null;
  result_received_at?: string | null;
  result_received_by?: string | null;
  result_received_by_name?: string | null;
  result_notes?: string | null;
  material_returned: boolean;
  material_returned_at?: string | null;
  blocks_returned_count: number;
  slides_returned_count: number;
  material_received_by?: string | null;
  material_received_by_name?: string | null;
  return_notes?: string | null;
  completed_at?: string | null;
  created_at: string;
  updated_at: string;
  patient?: {
    uhid: string;
    full_name: string;
    mobile: string;
    gender: string;
    age_years?: number | null;
  };
  bill?: {
    bill_number: string;
    created_at: string;
  };
  order_item?: { outsource_state?: string | null } | null;
}

export interface OutsourceSampleEvent {
  id: string;
  outsource_sample_id: string;
  event_type: string;
  from_status?: OutsourceSampleStatus | null;
  to_status: OutsourceSampleStatus;
  notes?: string | null;
  meta?: any;
  performed_by?: string | null;
  performed_by_name?: string | null;
  created_at: string;
}

export type ParameterValueType = 'Numeric' | 'Text' | 'Select' | 'Boolean' | 'Heading' | 'Calculated';

export interface ParameterMaster {
  id: string;
  testId: string;
  code: string;
  name: string;
  valueType: ParameterValueType;
  unit?: string | null;
  options?: string[] | null; // for Select
  formula?: string | null; // for Calculated (e.g. "TOTAL_BILIRUBIN - DIRECT_BILIRUBIN")
  formulaDependencies?: string[] | null; // e.g. ["TOTAL_BILIRUBIN", "DIRECT_BILIRUBIN"]
  displayOrder: number;
  isMandatory: boolean;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface ReferenceRange {
  id: string;
  parameterId: string;
  gender: 'All' | 'Male' | 'Female';
  ageMinDays: number;
  ageMaxDays: number;
  normalMin?: number | null;
  normalMax?: number | null;
  criticalLow?: number | null;
  criticalHigh?: number | null;
  normalText?: string | null; // Qualitative range e.g. "Non-reactive", "Negative"
  referenceText?: string | null; // Explicit formatted text
  unit?: string | null;
  method?: string | null;
  effectiveFrom?: string | null;
  effectiveTo?: string | null;
  isActive: boolean;
  isApproved: boolean;
  approvedBy?: string | null;
  approvedAt?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface TestResult {
  id: string;
  orderItemId: string;
  parameterId: string;
  parameterName: string; // Snapshot
  unit?: string | null; // Snapshot
  valueType: ParameterValueType;
  
  numericValue?: number | null;
  textValue?: string | null;
  displayValue: string;
  
  flag: ResultFlag;
  isCritical: boolean;
  criticalAcknowledged: boolean;
  criticalAcknowledgedBy?: string | null;
  criticalAcknowledgedAt?: string | null;
  
  normalRangeText?: string | null; // Snapshot for PDF
  normalMin?: number | null;
  normalMax?: number | null;
  criticalLow?: number | null;
  criticalHigh?: number | null;
  
  status: ResultStatus;
  enteredBy?: string | null;
  enteredByName?: string | null;
  enteredAt?: string | null;
  
  verifiedBy?: string | null;
  verifiedByName?: string | null;
  verifiedAt?: string | null;
  
  signedOffBy?: string | null;
  signedOffByName?: string | null;
  signedOffAt?: string | null;
  
  createdAt: string;
  updatedAt: string;
}

export interface DiagnosticReport {
  id: string;
  orderId: string;
  patientId: string;
  reportNumber: string; // e.g. REP-2026-00001
  version: number; // 1 for original, 2+ for amendments
  isAmendment: boolean;
  amendmentReason?: string | null;
  amendedFromReportId?: string | null;
  
  status: 'Draft' | 'SignedOff' | 'Amended';
  integrityHash?: string | null; // SHA-256 hash of signed clinical snapshot
  
  performedByPersonnelId?: string | null;
  performedByPersonnelName?: string | null;
  
  verifiedByPersonnelId?: string | null;
  verifiedByPersonnelName?: string | null;
  
  signedByPersonnelId?: string | null;
  signedByPersonnelName?: string | null;
  signedAt?: string | null;
  
  pdfStoragePath?: string | null;
  clinicalSnapshotJson?: Record<string, unknown> | null;
  createdAt: string;
  updatedAt: string;
}

export interface AuditLog {
  id: string;
  userId?: string | null;
  userName?: string | null;
  action: string;
  entityType: string;
  entityId: string;
  oldData?: Record<string, unknown> | null;
  newData?: Record<string, unknown> | null;
  ipAddress?: string | null;
  userAgent?: string | null;
  timestamp: string;
}
