/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Patient Master Registry & Comprehensive History Viewer (Phase 5)
 * Enforces Patient Rule: Patient registration is strictly initiated via New Bill booking.
 */

import React, { useState, useEffect, useCallback, useRef } from 'react';
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
  Alert,
  CircularProgress,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Tabs,
  Tab,
  Grid,
  MenuItem,
  Snackbar,
  FormControlLabel,
  Switch,
  Chip,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import AddShoppingCartIcon from '@mui/icons-material/AddShoppingCart';
import InfoOutlinedIcon from '@mui/icons-material/InfoOutlined';
import RefreshIcon from '@mui/icons-material/Refresh';
import EditIcon from '@mui/icons-material/Edit';
import VisibilityIcon from '@mui/icons-material/Visibility';
import PersonAddIcon from '@mui/icons-material/PersonAdd';
import ArchiveIcon from '@mui/icons-material/Archive';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import RestoreIcon from '@mui/icons-material/Restore';
import { normalizeNepalMobile, normalizePatientName, normalizePatientText, validateNepalMobile, validatePatientAge } from '@/lib/patientEntry';
import { useNavigate, useSearchParams } from 'react-router-dom';

import { PageHeader } from '@/components/common/PageHeader';
import { StatusChip } from '@/components/common/StatusChip';
import { MoneyDisplay } from '@/components/common/MoneyDisplay';
import { formatAdDateTime, formatDualDate } from '@/lib/dateTime';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { REGISTRY_PAGE_SIZE, registryCursor, splitServerPage, type RegistryCursor } from '@/lib/serverPagination';
import { publishWorkflowInvalidation, subscribeWorkflowInvalidation } from '@/lib/workflowInvalidation';

interface DbPatient {
  id: string;
  uhid: string;
  mobile: string;
  title?: string | null;
  full_name: string;
  gender: string;
  dob?: string | null;
  age_years?: number | null;
  address: string;
  email?: string | null;
  identification_no?: string | null;
  age_months?: number | null;
  age_days?: number | null;
  is_active: boolean;
  archived_at?: string | null;
  created_at: string;
}

export const PatientsPage: React.FC = () => {
  const navigate = useNavigate();
  const [routeParams] = useSearchParams();
  const { can } = usePermissions();
  const routeEditHandled = useRef(false);

  const [searchTerm, setSearchTerm] = useState('');
  const [serverSearch, setServerSearch] = useState('');
  const [dateFilter, setDateFilter] = useState(routeParams.get('date') || '');
  const [patients, setPatients] = useState<DbPatient[]>([]);
  const [cursor, setCursor] = useState<RegistryCursor | null>(null);
  const [cursorHistory, setCursorHistory] = useState<Array<RegistryCursor | null>>([]);
  const [hasNextPage, setHasNextPage] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const dateParam = routeParams.get('date');
    if (dateParam && dateParam !== dateFilter) {
      setDateFilter(dateParam);
      setCursor(null);
      setCursorHistory([]);
    }
  }, [dateFilter, routeParams]);

  // Patient Detail / History Dialog State
  const [detailOpen, setDetailOpen] = useState(false);
  const [selectedPatient, setSelectedPatient] = useState<DbPatient | null>(null);
  const [currentTab, setCurrentTab] = useState(0);

  // Patient History Sub-Data
  const [patientOrders, setPatientOrders] = useState<any[]>([]);
  const [patientBills, setPatientBills] = useState<any[]>([]);
  const [patientReports, setPatientReports] = useState<any[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyHasNext,setHistoryHasNext]=useState({orders:false,bills:false,reports:false});

  // Edit Patient State
  const [editOpen, setEditOpen] = useState(false);
  const [editForm, setEditForm] = useState<Partial<DbPatient>>({});
  const [isCreating, setIsCreating] = useState(false);
  const [showArchived, setShowArchived] = useState(false);
  const [confirmAction, setConfirmAction] = useState<{ kind: 'archive' | 'restore' | 'delete'; patient: DbPatient } | null>(null);
  const [saving, setSaving] = useState(false);
  const [toastMsg, setToastMsg] = useState<string | null>(null);

  const loadPatients = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: fetchErr } = await supabase.rpc('search_patient_registry', {
        p_search: serverSearch || null,
        p_active_state: showArchived ? 'All' : 'Active',
        p_date: dateFilter || null,
        p_cursor_created_at: cursor?.timestamp || null,
        p_cursor_id: cursor?.id || null,
        p_limit: REGISTRY_PAGE_SIZE,
      });

      if (fetchErr) throw fetchErr;
      const page=splitServerPage(((data||[]) as Array<{item:DbPatient}>).map(row=>row.item));
      setPatients(page.rows);setHasNextPage(page.hasNext);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load patient records.'));
    } finally {
      setLoading(false);
    }
  }, [cursor, dateFilter, serverSearch, showArchived]);

  useEffect(() => {
    loadPatients();
  }, [loadPatients]);

  useEffect(()=>{const timer=window.setTimeout(()=>{setCursor(null);setCursorHistory([]);setServerSearch(searchTerm.trim())},300);return()=>window.clearTimeout(timer)},[searchTerm]);
  useEffect(()=>subscribeWorkflowInvalidation('patients',loadPatients),[loadPatients]);

  const handleOpenDetail = async (patient: DbPatient) => {
    setSelectedPatient(patient);
    setCurrentTab(0);
    setDetailOpen(true);
    setHistoryLoading(true);

    try {
      const [ordersResult,billsResult,reportsResult]=await Promise.all(['orders','bills','reports'].map(section=>supabase.rpc('search_patient_history',{p_patient_id:patient.id,p_section:section,p_cursor_timestamp:null,p_cursor_id:null,p_limit:26})));

      const historyError = ordersResult.error || billsResult.error || reportsResult.error;
      if (historyError) throw historyError;

      const unwrap=(result:any)=>((result.data||[]) as Array<{item:any}>).map(row=>row.item);
      const orders=unwrap(ordersResult),bills=unwrap(billsResult),reports=unwrap(reportsResult);
      setPatientOrders(orders.slice(0,25));setPatientBills(bills.slice(0,25));setPatientReports(reports.slice(0,25));
      setHistoryHasNext({orders:orders.length>25,bills:bills.length>25,reports:reports.length>25});
    } catch (err: any) {
      console.error('[Patient History Error]', err);
      setPatientOrders([]);
      setPatientBills([]);
      setPatientReports([]);
      setError(safeErrorMessage(err, 'Failed to load patient history.'));
    } finally {
      setHistoryLoading(false);
    }
  };

  const loadMoreHistory=async()=>{
    if(!selectedPatient)return;const sections=['orders','bills','reports'] as const;const section=sections[currentTab];const current=section==='orders'?patientOrders:section==='bills'?patientBills:patientReports;const last=current.at(-1);if(!last)return;
    setHistoryLoading(true);const timestamp=section==='reports'?last.signed_at:last.created_at;const {data,error:loadError}=await supabase.rpc('search_patient_history',{p_patient_id:selectedPatient.id,p_section:section,p_cursor_timestamp:timestamp,p_cursor_id:last.id,p_limit:26});
    setHistoryLoading(false);if(loadError){setError(safeErrorMessage(loadError,'Failed to load older patient history.'));return;}const rows=((data||[]) as Array<{item:any}>).map(row=>row.item);const page=rows.slice(0,25);
    if(section==='orders')setPatientOrders(value=>[...value,...page]);else if(section==='bills')setPatientBills(value=>[...value,...page]);else setPatientReports(value=>[...value,...page]);setHistoryHasNext(value=>({...value,[section]:rows.length>25}));
  };

  const handleOpenEdit = (patient: DbPatient) => {
    setIsCreating(false);
    setSelectedPatient(patient);
    setEditForm({
      title: patient.title || 'Mr.',
      full_name: patient.full_name,
      mobile: patient.mobile,
      gender: patient.gender,
      dob: patient.dob || null,
      age_years: patient.age_years,
      age_months: patient.age_months,
      age_days: patient.age_days,
      address: patient.address,
      email: patient.email || '',
      identification_no: patient.identification_no || '',
    });
    setEditOpen(true);
  };

  useEffect(() => {
    const patientId = routeParams.get('edit');
    if (routeEditHandled.current || loading || !patientId || !can(PERMISSION_KEYS.CAN_EDIT_PATIENT)) return;
    const patient = patients.find((candidate) => candidate.id === patientId && candidate.is_active !== false);
    if (patient) {
      routeEditHandled.current = true;
      handleOpenEdit(patient);
      return;
    }

    // Route-driven editing must not depend on the patient being in the current
    // keyset page. This remains an ordinary authenticated, RLS-governed read.
    routeEditHandled.current = true;
    void supabase
      .from('patients')
      .select('id, uhid, mobile, title, full_name, gender, dob, age_years, age_months, age_days, address, email, identification_no, is_active, archived_at, created_at')
      .eq('id', patientId)
      .eq('is_active', true)
      .maybeSingle()
      .then(({ data, error: lookupError }) => {
        if (lookupError) {
          setError(safeErrorMessage(lookupError, 'Unable to open the requested patient.'));
          return;
        }
        if (!data) {
          setError('The requested active patient is unavailable or you do not have access.');
          return;
        }
        handleOpenEdit(data as DbPatient);
      });
  }, [can, loading, patients, routeParams]);

  const handleOpenAdd = () => {
    setSelectedPatient(null);
    setIsCreating(true);
    setEditForm({ title: 'Mr.', full_name: '', mobile: '', gender: 'Male', dob: null, age_years: null, age_months: null, age_days: null, address: '', email: '', identification_no: '' });
    setEditOpen(true);
  };

  const handleSaveEdit = async () => {
    const normalizedFullName = normalizePatientName(editForm.full_name);
    const normalizedAddress = normalizePatientText(editForm.address);
    const normalizedMobile = normalizeNepalMobile(editForm.mobile);
    if (!normalizedFullName) {
      setError('Patient full legal name is required.');
      return;
    }
    if (!normalizedAddress) { setError('Patient address is required.'); return; }
    const mobileError = validateNepalMobile(editForm.mobile);
    if (mobileError) { setError(mobileError); return; }
    const ageError = validatePatientAge({ years: editForm.age_years ?? null, months: editForm.age_months ?? null, days: editForm.age_days ?? null }, false);
    if (ageError) {
      setError(ageError);
      return;
    }

    const payload = {
          title: editForm.title,
          full_name: normalizedFullName,
          mobile: normalizedMobile,
          gender: editForm.gender,
          dob: editForm.dob || null,
          age_years: editForm.age_years,
          age_months: editForm.age_months,
          age_days: editForm.age_days,
          address: normalizedAddress,
          email: normalizePatientText(editForm.email) || null,
          identification_no: normalizePatientText(editForm.identification_no) || null,
        };
    try {
      setSaving(true);
      const result = isCreating
        ? await supabase.rpc('create_patient', { p_patient_data: payload })
        : await supabase.rpc('update_patient_demographics', { p_patient_id: selectedPatient?.id, p_patient_data: payload });
      if (result.error) throw result.error;

      setEditOpen(false);
      setToastMsg(isCreating ? 'Patient created successfully.' : 'Patient demographics updated. Historical documents were not changed.');
      publishWorkflowInvalidation('patient-changed',['patients','bills','samples','worklist','reports','dashboard'],selectedPatient?.id);
      await loadPatients();
      const returnTo = routeParams.get('returnTo');
      if (!isCreating && returnTo?.startsWith('/worklist/entry/')) navigate(returnTo);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to save patient record.'));
    } finally {
      setSaving(false);
    }
  };

  const handleConfirmedAction = async () => {
    if (!confirmAction) return;
    setSaving(true);
    try {
      const { kind, patient } = confirmAction;
      const result = kind === 'delete'
        ? await supabase.rpc('delete_unused_patient', { p_patient_id: patient.id })
        : await supabase.rpc('set_patient_archived', { p_patient_id: patient.id, p_archived: kind === 'archive' });
      if (result.error) throw result.error;
      setToastMsg(kind === 'delete' ? 'Unused patient deleted.' : kind === 'archive' ? 'Patient archived. Historical records remain intact.' : 'Patient restored.');
      publishWorkflowInvalidation('patient-changed',['patients','dashboard'],patient.id);
      setConfirmAction(null);
      await loadPatients();
    } catch (err: any) {
      setConfirmAction(null);
      setError(safeErrorMessage(err, 'Patient action failed.'));
    } finally { setSaving(false); }
  };

  const visiblePatients = patients;

  return (
    <Box>
      <PageHeader
        title="Patient Master Registry"
        subtitle="Lookup registered patients by Mobile, UHID, or Name. Comprehensive clinical visit and report history."
        action={
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button variant="outlined" startIcon={<RefreshIcon />} onClick={loadPatients} disabled={loading}>
              Refresh
            </Button>
            {can(PERMISSION_KEYS.CAN_EDIT_PATIENT) && (
              <Button variant="contained" startIcon={<PersonAddIcon />} onClick={handleOpenAdd}>Add Patient</Button>
            )}
            {can(PERMISSION_KEYS.CAN_CREATE_BILL) && (
              <Button
                variant="contained"
                color="primary"
                startIcon={<AddShoppingCartIcon />}
                onClick={() => navigate('/billing/new')}
              >
                Book Investigation / New Bill
              </Button>
            )}
          </Box>
        }
      />

      <Alert severity="info" icon={<InfoOutlinedIcon />} sx={{ mb: 3 }}>
        Add an unbilled patient here or register one during New Bill. Demographic corrections change only the current profile; finalized bills and signed reports keep their original snapshots.
      </Alert>

      <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />

      <Card>
        <CardContent>
          <Box sx={{ mb: 2, display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center' }}>
            <TextField
              size="small"
              placeholder="Search by Mobile, UHID, or Patient Name..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              sx={{ minWidth: 300, flex: '1 1 300px' }}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" />
                  </InputAdornment>
                ),
              }}
            />
            <TextField
              size="small"
              type="date"
              label="Registered Date"
              value={dateFilter}
              onChange={(e) => {
                setDateFilter(e.target.value);
                setCursor(null);
                setCursorHistory([]);
              }}
              InputLabelProps={{ shrink: true }}
              sx={{ minWidth: 160 }}
            />
            {dateFilter && (
              <Button
                size="small"
                variant="outlined"
                color="inherit"
                onClick={() => {
                  setDateFilter('');
                  setCursor(null);
                  setCursorHistory([]);
                }}
              >
                Clear Date
              </Button>
            )}
            <FormControlLabel
              control={
                <Switch
                  checked={showArchived}
                  onChange={(e) => {
                    setShowArchived(e.target.checked);
                    setCursor(null);
                    setCursorHistory([]);
                  }}
                />
              }
              label="Show archived patients"
            />
          </Box>

          {loading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
              <CircularProgress />
            </Box>
          ) : (
            <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0' }}>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>UHID</TableCell>
                    <TableCell>Patient Name & Gender</TableCell>
                    <TableCell>Primary Mobile</TableCell>
                    <TableCell>Address</TableCell>
                    <TableCell>Registered Date</TableCell>
                    <TableCell align="center">Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {visiblePatients.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={6} align="center" sx={{ py: 4, color: 'text.secondary' }}>
                        No patient records found in database.
                      </TableCell>
                    </TableRow>
                  ) : (
                    visiblePatients.map((pat) => (
                      <TableRow key={pat.id} hover sx={pat.is_active === false ? { opacity: 0.7, bgcolor: 'action.hover' } : undefined}>
                        <TableCell>
                          <Typography variant="body2" fontWeight={700} color="primary.main">
                            {pat.uhid}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2" fontWeight={600}>
                            {pat.title ? `${pat.title} ` : ''}{pat.full_name}
                            {pat.is_active === false && <Chip label="Archived" size="small" sx={{ ml: 1 }} />}
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            {pat.age_years !== null ? `${pat.age_years}Y` : ''} / {pat.gender}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2" sx={{ fontFamily: 'monospace' }}>
                            {pat.mobile}
                          </Typography>
                        </TableCell>
                        <TableCell>{pat.address}</TableCell>
                        <TableCell>{formatDualDate(pat.created_at)}</TableCell>
                        <TableCell align="center">
                          <Box sx={{ display: 'flex', gap: 0.5, justifyContent: 'center' }}>
                            <Button
                              size="small"
                              variant="outlined"
                              startIcon={<VisibilityIcon />}
                              onClick={() => handleOpenDetail(pat)}
                            >
                              History
                            </Button>
                            {can(PERMISSION_KEYS.CAN_EDIT_PATIENT) && pat.is_active !== false && (
                              <Button
                                size="small"
                                variant="text"
                                color="secondary"
                                startIcon={<EditIcon />}
                                onClick={() => handleOpenEdit(pat)}
                              >
                                Edit
                              </Button>
                            )}
                            {can(PERMISSION_KEYS.CAN_EDIT_PATIENT) && (
                              <Button size="small" color={pat.is_active === false ? 'success' : 'warning'} startIcon={pat.is_active === false ? <RestoreIcon /> : <ArchiveIcon />} onClick={() => setConfirmAction({ kind: pat.is_active === false ? 'restore' : 'archive', patient: pat })}>
                                {pat.is_active === false ? 'Restore' : 'Archive'}
                              </Button>
                            )}
                            {can(PERMISSION_KEYS.CAN_EDIT_PATIENT) && (
                              <Button size="small" color="error" startIcon={<DeleteOutlineIcon />} onClick={() => setConfirmAction({ kind: 'delete', patient: pat })}>Delete</Button>
                            )}
                            <Button
                              size="small"
                              variant="contained"
                              color="primary"
                              disabled={pat.is_active === false}
                              onClick={() => navigate(`/billing/new?mobile=${pat.mobile}`)}
                            >
                              New Bill
                            </Button>
                          </Box>
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </TableContainer>
          )}
          <Box sx={{display:'flex',justifyContent:'flex-end',gap:1,mt:2}}>
            <Button disabled={!cursorHistory.length||loading} onClick={()=>{setCursor(cursorHistory.at(-1)||null);setCursorHistory(h=>h.slice(0,-1))}}>Previous</Button>
            <Button disabled={!hasNextPage||loading||!patients.length} onClick={()=>{setCursorHistory(h=>[...h,cursor]);setCursor(registryCursor(patients.at(-1)!))}}>Next</Button>
          </Box>
        </CardContent>
      </Card>

      {/* Patient Detail / History Dialog */}
      <Dialog open={detailOpen} onClose={() => setDetailOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Box>
            <Typography variant="h6" fontWeight={700}>
              {selectedPatient?.full_name} ({selectedPatient?.uhid})
            </Typography>
            <Typography variant="caption" color="text.secondary">
              Mobile: {selectedPatient?.mobile} • Address: {selectedPatient?.address} • {selectedPatient?.age_years}Y / {selectedPatient?.gender}
            </Typography>
          </Box>
          <Button size="small" variant="contained" onClick={() => { setDetailOpen(false); navigate(`/billing/new?mobile=${selectedPatient?.mobile}`); }}>
            Book New Bill
          </Button>
        </DialogTitle>

        <DialogContent dividers sx={{ p: 0 }}>
          <Tabs value={currentTab} onChange={(_e, v) => setCurrentTab(v)} sx={{ borderBottom: '1px solid #e2e8f0', px: 2 }}>
            <Tab label={`Clinical Visits (${patientOrders.length})`} />
            <Tab label={`Invoices / Billing (${patientBills.length})`} />
            <Tab label={`Diagnostic Reports (${patientReports.length})`} />
          </Tabs>

          {historyLoading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
              <CircularProgress />
            </Box>
          ) : (
            <Box sx={{ p: 2 }}>
              {/* Tab 0: Clinical Orders */}
              {currentTab === 0 && (
                <TableContainer component={Paper} elevation={0}>
                  <Table size="small">
                    <TableHead>
                      <TableRow>
                        <TableCell>Lab Order No</TableCell>
                        <TableCell>Tests Ordered</TableCell>
                        <TableCell>Date</TableCell>
                        <TableCell>Status</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {patientOrders.length === 0 ? (
                        <TableRow>
                          <TableCell colSpan={4} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                            No orders found.
                          </TableCell>
                        </TableRow>
                      ) : (
                        patientOrders.map((ord) => (
                          <TableRow key={ord.id} hover>
                            <TableCell sx={{ fontWeight: 600 }}>{ord.order_number}</TableCell>
                            <TableCell>{(ord.items || []).map((i: any) => i.test_name).join(', ')}</TableCell>
                            <TableCell>{formatAdDateTime(ord.created_at)}</TableCell>
                            <TableCell><StatusChip status={ord.status} /></TableCell>
                          </TableRow>
                        ))
                      )}
                    </TableBody>
                  </Table>
                </TableContainer>
              )}

              {/* Tab 1: Billing & Invoices */}
              {currentTab === 1 && (
                <TableContainer component={Paper} elevation={0}>
                  <Table size="small">
                    <TableHead>
                      <TableRow>
                        <TableCell>Invoice No</TableCell>
                        <TableCell>Lab No</TableCell>
                        <TableCell align="right">Net Amount</TableCell>
                        <TableCell align="right">Paid</TableCell>
                        <TableCell align="right">Due</TableCell>
                        <TableCell align="center">Status</TableCell>
                        <TableCell>Payment Timeline</TableCell>
                        <TableCell>Date</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {patientBills.length === 0 ? (
                        <TableRow>
                          <TableCell colSpan={8} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                            No invoices found.
                          </TableCell>
                        </TableRow>
                      ) : (
                        patientBills.map((b) => (
                          <TableRow key={b.id} hover>
                            <TableCell sx={{ fontWeight: 600 }}>{b.bill_number}</TableCell>
                            <TableCell>{b.clinical_orders?.[0]?.order_number || '—'}</TableCell>
                            <TableCell align="right"><MoneyDisplay paisa={b.net_amount_paisa} /></TableCell>
                            <TableCell align="right"><MoneyDisplay paisa={b.paid_amount_paisa} /></TableCell>
                            <TableCell align="right"><MoneyDisplay paisa={b.due_amount_paisa} highlightDue /></TableCell>
                            <TableCell align="center"><StatusChip status={b.payment_status} /></TableCell>
                            <TableCell>{(b.payment_transactions || []).length ? (b.payment_transactions || []).map((p: any) => `${p.receipt_number}: NPR ${(p.amount_paisa / 100).toFixed(2)} (${p.payment_mode})`).join(' · ') : 'No payment received'}</TableCell>
                            <TableCell>{formatAdDateTime(b.created_at)}</TableCell>
                          </TableRow>
                        ))
                      )}
                    </TableBody>
                  </Table>
                </TableContainer>
              )}

              {/* Tab 2: Diagnostic Reports */}
              {currentTab === 2 && (
                <TableContainer component={Paper} elevation={0}>
                  <Table size="small">
                    <TableHead>
                      <TableRow>
                        <TableCell>Report No & Ver</TableCell>
                        <TableCell>Signed Date</TableCell>
                        <TableCell>Status</TableCell>
                        <TableCell align="center">Action</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {patientReports.length === 0 ? (
                        <TableRow>
                          <TableCell colSpan={4} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                            No signed reports issued yet.
                          </TableCell>
                        </TableRow>
                      ) : (
                        patientReports.map((rep) => (
                          <TableRow key={rep.id} hover>
                            <TableCell sx={{ fontWeight: 600 }}>
                              {rep.report_number} (v{rep.version} {rep.is_amendment ? 'Amended' : ''})
                            </TableCell>
                            <TableCell>{formatAdDateTime(rep.signed_at)}</TableCell>
                            <TableCell><StatusChip status={rep.status} /></TableCell>
                            <TableCell align="center">
                              {can(PERMISSION_KEYS.CAN_PRINT_REPORTS) && (
                              <Button
                                size="small"
                                variant="outlined"
                                onClick={() => {
                                  setDetailOpen(false);
                                  navigate(`/reports?reportId=${encodeURIComponent(rep.id)}`);
                                }}
                              >
                                Open in Reporting
                              </Button>
                              )}
                            </TableCell>
                          </TableRow>
                        ))
                      )}
                    </TableBody>
                  </Table>
                </TableContainer>
              )}
              {historyHasNext[['orders','bills','reports'][currentTab] as 'orders'|'bills'|'reports']&&<Box sx={{textAlign:'center',mt:2}}><Button onClick={()=>void loadMoreHistory()}>Load older history</Button></Box>}
            </Box>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDetailOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>

      {/* Edit Demographics Dialog */}
      <Dialog open={editOpen} onClose={() => setEditOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 700 }}>
          {isCreating ? 'Add Patient' : `Edit Demographics — ${selectedPatient?.uhid}`}
        </DialogTitle>
        <DialogContent dividers>
          <Grid container spacing={2} sx={{ mt: 0.5 }}>
            <Grid item xs={12} sm={4}>
              <TextField
                select
                fullWidth
                size="small"
                label="Title"
                value={editForm.title || 'Mr.'}
                onChange={(e) => setEditForm({ ...editForm, title: e.target.value })}
              >
                {['Mr.', 'Mrs.', 'Ms.', 'Master', 'Baby', 'Dr.', 'Prof.'].map((t) => (
                  <MenuItem key={t} value={t}>{t}</MenuItem>
                ))}
              </TextField>
            </Grid>
            <Grid item xs={12} sm={8}>
              <TextField
                fullWidth
                size="small"
                required
                label="Full Name"
                value={editForm.full_name || ''}
                onChange={(e) => setEditForm({ ...editForm, full_name: e.target.value })}
                onBlur={() => setEditForm({ ...editForm, full_name: normalizePatientName(editForm.full_name) })}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField fullWidth type="date" size="small" label="Date of Birth" value={editForm.dob || ''} onChange={(e) => setEditForm({ ...editForm, dob: e.target.value || null })} InputLabelProps={{ shrink: true }} />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                select
                fullWidth
                size="small"
                label="Gender"
                value={editForm.gender || 'Male'}
                onChange={(e) => setEditForm({ ...editForm, gender: e.target.value })}
              >
                {['Male', 'Female', 'Other'].map((g) => (
                  <MenuItem key={g} value={g}>{g}</MenuItem>
                ))}
              </TextField>
            </Grid>
            <Grid item xs={6} sm={3}>
              <TextField fullWidth type="number" size="small" label="Age Months" value={editForm.age_months ?? ''} onChange={(e) => setEditForm({ ...editForm, age_months: e.target.value === '' ? null : Number(e.target.value) })} inputProps={{ min: 0, max: 11, step: 1 }} />
            </Grid>
            <Grid item xs={6} sm={3}>
              <TextField fullWidth type="number" size="small" label="Age Days" value={editForm.age_days ?? ''} onChange={(e) => setEditForm({ ...editForm, age_days: e.target.value === '' ? null : Number(e.target.value) })} inputProps={{ min: 0, max: 31, step: 1 }} />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                type="number"
                size="small"
                label="Age (Years)"
                placeholder="Enter age"
                value={editForm.age_years ?? ''}
                onChange={(e) => setEditForm({
                  ...editForm,
                  age_years: e.target.value === '' ? null : Number(e.target.value),
                })}
                inputProps={{ min: 0, max: 120, step: 1 }}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                required
                size="small"
                type="tel"
                name="mobile"
                label="Mobile Number"
                value={editForm.mobile || ''}
                onChange={(e) => setEditForm({ ...editForm, mobile: e.target.value })}
                onBlur={() => setEditForm({ ...editForm, mobile: normalizeNepalMobile(editForm.mobile) })}
                inputProps={{ inputMode: 'numeric', autoComplete: 'tel', maxLength: 16 }}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                type="email"
                label="Email Address"
                value={editForm.email || ''}
                onChange={(e) => setEditForm({ ...editForm, email: e.target.value })}
              />
            </Grid>
            <Grid item xs={12}>
              <TextField
                fullWidth
                size="small"
                required
                label="Full Address"
                value={editForm.address || ''}
                onChange={(e) => setEditForm({ ...editForm, address: e.target.value })}
              />
            </Grid>
            <Grid item xs={12}>
              <TextField fullWidth size="small" label="Identification Number" value={editForm.identification_no || ''} onChange={(e) => setEditForm({ ...editForm, identification_no: e.target.value })} />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setEditOpen(false)}>Cancel</Button>
          <Button variant="contained" color="primary" onClick={handleSaveEdit} disabled={saving}>
            {saving ? 'Saving…' : isCreating ? 'Create Patient' : 'Save Demographics'}
          </Button>
        </DialogActions>
      </Dialog>

      <SmartMessageDialog
        open={Boolean(confirmAction)}
        variant="confirm"
        message={confirmAction?.kind === 'delete' ? 'Delete this unused patient record?' : confirmAction?.kind === 'archive' ? 'Archive this patient?' : 'Restore this patient?'}
        guidance={confirmAction?.kind === 'delete'
          ? 'Only a truly unused patient can be deleted. The database will refuse deletion when clinical, billing, report, payment, token, or SMS history exists.'
          : confirmAction?.kind === 'archive'
            ? 'The patient will be hidden from active searches. All historical records will remain intact.'
            : 'The patient will return to active searches and can be used for future care.'}
        primaryLabel={saving ? 'Working…' : confirmAction?.kind === 'delete' ? 'Delete unused patient' : confirmAction?.kind === 'archive' ? 'Archive patient' : 'Restore patient'}
        onPrimary={handleConfirmedAction}
        onSecondary={() => setConfirmAction(null)}
        busy={saving}
      />

      {/* Toast Notification */}
      <Snackbar
        open={Boolean(toastMsg)}
        autoHideDuration={3500}
        onClose={() => setToastMsg(null)}
        anchorOrigin={{ vertical: 'top', horizontal: 'center' }}
      >
        <Alert onClose={() => setToastMsg(null)} severity="success" variant="filled" sx={{ width: '100%' }}>
          {toastMsg}
        </Alert>
      </Snackbar>
    </Box>
  );
};
