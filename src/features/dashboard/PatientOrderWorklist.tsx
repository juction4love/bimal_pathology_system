import React, { useCallback, useEffect, useState } from 'react';
import {
  Box, Card, CardContent, Chip, CircularProgress, InputAdornment, MenuItem,
  Paper, Table, TableBody, TableCell, TableContainer, TableHead, TableRow,
  TextField, Typography,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { StatusChip } from '@/components/common/StatusChip';
import { subscribeWorkflowInvalidation } from '@/lib/workflowInvalidation';

type WorkflowFilter = 'Today' | 'Pending' | 'Processing' | 'AwaitingVerification' | 'ReportReady';

export const PatientOrderWorklist: React.FC = () => {
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<WorkflowFilter>('Today');
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadRows = useCallback(async (term: string, workflow: WorkflowFilter) => {
    setLoading(true);
    setError(null);
    try {
      const {data,error:queryError}=await supabase.rpc('search_dashboard_orders',{
        p_search:term.trim()||null,p_workflow:workflow,p_cursor_created_at:null,p_cursor_id:null,p_limit:30,
      });
      if (queryError) throw queryError;
      setRows(((data||[]) as Array<{item:any}>).slice(0,30).map(row=>row.item));
    } catch (caught: any) {
      setError(safeErrorMessage(caught, 'Unable to load patient/order worklist.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => loadRows(search, filter), 350);
    return () => window.clearTimeout(timer);
  }, [search, filter, loadRows]);
  useEffect(()=>subscribeWorkflowInvalidation('dashboard',()=>void loadRows(search,filter)),[search,filter,loadRows]);

  const openWorkflow = (order: any) => {
    const firstItem = order.items?.[0];
    if (firstItem?.id) navigate(`/worklist/entry/${firstItem.id}`);
    else navigate('/samples');
  };

  return (
    <Card sx={{ mt: 3 }}>
      <CardContent>
        <Typography variant="h6" fontWeight={700}>Patient / Order Worklist</Typography>
        <Typography variant="caption" color="text.secondary">
          Server-side lookup by Lab No., UHID, patient, mobile, invoice or test
        </Typography>
        <Box sx={{ display: 'flex', gap: 1.5, mt: 2, mb: 2, flexWrap: 'wrap' }}>
          <TextField
            size="small"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search Lab No., UHID, name, mobile, invoice, test…"
            sx={{ flex: '1 1 360px' }}
            InputProps={{ startAdornment: <InputAdornment position="start"><SearchIcon /></InputAdornment> }}
          />
          <TextField select size="small" value={filter} onChange={(event) => setFilter(event.target.value as WorkflowFilter)} sx={{ minWidth: 210 }}>
            <MenuItem value="Today">Today</MenuItem>
            <MenuItem value="Pending">Pending</MenuItem>
            <MenuItem value="Processing">Processing</MenuItem>
            <MenuItem value="AwaitingVerification">Awaiting Verification</MenuItem>
            <MenuItem value="ReportReady">Report Ready</MenuItem>
          </TextField>
        </Box>
        {error && <Typography color="error" variant="body2" sx={{ mb: 1 }}>{error}</Typography>}
        {loading ? <Box sx={{ p: 3, textAlign: 'center' }}><CircularProgress size={28} /></Box> : (
          <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', maxHeight: 420 }}>
            <Table size="small" stickyHeader>
              <TableHead><TableRow>
                <TableCell>Lab No. / Invoice</TableCell><TableCell>Patient</TableCell>
                <TableCell>Tests</TableCell><TableCell>Status</TableCell>
              </TableRow></TableHead>
              <TableBody>
                {rows.length === 0 ? <TableRow><TableCell colSpan={4} align="center" sx={{ py: 3 }}>No matching orders.</TableCell></TableRow> : rows.map((order) => (
                  <TableRow key={order.id} hover onClick={() => openWorkflow(order)} sx={{ cursor: 'pointer' }}>
                    <TableCell>
                      <Typography fontWeight={700} color="primary.main">{order.order_number}</Typography>
                      <Typography variant="caption" color="text.secondary">{order.bill?.bill_number || '-'}</Typography>
                    </TableCell>
                    <TableCell>
                      <Typography variant="body2" fontWeight={600}>{order.patient?.full_name || '-'}</Typography>
                      <Typography variant="caption" color="text.secondary">
                        {order.patient?.uhid ? `UHID: ${order.patient.uhid}` : ''} {order.patient?.mobile ? `· ${order.patient.mobile}` : ''}
                      </Typography>
                    </TableCell>
                    <TableCell>
                      <Box sx={{ display: 'flex', gap: 0.5, flexWrap: 'wrap', alignItems: 'center' }}>
                        {(order.items || []).slice(0, 4).map((item: any) => (
                          <Chip key={item.id} size="small" variant="outlined" label={item.test_name} />
                        ))}
                      </Box>
                    </TableCell>
                    <TableCell><StatusChip status={order.status} /></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        )}
      </CardContent>
    </Card>
  );
};
