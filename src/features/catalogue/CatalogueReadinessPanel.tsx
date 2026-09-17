import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Box, Button, Card, CardContent, Chip, Dialog, DialogActions, DialogContent, DialogTitle, MenuItem, Stack, TextField, Typography } from '@mui/material';
import { useSearchParams } from 'react-router-dom';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { useAuth } from '@/hooks/useAuth';
import { PERMISSION_KEYS } from '@/types/permissions';

type ReadinessState = 'Draft'|'NeedsConfiguration'|'ReadyForReview'|'Approved'|'Suspended';
type InventoryRow = {
  test_id: string; code: string; name: string; service_kind: 'Test'|'Package'; classification: string;
  approval_state: ReadinessState; configuration_version: number; clinical_reporting_enabled: boolean;
  reporting_type?: string; workflow_type?: string; parameter_count?: number;
  specimen?: string; container?: string; method?: string; test_row_version?: number; operational_status?: string;
  missing_requirements?: string[]; category_decisions?: Record<string,string>;
};
const categories = ['Identity','Specimen','ParameterStructure','ReferenceRanges','Calculations','CriticalLimits','MethodAnalyzer','SourceConflicts','Pricing','Workflow'];

export const CatalogueReadinessPanel: React.FC = () => {
  const { hasPermission } = useAuth();
  const canControlReadiness = hasPermission(PERMISSION_KEYS.CAN_MANAGE_CATALOGUE) || hasPermission(PERMISSION_KEYS.CAN_CONFIGURE_CATALOGUE_TECHNICAL);
  const [searchParams] = useSearchParams();
  const [rows,setRows] = useState<InventoryRow[]>([]);
  const [state,setState] = useState('');
  const [classification,setClassification] = useState('');
  const [query,setQuery] = useState('');
  const [busy,setBusy] = useState(false);
  const [error,setError] = useState('');
  const [selected,setSelected] = useState<InventoryRow|null>(null);
  const [category,setCategory] = useState('ParameterStructure');
  const [reason,setReason] = useState('');
  const [specimen,setSpecimen] = useState('');
  const [container,setContainer] = useState('');
  const [method,setMethod] = useState('');
  const highlightedId = searchParams.get('readiness');

  const load = useCallback(async () => {
    setBusy(true); setError('');
    const { data,error: rpcError } = await supabase.rpc('catalogue_readiness_inventory',{ p_state: state || null,p_query: query || null });
    if (rpcError) setError(safeErrorMessage(rpcError,'Catalogue readiness inventory could not be loaded.'));
    else setRows((data || []) as InventoryRow[]);
    setBusy(false);
  },[query,state]);
  useEffect(() => { void load(); },[load]);
  useEffect(() => { if (highlightedId) setSelected(rows.find((row) => row.test_id===highlightedId) || null); },[highlightedId,rows]);

  const displayedRows = useMemo(() => classification ? rows.filter((row) => row.classification===classification) : rows,[classification,rows]);
  const counts = useMemo(() => rows.reduce<Record<string,number>>((acc,row) => { acc[row.approval_state]=(acc[row.approval_state]||0)+1; acc[row.classification]=(acc[row.classification]||0)+1; return acc; },{}),[rows]);
  const mutate = async (operation:'review'|'MarkReady'|'MarkReportable'|'NeedsConfiguration'|'Suspend'|'Reactivate'|'MarkNonReportable') => {
    if (!selected || !reason.trim()) return;
    setBusy(true); setError('');
    const result = operation==='review'
      ? await supabase.rpc('catalogue_record_configuration_review',{p_test_id:selected.test_id,p_category:category,p_reason:reason,p_source_metadata:{entered_via:'CatalogueReadinessPanel'},p_expected_version:selected.configuration_version})
      : await supabase.rpc('catalogue_decide_readiness',{p_test_id:selected.test_id,p_decision:operation,p_reason:reason,p_expected_version:selected.configuration_version});
    if (result.error) setError(safeErrorMessage(result.error,'Readiness decision failed.'));
    else { setReason(''); setSelected(null); await load(); }
    setBusy(false);
  };
  const openService = (row: InventoryRow) => { setSelected(row); setSpecimen(row.specimen || ''); setContainer(row.container || ''); setMethod(row.method || ''); };
  const saveTechnical = async () => {
    if (!selected || !reason.trim() || selected.test_row_version==null) return;
    setBusy(true); setError('');
    const { error: rpcError } = await supabase.rpc('catalogue_technical_update_test', {
      p_test_id:selected.test_id,p_patch:{sample_type:specimen,container,method},p_expected_version:selected.test_row_version,p_reason:reason,
    });
    if (rpcError) setError(safeErrorMessage(rpcError,'Technical configuration could not be saved.'));
    else { setReason(''); setSelected(null); await load(); }
    setBusy(false);
  };

  return <Card sx={{mb:2,border:'1px solid',borderColor:'divider'}}><CardContent>
    <Typography variant="h6" fontWeight={800}>Catalogue operational status</Typography>
    <Typography variant="body2" color="text.secondary" sx={{mb:2}}>Normal tests are Ready &amp; Reportable by default. Use exception controls only when a service needs attention, is suspended, or intentionally produces no report.</Typography>
    {error && <Alert severity="error" sx={{mb:2}}>{error}</Alert>}
    <Stack direction={{xs:'column',md:'row'}} spacing={1} sx={{mb:2}}>
      <TextField size="small" label="Search service" value={query} onChange={(e)=>setQuery(e.target.value)} />
      <TextField size="small" select label="Operational status" value={state} onChange={(e)=>setState(e.target.value)} sx={{minWidth:190}}><MenuItem value="">All statuses</MenuItem><MenuItem value="Approved">Ready &amp; Reportable / Non-Reportable Service</MenuItem><MenuItem value="NeedsConfiguration">Needs Attention</MenuItem><MenuItem value="Suspended">Suspended</MenuItem></TextField>
      <TextField size="small" select label="Workflow class" value={classification} onChange={(e)=>setClassification(e.target.value)} sx={{minWidth:210}}><MenuItem value="">All workflow classes</MenuItem><MenuItem value="InHouse">InHouse</MenuItem><MenuItem value="OutsourceWithBimalReport">OutsourceWithBimalReport</MenuItem><MenuItem value="BillingOnly">Billing only</MenuItem><MenuItem value="CommercialPackage">Package</MenuItem><MenuItem value="SpecialistWorkflow">Specialist Workflow</MenuItem></TextField>
      <Button onClick={()=>void load()} disabled={busy}>Refresh</Button>
    </Stack>
    <Stack direction="row" spacing={1} useFlexGap flexWrap="wrap" sx={{mb:2}}>
      {Object.entries(counts).map(([label,count])=><Chip key={label} label={`${label}: ${count}`} variant="outlined" />)}
    </Stack>
    <Box sx={{display:'grid',gridTemplateColumns:{xs:'1fr',lg:'repeat(2,1fr)'},gap:1.5,maxHeight:520,overflow:'auto'}}>
      {displayedRows.map((row)=><Card key={`${row.service_kind}-${row.test_id}`} variant="outlined" sx={{borderColor:row.test_id===highlightedId?'warning.main':'divider'}}><CardContent>
        <Stack direction="row" justifyContent="space-between" gap={1}><Box><Typography fontWeight={800}>{row.name}</Typography><Typography variant="caption" color="text.secondary">{row.code} · {row.classification} · {row.reporting_type || row.service_kind}</Typography></Box><Chip size="small" label={row.operational_status || row.approval_state} color={row.operational_status==='Ready & Reportable'?'success':row.operational_status==='Inactive'?'default':'warning'} /></Stack>
        <Typography variant="caption" display="block" sx={{mt:1}}>Parameters: {row.parameter_count ?? 0} · Clinical reporting: {row.clinical_reporting_enabled?'Enabled':'Disabled'} · Revision: {row.configuration_version ?? '—'}</Typography>
        <Typography variant="caption" display="block">Method: {row.method || 'Method not configured'}</Typography>
        {(row.missing_requirements || []).length>0 ? <Box component="ul" sx={{my:1,pl:2.5}}>{row.missing_requirements!.map((item)=><Typography component="li" variant="caption" key={item}>{item}</Typography>)}</Box> : <Alert severity="success" sx={{my:1,py:0}}>{row.operational_status || 'Ready & Reportable'}</Alert>}
        {row.service_kind==='Test' && <Button size="small" onClick={()=>openService(row)}>Technician actions</Button>}
      </CardContent></Card>)}
    </Box>
    <Dialog open={Boolean(selected)} onClose={()=>setSelected(null)} maxWidth="sm" fullWidth><DialogTitle>{selected?.code}: readiness decision</DialogTitle><DialogContent>
      <Alert severity="info" sx={{mb:2}}>The Lab Technician controls operational exceptions. Ready/reportable actions still enforce genuine server-side reporting invariants.</Alert>
      <Stack spacing={1.5} sx={{mb:2}}><TextField label="Specimen" value={specimen} onChange={(e)=>setSpecimen(e.target.value)} /><TextField label="Container" value={container} onChange={(e)=>setContainer(e.target.value)} /><TextField label="Analytical method" placeholder="Method not configured" value={method} onChange={(e)=>setMethod(e.target.value)} /></Stack>
      <TextField fullWidth select label="Configuration category" value={category} onChange={(e)=>setCategory(e.target.value)} sx={{mb:2}}>{categories.map((x)=><MenuItem key={x} value={x}>{x}</MenuItem>)}</TextField>
      <TextField fullWidth multiline minRows={3} label="Technician decision reason" value={reason} onChange={(e)=>setReason(e.target.value)} required />
    </DialogContent><DialogActions sx={{flexWrap:'wrap'}}>
      <Button onClick={()=>setSelected(null)}>Cancel</Button>
      {hasPermission(PERMISSION_KEYS.CAN_CONFIGURE_CATALOGUE_TECHNICAL) && <Button disabled={busy||!reason.trim()} onClick={()=>void saveTechnical()}>Save technical configuration</Button>}
      <Button disabled={busy||!reason.trim()} onClick={()=>void mutate('review')}>Record configuration</Button>
      {canControlReadiness && <><Button color="error" disabled={busy||!reason.trim()} onClick={()=>void mutate(selected?.approval_state==='Suspended'?'Reactivate':'Suspend')}>{selected?.approval_state==='Suspended'?'Reactivate':'Suspend'}</Button><Button color="warning" disabled={busy||!reason.trim()} onClick={()=>void mutate('NeedsConfiguration')}>Needs Configuration</Button><Button color="inherit" disabled={busy||!reason.trim()} onClick={()=>void mutate('MarkNonReportable')}>Mark Not Reportable</Button><Button variant="contained" disabled={busy||!reason.trim()} onClick={()=>void mutate('MarkReady')}>Keep Ready</Button></>}
    </DialogActions></Dialog>
  </CardContent></Card>;
};
