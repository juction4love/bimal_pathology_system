/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Canonical Bill / Invoice Details Dialog (On-Screen View Only)
 * Purely provides on-screen inspection of immutable bill snapshots and workflow navigation.
 * All print and PDF generation actions have been completely removed per lab business rules.
 */

import React from 'react';
import {
  Box,
  Button,
  Dialog,
  DialogContent,
  DialogTitle,
  Typography,
  Grid,
  Card,
  CardContent,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Divider,
} from '@mui/material';
import ArrowForwardIcon from '@mui/icons-material/ArrowForward';
import CloseIcon from '@mui/icons-material/Close';
import { StatusChip } from '@/components/common/StatusChip';
import { MoneyDisplay } from '@/components/common/MoneyDisplay';
import { formatDualDate, formatAdDateTime } from '@/lib/dateTime';
import type { BillSnapshot } from './BillDocument';

interface BillViewerDialogProps {
  open: boolean;
  bill: BillSnapshot | null;
  onClose: () => void;
  onNavigateNext?: () => void;
  nextActionLabel?: string;
}

export const BillViewerDialog: React.FC<BillViewerDialogProps> = ({
  open,
  bill,
  onClose,
  onNavigateNext,
  nextActionLabel,
}) => {
  if (!bill) return null;

  const items = bill.bill_items || [];
  const payments = bill.payment_transactions || [];
  const patientName = bill.patient_name_snapshot || bill.patient?.full_name || 'Patient';
  const patientUhid = bill.patient_uhid_snapshot || bill.patient?.uhid || '-';
  const patientContact = bill.patient_mobile_snapshot || bill.patient?.mobile || '-';
  const patientAddress = bill.patient_address_snapshot || bill.patient?.address || 'Bharatpur, Chitwan';
  const referringDoc = bill.referring_doctor_name_snapshot || bill.referring_doctor?.full_name || 'Self / Walk-in';

  return (
    <Dialog
      open={open}
      onClose={onClose}
      maxWidth="md"
      fullWidth
      PaperProps={{
        sx: {
          borderRadius: 2,
        },
      }}
    >
      <DialogTitle
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          borderBottom: '1px solid #e2e8f0',
          py: 1.5,
          px: 3,
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
          <Typography variant="h6" fontWeight={700} color="primary.main">
            Bill Details — {bill.bill_number}
          </Typography>
          <StatusChip status={bill.payment_status} />
        </Box>

        <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
          {onNavigateNext && (
            <Button
              variant="contained"
              color="success"
              size="small"
              endIcon={<ArrowForwardIcon />}
              onClick={onNavigateNext}
              sx={{ fontWeight: 700 }}
            >
              {nextActionLabel || 'Continue to Samples'}
            </Button>
          )}

          <Button
            variant="outlined"
            color="inherit"
            size="small"
            startIcon={<CloseIcon />}
            onClick={onClose}
          >
            Close
          </Button>
        </Box>
      </DialogTitle>

      <DialogContent sx={{ p: 3 }}>
        {/* Patient Demographics & Bill Meta */}
        <Grid container spacing={2} sx={{ mb: 3 }}>
          <Grid item xs={12} sm={6}>
            <Card variant="outlined" sx={{ height: '100%', bgcolor: '#f8fafc' }}>
              <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
                <Typography variant="caption" fontWeight={700} color="text.secondary" textTransform="uppercase">
                  Patient Information
                </Typography>
                <Typography variant="subtitle1" fontWeight={700} sx={{ mt: 0.5 }}>
                  {patientName}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  UHID: <strong>{patientUhid}</strong>
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Contact: {patientContact}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Address: {patientAddress}
                </Typography>
              </CardContent>
            </Card>
          </Grid>

          <Grid item xs={12} sm={6}>
            <Card variant="outlined" sx={{ height: '100%', bgcolor: '#f8fafc' }}>
              <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
                <Typography variant="caption" fontWeight={700} color="text.secondary" textTransform="uppercase">
                  Billing & Referral Information
                </Typography>
                <Typography variant="body2" sx={{ mt: 0.5 }}>
                  Invoice Date: <strong>{formatDualDate(bill.created_at)}</strong> ({formatAdDateTime(bill.created_at)})
                </Typography>
                <Typography variant="body2" sx={{ mt: 0.5 }}>
                  Referred By: <strong>{referringDoc}</strong>
                </Typography>
                {bill.remarks && (
                  <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                    Remarks: {bill.remarks}
                  </Typography>
                )}
              </CardContent>
            </Card>
          </Grid>
        </Grid>

        {/* Billed Items Table */}
        <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>
          Billed Tests & Services ({items.length})
        </Typography>
        <TableContainer component={Paper} variant="outlined" sx={{ mb: 3 }}>
          <Table size="small">
            <TableHead sx={{ bgcolor: '#f1f5f9' }}>
              <TableRow>
                <TableCell>Test / Service</TableCell>
                <TableCell>Code</TableCell>
                <TableCell align="right">Rate (NPR)</TableCell>
                <TableCell align="right">Discount</TableCell>
                <TableCell align="right">Net Amount (NPR)</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {items.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={5} align="center" sx={{ py: 2, color: 'text.secondary' }}>
                    No items in this bill record.
                  </TableCell>
                </TableRow>
              ) : (
                items.map((it, idx) => (
                  <TableRow key={it.id || idx} hover>
                    <TableCell>
                      <Typography variant="body2" fontWeight={600}>
                        {it.test_name_snapshot || it.test_name}
                      </Typography>
                      {it.item_description && (
                        <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                          {it.item_description}
                        </Typography>
                      )}
                    </TableCell>
                    <TableCell>{it.test_code_snapshot || it.test_code || '-'}</TableCell>
                    <TableCell align="right">
                      <MoneyDisplay paisa={it.unit_price_paisa} />
                    </TableCell>
                    <TableCell align="right">
                      {it.discount_paisa ? <MoneyDisplay paisa={it.discount_paisa} sx={{ color: 'success.main' }} /> : '-'}
                    </TableCell>
                    <TableCell align="right">
                      <MoneyDisplay paisa={it.net_price_paisa ?? (it.unit_price_paisa - (it.discount_paisa || 0))} sx={{ fontWeight: 600 }} />
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </TableContainer>

        {/* Financial Summary Breakdown */}
        <Grid container spacing={2}>
          <Grid item xs={12} sm={6}>
            {payments.length > 0 && (
              <Box>
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>
                  Payment Transactions ({payments.length})
                </Typography>
                <TableContainer component={Paper} variant="outlined">
                  <Table size="small">
                    <TableHead sx={{ bgcolor: '#f1f5f9' }}>
                      <TableRow>
                        <TableCell>Receipt / Mode</TableCell>
                        <TableCell>Date</TableCell>
                        <TableCell align="right">Amount</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {payments.map((p, idx) => (
                        <TableRow key={p.id || idx}>
                          <TableCell>
                            <Typography variant="body2" fontWeight={600}>{p.receipt_number}</Typography>
                            <Typography variant="caption" color="text.secondary">{p.payment_mode} {p.transaction_reference ? `(${p.transaction_reference})` : ''}</Typography>
                          </TableCell>
                          <TableCell sx={{ fontSize: '0.78rem' }}>{formatDualDate(p.created_at)}</TableCell>
                          <TableCell align="right">
                            <MoneyDisplay paisa={p.amount_paisa} sx={{ color: 'success.main', fontWeight: 600 }} />
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </TableContainer>
              </Box>
            )}
          </Grid>

          <Grid item xs={12} sm={6}>
            <Card variant="outlined" sx={{ bgcolor: '#f8fafc' }}>
              <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
                <Typography variant="caption" fontWeight={700} color="text.secondary" textTransform="uppercase">
                  Financial Settlement Summary
                </Typography>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 1 }}>
                  <Typography variant="body2" color="text.secondary">Gross Amount:</Typography>
                  <MoneyDisplay paisa={bill.gross_amount_paisa} />
                </Box>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 0.5 }}>
                  <Typography variant="body2" color="text.secondary">Discount Applied:</Typography>
                  <MoneyDisplay paisa={bill.discount_amount_paisa} sx={{ color: 'success.main' }} />
                </Box>
                <Divider sx={{ my: 1 }} />
                <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                  <Typography variant="subtitle1" fontWeight={700}>Net Payable:</Typography>
                  <MoneyDisplay paisa={bill.net_amount_paisa} sx={{ fontWeight: 800, fontSize: '1.1rem', color: 'primary.main' }} />
                </Box>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 0.5 }}>
                  <Typography variant="body2" color="text.secondary">Total Paid:</Typography>
                  <MoneyDisplay paisa={bill.paid_amount_paisa} sx={{ color: 'success.main', fontWeight: 600 }} />
                </Box>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 0.5 }}>
                  <Typography variant="subtitle2" fontWeight={700} color={bill.due_amount_paisa > 0 ? 'error.main' : 'inherit'}>
                    Outstanding Balance:
                  </Typography>
                  <MoneyDisplay paisa={bill.due_amount_paisa} highlightDue sx={{ fontWeight: 700 }} />
                </Box>
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      </DialogContent>
    </Dialog>
  );
};
