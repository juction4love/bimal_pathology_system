/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Append-Only Security & Clinical Audit Log Viewer
 */

import React, { useCallback, useEffect, useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  TextField,
  InputAdornment,
  Typography,
  Chip,
  CircularProgress,
  Button, Stack,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';

import { PageHeader } from '@/components/common/PageHeader';
import { formatAdDateTime } from '@/lib/dateTime';
import { supabase } from '@/lib/supabase';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';

interface AuditRow {
  id: string;
  action: string;
  entity_type: string;
  entity_id: string;
  user_name: string | null;
  timestamp: string;
}

export const AuditLogPage: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState('');
  const [logs, setLogs] = useState<AuditRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actor,setActor]=useState(''); const [action,setAction]=useState(''); const [entity,setEntity]=useState(''); const [dateFrom,setDateFrom]=useState(''); const [dateTo,setDateTo]=useState('');
  const [cursor,setCursor]=useState<{timestamp:string;id:string}|null>(null); const [history,setHistory]=useState<Array<{timestamp:string;id:string}|null>>([]); const [hasNext,setHasNext]=useState(false);

  const loadAuditLogs = useCallback(async () => {
    setLoading(true);
    setError(null);
    const { data, error: queryError } = await supabase.rpc('search_audit_log',{p_actor:actor||null,p_action:action||null,p_entity:entity||null,p_date_from:dateFrom||null,p_date_to:dateTo||null,p_exact_id:searchTerm.trim()||null,p_cursor_timestamp:cursor?.timestamp||null,p_cursor_id:cursor?.id||null,p_limit:51});

    if (queryError) {
      setLogs([]);
      setError('Unable to load the audit trail. Verify your audit-log permission and try again.');
    } else {
      const result=((data||[]) as Array<{item:AuditRow}>).map(row=>row.item);setHasNext(result.length>50);setLogs(result.slice(0,50));
    }
    setLoading(false);
  }, [actor,action,entity,dateFrom,dateTo,searchTerm,cursor]);

  useEffect(() => {
    void loadAuditLogs();
  }, [loadAuditLogs]);

  const visibleLogs = logs;

  return (
    <Box>
      <PageHeader
        title="Append-Only Audit Trail"
        subtitle="Read-only clinical, financial, security, and authentication event history"
      />

      <Card>
        <CardContent>
          <Box sx={{ mb: 2, display:'grid',gridTemplateColumns:{xs:'1fr',md:'repeat(3,1fr)'},gap:1 }}>
            <TextField
              fullWidth
              size="small"
              placeholder="Exact entity ID"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" />
                  </InputAdornment>
                ),
              }}
            />
            <TextField size="small" label="Actor" value={actor} onChange={e=>{setActor(e.target.value);setCursor(null);setHistory([])}}/>
            <TextField size="small" label="Action / event" value={action} onChange={e=>{setAction(e.target.value);setCursor(null);setHistory([])}}/>
            <TextField size="small" label="Entity type" value={entity} onChange={e=>{setEntity(e.target.value);setCursor(null);setHistory([])}}/>
            <TextField size="small" type="date" label="From" InputLabelProps={{shrink:true}} value={dateFrom} onChange={e=>{setDateFrom(e.target.value);setCursor(null);setHistory([])}}/>
            <TextField size="small" type="date" label="To" InputLabelProps={{shrink:true}} value={dateTo} onChange={e=>{setDateTo(e.target.value);setCursor(null);setHistory([])}}/>
          </Box>

          <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />

          <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0' }}>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Timestamp (AD)</TableCell>
                  <TableCell>Action</TableCell>
                  <TableCell>Entity & ID</TableCell>
                  <TableCell>User / Actor</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {loading && (
                  <TableRow>
                    <TableCell colSpan={4} align="center" sx={{ py: 5 }}>
                      <CircularProgress size={28} aria-label="Loading audit trail" />
                    </TableCell>
                  </TableRow>
                )}
                {!loading && visibleLogs.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={4} align="center" sx={{ py: 5, color: 'text.secondary' }}>
                      {searchTerm.trim() ? 'No audit events match this search.' : 'No audit events recorded.'}
                    </TableCell>
                  </TableRow>
                )}
                {!loading && visibleLogs.map((log) => (
                  <TableRow key={log.id} hover>
                    <TableCell sx={{ whiteSpace: 'nowrap' }}>
                      <Typography variant="body2">{formatAdDateTime(log.timestamp)}</Typography>
                    </TableCell>
                    <TableCell>
                      <Chip
                        label={log.action}
                        size="small"
                        color={
                          log.action.includes('CRITICAL') || log.action.includes('REJECT') || log.action.includes('FAILED')
                            ? 'error'
                            : log.action.includes('SIGNED') || log.action.includes('SENT')
                            ? 'success'
                            : 'primary'
                        }
                        sx={{ fontWeight: 700, fontSize: '0.7rem' }}
                      />
                    </TableCell>
                    <TableCell>
                      <Typography variant="body2" fontWeight={600}>
                        {log.entity_type}
                      </Typography>
                      <Typography variant="caption" sx={{ fontFamily: 'monospace', color: 'text.secondary' }}>
                        {log.entity_id}
                      </Typography>
                    </TableCell>
                    <TableCell>
                      <Typography variant="body2">{log.user_name || 'System'}</Typography>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
          <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1.5 }}>
            Server-filtered immutable events. Sensitive before/after payloads are intentionally omitted.
          </Typography>
          <Stack direction="row" justifyContent="space-between" sx={{mt:1}}><Button disabled={!history.length} onClick={()=>{const next=[...history];setCursor(next.pop()||null);setHistory(next)}}>Previous</Button><Button disabled={!hasNext||!logs.length} onClick={()=>{setHistory(current=>[...current,cursor]);const last=logs.at(-1)!;setCursor({timestamp:last.timestamp,id:last.id})}}>Next</Button></Stack>
        </CardContent>
      </Card>
    </Box>
  );
};
