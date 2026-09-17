import { ORG_CONFIG } from '@/config/constants';

export const AGE_GROUPS = ['<1 Year','1–4 Years','5–9 Years','10–14 Years','15–19 Years','20–29 Years','30–59 Years','60–69 Years','70+ Years'] as const;
export const CLIENT_METRICS = ['newClients','totalClients','emergency'] as const;
export const CONDITIONS = ['Heart','Kidney','Cancer','Road Injury','Spinal Injury','Alzheimer','Parkinson','Sickle Cell Anaemia'] as const;
export const OPD_ROWS = ['Outreach Clinic','Immunization Clinic','Immunization Session','Hygiene Promotion Session','FCHV'] as const;
export const CAPACITY_ROWS = ['Sanctioned Bed','Operational In-Patient Bed','Emergency Bed','Total Inpatient Days','Total Patient Admitted','Total Discharge','Total Death','Total Delivery','ICU','NICU','PICU'] as const;
export const SERVICES = ['X-Ray','Ultrasonogram (USG)','Echocardiogram','Electrocardiogram (ECG)','Treadmill','Computer Tomography (CT)','Magnetic Resonance Imaging (MRI)','Endoscopy','Colonoscopy','Bronchoscopy','Nuclear Medicine','Mammogram','Cystoscopy','Dexa Scan','DTPA Scan','Electromagnetic Therapy (ECT)','Transcranial Magnetic Stimulation (TMS)','Other Laboratory Services Provided'] as const;
export const SERVICE_SITES = ['Birthing Centre','Cancer Site','CBO/NGO Site','Safe Abortion Service (SAS) Site','UHC Service Site','Immunization Site','Adolescent Friendly Service Site','OTC Site'] as const;
export const REFERRAL_SITES = ['DOTS Site','Microscopy Site','Laboratory Service','HTS Site','PMTCT Site','ART Site','Others'] as const;

export type Availability = 'Available' | 'Not Available' | 'Not Applicable';
export type HmisIdentitySnapshot = {source:'ReportingPersonnel'|'Staff';id:string;name:string;designation:string;signatureUrl:string|null};
export type HmisConfig = {
  facilityName:string; hfCode:string; province:string; district:string; municipality:string; ward:string;
  ownershipType:string; nonApplicableValue:'N/A'|'0'; referencePrefix:string;
  services:Record<string,{availability:Availability;unit:string}>; serviceSites:Record<string,boolean>; referralSites:Record<string,boolean>;
  preparedByPersonnelId:string; verifiedByPersonnelId:string; approvedByPersonnelId:string;
};
export const defaultHmisConfig = (): HmisConfig => ({
  facilityName: ORG_CONFIG.nameEn, hfCode:'', province:'', district:'', municipality:'', ward:'', ownershipType:'Private',
  nonApplicableValue:'N/A', referencePrefix:'HMIS', preparedByPersonnelId:'', verifiedByPersonnelId:'', approvedByPersonnelId:'',
  services:Object.fromEntries(SERVICES.map(x=>[x,{availability:'Not Applicable' as Availability,unit:'Service'}])),
  serviceSites:Object.fromEntries(SERVICE_SITES.map(x=>[x,false])), referralSites:Object.fromEntries(REFERRAL_SITES.map(x=>[x,false])),
});
export type HmisSnapshot = {header:Record<string,string>; auto:Record<string,unknown>; manual:Record<string,unknown>; identities:{prepared:HmisIdentitySnapshot;verified:HmisIdentitySnapshot|null;approved:HmisIdentitySnapshot|null}; configured:HmisConfig; provenance:Record<string,'Auto from LIS'|'Manual HMIS Entry'|'Configured Facility Data'>};

export function csvSummary(snapshot:HmisSnapshot): string {
  const rows: string[][] = [['Section','Field','Value','Source']];
  for (const [section, values] of Object.entries({auto:snapshot.auto,manual:snapshot.manual})) for (const [key,value] of Object.entries(values as Record<string,unknown>)) {
    rows.push([section,key,typeof value==='object'?JSON.stringify(value):String(value??''),section==='auto'?'Auto from LIS':'Manual HMIS Entry']);
  }
  return rows.map(row=>row.map(v=>`"${v.replaceAll('"','""')}"`).join(',')).join('\r\n');
}
