/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Laboratory Worklist & Results
 * High-Density Operational Workspace for Investigation Tracking, Result Entry, and Pathologist Verification
 */

import React, { useState, useEffect, useCallback } from 'react';
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
  Button,
  Typography,
  Tabs,
  Tab,
  Chip,
  MenuItem,
  CircularProgress,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import EditIcon from '@mui/icons-material/Edit';
import FactCheckIcon from '@mui/icons-material/FactCheck';
import RefreshIcon from '@mui/icons-material/Refresh';
import VisibilityIcon from '@mui/icons-material/Visibility';
import { useNavigate, useSearchParams } from 'react-router-dom';

import { PageHeader } from '@/components/common/PageHeader';
import { StatusChip } from '@/components/common/StatusChip';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { formatAdDateTime } from '@/lib/dateTime';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { WORKLIST_PAGE_SIZE, splitWorklistPage, worklistCursor, type WorklistCursor } from './worklistQuery';
import { subscribeWorkflowInvalidation } from '@/lib/workflowInvalidation';

interface WorklistItem {
  id: string; // clinical_order_item_id
  order_id: string;
  test_id: string;
  test_name: string;
  department: string;
  reporting_type: string;
  outsource_lab_name?: string | null;
  status: string; // Pending, SampleCollected, SampleReceived, ResultDrafted, Verified, SignedOff
  created_at: string;
  order?: {
    id: string;
    order_number: string;
    order_date_ad: string;
    order_date_bs: string;
    patient?: {
      uhid: string;
      full_name: string;
      mobile: string;
      gender: string;
      age_years?: number | null;
    };
  };
  sample?: {
    barcode: string;
    status: string;
    specimen_type: string;
    container_type: string;
  };
  results?: Array<{
    id: string;
    flag: string;
    is_critical: boolean;
    status: string;
  }>;
  report?: {
    id: string;
    report_number: string;
    version: number;
    status: string;
  } | null;
}

export const WorklistPage: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { can } = usePermissions();
  const canVerify = can(PERMISSION_KEYS.CAN_VERIFY_RESULTS);
  const getTabFromView = (view: string | null) => {
    if (view === 'Pending') return 1;
    if (view === 'ToVerify') return 2;
    if (view === 'Verified') return 3;
    if (view === 'Signed') return 4;
    return 0;
  };

  const [tabValue, setTabValue] = useState(() => getTabFromView(searchParams.get('view')));
  const [searchTerm, setSearchTerm] = useState(searchParams.get('search') || '');
  const [serverSearch, setServerSearch] = useState(searchParams.get('search') || '');
  const [deptFilter, setDeptFilter] = useState(searchParams.get('department') || 'All');
  const [sampleStatusFilter, setSampleStatusFilter] = useState(searchParams.get('sampleStatus') || 'All');
  const [dateFilter, setDateFilter] = useState(searchParams.get('date') || '');
  const [items, setItems] = useState<WorklistItem[]>([]);
  const [departments, setDepartments] = useState<string[]>([]);
  const [cursor, setCursor] = useState<WorklistCursor | null>(null);
  const [cursorHistory, setCursorHistory] = useState<Array<WorklistCursor | null>>([]);
  const [hasNextPage, setHasNextPage] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const serverView = ['All', 'Pending', 'ToVerify', 'Verified', 'Signed'][tabValue];

  useEffect(() => {
    const view = searchParams.get('view');
    if (view) {
      setTabValue(getTabFromView(view));
    }
  }, [searchParams]);

  const loadWorklist = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: fetchErr } = await supabase.rpc('search_laboratory_worklist', {
        p_search: serverSearch || null,
        p_department: deptFilter === 'All' ? null : deptFilter,
        p_sample_status: sampleStatusFilter === 'All' ? null : sampleStatusFilter,
        p_order_date: dateFilter || null,
        p_view: serverView,
        p_cursor_created_at: cursor?.createdAt || null,
        p_cursor_id: cursor?.id || null,
        p_limit: WORKLIST_PAGE_SIZE,
      });

      if (fetchErr) throw fetchErr;

      const page = splitWorklistPage(
        ((data || []) as Array<{ item: WorklistItem }>).map((row) => row.item),
      );
      setItems(page.rows);
      setHasNextPage(page.hasNext);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load laboratory worklist.'));
    } finally {
      setLoading(false);
    }
  }, [cursor, dateFilter, deptFilter, sampleStatusFilter, serverSearch, serverView]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      setCursor(null);
      setCursorHistory([]);
      setServerSearch(searchTerm.trim());
    }, 300);
    return () => window.clearTimeout(timer);
  }, [searchTerm]);

  useEffect(() => {
    loadWorklist();
  }, [loadWorklist]);
  useEffect(()=>subscribeWorkflowInvalidation('worklist',loadWorklist),[loadWorklist]);

  useEffect(() => {
    void supabase.rpc('list_laboratory_worklist_departments').then(({ data, error: departmentError }) => {
      if (departmentError) {
        setError(safeErrorMessage(departmentError, 'Failed to load worklist departments.'));
        return;
      }
      setDepartments(((data || []) as Array<{ department: string }>).map((row) => row.department));
    });
  }, []);

  const filteredItems = items;

  const resetPagination = () => {
    setCursor(null);
    setCursorHistory([]);
  };

  const loadNextPage = () => {
    const last = items.at(-1);
    if (!last) return;
    setCursorHistory((history) => [...history, cursor]);
    setCursor(worklistCursor(last));
  };

  const loadPreviousPage = () => {
    if (!cursorHistory.length) return;
    setCursor(cursorHistory.at(-1) || null);
    setCursorHistory((history) => history.slice(0, -1));
  };

  return (
    <Box sx={{ width: '100%' }}>
      <PageHeader
        title="Laboratory Worklist & Results"
        subtitle="Manage routine investigations, result entry, verification, and authorized report delivery"
        action={
          <Button variant="outlined" size="small" startIcon={<RefreshIcon />} onClick={loadWorklist} disabled={loading}>
            Refresh
          </Button>
        }
      />

      <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />

      <Card elevation={0} sx={{ border: '1px solid #e2e8f0', bgcolor: '#ffffff' }}>
        {/* Status Filter Tabs */}
        <Box sx={{ borderBottom: 1, borderColor: 'divider', px: 2, pt: 0.5 }}>
          <Tabs
            value={tabValue}
            onChange={(_, val) => { setTabValue(val); resetPagination(); }}
            textColor="primary"
            indicatorColor="primary"
            variant="scrollable"
            scrollButtons="auto"
          >
            <Tab label={`All Items (${items.length})`} sx={{ textTransform: 'none', fontWeight: 600 }} />
            <Tab label="Pending / Draft" sx={{ textTransform: 'none', fontWeight: 600 }} />
            <Tab label="To Verify" sx={{ textTransform: 'none', fontWeight: 600 }} />
            <Tab label="Verified" sx={{ textTransform: 'none', fontWeight: 600 }} />
            <Tab label="Signed Reports" sx={{ textTransform: 'none', fontWeight: 600 }} />
          </Tabs>
        </Box>

        <CardContent sx={{ p: 2 }}>
          {/* Search & Department Toolbar */}
          <Box sx={{ display: 'flex', gap: 2, mb: 2, flexWrap: 'wrap', alignItems: 'center' }}>
            <TextField
              size="small"
              placeholder="Search by Patient, UHID, Lab No, Barcode, Test..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              sx={{ minWidth: 320, flexGrow: { xs: 1, sm: 0 } }}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" sx={{ color: 'text.secondary' }} />
                  </InputAdornment>
                ),
              }}
            />
            <TextField
              select
              size="small"
              label="Department"
              value={deptFilter}
              onChange={(e) => { setDeptFilter(e.target.value); resetPagination(); }}
              sx={{ minWidth: 180 }}
            >
              <MenuItem value="All">All Departments</MenuItem>
              {departments.map((d) => (
                <MenuItem key={d} value={d}>
                  {d}
                </MenuItem>
              ))}
            </TextField>
            <TextField
              select size="small" label="Sample Status" value={sampleStatusFilter}
              onChange={(e) => { setSampleStatusFilter(e.target.value); resetPagination(); }} sx={{ minWidth: 165 }}
            >
              <MenuItem value="All">All Statuses</MenuItem>
              {['Pending', 'Collected', 'Received', 'Processing', 'Completed'].map((status) => (
                <MenuItem key={status} value={status}>{status}</MenuItem>
              ))}
            </TextField>
            <TextField
              size="small" type="date" label="Order Date" value={dateFilter}
              onChange={(e) => { setDateFilter(e.target.value); resetPagination(); }} InputLabelProps={{ shrink: true }}
            />
          </Box>

          {loading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
              <CircularProgress size={32} />
            </Box>
          ) : (
            <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0' }}>
              <Table size="small">
                <TableHead>
                  <TableRow sx={{ bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0' }}>
                    <TableCell sx={{ fontWeight: 700, color: '#0f172a', py: 1 }}>Lab No / Registered</TableCell>
                    <TableCell sx={{ fontWeight: 700, color: '#0f172a', py: 1 }}>Patient Details</TableCell>
                    <TableCell sx={{ fontWeight: 700, color: '#0f172a', py: 1 }}>Investigation & Dept</TableCell>
                    <TableCell sx={{ fontWeight: 700, color: '#0f172a', py: 1 }}>Sample Barcode</TableCell>
                    <TableCell sx={{ fontWeight: 700, color: '#0f172a', py: 1 }}>Progress Status</TableCell>
                    <TableCell align="center" sx={{ fontWeight: 700, color: '#0f172a', py: 1, width: 160 }}>
                      Actions
                    </TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredItems.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={6} align="center" sx={{ py: 4, color: 'text.secondary' }}>
                        No worklist items match your criteria.
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredItems.map((item) => {
                      const resList = item.results || [];
                      const hasCritical = resList.some((r) => r.is_critical || (r.flag && r.flag.includes('Critical')));
                      const isVerified = item.status === 'Verified' || item.status === 'SignedOff';
                      const isSubmitted = !isVerified && resList.some((r) => r.status === 'SubmittedForVerification');
                      const hasEnteredResults = resList.length > 0;
                      const hasSignedReport = Boolean(item.report);
                      const sampleReady = !item.sample || ['Collected', 'Received', 'Processing', 'Completed'].includes(item.sample.status);

                      return (
                        <TableRow
                          key={item.id}
                          hover
                          sx={{
                            borderBottom: '1px solid #f1f5f9',
                            '&:last-child td, &:last-child th': { border: 0 },
                          }}
                        >
                          {/* 1. Lab No / Registered */}
                          <TableCell sx={{ py: 1 }}>
                            <Typography variant="body2" fontWeight={700} color="primary.main" sx={{ fontFamily: 'monospace' }}>
                              {item.order?.order_number || 'Lab Order'}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              {formatAdDateTime(item.created_at)}
                            </Typography>
                          </TableCell>

                          {/* 2. Patient Details */}
                          <TableCell sx={{ py: 1 }}>
                            <Typography variant="body2" fontWeight={600} color="text.primary">
                              {item.order?.patient?.full_name || 'Patient'}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              {item.order?.patient?.uhid} &bull; {item.order?.patient?.age_years ? `${item.order.patient.age_years}Y` : ''} / {item.order?.patient?.gender}
                            </Typography>
                          </TableCell>

                          {/* 3. Investigation & Department */}
                          <TableCell sx={{ py: 1 }}>
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, flexWrap: 'wrap' }}>
                              <Typography variant="body2" fontWeight={600} color="text.primary">
                                {item.test_name}
                              </Typography>
                              {hasCritical && (
                                <Chip
                                  size="small"
                                  label="CRITICAL"
                                  color="error"
                                  sx={{ height: 18, fontSize: '0.62rem', fontWeight: 800 }}
                                />
                              )}
                            </Box>
                            <Typography variant="caption" color="text.secondary">
                              {item.department}
                            </Typography>
                            {item.reporting_type === 'OutsourceWithBimalReport' && item.outsource_lab_name && (
                              <Typography variant="caption" sx={{ display: 'block', color: 'secondary.main' }}>
                                Ref: {item.outsource_lab_name}
                              </Typography>
                            )}
                          </TableCell>

                          {/* 4. Sample Barcode & Specimen */}
                          <TableCell sx={{ py: 1 }}>
                            <Typography variant="body2" sx={{ fontFamily: 'monospace', fontWeight: 600 }}>
                              {item.sample?.barcode || '-'}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              {item.sample?.specimen_type || 'No specimen'} · {item.sample?.status || 'Sample Pending'}
                            </Typography>
                          </TableCell>

                          {/* 5. Progress Status */}
                          <TableCell sx={{ py: 1 }}>
                            {hasSignedReport ? (
                              <Chip
                                label={`Report: ${item.report?.report_number || 'Signed'}`}
                                color="success"
                                size="small"
                                sx={{ fontWeight: 700, fontSize: '0.72rem', height: 22 }}
                              />
                            ) : (
                              <StatusChip status={isVerified ? 'Verified' : isSubmitted ? 'SubmittedForVerification' : 'Draft'} />
                            )}
                          </TableCell>

                          {/* 6. Operational Action Column (Zero PDF/Print buttons) */}
                          <TableCell align="center" sx={{ py: 1 }}>
                            {hasSignedReport || isVerified ? (
                              /* Signed / Verified -> View Input */
                              <Button
                                size="small"
                                variant="outlined"
                                color="primary"
                                startIcon={<VisibilityIcon />}
                                onClick={() => navigate(`/worklist/order/${item.order_id}?item=${item.id}`)}
                                sx={{ fontSize: '0.75rem', px: 1.25, py: 0.35, textTransform: 'none', fontWeight: 600 }}
                              >
                                View Input
                              </Button>
                            ) : isSubmitted ? (
                              /* Submitted For Verification -> Review & Verify (Verifier) or View Input (Tech) */
                              canVerify ? (
                                <Button
                                  size="small"
                                  variant="contained"
                                  color="primary"
                                  startIcon={<FactCheckIcon />}
                                  onClick={() => navigate(`/worklist/order/${item.order_id}?item=${item.id}`)}
                                  sx={{ fontSize: '0.75rem', px: 1.25, py: 0.35, textTransform: 'none', fontWeight: 700 }}
                                >
                                  Review & Verify
                                </Button>
                              ) : (
                                <Button
                                  size="small"
                                  variant="outlined"
                                  color="primary"
                                  startIcon={<VisibilityIcon />}
                                  onClick={() => navigate(`/worklist/order/${item.order_id}?item=${item.id}`)}
                                  sx={{ fontSize: '0.75rem', px: 1.25, py: 0.35, textTransform: 'none', fontWeight: 600 }}
                                >
                                  View Input
                                </Button>
                              )
                            ) : !sampleReady ? (
                              <Button
                                size="small"
                                variant="outlined"
                                color="warning"
                                onClick={() => navigate(`/samples?search=${encodeURIComponent(item.order?.order_number || '')}`)}
                                sx={{ fontSize: '0.75rem', px: 1.25, py: 0.35, textTransform: 'none', fontWeight: 700 }}
                              >
                                Sample Pending
                              </Button>
                            ) : (
                              /* Ready Draft / Pending -> Enter Results or Continue Entry */
                              <Button
                                size="small"
                                variant="contained"
                                color="primary"
                                startIcon={<EditIcon />}
                                onClick={() => navigate(`/worklist/order/${item.order_id}?item=${item.id}`)}
                                sx={{ fontSize: '0.75rem', px: 1.25, py: 0.35, textTransform: 'none', fontWeight: 700 }}
                              >
                                {hasEnteredResults ? 'Continue Entry' : 'Enter Results'}
                              </Button>
                            )}
                          </TableCell>
                        </TableRow>
                      );
                    })
                  )}
                </TableBody>
              </Table>
            </TableContainer>
          )}
          {!loading && (
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mt: 2 }}>
              <Typography variant="caption" color="text.secondary">
                Page {cursorHistory.length + 1} · {items.length} item{items.length === 1 ? '' : 's'}
              </Typography>
              <Box sx={{ display: 'flex', gap: 1 }}>
                <Button size="small" variant="outlined" onClick={loadPreviousPage} disabled={!cursorHistory.length}>
                  Previous
                </Button>
                <Button size="small" variant="outlined" onClick={loadNextPage} disabled={!hasNextPage}>
                  Next
                </Button>
              </Box>
            </Box>
          )}
        </CardContent>
      </Card>
    </Box>
  );
};
