/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Organization & System Configuration Constants
 */

export const ORG_CONFIG = {
  nameEn: 'BIMAL PATHOLOGY & DIAGNOSTIC CENTER',
  nameNp: 'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर',
  addressEn: 'Bharatpur-7, Chitwan, Nepal',
  addressNp: 'भरतपुर-७, चितवन, नेपाल',
  regNo: '7-1496',
  panNo: '302481477',
  phone: '056-593288',
  email: 'info@bimalpathology.com',
  headerZoneCm: 6.0,
} as const;

export const REPORTING_TYPES = {
  IN_HOUSE: 'InHouse',
  OUTSOURCE_WITH_BIMAL_REPORT: 'OutsourceWithBimalReport',
  NO_REPORTING: 'NoReporting',
} as const;

export type ReportingType = typeof REPORTING_TYPES[keyof typeof REPORTING_TYPES];

export const SAMPLE_STATUSES = {
  PENDING: 'Pending',
  COLLECTED: 'Collected',
  RECEIVED: 'Received',
  REJECTED: 'Rejected',
  RECOLLECTED: 'Recollected',
  PROCESSING: 'Processing',
  COMPLETED: 'Completed',
} as const;

export type SampleStatus = typeof SAMPLE_STATUSES[keyof typeof SAMPLE_STATUSES];

export const RESULT_STATUSES = {
  DRAFT: 'Draft',
  SUBMITTED_FOR_VERIFICATION: 'SubmittedForVerification',
  VERIFIED: 'Verified',
  SIGNED_OFF: 'SignedOff',
  RETURNED_FOR_CORRECTION: 'ReturnedForCorrection',
} as const;

export type ResultStatus = typeof RESULT_STATUSES[keyof typeof RESULT_STATUSES];

export const RESULT_FLAGS = {
  NORMAL: 'Normal',
  LOW: 'Low',
  HIGH: 'High',
  CRITICAL_LOW: 'CriticalLow',
  CRITICAL_HIGH: 'CriticalHigh',
  ABNORMAL: 'Abnormal',
  NO_RANGE: 'NoRange',
} as const;

export type ResultFlag = typeof RESULT_FLAGS[keyof typeof RESULT_FLAGS];

export const PAYMENT_MODES = {
  CASH: 'Cash',
  FONEPAY: 'Fonepay',
  ESEWA: 'eSewa',
  KHALTI: 'Khalti',
  CARD: 'Card',
  BANK: 'Bank',
  CREDIT: 'Credit',
  OTHER: 'Other',
} as const;

export type PaymentMode = typeof PAYMENT_MODES[keyof typeof PAYMENT_MODES];

export const PROFESSIONAL_TYPES = {
  PATHOLOGIST: 'Pathologist',
  LAB_TECHNOLOGIST: 'Lab Technologist',
  LAB_TECHNICIAN: 'Lab Technician',
  LAB_ASSISTANT: 'Lab Assistant',
  RECEPTIONIST: 'Receptionist',
  ADMIN: 'Admin',
} as const;

export type ProfessionalType = typeof PROFESSIONAL_TYPES[keyof typeof PROFESSIONAL_TYPES];

export const SPECIMEN_TYPES = [
  'Whole Blood (EDTA)',
  'Serum (Plain / Clot Activator)',
  'Plasma (Fluoride / Citrate / Heparin)',
  'Urine (Routine / 24h)',
  'Stool (Routine / Occult Blood)',
  'Sputum',
  'Swab / Body Fluid',
  'Semen',
  'Tissue / Biopsy',
] as const;

export const DEPARTMENTS = [
  'Hematology',
  'Clinical Biochemistry',
  'Immunology & Serology',
  'Microbiology & Parasitology',
  'Histopathology & Cytology',
  'Molecular Diagnostics',
  'Clinical Pathology (Urine & Stool)',
] as const;
