import fs from 'node:fs';

let content = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

content = content.replace(
  `('8ea45b9a-2bc5-4edd-8f1c-f4e3eb34bd62', 'BIO-0019', 'Indirect Bilirubin', 'BIO-0019', 'Clinical Biochemistry', 'General Chemistry', NULL, 'InHouse'::public.reporting_type_enum, NULL, 0, 'Serum / Plasma', 'Plain/SST', 'Ion Selective Electrode (ISE) / Colorimetric'`,
  `('8ea45b9a-2bc5-4edd-8f1c-f4e3eb34bd62', 'BIO-0019', 'Indirect Bilirubin', 'BIO-0019', 'Clinical Biochemistry', 'General Chemistry', NULL, 'InHouse'::public.reporting_type_enum, NULL, 0, 'Serum / Plasma', 'Plain/SST', 'Calculated: Total Bilirubin - Direct Bilirubin'`
);

content = content.replace(
  `('d3ce5970-61f7-4103-a015-a66bc24863d8', '8ea45b9a-2bc5-4edd-8f1c-f4e3eb34bd62', 'BIO-0019', 'Indirect Bilirubin', 'Numeric'::public.parameter_value_type_enum, 'mg/dL', NULL, NULL, NULL, NULL, 1, TRUE, TRUE, 'Active', 'Configured', NULL)`,
  `('d3ce5970-61f7-4103-a015-a66bc24863d8', '8ea45b9a-2bc5-4edd-8f1c-f4e3eb34bd62', 'BIO-0019', 'Indirect Bilirubin', 'Calculated'::public.parameter_value_type_enum, 'mg/dL', NULL, 'TBIL - DBIL', NULL, 'LFT_IBIL_V1', 1, TRUE, TRUE, 'Active', 'Configured', NULL)`
);

fs.writeFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', content, 'utf8');
console.log('Successfully updated Indirect Bilirubin BIO-0019 to Calculated in baseline!');
