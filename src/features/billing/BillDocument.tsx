/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Canonical A4 Bill / Invoice Document Component
 * Strictly renders immutable frozen bill snapshots with integer paisa precision.
 * Isolated iframe and preview print compliant.
 */

import React from 'react';
import {
  Box,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Divider,
} from '@mui/material';
import { ORG_CONFIG } from '@/config/constants';
import { BIMAL_PRINT, BIMAL_PRINT_CSS } from '@/lib/printDesign';
import { formatDualDate, formatAdDateTime } from '@/lib/dateTime';

export interface BillItemSnapshot {
  id?: string;
  test_name?: string;
  test_name_snapshot?: string;
  test_code?: string | null;
  test_code_snapshot?: string | null;
  reporting_type?: string | null;
  unit_price_paisa: number;
  discount_paisa?: number | null;
  net_price_paisa?: number | null;
  item_description?: string | null;
}

export interface PaymentTransactionSnapshot {
  id?: string;
  receipt_number: string;
  amount_paisa: number;
  payment_mode: string;
  transaction_reference?: string | null;
  created_at: string;
}

export interface BillSnapshot {
  id?: string;
  bill_number: string;
  patient_uhid_snapshot?: string;
  patient_name_snapshot?: string;
  patient_age_gender_snapshot?: string;
  patient_mobile_snapshot?: string | null;
  patient_address_snapshot?: string | null;
  patient?: {
    full_name?: string;
    uhid?: string;
    age_years?: number | null;
    age_months?: number | null;
    age_days?: number | null;
    gender?: string;
    mobile?: string | null;
    address?: string | null;
  } | null;
  referring_doctor_name_snapshot?: string | null;
  referring_doctor?: { full_name?: string } | null;
  lab_number_snapshot?: string | null;
  gross_amount_paisa: number;
  discount_amount_paisa: number;
  discount_reason?: string | null;
  net_amount_paisa: number;
  paid_amount_paisa: number;
  due_amount_paisa: number;
  payment_status: string;
  remarks?: string | null;
  created_at: string;
  bill_items?: BillItemSnapshot[];
  payment_transactions?: PaymentTransactionSnapshot[];
  outsource_samples?: Array<{
    id: string;
    tracking_number: string;
    service_description: string;
    specimen_type: string;
  }>;
}

interface BillDocumentProps {
  bill: BillSnapshot;
  printedAt?: string;
}

function formatMoney(paisa: number): string {
  const rupees = (paisa || 0) / 100;
  return `NPR ${rupees.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export const BillDocument: React.FC<BillDocumentProps> = ({ bill, printedAt }) => {
  const items = bill.bill_items || [];
  const payments = bill.payment_transactions || [];
  const isPaidInFull = bill.due_amount_paisa <= 0;

  const patientName = bill.patient_name_snapshot || bill.patient?.full_name || 'Patient';
  const patientUhid = bill.patient_uhid_snapshot || bill.patient?.uhid || '-';
  const patientAgeGender = bill.patient_age_gender_snapshot || (
    bill.patient ? [
      typeof bill.patient.age_years === 'number' ? `${bill.patient.age_years}Y` : '',
      typeof bill.patient.age_months === 'number' && bill.patient.age_months > 0 ? `${bill.patient.age_months}M` : '',
      typeof bill.patient.age_days === 'number' && bill.patient.age_days > 0 ? `${bill.patient.age_days}D` : '',
      bill.patient.gender || '',
    ].filter(Boolean).join(' ') : '-'
  );
  const patientContact = bill.patient_mobile_snapshot || bill.patient?.mobile;
  const patientAddress = bill.patient_address_snapshot || bill.patient?.address;
  const referringDoc = bill.referring_doctor_name_snapshot || bill.referring_doctor?.full_name || 'Self / Direct';

  return (
    <Box
      id="printable-invoice"
      className="bimal-print-document bimal-a4-page"
      data-testid="printable-bill-document"
      sx={{
        position: 'relative',
        width: '210mm',
        minHeight: '297mm',
        p: '10mm',
        bgcolor: '#ffffff',
        color: BIMAL_PRINT.ink,
        fontFamily: BIMAL_PRINT.fontStack,
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'space-between',
        boxSizing: 'border-box',
        overflow: 'hidden',
        mx: 'auto',
      }}
    >
      <style>{BIMAL_PRINT_CSS}</style>
      
      {/* Background Watermark */}
      <Box
        component="img"
        src={BIMAL_PRINT.logoPath}
        alt=""
        className="bimal-page-watermark"
        sx={{
          position: 'absolute',
          left: '50%',
          top: '42%',
          transform: 'translate(-50%, -50%)',
          width: '110mm',
          opacity: BIMAL_PRINT.watermarkOpacity,
          zIndex: 0,
          pointerEvents: 'none',
        }}
      />

      {/* Main Content Area */}
      <Box className="bimal-page-content" sx={{ position: 'relative', zIndex: 1 }}>
        
        {/* 1. Header with Official Branding */}
        <Box
          sx={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            pb: 1.5,
            mb: 2,
            borderBottom: `2.5px solid ${BIMAL_PRINT.brand}`,
          }}
        >
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
            <Box
              component="img"
              src={BIMAL_PRINT.logoPath}
              alt="Bimal Pathology"
              sx={{ width: 62, height: 62, objectFit: 'contain' }}
            />
            <Box>
              <Typography
                variant="h6"
                sx={{
                  fontWeight: 900,
                  color: BIMAL_PRINT.brandDeep,
                  fontSize: '1.25rem',
                  lineHeight: 1.2,
                  letterSpacing: '0.01em',
                }}
              >
                {ORG_CONFIG.nameEn}
              </Typography>
              <Typography
                sx={{
                  fontSize: '0.82rem',
                  fontWeight: 600,
                  color: BIMAL_PRINT.brand,
                  fontFamily: "'Noto Sans Devanagari', 'Mukta', sans-serif",
                  lineHeight: 1.3,
                }}
              >
                {ORG_CONFIG.nameNp}
              </Typography>
              <Typography
                sx={{
                  fontSize: '0.72rem',
                  color: BIMAL_PRINT.muted,
                  mt: 0.25,
                }}
              >
                {ORG_CONFIG.addressEn} • Phone: <strong>{ORG_CONFIG.phone}</strong> • PAN: <strong>{ORG_CONFIG.panNo}</strong> • Reg: <strong>{ORG_CONFIG.regNo}</strong>
              </Typography>
            </Box>
          </Box>

          <Box
            sx={{
              textAlign: 'right',
              bgcolor: BIMAL_PRINT.brandSoft,
              px: 2,
              py: 0.75,
              borderRadius: 1,
              border: `1px solid ${BIMAL_PRINT.border}`,
            }}
          >
            <Typography
              sx={{
                fontWeight: 900,
                fontSize: '0.95rem',
                color: BIMAL_PRINT.brandDeep,
                letterSpacing: '0.05em',
              }}
            >
              INVOICE / RECEIPT
            </Typography>
            <Typography
              sx={{
                fontSize: '0.7rem',
                fontWeight: 700,
                color: isPaidInFull ? 'success.dark' : 'error.main',
              }}
            >
              {isPaidInFull ? '● PAID IN FULL' : `● ${bill.payment_status?.toUpperCase() || 'UNPAID'}`}
            </Typography>
          </Box>
        </Box>

        {/* 2. Bill Identity & Patient Details Grid */}
        <Box
          sx={{
            display: 'grid',
            gridTemplateColumns: '1.2fr 0.8fr',
            gap: 2,
            p: 1.5,
            mb: 2,
            bgcolor: '#f8fafc',
            border: `1px solid #e2e8f0`,
            borderRadius: 1,
            fontSize: '0.8rem',
          }}
        >
          {/* Patient Details Column */}
          <Box sx={{ display: 'grid', gap: 0.5 }}>
            <Box sx={{ display: 'flex', gap: 1 }}>
              <Typography sx={{ width: 90, fontSize: '0.78rem', color: BIMAL_PRINT.muted, fontWeight: 600 }}>
                Patient Name:
              </Typography>
              <Typography sx={{ fontSize: '0.85rem', fontWeight: 800, color: BIMAL_PRINT.ink }}>
                {patientName}
              </Typography>
            </Box>

            <Box sx={{ display: 'flex', gap: 1 }}>
              <Typography sx={{ width: 90, fontSize: '0.78rem', color: BIMAL_PRINT.muted, fontWeight: 600 }}>
                UHID / Age / Sex:
              </Typography>
              <Typography sx={{ fontSize: '0.78rem', fontWeight: 700 }}>
                <span style={{ fontFamily: 'monospace', color: BIMAL_PRINT.brandDeep }}>{patientUhid}</span>
                {' · '}{patientAgeGender}
              </Typography>
            </Box>

            {patientContact && (
              <Box sx={{ display: 'flex', gap: 1 }}>
                <Typography sx={{ width: 90, fontSize: '0.78rem', color: BIMAL_PRINT.muted, fontWeight: 600 }}>
                  Contact:
                </Typography>
                <Typography sx={{ fontSize: '0.78rem', fontWeight: 600 }}>
                  {patientContact}
                </Typography>
              </Box>
            )}

            {patientAddress && (
              <Box sx={{ display: 'flex', gap: 1 }}>
                <Typography sx={{ width: 90, fontSize: '0.78rem', color: BIMAL_PRINT.muted, fontWeight: 600 }}>
                  Address:
                </Typography>
                <Typography sx={{ fontSize: '0.78rem', color: BIMAL_PRINT.ink }}>
                  {patientAddress}
                </Typography>
              </Box>
            )}

            <Box sx={{ display: 'flex', gap: 1 }}>
              <Typography sx={{ width: 90, fontSize: '0.78rem', color: BIMAL_PRINT.muted, fontWeight: 600 }}>
                Referred By:
              </Typography>
              <Typography sx={{ fontSize: '0.78rem', fontWeight: 700, color: BIMAL_PRINT.brandDeep }}>
                {referringDoc}
              </Typography>
            </Box>
          </Box>

          {/* Bill Identity Column */}
          <Box sx={{ display: 'grid', gap: 0.5, borderLeft: '1px dashed #cbd5e1', pl: 2 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
              <Typography sx={{ fontSize: '0.78rem', color: BIMAL_PRINT.muted, fontWeight: 600 }}>
                Bill / Invoice No:
              </Typography>
              <Typography sx={{ fontSize: '0.85rem', fontWeight: 800, fontFamily: 'monospace', color: BIMAL_PRINT.ink }}>
                {bill.bill_number}
              </Typography>
            </Box>

            {bill.lab_number_snapshot && (
              <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                <Typography sx={{ fontSize: '0.78rem', color: BIMAL_PRINT.muted, fontWeight: 600 }}>
                  Lab Sample No:
                </Typography>
                <Typography sx={{ fontSize: '0.8rem', fontWeight: 700, fontFamily: 'monospace' }}>
                  {bill.lab_number_snapshot}
                </Typography>
              </Box>
            )}

            <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
              <Typography sx={{ fontSize: '0.78rem', color: BIMAL_PRINT.muted, fontWeight: 600 }}>
                Bill Date:
              </Typography>
              <Typography sx={{ fontSize: '0.78rem', fontWeight: 700 }}>
                {formatDualDate(bill.created_at)}
              </Typography>
            </Box>

            <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
              <Typography sx={{ fontSize: '0.78rem', color: BIMAL_PRINT.muted, fontWeight: 600 }}>
                Payment Status:
              </Typography>
              <Typography
                sx={{
                  fontSize: '0.78rem',
                  fontWeight: 800,
                  color: isPaidInFull ? 'success.main' : 'error.main',
                }}
              >
                {bill.payment_status}
              </Typography>
            </Box>
          </Box>
        </Box>

        {/* 3. Outsource Tracking (if applicable) */}
        {bill.outsource_samples && bill.outsource_samples.length > 0 && (
          <Box
            sx={{
              mb: 2,
              p: 1.25,
              bgcolor: '#f0f9ff',
              borderRadius: 1,
              border: '1px solid #bae6fd',
              fontSize: '0.75rem',
            }}
          >
            <Typography variant="caption" sx={{ fontWeight: 800, color: '#0369a1', display: 'block', mb: 0.25 }}>
              Outsource Sample Tracking:
            </Typography>
            {bill.outsource_samples.map((os) => (
              <Typography key={os.id} sx={{ fontSize: '0.72rem', fontFamily: 'monospace', color: '#0284c7' }}>
                Tracking: <strong>{os.tracking_number}</strong> — {os.service_description} ({os.specimen_type})
              </Typography>
            ))}
          </Box>
        )}

        {/* 4. Investigation Items Table */}
        <Box sx={{ mb: 2 }}>
          <Table
            size="small"
            sx={{
              '& th': {
                bgcolor: BIMAL_PRINT.brandDeep,
                color: '#ffffff',
                fontWeight: 800,
                fontSize: '0.78rem',
                py: 0.75,
                borderBottom: 'none',
              },
              '& td': {
                py: 0.65,
                fontSize: '0.78rem',
                borderBottom: '1px solid #e2e8f0',
              },
            }}
          >
            <TableHead>
              <TableRow>
                <TableCell sx={{ width: 36, textAlign: 'center' }}>SN</TableCell>
                <TableCell>Investigation / Test / Service Description</TableCell>
                <TableCell sx={{ width: 110 }}>Type</TableCell>
                <TableCell align="right" sx={{ width: 110 }}>Rate (NPR)</TableCell>
                <TableCell align="right" sx={{ width: 100 }}>Discount</TableCell>
                <TableCell align="right" sx={{ width: 120 }}>Amount (NPR)</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {items.map((item, index) => {
                const unitPrice = item.unit_price_paisa || 0;
                const itemDiscount = item.discount_paisa || 0;
                const itemNet = item.net_price_paisa ?? (unitPrice - itemDiscount);

                return (
                  <TableRow key={item.id || index} sx={{ '&:nth-of-type(even)': { bgcolor: '#f8fafc' } }}>
                    <TableCell sx={{ textAlign: 'center', fontWeight: 600, color: BIMAL_PRINT.muted }}>
                      {index + 1}
                    </TableCell>
                    <TableCell>
                      <Typography sx={{ fontSize: '0.8rem', fontWeight: 700, color: BIMAL_PRINT.ink }}>
                        {item.test_name_snapshot || item.test_name || (item as any).tests?.name || 'Investigation'}
                      </Typography>
                      {item.item_description && (
                        <Typography sx={{ fontSize: '0.68rem', color: BIMAL_PRINT.muted, fontStyle: 'italic', mt: 0.1 }}>
                          Description: {item.item_description}
                        </Typography>
                      )}
                    </TableCell>
                    <TableCell sx={{ fontSize: '0.72rem', color: BIMAL_PRINT.muted }}>
                      {item.reporting_type || 'InHouse'}
                    </TableCell>
                    <TableCell align="right" sx={{ fontFamily: 'monospace', fontWeight: 600 }}>
                      {((unitPrice) / 100).toFixed(2)}
                    </TableCell>
                    <TableCell align="right" sx={{ fontFamily: 'monospace', color: itemDiscount > 0 ? 'success.dark' : BIMAL_PRINT.muted }}>
                      {itemDiscount > 0 ? ((itemDiscount) / 100).toFixed(2) : '-'}
                    </TableCell>
                    <TableCell align="right" sx={{ fontFamily: 'monospace', fontWeight: 700, color: BIMAL_PRINT.ink }}>
                      {((itemNet) / 100).toFixed(2)}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </Box>

        {/* 5. Payment Details & Totals Summary Grid */}
        <Box
          sx={{
            display: 'grid',
            gridTemplateColumns: '1.2fr 0.8fr',
            gap: 2,
            pt: 1,
            borderTop: `1.5px solid ${BIMAL_PRINT.border}`,
          }}
        >
          {/* Left Column: Payment Log & Remarks */}
          <Box sx={{ fontSize: '0.75rem' }}>
            {payments.length > 0 && (
              <Box sx={{ mb: 1.5 }}>
                <Typography sx={{ fontWeight: 800, fontSize: '0.75rem', color: BIMAL_PRINT.brandDeep, mb: 0.5 }}>
                  Payment Receipts / Transactions:
                </Typography>
                <Box sx={{ display: 'grid', gap: 0.5, p: 1, bgcolor: '#f8fafc', border: '1px solid #e2e8f0', borderRadius: 1 }}>
                  {payments.map((p) => (
                    <Box key={p.id || p.receipt_number} sx={{ display: 'flex', justifyContent: 'space-between', gap: 1 }}>
                      <Typography sx={{ fontSize: '0.72rem', color: BIMAL_PRINT.ink }}>
                        <strong>{p.receipt_number}</strong> ({p.payment_mode}{p.transaction_reference ? ` · Ref: ${p.transaction_reference}` : ''})
                        <span style={{ color: '#64748b', marginLeft: 4 }}>{formatAdDateTime(p.created_at)}</span>
                      </Typography>
                      <Typography sx={{ fontSize: '0.72rem', fontWeight: 700, fontFamily: 'monospace' }}>
                        {formatMoney(p.amount_paisa)}
                      </Typography>
                    </Box>
                  ))}
                </Box>
              </Box>
            )}

            {bill.remarks && (
              <Box sx={{ p: 1, bgcolor: '#f1f5f9', borderRadius: 1, border: '1px solid #e2e8f0' }}>
                <Typography sx={{ fontSize: '0.7rem', fontWeight: 700, color: BIMAL_PRINT.muted }}>
                  Billing Remarks:
                </Typography>
                <Typography sx={{ fontSize: '0.72rem', color: BIMAL_PRINT.ink }}>
                  {bill.remarks}
                </Typography>
              </Box>
            )}
          </Box>

          {/* Right Column: Authoritative Financial Totals */}
          <Box
            sx={{
              display: 'grid',
              gap: 0.5,
              p: 1.5,
              bgcolor: BIMAL_PRINT.brandSoft,
              border: `1px solid ${BIMAL_PRINT.border}`,
              borderRadius: 1,
            }}
          >
            <Box sx={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
              <Typography sx={{ color: BIMAL_PRINT.muted, fontWeight: 600 }}>Gross Total:</Typography>
              <Typography sx={{ fontFamily: 'monospace', fontWeight: 700 }}>
                {formatMoney(bill.gross_amount_paisa)}
              </Typography>
            </Box>

            {bill.discount_amount_paisa > 0 && (
              <Box sx={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
                <Typography sx={{ color: 'success.dark', fontWeight: 600 }}>
                  Discount {bill.discount_reason ? `(${bill.discount_reason})` : ''}:
                </Typography>
                <Typography sx={{ fontFamily: 'monospace', fontWeight: 700, color: 'success.dark' }}>
                  - {formatMoney(bill.discount_amount_paisa)}
                </Typography>
              </Box>
            )}

            <Divider sx={{ my: 0.5, borderColor: BIMAL_PRINT.border }} />

            <Box sx={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.88rem' }}>
              <Typography sx={{ fontWeight: 800, color: BIMAL_PRINT.brandDeep }}>Net Payable:</Typography>
              <Typography sx={{ fontFamily: 'monospace', fontWeight: 900, color: BIMAL_PRINT.brandDeep, fontSize: '0.95rem' }}>
                {formatMoney(bill.net_amount_paisa)}
              </Typography>
            </Box>

            <Box sx={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
              <Typography sx={{ color: 'success.dark', fontWeight: 700 }}>Amount Received:</Typography>
              <Typography sx={{ fontFamily: 'monospace', fontWeight: 800, color: 'success.dark' }}>
                {formatMoney(bill.paid_amount_paisa)}
              </Typography>
            </Box>

            <Divider sx={{ my: 0.5, borderColor: BIMAL_PRINT.border }} />

            <Box sx={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.88rem' }}>
              <Typography sx={{ fontWeight: 800, color: bill.due_amount_paisa > 0 ? 'error.main' : 'success.main' }}>
                Balance Due:
              </Typography>
              <Typography
                sx={{
                  fontFamily: 'monospace',
                  fontWeight: 900,
                  fontSize: '0.95rem',
                  color: bill.due_amount_paisa > 0 ? 'error.main' : 'success.main',
                }}
              >
                {formatMoney(bill.due_amount_paisa)}
              </Typography>
            </Box>
          </Box>
        </Box>
      </Box>

      {/* 6. Footer Information */}
      <Box
        className="bimal-footer-strip"
        sx={{
          mt: 3,
          pt: 1,
          borderTop: `1px solid ${BIMAL_PRINT.border}`,
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          fontSize: '0.68rem',
          color: BIMAL_PRINT.muted,
        }}
      >
        <Typography sx={{ fontSize: '0.68rem', color: BIMAL_PRINT.muted }}>
          This is a computer-generated official bill receipt.
          {printedAt ? ` Printed on: ${printedAt}` : ` Generated: ${formatAdDateTime(bill.created_at)}`}
        </Typography>
        <Typography sx={{ fontSize: '0.68rem', fontWeight: 700, color: BIMAL_PRINT.brandDeep }}>
          Page 1 of 1
        </Typography>
      </Box>
    </Box>
  );
};
