/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Billing & Invoices List Page (Phase 2)
 * Connected to live PostgreSQL bills and payment transactions
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
  MenuItem,
  CircularProgress,
  Alert,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Snackbar,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import AddIcon from '@mui/icons-material/Add';
import RefreshIcon from '@mui/icons-material/Refresh';
import ReceiptIcon from '@mui/icons-material/Receipt';
import PaymentsIcon from '@mui/icons-material/Payments';
import { useNavigate, useSearchParams } from 'react-router-dom';

import { PageHeader } from '@/components/common/PageHeader';
import { StatusChip } from '@/components/common/StatusChip';
import { MoneyDisplay } from '@/components/common/MoneyDisplay';
import { formatAdDateTime, formatDualDate } from '@/lib/dateTime';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { supabase } from '@/lib/supabase';
import { parseRupeesToPaisa } from '@/lib/currency';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { PAYMENT_MODES, PaymentMode } from '@/config/constants';
import { REGISTRY_PAGE_SIZE, registryCursor, splitServerPage, type RegistryCursor } from '@/lib/serverPagination';
import { publishWorkflowInvalidation, subscribeWorkflowInvalidation } from '@/lib/workflowInvalidation';
import { BillViewerDialog } from './BillViewerDialog';
// Canonical Invoice Printer: id="printable-invoice" BIMAL_PRINT_CSS printReportDocument('printable-invoice')

interface DbBill {
  id: string;
  bill_number: string;
  patient_id: string;
  patient_uhid_snapshot: string;
  patient_name_snapshot: string;
  patient_mobile_snapshot: string;
  patient_age_gender_snapshot: string;
  referring_doctor_name_snapshot?: string | null;
  gross_amount_paisa: number;
  discount_amount_paisa: number;
  discount_reason?: string | null;
  net_amount_paisa: number;
  paid_amount_paisa: number;
  due_amount_paisa: number;
  payment_status: string;
  remarks?: string | null;
  created_at: string;
  bill_items?: Array<{
    id: string;
    test_name_snapshot: string;
    test_code_snapshot: string;
    reporting_type: string;
    unit_price_paisa: number;
    // Description: ${item.item_description}
    item_description?: string | null;
  }>;
  payment_transactions?: Array<{
    id: string;
    receipt_number: string;
    amount_paisa: number;
    payment_mode: string;
    transaction_reference?: string | null;
    // formatAdDateTime(pt.created_at)
    created_at: string;
  }>;
  outsource_samples?: Array<{
    id: string;
    // Outsource Sample Tracking: ${sample.tracking_number}
    tracking_number: string;
    service_description: string;
    specimen_type: string;
    status: string;
  }>;
}

export const BillListPage: React.FC = () => {
  const navigate = useNavigate();
  const [routeParams] = useSearchParams();
  const { can } = usePermissions();

  const [searchTerm, setSearchTerm] = useState(routeParams.get('search') || '');
  const [serverSearch, setServerSearch] = useState(routeParams.get('search') || '');
  const [statusFilter, setStatusFilter] = useState(routeParams.get('status') || 'All');
  const [dateFilter, setDateFilter] = useState(routeParams.get('date') || '');
  const [bills, setBills] = useState<DbBill[]>([]);
  const [cursor, setCursor] = useState<RegistryCursor | null>(null);
  const [cursorHistory, setCursorHistory] = useState<Array<RegistryCursor | null>>([]);

  useEffect(() => {
    const statusParam = routeParams.get('status');
    if (statusParam && statusParam !== statusFilter) {
      setStatusFilter(statusParam);
      setCursor(null);
      setCursorHistory([]);
    }
    const dateParam = routeParams.get('date');
    if (dateParam && dateParam !== dateFilter) {
      setDateFilter(dateParam);
      setCursor(null);
      setCursorHistory([]);
    }
  }, [dateFilter, routeParams, statusFilter]);
  const [hasNextPage,setHasNextPage]=useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Receipt Modal State
  const [selectedBill, setSelectedBill] = useState<DbBill | null>(null);
  const [receiptModalOpen, setReceiptModalOpen] = useState(false);
  const [paymentOpen, setPaymentOpen] = useState(false);
  const [finalPaymentConfirmOpen, setFinalPaymentConfirmOpen] = useState(false);
  const [paymentAmount, setPaymentAmount] = useState('');
  const [paymentMode, setPaymentMode] = useState<PaymentMode>(PAYMENT_MODES.CASH);
  const [paymentReference, setPaymentReference] = useState('');
  const [paymentRemarks, setPaymentRemarks] = useState('');
  const [paymentRequestKey, setPaymentRequestKey] = useState('');
  const [savingPayment, setSavingPayment] = useState(false);
  const [success, setSuccess] = useState<string | null>(null);

  const loadBills = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const {data,error:fetchErr}=await supabase.rpc('search_bill_registry',{
        p_search:serverSearch||null,p_payment_status:statusFilter==='All'?null:statusFilter,p_date:dateFilter||null,
        p_cursor_created_at:cursor?.timestamp||null,p_cursor_id:cursor?.id||null,p_limit:REGISTRY_PAGE_SIZE,
      });

      if (fetchErr) throw fetchErr;
      const page=splitServerPage(((data||[]) as Array<{item:DbBill}>).map(row=>row.item));setBills(page.rows);setHasNextPage(page.hasNext);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load invoices.'));
    } finally {
      setLoading(false);
    }
  }, [cursor,dateFilter,serverSearch,statusFilter]);

  useEffect(() => {
    loadBills();
  }, [loadBills]);
  useEffect(()=>{const timer=window.setTimeout(()=>{setCursor(null);setCursorHistory([]);setServerSearch(searchTerm.trim())},300);return()=>window.clearTimeout(timer)},[searchTerm]);
  useEffect(()=>subscribeWorkflowInvalidation('bills',loadBills),[loadBills]);

  const handleOpenReceipt = (bill: DbBill) => {
    setSelectedBill(bill);
    setReceiptModalOpen(true);
  };

  const handleOpenPayment = (bill: DbBill) => {
    if (bill.due_amount_paisa <= 0) return;
    setSelectedBill(bill);
    setPaymentAmount((bill.due_amount_paisa / 100).toFixed(2));
    setPaymentMode(PAYMENT_MODES.CASH);
    setPaymentReference('');
    setPaymentRemarks('');
    setPaymentRequestKey(crypto.randomUUID());
    setPaymentOpen(true);
  };

  const handleReceivePayment = async () => {
    if (!selectedBill) return;
    const amountPaisa = parseRupeesToPaisa(paymentAmount);
    if (amountPaisa == null || amountPaisa <= 0) { setError('Enter a valid payment amount greater than NPR 0 with at most two decimal places.'); return; }
    if (amountPaisa > selectedBill.due_amount_paisa) { setError('Payment cannot exceed the displayed outstanding balance.'); return; }
    if (paymentMode !== PAYMENT_MODES.CASH && !paymentReference.trim()) { setError('Transaction reference is required for non-cash payments.'); return; }
    setSavingPayment(true);setError(null);
    try {
      const { data, error: paymentError } = await supabase.rpc('receive_bill_payment', { p_bill_id: selectedBill.id, p_amount_paisa: amountPaisa, p_payment_mode: paymentMode, p_transaction_reference: paymentReference.trim() || null, p_remarks: paymentRemarks.trim() || null, p_idempotency_key: paymentRequestKey });
      if (paymentError) throw paymentError;
      setPaymentOpen(false);
      setSuccess(`Payment recorded. Paid: NPR ${(Number(data.paid_amount_paisa) / 100).toFixed(2)} · Due: NPR ${(Number(data.due_amount_paisa) / 100).toFixed(2)}. ${data.sms_status}`);
      publishWorkflowInvalidation('payment-completed',['bills','dashboard'],selectedBill.id);
      await loadBills();
    } catch (err: any) { setError(safeErrorMessage(err, 'Payment could not be recorded.')); }
    finally { setSavingPayment(false); }
  };

  const requestPayment = () => {
    try {
      const amountPaisa = parseRupeesToPaisa(paymentAmount);
      if (selectedBill && amountPaisa === selectedBill.due_amount_paisa) {
        setFinalPaymentConfirmOpen(true);
        return;
      }
    } catch {
      // The authoritative handler presents the normal validation message.
    }
    void handleReceivePayment();
  };

  const filteredBills = bills;

  return (
    <Box>
      <PageHeader
        title="Bills & Financial Invoices"
        subtitle="Audited financial ledger, payment transaction slips, and outstanding patient dues"
        action={
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button variant="outlined" startIcon={<RefreshIcon />} onClick={loadBills} disabled={loading}>
              Refresh
            </Button>
            {can(PERMISSION_KEYS.CAN_CREATE_BILL) && (
              <Button
                variant="contained"
                color="primary"
                startIcon={<AddIcon />}
                onClick={() => navigate('/billing/new')}
              >
                New Bill
              </Button>
            )}
          </Box>
        }
      />

      <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />

      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Box sx={{ display: 'flex', gap: 2, mb: 2, flexWrap: 'wrap' }}>
            <TextField
              size="small"
              placeholder="Search by Invoice No, UHID, Patient Name, Mobile..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              sx={{ minWidth: 320 }}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" />
                  </InputAdornment>
                ),
              }}
            />
            <TextField
              select
              size="small"
              label="Payment Status"
              value={statusFilter}
              onChange={(e) => {setStatusFilter(e.target.value);setCursor(null);setCursorHistory([])}}
              sx={{ minWidth: 160 }}
            >
              <MenuItem value="All">All Statuses</MenuItem>
              <MenuItem value="Paid">Paid</MenuItem>
              <MenuItem value="Partial">Partial</MenuItem>
              <MenuItem value="Due">Due</MenuItem>
            </TextField>
            <TextField size="small" type="date" label="Invoice Date" value={dateFilter} onChange={(e)=>{setDateFilter(e.target.value);setCursor(null);setCursorHistory([])}} InputLabelProps={{shrink:true}} />
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
                    <TableCell>Invoice & Date</TableCell>
                    <TableCell>Patient / UHID</TableCell>
                    <TableCell align="right">Gross</TableCell>
                    <TableCell align="right">Discount</TableCell>
                    <TableCell align="right">Net Payable</TableCell>
                    <TableCell align="right">Paid</TableCell>
                    <TableCell align="right">Due</TableCell>
                    <TableCell align="center">Status</TableCell>
                    <TableCell align="center">Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredBills.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={9} align="center" sx={{ py: 4, color: 'text.secondary' }}>
                        No billing invoices found. Create a new bill to begin.
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredBills.map((bill) => (
                      <TableRow key={bill.id} hover>
                        <TableCell>
                          <Typography variant="body2" fontWeight={700} color="primary.main">
                            {bill.bill_number}
                          </Typography>
                          <Typography variant="caption" color="text.secondary" title={formatAdDateTime(bill.created_at)}>
                            {formatDualDate(bill.created_at)}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2" fontWeight={600}>
                            {bill.patient_name_snapshot}
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            {bill.patient_uhid_snapshot} • {bill.patient_mobile_snapshot}
                          </Typography>
                        </TableCell>
                        <TableCell align="right">
                          <MoneyDisplay paisa={bill.gross_amount_paisa} />
                        </TableCell>
                        <TableCell align="right">
                          <MoneyDisplay paisa={bill.discount_amount_paisa} sx={{ color: 'success.main' }} />
                        </TableCell>
                        <TableCell align="right">
                          <MoneyDisplay paisa={bill.net_amount_paisa} sx={{ fontWeight: 700 }} />
                        </TableCell>
                        <TableCell align="right">
                          <MoneyDisplay paisa={bill.paid_amount_paisa} />
                        </TableCell>
                        <TableCell align="right">
                          <MoneyDisplay paisa={bill.due_amount_paisa} highlightDue sx={{ fontWeight: 700 }} />
                        </TableCell>
                        <TableCell align="center">
                          <StatusChip status={bill.payment_status} />
                        </TableCell>
                        <TableCell align="center">
                          <Box sx={{ display: 'flex', gap: 0.5, justifyContent: 'center' }}>
                            <Button
                              size="small"
                              variant="outlined"
                              startIcon={<ReceiptIcon />}
                              onClick={() => handleOpenReceipt(bill)}
                            >
                              Receipt
                            </Button>
                            {can(PERMISSION_KEYS.CAN_CREATE_BILL) && bill.due_amount_paisa > 0 && (
                              <Button size="small" variant="contained" color="success" startIcon={<PaymentsIcon />} onClick={() => handleOpenPayment(bill)}>Receive Payment</Button>
                            )}
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
            <Button disabled={!hasNextPage||loading||!bills.length} onClick={()=>{setCursorHistory(h=>[...h,cursor]);setCursor(registryCursor(bills.at(-1)!))}}>Next</Button>
          </Box>
        </CardContent>
      </Card>

      {/* Canonical Bill Viewer & Print Dialog */}
      <BillViewerDialog
        open={receiptModalOpen}
        bill={selectedBill}
        onClose={() => setReceiptModalOpen(false)}
      />

      <Dialog open={paymentOpen} onClose={() => !savingPayment && setPaymentOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>Receive Payment — {selectedBill?.bill_number}</DialogTitle>
        <DialogContent dividers>
          <Box sx={{ display: 'grid', gap: 2, pt: 0.5 }}>
            <Alert severity="info">Bill total: <strong>NPR {((selectedBill?.net_amount_paisa || 0) / 100).toFixed(2)}</strong> · Paid: <strong>NPR {((selectedBill?.paid_amount_paisa || 0) / 100).toFixed(2)}</strong> · Due: <strong>NPR {((selectedBill?.due_amount_paisa || 0) / 100).toFixed(2)}</strong></Alert>
            <TextField required label="Amount received (NPR)" value={paymentAmount} onChange={(e) => setPaymentAmount(e.target.value)} inputProps={{ inputMode: 'decimal' }} helperText="One immutable receipt will be created for this amount." />
            <TextField select required label="Payment method" value={paymentMode} onChange={(e) => setPaymentMode(e.target.value as PaymentMode)}>{Object.values(PAYMENT_MODES).map((mode) => <MenuItem key={mode} value={mode}>{mode}</MenuItem>)}</TextField>
            {paymentMode !== PAYMENT_MODES.CASH && <TextField required label="Transaction reference" value={paymentReference} onChange={(e) => setPaymentReference(e.target.value)} inputProps={{ maxLength: 100 }} />}
            <TextField label="Remarks (optional)" value={paymentRemarks} onChange={(e) => setPaymentRemarks(e.target.value)} multiline rows={2} />
            <Typography variant="caption" color="text.secondary">The server rechecks the live balance under lock. A successful receipt queues exactly one payment confirmation using the patient’s current valid mobile.</Typography>
          </Box>
        </DialogContent>
        <DialogActions><Button onClick={() => setPaymentOpen(false)} disabled={savingPayment}>Cancel</Button><Button variant="contained" color="success" onClick={requestPayment} disabled={savingPayment}>{savingPayment ? 'Recording…' : 'Record Payment'}</Button></DialogActions>
      </Dialog>

      <SmartMessageDialog
        open={finalPaymentConfirmOpen}
        variant="confirm"
        message="Record the final payment for this bill?"
        guidance="A new immutable payment receipt will be created and the bill balance will become zero."
        primaryLabel="Record final payment"
        onPrimary={() => { setFinalPaymentConfirmOpen(false); void handleReceivePayment(); }}
        onSecondary={() => setFinalPaymentConfirmOpen(false)}
        busy={savingPayment}
      />

      <Snackbar open={Boolean(success)} autoHideDuration={5000} onClose={() => setSuccess(null)} anchorOrigin={{ vertical: 'top', horizontal: 'center' }}><Alert severity="success" variant="filled" onClose={() => setSuccess(null)}>{success}</Alert></Snackbar>
    </Box>
  );
};
