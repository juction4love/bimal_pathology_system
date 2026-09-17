import React, { useCallback, useEffect, useState } from 'react';
import { Box, Button, Chip, CircularProgress, MenuItem, Paper, Stack, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, TextField, Typography } from '@mui/material';
import { supabase } from '@/lib/supabase';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';

type SmsStatusRow = {
  id: string;
  event_type: string;
  lab_no: string | null;
  mobile: string;
  status: string;
  provider_status: string | null;
  retry_count: number;
  manual_retry_count: number;
  provider_message_id: string | null;
  estimated_segments: number;
  created_at: string;
  sent_at: string | null;
};
type GatewayHealth = { server_time:string;queue:{pending_count:number;failed_count:number;deadletter_count:number;stale_processing_count:number;oldest_pending_at:string|null};instances:Array<{instance_id:string;hostname:string;gateway_version:string;provider_name:string;last_heartbeat_at:string|null;last_provider_success_at:string|null;provider_health:string;safe_last_error_code:string|null;active_job_count:number;claiming_enabled:boolean;online:boolean}> };

export const SmsDeliveryPage: React.FC = () => {
  const [rows, setRows] = useState<SmsStatusRow[]>([]);
  const [gatewayHealth,setGatewayHealth]=useState<GatewayHealth|null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [statusFilter, setStatusFilter] = useState('All');
  const [typeFilter, setTypeFilter] = useState('All');
  const [search, setSearch] = useState('');
  const [serverSearch,setServerSearch]=useState(''); const [dateFilter,setDateFilter]=useState('');
  const [cursor,setCursor]=useState<{timestamp:string;id:string}|null>(null); const [cursorHistory,setCursorHistory]=useState<Array<{timestamp:string;id:string}|null>>([]); const [hasNext,setHasNext]=useState(false);

  useEffect(() => {
    const timer=window.setTimeout(()=>{setServerSearch(search.trim());setCursor(null);setCursorHistory([])},300);return()=>window.clearTimeout(timer);
  }, [search]);
  const reload = useCallback(async () => {
      setLoading(true);
      const { data, error: rpcError } = await supabase.rpc('search_sms_delivery_status', { p_status:statusFilter==='All'?null:statusFilter,p_event_type:typeFilter==='All'?null:typeFilter,p_search:serverSearch||null,p_date:dateFilter||null,p_cursor_created_at:cursor?.timestamp||null,p_cursor_id:cursor?.id||null,p_limit:51 });
      if (rpcError) setError('SMS delivery status is unavailable.');
      else {const result=((data??[]) as Array<{item:SmsStatusRow}>).map(row=>row.item);setHasNext(result.length>50);setRows(result.slice(0,50));}
      setLoading(false);
  },[statusFilter,typeFilter,serverSearch,dateFilter,cursor]);
  useEffect(()=>{void reload()},[reload]);
  useEffect(()=>{let mounted=true;const load=async()=>{const rpc=supabase.rpc as unknown as (name:'get_sms_gateway_v2_health')=>Promise<{data:unknown;error:unknown}>;const {data,error:healthError}=await rpc('get_sms_gateway_v2_health');if(mounted&&!healthError)setGatewayHealth(data as GatewayHealth);};void load();const timer=window.setInterval(()=>void load(),30000);return()=>{mounted=false;window.clearInterval(timer)}},[]);
  const retry = async (row: SmsStatusRow) => {
    const reason = window.prompt('Reason for retry (required):')?.trim();
    if (!reason) return;
    const { error: retryError } = await supabase.rpc('retry_sms_delivery', { p_sms_id: row.id, p_reason: reason });
    if (retryError) setError('Retry was refused. Sent items and unauthorized retries cannot be retried.');
    else await reload();
  };
  const visible = rows;

  return (
    <Box>
      <Typography variant="h4" gutterBottom>SMS Delivery Status</Typography>
      <Typography color="text.secondary" sx={{ mb: 3 }}>
        Super Admin system-delivery monitoring. SMS failures never block billing or report issuance.
      </Typography>
      <SmartMessageDialog open={Boolean(error)} message={error} onPrimary={() => setError('')} />
      {gatewayHealth && <Paper variant="outlined" sx={{p:2,mb:2}}><Stack direction={{xs:'column',md:'row'}} spacing={2} alignItems={{md:'center'}}>
        <Typography variant="subtitle1">Gateway 2.0</Typography>
        {gatewayHealth.instances.length===0?<Chip label="Not registered"/>:gatewayHealth.instances.map(instance=><React.Fragment key={instance.instance_id}><Chip color={instance.online?'success':'error'} label={instance.online?'Online':'Offline'}/><Typography variant="body2">{instance.hostname} · {instance.gateway_version} · {instance.provider_name}</Typography><Chip size="small" label={instance.provider_health}/>{instance.safe_last_error_code&&<Typography variant="caption">{instance.safe_last_error_code}</Typography>}</React.Fragment>)}
        <Typography variant="caption">Pending {gatewayHealth.queue.pending_count} · Failed {gatewayHealth.queue.failed_count} · DeadLetter {gatewayHealth.queue.deadletter_count} · Stale {gatewayHealth.queue.stale_processing_count}</Typography>
      </Stack></Paper>}
      <Stack direction={{ xs: 'column', md: 'row' }} spacing={2} sx={{ mb: 2 }}>
        <TextField select size="small" label="Status" value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)} sx={{ minWidth: 170 }}>
          {['All', 'Pending', 'Processing', 'Sent', 'Failed', 'DeadLetter'].map((value) => <MenuItem key={value} value={value}>{value}</MenuItem>)}
        </TextField>
        <TextField select size="small" label="Type" value={typeFilter} onChange={(event) => setTypeFilter(event.target.value)} sx={{ minWidth: 210 }}>
          {['All', 'Payment Confirmation', 'Report Ready'].map((value) => <MenuItem key={value} value={value}>{value}</MenuItem>)}
        </TextField>
        <TextField size="small" label="Lab No. or mobile" value={search} onChange={(event) => setSearch(event.target.value)} />
        <TextField size="small" type="date" label="Created date" value={dateFilter} onChange={event=>{setDateFilter(event.target.value);setCursor(null);setCursorHistory([])}} InputLabelProps={{shrink:true}}/>
      </Stack>
      {loading ? <CircularProgress /> : (
        <TableContainer component={Paper}>
          <Table size="small">
            <TableHead><TableRow>
              {['Type', 'Lab No.', 'Mobile', 'Status', 'Last safe error', 'Attempts', 'Provider message', 'Created', 'Sent', 'Action'].map((label) => <TableCell key={label}>{label}</TableCell>)}
            </TableRow></TableHead>
            <TableBody>
              {visible.map((row) => <TableRow key={row.id}>
                <TableCell>{row.event_type}</TableCell>
                <TableCell>{row.lab_no || '—'}</TableCell>
                <TableCell>{row.mobile}</TableCell>
                <TableCell><Chip size="small" label={row.status} color={row.status === 'Sent' ? 'success' : row.status === 'DeadLetter' ? 'error' : 'default'} /></TableCell>
                <TableCell>{row.provider_status || '—'}</TableCell>
                <TableCell>{row.retry_count}</TableCell>
                <TableCell>{row.provider_message_id || '—'}</TableCell>
                <TableCell>{new Date(row.created_at).toLocaleString()}</TableCell>
                <TableCell>{row.sent_at ? new Date(row.sent_at).toLocaleString() : '—'}</TableCell>
                <TableCell>{['Failed', 'DeadLetter'].includes(row.status) ? <Button size="small" onClick={() => void retry(row)}>Retry</Button> : '—'}</TableCell>
              </TableRow>)}
              {visible.length === 0 && <TableRow><TableCell colSpan={10}>No SMS queue events match the filters.</TableCell></TableRow>}
            </TableBody>
          </Table>
        </TableContainer>
      )}
      <Stack direction="row" justifyContent="space-between" sx={{mt:2}}><Button disabled={!cursorHistory.length} onClick={()=>{const history=[...cursorHistory];setCursor(history.pop()||null);setCursorHistory(history)}}>Previous</Button><Typography variant="caption">50 rows per page · server-filtered</Typography><Button disabled={!hasNext||!rows.length} onClick={()=>{setCursorHistory(current=>[...current,cursor]);const last=rows.at(-1)!;setCursor({timestamp:last.created_at,id:last.id})}}>Next</Button></Stack>
    </Box>
  );
};
