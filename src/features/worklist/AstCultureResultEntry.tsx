import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Autocomplete, Box, Button, Card, CardContent, Chip, Divider, MenuItem, Stack, Table, TableBody, TableCell, TableHead, TableRow, TextField, Typography } from '@mui/material';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';

type Master = { id: string; code: string; name?: string; display_name?: string; organism_group_id?: string | null };
type AstRow = { antibiotic_id: string; method: 'Disk' | 'MIC'; metric_value: string; metric_secondary_value: string; automatic_interpretation: string; final_interpretation: string; override_reason: string; row_version: number; message?: string };
type Worksheet = { specimen_source:string; specimen_source_other:string; gram_stain_pus_cells:string; direct_smear_organisms:string; culture_status:string; final_remarks:string; status:string; row_version:number };
const SOURCES=['Wound Swab','Abscess Aspirate','Surgical Site','Ulcer Swab','Tissue Biopsy','Other'];
const PUS_CELLS=['Occasional (0-1 / LPF)','Few (1-5 / HPF)','Moderate (5-20 / HPF)','Plenty / Numerous (>20 / HPF)'];
const CULTURE_STATES=['No growth after 48 hours of aerobic incubation at 37°C','Growth obtained (Pathogen isolated)','Mixed bacterial growth (Skin flora / Probable contamination)','Light growth of doubtful clinical significance'];

export const AstCultureResultEntry: React.FC<{ orderItemId: string; canEnter: boolean }> = ({ orderItemId, canEnter }) => {
  const [organisms, setOrganisms] = useState<Master[]>([]);
  const [groups, setGroups] = useState<Master[]>([]);
  const [antibiotics, setAntibiotics] = useState<Master[]>([]);
  const [setVersion, setSetVersion] = useState('');
  const [isolateNumber, setIsolateNumber] = useState(1);
  const [growth, setGrowth] = useState<'Positive' | 'NoGrowth'>('Positive');
  const [organismId, setOrganismId] = useState('');
  const [isolateId, setIsolateId] = useState('');
  const [isolateRevision, setIsolateRevision] = useState(0);
  const [rows, setRows] = useState<AstRow[]>([]);
  const [worksheet,setWorksheet]=useState<Worksheet>({specimen_source:'Wound Swab',specimen_source_other:'',gram_stain_pus_cells:'Occasional (0-1 / LPF)',direct_smear_organisms:'',culture_status:'Growth obtained (Pathogen isolated)',final_remarks:'',status:'Draft',row_version:0});
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  const selectedOrganism = organisms.find((item) => item.id === organismId);
  const selectedGroup = groups.find((item) => item.id === selectedOrganism?.organism_group_id);
  const load = useCallback(async () => {
    const [org, grp, ab, active, iso, work] = await Promise.all([
      supabase.from('ast_microorganisms').select('id,code,display_name,organism_group_id').eq('is_active', true).order('display_name'),
      supabase.from('ast_organism_groups').select('id,code,display_name').eq('is_active', true).order('display_name'),
      supabase.from('ast_antibiotics').select('id,code,name').eq('is_active', true).order('name'),
      supabase.from('ast_breakpoint_sets').select('version').eq('is_active', true).single(),
      supabase.from('ast_isolates').select('*').eq('order_item_id', orderItemId).order('isolate_number'),
      supabase.from('pus_culture_worksheets').select('*').eq('order_item_id',orderItemId).maybeSingle(),
    ]);
    const firstError = [org.error, grp.error, ab.error, active.error, iso.error, work.error].find(Boolean);
    if (firstError) throw firstError;
    setOrganisms((org.data || []) as Master[]); setGroups((grp.data || []) as Master[]); setAntibiotics((ab.data || []) as Master[]); setSetVersion(active.data?.version || 'Not selected');
    if(work.data)setWorksheet({specimen_source:work.data.specimen_source,specimen_source_other:work.data.specimen_source_other||'',gram_stain_pus_cells:work.data.gram_stain_pus_cells,direct_smear_organisms:work.data.direct_smear_organisms||'',culture_status:work.data.culture_status,final_remarks:work.data.final_remarks||'',status:work.data.status,row_version:work.data.row_version});
    const current = (iso.data || []).find((item: any) => item.isolate_number === isolateNumber);
    if (current) {
      setIsolateId(current.id); setIsolateRevision(current.row_version); setGrowth(current.growth_state); setOrganismId(current.microorganism_id || '');
      const observations = await supabase.from('ast_observations').select('*').eq('isolate_id', current.id).order('antibiotic_name_snapshot');
      if (observations.error) throw observations.error;
      setRows((observations.data || []).map((item: any) => ({ antibiotic_id: item.antibiotic_id, method: item.method, metric_value: String(item.metric_value), metric_secondary_value: item.metric_secondary_value == null ? '' : String(item.metric_secondary_value), automatic_interpretation: item.automatic_interpretation || '', final_interpretation: item.final_interpretation, override_reason: item.override_reason || '', row_version: item.row_version })));
    } else { setIsolateId(''); setIsolateRevision(0); setOrganismId(''); setRows([]); }
  }, [isolateNumber, orderItemId]);
  useEffect(() => { void load().catch((reason) => setError(safeErrorMessage(reason))); }, [load]);

  const saveWorksheet=async()=>{
    setError(''); const result=await supabase.rpc('save_pus_culture_worksheet',{p_order_item_id:orderItemId,p_payload:{...worksheet,status:'Draft'},p_expected_revision:worksheet.row_version});
    if(result.error){setError(safeErrorMessage(result.error));return;} setWorksheet((current)=>({...current,row_version:result.data.row_version,status:result.data.status}));setMessage('Pus Culture worksheet saved. You can safely resume later.');
  };

  const saveIsolate = async () => {
    setError('');
    const result = await supabase.rpc('ast_save_isolate', { p_order_item_id: orderItemId, p_isolate_number: isolateNumber, p_microorganism_id: growth === 'Positive' ? organismId : null, p_growth_state: growth, p_expected_revision: isolateRevision });
    if (result.error) { setError(safeErrorMessage(result.error)); return; }
    setIsolateId(result.data.id); setIsolateRevision(result.data.row_version); setMessage('Isolate saved.');
  };
  const interpret = async (index: number, next: AstRow) => {
    if (!selectedGroup || !next.antibiotic_id || next.metric_value === '') return;
    const antibiotic = antibiotics.find((item) => item.id === next.antibiotic_id);
    const result = await supabase.rpc('ast_interpret_breakpoint', { p_organism_group_code: selectedGroup.code, p_antibiotic_code: antibiotic?.code, p_method: next.method, p_metric_value: next.metric_value, p_metric_secondary_value: next.metric_secondary_value || null, p_breakpoint_set_id: null });
    if (result.error) { setError(safeErrorMessage(result.error)); return; }
    const nextAutomatic = result.data.automatic_interpretation || '';
    const mayFollowAutomatic = !next.override_reason && (!next.final_interpretation || next.final_interpretation === next.automatic_interpretation);
    setRows((current) => current.map((row, rowIndex) => rowIndex === index ? { ...next, automatic_interpretation: nextAutomatic, final_interpretation: mayFollowAutomatic ? (nextAutomatic || next.final_interpretation) : next.final_interpretation, message: result.data.message || result.data.notes || '' } : row));
  };
  const saveRow = async (row: AstRow) => {
    if (!isolateId) { setError('Save the isolate before entering AST observations.'); return; }
    const result = await supabase.rpc('ast_save_observation', { p_isolate_id: isolateId, p_antibiotic_id: row.antibiotic_id, p_method: row.method, p_metric_value: row.metric_value, p_metric_secondary_value: row.metric_secondary_value || null, p_final_interpretation: row.final_interpretation, p_override_reason: row.override_reason || null, p_expected_revision: row.row_version });
    if (result.error) { setError(safeErrorMessage(result.error)); return; }
    setMessage('AST observation saved with breakpoint version evidence.'); await load();
  };
  const addRow = () => setRows((current) => [...current, { antibiotic_id: '', method: 'Disk', metric_value: '', metric_secondary_value: '', automatic_interpretation: '', final_interpretation: '', override_reason: '', row_version: 0 }]);
  const groupLabel = selectedGroup?.display_name || 'No approved group mapping';
  const interpretationLabels = useMemo(() => ({ S: 'Sensitive (S)', I: 'Intermediate (I)', R: 'Resistant (R)', SDD: 'Susceptible Dose-Dependent (SDD)' }), []);

  return <Card sx={{ mb: 3 }}><CardContent>
    <Typography variant="h6" fontWeight={800}>Pus Culture and Sensitivity</Typography>
    <Typography variant="body2" color="text.secondary">Specialist worksheet with staged save. Laboratory-approved breakpoint set {setVersion}; mechanism conclusions remain verifier-controlled.</Typography>
    {error && <Alert severity="error" sx={{ mt: 2 }}>{error}</Alert>}{message && <Alert severity="success" sx={{ mt: 2 }}>{message}</Alert>}
    <Typography variant="subtitle1" fontWeight={800} sx={{mt:2}}>1. Specimen / Direct Smear</Typography>
    <Stack direction={{xs:'column',md:'row'}} spacing={1.5} sx={{my:1.5}}>
      <TextField select size="small" label="Specimen Source / Site" value={worksheet.specimen_source} onChange={e=>setWorksheet({...worksheet,specimen_source:e.target.value})} sx={{minWidth:230}}>{SOURCES.map(value=><MenuItem key={value} value={value}>{value}</MenuItem>)}</TextField>
      {worksheet.specimen_source==='Other'&&<TextField size="small" required label="Other source / site" value={worksheet.specimen_source_other} onChange={e=>setWorksheet({...worksheet,specimen_source_other:e.target.value})}/>} 
      <TextField select size="small" label="Gram Stain Pus Cells" value={worksheet.gram_stain_pus_cells} onChange={e=>setWorksheet({...worksheet,gram_stain_pus_cells:e.target.value})} sx={{minWidth:260}}>{PUS_CELLS.map(value=><MenuItem key={value} value={value}>{value}</MenuItem>)}</TextField>
    </Stack>
    <TextField fullWidth multiline minRows={2} label="Direct Smear Organisms" value={worksheet.direct_smear_organisms} onChange={e=>setWorksheet({...worksheet,direct_smear_organisms:e.target.value})}/>
    <Divider sx={{my:2}}/><Typography variant="subtitle1" fontWeight={800}>2. Culture</Typography>
    <TextField select fullWidth size="small" sx={{my:1.5}} label="Culture Status" value={worksheet.culture_status} onChange={e=>{const value=e.target.value;setWorksheet({...worksheet,culture_status:value,final_remarks:value.startsWith('No growth')&&!worksheet.final_remarks?'No aerobic bacterial pathogen grown after 48 hours of incubation at 37°C.':worksheet.final_remarks});setGrowth(value.startsWith('No growth')?'NoGrowth':'Positive')}}>{CULTURE_STATES.map(value=><MenuItem key={value} value={value}>{value}</MenuItem>)}</TextField>
    <Typography variant="subtitle1" fontWeight={800}>3. Organism / Isolates</Typography>
    <Stack direction={{ xs: 'column', md: 'row' }} spacing={1.5} sx={{ my: 2 }}>
      <TextField size="small" type="number" label="Isolate" value={isolateNumber} onChange={(e) => setIsolateNumber(Math.max(1, Number(e.target.value)))} />
      <TextField select size="small" label="Growth" value={growth} onChange={(e) => setGrowth(e.target.value as any)}><MenuItem value="Positive">Positive culture</MenuItem><MenuItem value="NoGrowth">No growth</MenuItem></TextField>
      {growth === 'Positive' && <Autocomplete size="small" options={organisms} value={selectedOrganism||null} getOptionLabel={item=>item.display_name||item.name||item.code} onChange={(_,item)=>setOrganismId(item?.id||'')} renderInput={params=><TextField {...params} label={isolateNumber===1?'Primary microorganism':'Secondary isolate (optional)'}/>} sx={{minWidth:280}}/>}
      <Chip label={`Group: ${growth === 'NoGrowth' ? 'Not applicable' : groupLabel}`} color={selectedGroup || growth === 'NoGrowth' ? 'success' : 'warning'} />
      <Button variant="contained" disabled={!canEnter || (growth === 'Positive' && !organismId)} onClick={() => void saveIsolate()}>Save Isolate</Button>
    </Stack>
    {growth === 'Positive' && <><Divider sx={{my:2}}/><Typography variant="subtitle1" fontWeight={800}>4. Antimicrobial Susceptibility (isolate {isolateNumber})</Typography><Table size="small"><TableHead><TableRow><TableCell>Antibiotic</TableCell><TableCell>Method</TableCell><TableCell>Zone/MIC</TableCell><TableCell>Automatic Interpretation</TableCell><TableCell>Final Interpretation</TableCell><TableCell>Override reason</TableCell><TableCell /></TableRow></TableHead><TableBody>{rows.map((row, index) => <TableRow key={`${index}-${row.antibiotic_id}`}>
      <TableCell><TextField select size="small" value={row.antibiotic_id} onChange={(e) => setRows((all) => all.map((item, i) => i === index ? { ...item, antibiotic_id: e.target.value } : item))} sx={{ minWidth: 180 }}>{antibiotics.map((item) => <MenuItem key={item.id} value={item.id}>{item.name}</MenuItem>)}</TextField></TableCell>
      <TableCell><TextField select size="small" value={row.method} onChange={(e) => void interpret(index, { ...row, method: e.target.value as 'Disk' | 'MIC' })}><MenuItem value="Disk">Disk</MenuItem><MenuItem value="MIC">MIC</MenuItem></TextField></TableCell>
      <TableCell><Stack direction="row" spacing={0.5}><TextField size="small" inputMode="decimal" value={row.metric_value} onChange={(e) => setRows((all) => all.map((item, i) => i === index ? { ...item, metric_value: e.target.value } : item))} onBlur={() => void interpret(index, row)} /><TextField size="small" inputMode="decimal" placeholder="Second" value={row.metric_secondary_value} onChange={(e) => setRows((all) => all.map((item, i) => i === index ? { ...item, metric_secondary_value: e.target.value } : item))} onBlur={() => void interpret(index, row)} /></Stack></TableCell>
      <TableCell>{row.automatic_interpretation ? interpretationLabels[row.automatic_interpretation as keyof typeof interpretationLabels] : <><Chip size="small" color="warning" label="No approved breakpoint configured" />{row.message && <Typography variant="caption" display="block">{row.message}</Typography>}</>}</TableCell>
      <TableCell><TextField select size="small" value={row.final_interpretation} onChange={(e) => setRows((all) => all.map((item, i) => i === index ? { ...item, final_interpretation: e.target.value } : item))}>{Object.entries(interpretationLabels).map(([code, label]) => <MenuItem key={code} value={code}>{label}</MenuItem>)}</TextField></TableCell>
      <TableCell><TextField size="small" value={row.override_reason} onChange={(e) => setRows((all) => all.map((item, i) => i === index ? { ...item, override_reason: e.target.value } : item))} placeholder={row.automatic_interpretation === row.final_interpretation ? 'Not required' : 'Required'} /></TableCell>
      <TableCell><Button disabled={!canEnter || !row.final_interpretation} onClick={() => void saveRow(row)}>Save</Button></TableCell>
    </TableRow>)}</TableBody></Table><Box sx={{ mt: 1 }}><Button disabled={!canEnter || !isolateId} onClick={addRow}>Add Antibiotic</Button></Box></>}
    <Divider sx={{my:2}}/><Typography variant="subtitle1" fontWeight={800}>5. Final Remarks</Typography>
    <TextField fullWidth multiline minRows={3} label="Microbiology Remarks" value={worksheet.final_remarks} onChange={e=>setWorksheet({...worksheet,final_remarks:e.target.value})} sx={{my:1.5}}/>
    <Button variant="contained" disabled={!canEnter||!worksheet.specimen_source||!worksheet.gram_stain_pus_cells||!worksheet.culture_status||(worksheet.specimen_source==='Other'&&!worksheet.specimen_source_other.trim())} onClick={()=>void saveWorksheet()}>Save Worksheet</Button>
  </CardContent></Card>;
};
