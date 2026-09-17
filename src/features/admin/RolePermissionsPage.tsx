import { Alert, Box, Card, CardContent, Chip, Divider, List, ListItem, ListItemText, Typography } from '@mui/material';
import { PageHeader } from '@/components/common/PageHeader';

const technicianCapabilities = [
  'Patient registration, billing, payments and dues',
  'Sample collection, receipt, rejection and recollection',
  'Worklist, result entry, verification and critical-value acknowledgement',
  'Report signing, amendment, history, PDF and printing',
  'Outsource tracking',
];

export const RolePermissionsPage=()=> <Box>
 <PageHeader title="Roles" subtitle="Two clear access levels: System Owner and Laboratory Operator"/>
 <Alert severity="info" sx={{mb:2}}>Access is system-defined. There is no granular permission checkbox setup to maintain.</Alert>
 <Box sx={{display:'grid',gridTemplateColumns:{xs:'1fr',md:'1fr 2fr'},gap:2}}>
  <Card><CardContent><Typography variant="h6" fontWeight={800}>Super Admin</Typography><Chip label="System Owner" color="warning" size="small" sx={{my:1}}/><Typography>Not a normal assignable role. Effective server-side authority for users, roles, security and infrastructure, with access to all laboratory operations.</Typography><Divider sx={{my:2}}/><Typography variant="body2" color="text.secondary">Super Admin state is protected by the server-authoritative owner mechanism, including final-owner and self-deactivation safeguards.</Typography></CardContent></Card>
  <Card><CardContent><Typography variant="h6" fontWeight={800}>Lab Technician</Typography><Chip label="Laboratory Operator" color="success" size="small" sx={{my:1}}/><Typography sx={{mb:1}}>Runs the complete day-to-day laboratory workflow.</Typography><List dense>{technicianCapabilities.map(capability=><ListItem key={capability} disableGutters><ListItemText primary={capability}/></ListItem>)}</List><Divider sx={{my:2}}/><Typography variant="body2" color="text.secondary">User accounts and role assignment remain Super Admin responsibilities.</Typography></CardContent></Card>
 </Box>
 </Box>;
