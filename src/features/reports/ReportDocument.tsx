/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Deterministic Multi-Page A4 Diagnostic Report Component
 * Current canonical presentation for every frozen report snapshot, regardless
 * of signing date or version. Handles 1-page CBC and deterministic N-page
 * pathology reports with identical headers and exact page counts.
 */

import React, { useMemo } from 'react';
import {
  Box,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
} from '@mui/material';
import { ClinicalSnapshot, formatResultFlag } from '@/lib/reportRenderer';
import { formatReferenceRangeText } from '@/lib/clinicalReferenceRange';
import { formatAdDateTime, formatDualDate } from '@/lib/dateTime';
import { generateQrSvgPath } from '@/lib/qrCode';
import { BIMAL_PRINT, BIMAL_PRINT_CSS } from '@/lib/printDesign';
import {
  paginateInvestigations,
  isReportableParameter,
  formatReportReferenceRange,
} from './reportPagination';

interface ReportDocumentProps {
  snapshot: ClinicalSnapshot;
  isAmended?: boolean;
  amendmentReason?: string | null;
  version?: number;
  isDraft?: boolean;
  reportNumber?: string | null;
  integrityHash?: string | null;
  publicToken?: string | null;
}

/** Returns true when bill number is missing or an uncommitted placeholder */
function isBillPending(billNumber?: string | null): boolean {
  if (!billNumber) return true;
  const n = billNumber.trim().toUpperCase();
  return n === '' || n === 'INV-PENDING' || n === 'PENDING' || n === '-' || n === 'N/A';
}

function clinicalSectionName(department?: string | null): string {
  const normalized = String(department || '').trim().toLowerCase();
  if (normalized === 'serology' || normalized === 'immunology') return 'SEROLOGY & IMMUNOLOGY';
  if (normalized === 'biochemistry') return 'CLINICAL BIOCHEMISTRY';
  if (normalized === 'hematology') return 'HEMATOLOGY';
  return department || 'CLINICAL PATHOLOGY';
}

/** Preview spacing only; all physical design rules live in printDesign.ts. */
const PREVIEW_STYLES = `
@media screen {
  .report-page {
    margin-bottom: 24px;
  }
  .report-page:last-child {
    margin-bottom: 0;
  }
}
`;

export const ReportDocument: React.FC<ReportDocumentProps> = ({
  snapshot,
  isAmended = false,
  amendmentReason,
  version = 1,
  isDraft = false,
  reportNumber,
  integrityHash,
  publicToken,
}) => {
  const patient = snapshot?.patient || ({} as any);
  const order = snapshot?.order || ({} as any);
  const org = snapshot?.organization || {
    name_en: 'BIMAL PATHOLOGY & DIAGNOSTIC CENTER',
    name_ne: 'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर',
    address_en: 'Bharatpur-7, Chitwan, Nepal',
    address_ne: 'भरतपुर-७, चितवन, नेपाल',
    reg_no: '7-1496',
    pan_no: '302481477',
    phone: '056-593288',
  };
  const signatories = snapshot?.signatories || ({} as any);
  const investigations = useMemo(() => {
    const raw = snapshot?.investigations || [];
    return raw.map((inv) => ({
      ...inv,
      results: (inv.results || []).filter((r: any) => isReportableParameter(r, inv)),
    }));
  }, [snapshot?.investigations]);
  const footerEmail = (org as { email?: string }).email || 'admin@bimalpathology.com.np';

  // Age formatting
  const ageDisplay = patient.age_years
    ? `${patient.age_years} Y`
    : patient.age_months
    ? `${patient.age_months} M`
    : patient.age_days
    ? `${patient.age_days} D`
    : '-';

  const patientNameWithTitle = patient.title
    ? `${patient.title} ${patient.full_name}`
    : patient.full_name;

  // A verification QR is emitted only when the unguessable public token is
  // available. Report/order numbers are identifiers, never access tokens.
  const securePublicToken = publicToken && /^[A-Za-z0-9_-]{32,256}$/.test(publicToken)
    ? publicToken
    : null;
  const verifyUrl = securePublicToken
    ? `https://lis.bimalpathology.com.np/r/${securePublicToken}`
    : null;
  const qrData = useMemo(
    () => verifyUrl ? generateQrSvgPath(verifyUrl, 68) : null,
    [verifyUrl]
  );

  // Deterministic Page Split
  const pages = useMemo(
    () => paginateInvestigations(investigations),
    [investigations]
  );
  const totalPageCount = pages.length;

  return (
    <Box
      id="printable-report"
      className="printable-report-wrapper"
      data-canonical-report-design="current"
      data-report-theme="bimal-premium-green"
    >
      <style>{PREVIEW_STYLES}</style>
      <style>{BIMAL_PRINT_CSS}</style>

      {pages.map((pageData) => {
        const { pageNumber, isFinalPage, investigations: pageInvs, usedMm, capacityMm } = pageData;
        const remainingClinicalMm = Math.max(0, capacityMm - usedMm);
        // Sparse reports intentionally use the empty clinical field for a broad,
        // quiet brand mark. This changes only the watermark, never row geometry.
        const adaptiveWatermarkMm = Math.max(0, Math.min(110, remainingClinicalMm - 6));

        return (
          <Box
            key={`page-${pageNumber}`}
            className="a4-page report-page"
            data-report-page={pageNumber}
            data-final-page={isFinalPage ? 'true' : 'false'}
            data-pagination-used-mm={usedMm}
            data-pagination-capacity-mm={capacityMm}
            sx={{
              width: '210mm',
              maxWidth: 'none',
              minHeight: '297mm',
              height: '297mm',
              overflow: 'hidden',
              mx: 'auto',
              bgcolor: '#ffffff',
              color: '#0f172a',
              fontFamily: "'Inter', 'Mukta', 'Noto Sans Devanagari', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
              boxShadow: { xs: 'none', md: '0 4px 20px rgba(0, 0, 0, 0.08)' },
              p: '10mm',
              boxSizing: 'border-box',
              position: 'relative',
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'space-between',
            }}
          >
            <>
              {/* ============================================================ */}
              {/* IDENTICAL OFFICIAL HEADER & PATIENT BLOCK ON EVERY PAGE     */}
              {/* ============================================================ */}
              <Box className="report-identity-header" sx={{ position: 'relative', height: '68mm', minHeight: '68mm', maxHeight: '68mm', overflow: 'hidden', isolation: 'isolate', flexShrink: 0 }}>
                  <Box
                    className="report-header-diagonal-accent"
                    aria-hidden="true"
                    sx={{
                      position: 'absolute',
                      inset: '0 22mm 0 0',
                      zIndex: 0,
                      pointerEvents: 'none',
                      overflow: 'hidden',
                      WebkitMaskImage: 'linear-gradient(to top right, #000 0%, rgba(0,0,0,0.72) 40%, transparent 72%)',
                      maskImage: 'linear-gradient(to top right, #000 0%, rgba(0,0,0,0.72) 40%, transparent 72%)',
                    }}
                  >
                    <Box
                      className="report-header-background-wordmark"
                      sx={{
                        position: 'absolute',
                        left: '-4mm',
                        bottom: '2mm',
                        width: '142mm',
                        height: '25mm',
                        backgroundImage: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='1420' height='250' viewBox='0 0 1420 250'%3E%3Ctext x='0' y='202' font-family='Arial,sans-serif' font-size='184' font-weight='900' letter-spacing='-6' fill='rgb(11,107,58)' fill-opacity='.18'%3EBIMAL PATHOLOGY%3C/text%3E%3C/svg%3E")`,
                        backgroundRepeat: 'no-repeat',
                        backgroundSize: 'contain',
                        transform: 'rotate(-8deg)',
                        transformOrigin: 'left bottom',
                      }}
                    />
                    <Box
                      component="img"
                      className="report-header-background-logo"
                      src="/pathology-logo.png"
                      alt=""
                      aria-hidden="true"
                      sx={{
                        position: 'absolute',
                        left: '16mm',
                        bottom: '2mm',
                        width: '20mm',
                        height: '20mm',
                        objectFit: 'contain',
                        opacity: 0.09,
                        transform: 'rotate(-8deg)',
                        transformOrigin: 'center',
                        mixBlendMode: 'multiply',
                      }}
                    />
                  </Box>
                  <Box
                    className="report-header"
                    sx={{
                      position: 'relative',
                      zIndex: 1,
                      display: 'grid',
                      gridTemplateColumns: 'minmax(0, 1fr) 75mm',
                      alignItems: 'flex-start',
                      columnGap: '4mm',
                      minHeight: '30mm',
                      pb: 1.75,
                      borderBottom: '1.5px solid #0b6b3a',
                    }}
                  >
                    {/* Top-Left: Logo & Lab Contact Details */}
                    <Box className="report-header-left" sx={{ display: 'grid', gridTemplateColumns: '52px minmax(0, 1fr)', alignItems: 'start', columnGap: 1.5, minWidth: 0 }}>
                      <Box
                        component="img"
                        src="/pathology-logo.png"
                        alt="Bimal Pathology"
                        sx={{
                          height: 52,
                          width: 'auto',
                          objectFit: 'contain',
                          mt: 0.25,
                        }}
                      />
                      <Box className="laboratory-brand-stack" sx={{ minWidth: 0, display: 'grid', alignContent: 'start', rowGap: '1px' }}>
                        <Box
                          className="english-laboratory-name"
                          sx={{
                            color: BIMAL_PRINT.brandDeep,
                            textAlign: 'left',
                          }}
                        >
                          <Box component="span" className="english-laboratory-name-line english-laboratory-name-primary" sx={{ display: 'block', whiteSpace: 'nowrap', fontSize: '1.52rem', fontWeight: 900, letterSpacing: '-0.025em', lineHeight: 1 }}>
                            BIMAL PATHOLOGY
                          </Box>
                          <Box component="span" className="english-laboratory-name-line english-laboratory-name-secondary" sx={{ display: 'block', whiteSpace: 'nowrap', fontSize: '1.18rem', fontWeight: 800, letterSpacing: '-0.015em', lineHeight: 1.08 }}>
                            &amp; DIAGNOSTIC CENTER
                          </Box>
                        </Box>
                        <Typography
                          sx={{
                            fontFamily: "'Mukta', 'Noto Sans Devanagari', sans-serif",
                            fontSize: '0.96rem',
                            fontWeight: 600,
                            color: BIMAL_PRINT.brand,
                            lineHeight: 1.3,
                            mt: 0,
                          }}
                        >
                          {org.name_ne}
                        </Typography>
                        <Typography
                          sx={{
                            fontSize: '0.74rem',
                            color: '#334f41',
                            mt: '2px',
                            lineHeight: 1.4,
                          }}
                        >
                          {org.address_en}
                          <br />
                          Phone: {org.phone}
                        </Typography>
                      </Box>
                    </Box>

                    {/* Top-Right: Pathology Report, Registrations & Small Secure QR */}
                    <Box
                      className="report-header-right"
                      sx={{
                        display: 'grid',
                        gridTemplateColumns: 'minmax(0, 1fr) 68px',
                        alignItems: 'start',
                        columnGap: '3mm',
                        minWidth: '75mm',
                        textAlign: 'right',
                      }}
                    >
                      <Box className="report-title-stack" sx={{ minWidth: 0, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', rowGap: '4px' }}>
                        <Typography
                          className="report-title"
                          sx={{
                            display: 'block',
                            fontSize: '1.25rem',
                            fontWeight: 800,
                            color: BIMAL_PRINT.brandDeep,
                            letterSpacing: '0.04em',
                            lineHeight: 1.1,
                            whiteSpace: 'nowrap',
                          }}
                        >
                          PATHOLOGY REPORT
                        </Typography>
                        {isDraft ? (
                          <Typography
                            className="report-state"
                            sx={{
                              fontSize: '0.70rem',
                              fontWeight: 800,
                              color: '#dc2626',
                              letterSpacing: '0.06em',
                              textTransform: 'uppercase',
                              mt: 0,
                              whiteSpace: 'nowrap',
                            }}
                          >
                            DRAFT &mdash; NOT VERIFIED
                          </Typography>
                        ) : isAmended ? (
                          <Typography
                            className="report-state"
                            sx={{
                              fontSize: '0.70rem',
                              fontWeight: 800,
                              color: '#d97706',
                              letterSpacing: '0.06em',
                              textTransform: 'uppercase',
                              mt: 0,
                              whiteSpace: 'nowrap',
                            }}
                          >
                            AMENDED REPORT (v{version})
                          </Typography>
                        ) : (
                          <Typography
                            className="report-state"
                            sx={{
                              fontSize: '0.68rem',
                              fontWeight: 700,
                              color: BIMAL_PRINT.brand,
                              letterSpacing: '0.06em',
                              textTransform: 'uppercase',
                              mt: 0,
                              whiteSpace: 'nowrap',
                            }}
                          >
                            {signatories?.authorized_by ? 'FINAL SIGNED REPORT' : 'FINAL REPORT'}
                          </Typography>
                        )}
                        <Typography
                          className="report-registration"
                          sx={{
                            fontSize: '0.74rem',
                            color: '#475569',
                            mt: '2px',
                            lineHeight: 1.4,
                            whiteSpace: 'nowrap',
                          }}
                        >
                          Regd. No.: <strong>{org.reg_no}</strong>
                          <br />
                          PAN: <strong>{org.pan_no}</strong>
                        </Typography>
                        <Typography className="report-header-page-number" sx={{ fontSize: '0.66rem', color: '#475569', fontWeight: 700, whiteSpace: 'nowrap' }}>
                          Page {pageNumber} of {totalPageCount}
                        </Typography>
                      </Box>

                      {/* Small Secure QR Code (Final Signed Reports Only, ~18-20mm) */}
                      {!isDraft && qrData?.path && (
                        <Box className="report-qr-quiet-zone" sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', minWidth: '68px' }}>
                          <svg
                            width="68"
                            height="68"
                            viewBox={qrData.viewBox}
                            style={{ display: 'block', shapeRendering: 'crispEdges' }}
                          >
                            <rect width="100%" height="100%" fill="#ffffff" />
                            <path d={qrData.path} fill="#0f172a" />
                          </svg>
                          <Typography
                            sx={{
                              width: '68px',
                              fontSize: '0.52rem',
                              color: '#64748b',
                              fontWeight: 600,
                              mt: 0.25,
                              textAlign: 'center',
                              lineHeight: 1.1,
                              whiteSpace: 'normal',
                            }}
                          >
                            Scan to verify report
                          </Typography>
                        </Box>
                      )}
                    </Box>
                  </Box>

                  <Box className="patient-identity-strip" sx={{ position: 'relative', zIndex: 1, height: '32mm', px: '2mm', py: '2.2mm', display: 'grid', gridTemplateRows: '1fr 1fr', rowGap: '1.2mm', border: '1px solid #0b6b3a', bgcolor: 'rgba(237,247,241,0.94)' }}>
                    <Box sx={{ display: 'grid', gridTemplateColumns: '2fr 0.8fr 1fr 1fr 0.55fr', minHeight: 0 }}>
                      <Box sx={{ minWidth: 0, pr: '2mm', borderRight: '1px solid #d5e6dc' }}><Typography sx={{ fontSize: '0.58rem', color: '#527061', fontWeight: 700, textTransform: 'uppercase' }}>Patient Name</Typography><Typography sx={{ fontSize: '0.76rem', lineHeight: 1.12, fontWeight: 800, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>{patientNameWithTitle || '—'}</Typography></Box>
                      <Box sx={{ minWidth: 0, px: '2mm', borderRight: '1px solid #d5e6dc' }}><Typography sx={{ fontSize: '0.58rem', color: '#527061', fontWeight: 700, textTransform: 'uppercase' }}>Age / Sex</Typography><Typography sx={{ fontSize: '0.70rem', fontWeight: 700, whiteSpace: 'nowrap' }}>{ageDisplay} / {patient.gender || '—'}</Typography></Box>
                      <Box sx={{ minWidth: 0, px: '2mm', borderRight: '1px solid #d5e6dc' }}><Typography sx={{ fontSize: '0.58rem', color: '#527061', fontWeight: 700, textTransform: 'uppercase' }}>UHID</Typography><Typography sx={{ fontSize: '0.70rem', fontWeight: 700, fontFamily: 'monospace', overflowWrap: 'anywhere' }}>{patient.uhid || '—'}</Typography></Box>
                      <Box sx={{ minWidth: 0, px: '2mm', borderRight: '1px solid #d5e6dc' }}><Typography sx={{ fontSize: '0.58rem', color: '#527061', fontWeight: 700, textTransform: 'uppercase' }}>Lab No.</Typography><Typography sx={{ fontSize: '0.72rem', fontWeight: 800, fontFamily: 'monospace', overflowWrap: 'anywhere' }}>{order.order_number || '—'}</Typography></Box>
                      <Box sx={{ minWidth: 0, pl: '2mm' }}><Typography sx={{ fontSize: '0.58rem', color: '#527061', fontWeight: 700, textTransform: 'uppercase' }}>Page</Typography><Typography sx={{ fontSize: '0.72rem', fontWeight: 800, fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>{pageNumber} of {totalPageCount}</Typography></Box>
                    </Box>
                    <Box sx={{ display: 'grid', gridTemplateColumns: '1.4fr 1.1fr 1fr 1fr 1fr', minHeight: 0, pt: '0.7mm', borderTop: '1px solid #d5e6dc' }}>
                      <Box sx={{ minWidth: 0, pr: '2mm', borderRight: '1px solid #d5e6dc' }}><Typography sx={{ fontSize: '0.56rem', color: '#527061', fontWeight: 700, textTransform: 'uppercase' }}>Referred By</Typography><Typography sx={{ fontSize: '0.64rem', lineHeight: 1.12, fontWeight: 600, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>{order.referring_doctor_name || '—'}</Typography></Box>
                      <Box sx={{ minWidth: 0, px: '2mm', borderRight: '1px solid #d5e6dc' }}><Typography sx={{ fontSize: '0.56rem', color: '#527061', fontWeight: 700, textTransform: 'uppercase' }}>Registered</Typography><Typography sx={{ fontSize: '0.59rem', lineHeight: 1.12 }}>{formatDualDate(order.registered_date_ad, order.registered_date_bs)}</Typography></Box>
                      <Box sx={{ minWidth: 0, px: '2mm', borderRight: '1px solid #d5e6dc' }}><Typography sx={{ fontSize: '0.56rem', color: '#527061', fontWeight: 700, textTransform: 'uppercase' }}>Collected</Typography><Typography sx={{ fontSize: '0.59rem', lineHeight: 1.12 }}>{order.collected_at ? formatAdDateTime(order.collected_at) : '—'}</Typography></Box>
                      <Box sx={{ minWidth: 0, px: '2mm', borderRight: '1px solid #d5e6dc' }}><Typography sx={{ fontSize: '0.56rem', color: '#527061', fontWeight: 700, textTransform: 'uppercase' }}>Received</Typography><Typography sx={{ fontSize: '0.59rem', lineHeight: 1.12 }}>{order.received_at ? formatAdDateTime(order.received_at) : '—'}</Typography></Box>
                      <Box sx={{ minWidth: 0, pl: '2mm' }}><Typography sx={{ fontSize: '0.56rem', color: '#527061', fontWeight: 700, textTransform: 'uppercase' }}>Reported</Typography><Typography sx={{ fontSize: '0.59rem', lineHeight: 1.12 }}>{order.reported_at ? formatAdDateTime(order.reported_at) : '—'}</Typography></Box>
                    </Box>
                  </Box>

                  {/* Legacy metadata DOM retained for snapshot-field compatibility; hidden by the compact fixed strip. */}
                  <Box
                    className="patient-info-box"
                    sx={{
                      display: 'none',
                      position: 'relative',
                      zIndex: 1,
                      gridTemplateColumns: { xs: '1fr', sm: '1.1fr 0.9fr' },
                      columnGap: '7mm',
                      py: 1.5,
                      borderBottom: '1px solid #e2e8f0',
                      fontSize: '0.78rem',
                      lineHeight: 1.5,
                    }}
                  >
                    {/* Left Column: Patient Demographics */}
                    <Box>
                      <Box sx={{ display: 'grid', gridTemplateColumns: '24mm minmax(0, 1fr)', rowGap: 0.45 }}>
                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Patient:
                        </Typography>
                        <Typography sx={{ fontSize: '0.80rem', fontWeight: 700, color: '#0f172a', overflowWrap: 'anywhere' }}>
                          {patientNameWithTitle || '-'}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          UHID:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', fontWeight: 600, color: '#0f172a', fontFamily: 'monospace' }}>
                          {patient.uhid || '-'}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Age / Sex:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', fontWeight: 600, color: '#0f172a' }}>
                          {ageDisplay} / {patient.gender || '-'}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Mobile:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', fontWeight: 600, color: '#0f172a' }}>
                          {patient.mobile || '-'}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Address:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', color: '#334155', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
                          {patient.address || '—'}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Referred By:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', fontWeight: 600, color: '#0f172a', overflowWrap: 'anywhere' }}>
                          {order.referring_doctor_name || '—'}
                        </Typography>
                      </Box>
                    </Box>

                    {/* Right Column: Order, Dates & Specimen */}
                    <Box>
                      <Box sx={{ display: 'grid', gridTemplateColumns: '25mm minmax(0, 1fr)', rowGap: 0.45 }}>
                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Lab No.:
                        </Typography>
                        <Typography sx={{ fontSize: '0.80rem', fontWeight: 700, color: '#0f172a', fontFamily: 'monospace' }}>
                          {order.order_number || '-'}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Invoice No.:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', fontWeight: 600, color: '#0f172a' }}>
                          {isBillPending(order.bill_number) ? 'Pending' : order.bill_number}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Invoice Date:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', fontWeight: 600, color: '#0f172a' }}>
                          {formatDualDate(order.registered_date_ad, order.registered_date_bs)}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Registered:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', color: '#334155' }}>
                          {formatDualDate(order.registered_date_ad, order.registered_date_bs)}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Collected:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', color: '#334155' }}>
                          {order.collected_at ? formatAdDateTime(order.collected_at) : formatAdDateTime(order.registered_date_ad)}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Received:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', color: '#334155' }}>
                          {order.received_at ? formatAdDateTime(order.received_at) : formatAdDateTime(order.registered_date_ad)}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Reported:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', color: '#334155' }}>
                          {order.reported_at ? formatAdDateTime(order.reported_at) : '—'}
                        </Typography>

                        <Typography sx={{ fontSize: '0.76rem', color: '#64748b', fontWeight: 500 }}>
                          Specimen:
                        </Typography>
                        <Typography sx={{ fontSize: '0.78rem', fontWeight: 600, color: '#0f172a' }}>
                          {investigations[0]?.specimen_type || '—'}
                        </Typography>
                      </Box>
                    </Box>
                  </Box>

              </Box>

              <Box className="page-content bimal-page-content clinical-workspace" sx={{ position: 'relative', zIndex: 1, height: '189mm', minHeight: '189mm', maxHeight: '189mm', overflow: 'hidden', display: 'flex', flexDirection: 'column', flexShrink: 0 }}>
                <Box className="bimal-workspace-texture" aria-hidden="true" sx={{ position: 'absolute', inset: 0, pointerEvents: 'none', zIndex: 0, backgroundImage: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='280' height='240' viewBox='0 0 280 240'%3E%3Cg fill='none' stroke='rgb(11,107,58)' stroke-opacity='.026' stroke-width='1'%3E%3Cpath d='M30 58h28M44 44v28M208 168h22M219 157v22'/%3E%3Ccircle cx='140' cy='120' r='42'/%3E%3Ccircle cx='140' cy='120' r='34' stroke-dasharray='3 5'/%3E%3C/g%3E%3Ctext x='106' y='130' font-family='Arial,sans-serif' font-size='27' font-weight='800' fill='rgb(11,107,58)' fill-opacity='.022'%3EBP%3C/text%3E%3C/svg%3E")`, backgroundRepeat: 'repeat', backgroundSize: '74mm 63.5mm' }} />
                {adaptiveWatermarkMm >= 10 && (
                  <Box
                    className="watermark-container bimal-page-watermark"
                    aria-hidden="true"
                    data-watermark-available-mm={remainingClinicalMm.toFixed(2)}
                    data-watermark-size-mm={adaptiveWatermarkMm.toFixed(2)}
                    sx={{
                      position: 'absolute',
                      top: `${usedMm + 3}mm`,
                      left: '50%',
                      width: `${adaptiveWatermarkMm}mm`,
                      height: `${Math.max(0, remainingClinicalMm - 6)}mm`,
                      transform: 'translateX(-50%)',
                      display: 'grid',
                      placeItems: 'center',
                      opacity: BIMAL_PRINT.watermarkOpacity,
                      pointerEvents: 'none',
                      zIndex: 0,
                      overflow: 'hidden',
                    }}
                  >
                    <Box component="img" src={BIMAL_PRINT.logoPath} alt="" sx={{ display: 'block', width: '100%', height: '100%', maxWidth: `${adaptiveWatermarkMm}mm`, maxHeight: `${adaptiveWatermarkMm}mm`, objectFit: 'contain' }} />
                  </Box>
                )}
                <Box className="clinical-flow-region" data-clinical-capacity-mm={capacityMm} sx={{ position: 'relative', zIndex: 1, height: `${capacityMm}mm`, minHeight: `${capacityMm}mm`, maxHeight: `${capacityMm}mm`, overflow: 'hidden', flexShrink: 0 }}>
                {isAmended && amendmentReason && (
                  <Box sx={{ position: 'relative', zIndex: 1, borderLeft: '2px solid #f59e0b', px: 1, py: 0.5, mt: 1 }}>
                    <Typography sx={{ fontSize: '0.72rem', color: '#92400e', fontWeight: 600 }}>Amendment Note (v{version}): {amendmentReason}</Typography>
                  </Box>
                )}

              {/* ============================================================ */}
              {/* INVESTIGATIONS & CLINICAL RESULTS TABLE                      */}
              {/* ============================================================ */}
              {pageInvs.map((inv, invIdx) => {
                const compactSingle = (inv.source_result_count ?? inv.results.length) === 1 && !inv.interpretation_template;
                const isContinuation = Boolean(inv.is_continuation);
                const previousInvestigation = pageInvs[invIdx - 1];
                const continuesCompactSeries = compactSingle && Boolean(
                  previousInvestigation && (previousInvestigation.source_result_count ?? previousInvestigation.results.length) === 1 && !previousInvestigation.interpretation_template
                );
                return (
                <Box
                  className={`${compactSingle ? 'investigation-block compact-single-investigation' : 'investigation-block'}${isContinuation ? ' investigation-continuation' : ''}`}
                  data-investigation-id={inv.order_item_id || inv.test_id || invIdx}
                  data-investigation-continuation={isContinuation ? 'true' : 'false'}
                  key={`${inv.order_item_id || invIdx}-${pageNumber}`}
                  sx={{
                    mt: compactSingle ? 0.35 : 1.5,
                    mb: compactSingle ? 0.25 : 1.25,
                    border: `1px solid ${BIMAL_PRINT.border}`,
                    bgcolor: 'rgba(255,255,255,0.93)',
                    overflow: 'visible',
                    breakInside: 'avoid-page',
                  }}
                >
                  {/* Clean Department & Test Header */}
                  <Box className="department-header-block" sx={{ px: 1.25, py: compactSingle ? 0.5 : isContinuation ? 0.55 : 0.8, bgcolor: BIMAL_PRINT.brand, borderBottom: `1px solid ${BIMAL_PRINT.brandDeep}`, display: compactSingle || isContinuation ? 'flex' : 'block', alignItems: 'baseline', gap: compactSingle || isContinuation ? 1 : 0 }}>
                    <Typography
                      sx={{
                        fontSize: compactSingle || isContinuation ? '0.62rem' : '0.70rem',
                        fontWeight: 700,
                        color: '#ffffff',
                        textTransform: 'uppercase',
                        letterSpacing: '0.06em',
                      }}
                    >
                      {clinicalSectionName(inv.department)}
                    </Typography>
                    <Typography
                      sx={{
                        fontSize: compactSingle || isContinuation ? '0.80rem' : '0.94rem',
                        fontWeight: 800,
                        color: '#ffffff',
                        letterSpacing: '-0.01em',
                        whiteSpace: compactSingle || isContinuation ? 'nowrap' : 'normal',
                        minWidth: 0,
                      }}
                    >
                      {inv.test_name}{isContinuation ? ' — continued' : ''}
                    </Typography>
                    {inv.method && !compactSingle && !isContinuation && (
                      <Typography sx={{ fontSize: '0.70rem', color: '#e5f5eb', fontStyle: 'italic', mt: 0.2 }}>
                        Method: {inv.method}
                      </Typography>
                    )}
                    {inv.reporting_type === 'OutsourceWithBimalReport' && inv.outsource_lab_name && (
                      <Typography sx={{ fontSize: '0.70rem', color: '#92400e', fontWeight: 700, mt: 0.25 }}>
                        Reference Laboratory Disclosure: Testing performed by {inv.outsource_lab_name}; report issued through Bimal Pathology.
                      </Typography>
                    )}
                  </Box>

                  {/* Minimal Clean Result Table */}
                  <TableContainer sx={{ px: 0.75, overflow: 'visible' }}>
                    <Table size="small" sx={{ width: '100%', borderCollapse: 'collapse' }}>
                      {!continuesCompactSeries && <TableHead>
                        <TableRow
                          sx={{
                            borderTop: `1px solid ${BIMAL_PRINT.brand}`,
                            borderBottom: `1px solid ${BIMAL_PRINT.brand}`,
                            bgcolor: 'rgba(237,247,241,0.72)',
                          }}
                        >
                          <TableCell sx={{ color: BIMAL_PRINT.brandDeep, fontWeight: 700, fontSize: '0.72rem', py: 0.6, px: 0.5, width: '39%', letterSpacing: '0.025em' }}>
                            TEST / PARAMETER
                          </TableCell>
                          <TableCell align="center" sx={{ color: BIMAL_PRINT.brandDeep, fontWeight: 700, fontSize: '0.68rem', py: 0.4, px: 0.35, width: '7%', letterSpacing: '0.025em' }}>
                            FLAG
                          </TableCell>
                          <TableCell align="right" sx={{ color: BIMAL_PRINT.brandDeep, fontWeight: 700, fontSize: '0.68rem', py: 0.4, px: 0.75, width: '18%', letterSpacing: '0.025em' }}>
                            VALUE
                          </TableCell>
                          <TableCell align="left" sx={{ color: BIMAL_PRINT.brandDeep, fontWeight: 700, fontSize: '0.68rem', py: 0.4, px: 0.75, width: '13%', letterSpacing: '0.025em' }}>
                            UNIT
                          </TableCell>
                          <TableCell align="left" sx={{ color: BIMAL_PRINT.brandDeep, fontWeight: 700, fontSize: '0.68rem', py: 0.4, px: 0.5, width: '24%', letterSpacing: '0.025em' }}>
                            REFERENCE RANGE
                          </TableCell>
                        </TableRow>
                      </TableHead>}
                      <TableBody>
                        {inv.results.map((r: any, idx: number) => {
                          const flagInfo = formatResultFlag(r.flag);
                          const isAbnormal = flagInfo.isAbnormal || r.is_critical;
                          const isCritical = flagInfo.isCritical || r.is_critical;

                          const rawRangeText = r.reference_range
                            ? r.reference_range
                            : formatReferenceRangeText({
                                range_type: r.value_type === 'Text' ? 'Qualitative' : 'Numeric',
                                normal_min: r.normal_min,
                                normal_max: r.normal_max,
                                critical_low: r.critical_low,
                                critical_high: r.critical_high,
                                reference_text: r.reference_range || undefined,
                                is_approved: true,
                                is_active: true,
                              } as any);

                          const displayValue =
                            r.display_value !== '' && r.display_value !== undefined && r.display_value !== null
                              ? r.display_value
                              : '—';

                          const formattedRange = formatReportReferenceRange(rawRangeText);

                          return (
                            <TableRow
                              key={r.parameter_id || idx}
                              className="clinical-result-row"
                              data-parameter-id={r.parameter_id || idx}
                              sx={{
                                borderBottom: '1px solid #f1f5f9',
                              }}
                            >
                              {/* Parameter Name */}
                              <TableCell sx={{ py: 0.3, px: 0.5, fontSize: '0.74rem', lineHeight: 1.25, fontWeight: 600, color: '#0f172a', overflowWrap: compactSingle ? 'normal' : 'anywhere', whiteSpace: compactSingle ? 'nowrap' : 'normal' }}>
                                {r.name}
                                {r.value_type === 'Calculated' && (
                                  <Typography component="span" sx={{ fontSize: '0.64rem', color: '#64748b', ml: 0.75, fontStyle: 'italic' }}>
                                    (Calculated)
                                  </Typography>
                                )}
                              </TableCell>

                              {/* Abnormal Flag (H / L / HH / LL / A) */}
                              <TableCell
                                align="center"
                                sx={{
                                  py: 0.3,
                                  px: 0.35,
                                  fontSize: '0.74rem',
                                  fontWeight: 800,
                                  color: isCritical ? '#b91c1c' : isAbnormal ? '#c2410c' : 'inherit',
                                  textDecoration: isCritical ? 'double underline' : isAbnormal ? 'underline' : 'none',
                                  textUnderlineOffset: '2px',
                                }}
                              >
                                {flagInfo.label || ''}
                              </TableCell>

                              {/* Result Value */}
                              <TableCell
                                align="right"
                                sx={{
                                  py: 0.3,
                                  px: 0.75,
                                  fontSize: '0.76rem',
                                  fontWeight: 700,
                                  color: isCritical ? '#b91c1c' : isAbnormal ? '#c2410c' : '#0f172a',
                                  fontVariantNumeric: 'tabular-nums',
                                  overflowWrap: 'anywhere',
                                  textDecoration: isCritical ? 'double underline' : isAbnormal ? 'underline' : 'none',
                                  textUnderlineOffset: '2px',
                                }}
                              >
                                {displayValue}
                              </TableCell>

                              {/* Unit */}
                              <TableCell align="left" sx={{ py: 0.3, px: 0.75, fontSize: '0.70rem', lineHeight: 1.25, color: '#475569', overflowWrap: 'anywhere' }}>
                                {r.unit || '-'}
                              </TableCell>

                              {/* Reference Interval */}
                              <TableCell align="left" sx={{ py: 0.3, px: 0.5, fontSize: '0.70rem', lineHeight: 1.25, color: '#334155' }}>
                                <Box component="span" sx={{ whiteSpace: 'normal', overflowWrap: 'anywhere' }}>
                                  {formattedRange}
                                </Box>
                              </TableCell>
                            </TableRow>
                          );
                        })}
                      </TableBody>
                    </Table>
                  </TableContainer>

                  {inv.pus_culture_worksheet && <Box sx={{mx:.75,my:.8}}>
                    <Typography sx={{fontSize:'.76rem',fontWeight:800,color:BIMAL_PRINT.brandDeep}}>Specimen / Direct Smear</Typography>
                    <Typography sx={{fontSize:'.74rem'}}>Source / Site: {inv.pus_culture_worksheet.specimen_source}{inv.pus_culture_worksheet.specimen_source_other?` — ${inv.pus_culture_worksheet.specimen_source_other}`:''}</Typography>
                    <Typography sx={{fontSize:'.74rem'}}>Gram Stain Pus Cells: {inv.pus_culture_worksheet.gram_stain_pus_cells}</Typography>
                    {inv.pus_culture_worksheet.direct_smear_organisms&&<Typography sx={{fontSize:'.74rem',whiteSpace:'pre-wrap'}}>Direct Smear Organisms: {inv.pus_culture_worksheet.direct_smear_organisms}</Typography>}
                    <Typography sx={{fontSize:'.76rem',fontWeight:800,color:BIMAL_PRINT.brandDeep,mt:.5}}>Culture</Typography>
                    <Typography sx={{fontSize:'.74rem'}}>{inv.pus_culture_worksheet.culture_status}</Typography>
                  </Box>}
                  {(inv.ast_isolates || []).map((isolate: any) => (
                    <Box key={isolate.isolate_number} sx={{ mx: 0.75, my: 0.8 }}>
                      <Typography sx={{ fontSize: '0.76rem', fontWeight: 800, color: BIMAL_PRINT.brandDeep }}>
                        Isolate {isolate.isolate_number}: {isolate.organism}{isolate.organism_group ? ` · ${isolate.organism_group}` : ''}
                      </Typography>
                      {isolate.growth_state === 'NoGrowth' ? <Typography sx={{ fontSize: '0.76rem' }}>No growth</Typography> : <>
                        <Table size="small"><TableHead><TableRow><TableCell>Antibiotic</TableCell><TableCell>Method</TableCell><TableCell>Zone/MIC</TableCell><TableCell>Interpretation</TableCell></TableRow></TableHead>
                          <TableBody>{(isolate.observations || []).map((observation: any) => <TableRow key={`${observation.antibiotic}-${observation.method}`}>
                            <TableCell>{observation.antibiotic}</TableCell><TableCell>{observation.method}</TableCell>
                            <TableCell>{observation.metric_value}{observation.metric_secondary_value == null ? '' : `/${observation.metric_secondary_value}`}{observation.method === 'Disk' ? ' mm' : ''}</TableCell>
                            <TableCell>{observation.interpretation}</TableCell>
                          </TableRow>)}</TableBody></Table>
                        {isolate.breakpoint_reference && <Typography sx={{ fontSize: '0.66rem', color: '#475569', mt: 0.4 }}>{isolate.breakpoint_reference}</Typography>}
                      </>}
                    </Box>
                  ))}
                  {inv.pus_culture_worksheet?.final_remarks&&<Box sx={{mx:.75,my:.8}}><Typography sx={{fontSize:'.76rem',fontWeight:800,color:BIMAL_PRINT.brandDeep}}>Microbiology Remarks</Typography><Typography sx={{fontSize:'.74rem',whiteSpace:'pre-wrap'}}>{inv.pus_culture_worksheet.final_remarks}</Typography></Box>}

                  {/* Interpretation Template if present on this page chunk */}
                  {inv.interpretation_template && (
                    <Box className="report-interpretation" sx={{ mx: 1, mt: 1.15, mb: 1, px: 1, py: 0.65, border: '1px solid #c7d8cf', borderLeft: '2px solid #0b6b3a', bgcolor: 'rgba(244,249,246,0.94)' }}>
                      <Typography sx={{ fontSize: '0.70rem', fontWeight: 700, color: '#475569', textTransform: 'uppercase' }}>
                        Clinical Note / Interpretation:
                      </Typography>
                      <Typography sx={{ fontSize: '0.75rem', lineHeight: 1.45, color: '#334155', mt: 0.25, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
                        {inv.interpretation_template}
                      </Typography>
                    </Box>
                  )}
                </Box>
                );
              })}

              {/* The clinical-end marker follows the final result/comment. It is
                  intentionally independent from the bottom-aligned signatures. */}
              {isFinalPage && (
                <Box className="clinical-end-marker" sx={{ position: 'relative', zIndex: 2, textAlign: 'center', mt: 0.8, mb: 0.5, bgcolor: '#ffffff', py: 0.2 }}>
                  <Typography
                    component="span"
                    sx={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: 1,
                      fontSize: '0.68rem',
                      fontWeight: 700,
                      color: BIMAL_PRINT.brand,
                      letterSpacing: '0.08em',
                      whiteSpace: 'nowrap',
                      '&::before, &::after': {
                        content: '""',
                        display: 'block',
                        width: '14mm',
                        borderTop: `1px solid ${BIMAL_PRINT.border}`,
                      },
                    }}
                  >
                    * END OF REPORT *
                  </Typography>
                </Box>
              )}
                </Box>
            {/* ============================================================ */}
            {/* EVERY PAGE: BORDERED TWO-COLUMN SIGNATURE SECTION             */}
            {/* ============================================================ */}
              <Box className="signature-block" data-signatory-count={signatories?.authorized_by ? 2 : 1} sx={{ height: '23mm', minHeight: '23mm', maxHeight: '23mm', px: '2.5mm', py: '1.8mm', mt: '5mm', flexShrink: 0, position: 'relative', zIndex: 2, bgcolor: '#ffffff', border: `1px solid ${BIMAL_PRINT.brand}`, boxSizing: 'border-box' }}>
                {/* Two-Column Signatures */}
                <Box
                  sx={{
                    display: 'grid',
                    gridTemplateColumns: signatories?.authorized_by ? '1fr 1fr' : '1fr',
                    gap: 0,
                    minHeight: '19mm',
                  }}
                >
                  {/* Left: Performed / Reported By */}
                  <Box sx={{ pr: signatories?.authorized_by ? '5mm' : 0 }}>
                    <Typography sx={{ fontSize: '0.70rem', fontWeight: 800, color: '#0b6b3a', textTransform: 'uppercase', letterSpacing: '0.04em', pb: 0.35, borderBottom: '1px solid #d5e6dc' }}>
                      Reported / Performed By:
                    </Typography>
                    {signatories?.performed_by?.signature_url ? (
                      <Box sx={{ height: '8mm', my: 0.35, display: 'flex', alignItems: 'flex-end' }}>
                        <Box
                          component="img"
                          src={signatories.performed_by.signature_url}
                          alt="Signature"
                          sx={{ maxHeight: '8mm', maxWidth: '32mm', objectFit: 'contain' }}
                        />
                      </Box>
                    ) : null}
                    <Typography sx={{ fontSize: '0.80rem', fontWeight: 700, color: '#0f172a' }}>
                      {signatories?.performed_by?.full_name || 'Not recorded'}
                    </Typography>
                    <Typography sx={{ fontSize: '0.72rem', color: '#475569' }}>
                      {signatories?.performed_by?.qualification || '—'}
                    </Typography>
                    <Typography sx={{ fontSize: '0.70rem', color: '#64748b' }}>
                      {signatories?.performed_by?.registration_council || 'Registration'}: {signatories?.performed_by?.registration_number || '—'}
                    </Typography>
                  </Box>

                  {/* Right: Verified / Authorized By */}
                  {signatories?.authorized_by && <Box sx={{ textAlign: 'right', pl: '5mm', borderLeft: '1px solid #d5e6dc' }}>
                    <Typography sx={{ fontSize: '0.70rem', fontWeight: 800, color: '#0b6b3a', textTransform: 'uppercase', letterSpacing: '0.04em', pb: 0.35, borderBottom: '1px solid #d5e6dc' }}>
                      Verified / Authorized By:
                    </Typography>
                    {signatories?.authorized_by?.signature_url ? (
                      <Box sx={{ height: '8mm', my: 0.35, display: 'flex', alignItems: 'flex-end', justifyContent: 'flex-end' }}>
                        <Box
                          component="img"
                          src={signatories.authorized_by.signature_url}
                          alt="Signature"
                          sx={{ maxHeight: '8mm', maxWidth: '32mm', objectFit: 'contain' }}
                        />
                      </Box>
                    ) : null}
                      <>
                        <Typography sx={{ fontSize: '0.80rem', fontWeight: 700, color: '#0f172a' }}>
                          {signatories.authorized_by.full_name}
                        </Typography>
                        <Typography sx={{ fontSize: '0.72rem', color: '#475569' }}>
                          {signatories.authorized_by.qualification}
                          {signatories.authorized_by.specialization ? ` &bull; ${signatories.authorized_by.specialization}` : ''}
                        </Typography>
                        <Typography sx={{ fontSize: '0.70rem', color: '#64748b' }}>
                          {signatories.authorized_by.registration_council}: {signatories.authorized_by.registration_number}
                        </Typography>
                      </>
                  </Box>}
                </Box>
              </Box>
            </Box>

            <Box
              className="report-clinical-note"
              sx={{
                height: '7mm', minHeight: '7mm', maxHeight: '7mm',
                display: 'flex', alignItems: 'center', px: '1mm',
                color: BIMAL_PRINT.brandDeep, fontSize: '0.58rem', lineHeight: 1.15,
                borderTop: '1px solid #d5e6dc', flexShrink: 0,
              }}
            >
              <Box component="span" sx={{ fontWeight: 800, mr: 0.5 }}>NOTE:</Box>
              Test results relate only to the specimen tested and should be clinically correlated.
            </Box>

            {/* BOTTOM STRIP: ACCURATE "Page X of Y" ON EVERY PAGE */}
            <Box
              className="bimal-footer-strip"
              sx={{
                height: '13mm',
                minHeight: '13mm',
                maxHeight: '13mm',
                pt: 0.5,
                borderTop: '1.5px solid #0b6b3a',
                display: 'grid',
                gridTemplateColumns: 'minmax(0, 1.3fr) minmax(0, 1.5fr) auto',
                columnGap: '2.5mm',
                alignItems: 'center',
                fontSize: '0.64rem',
                lineHeight: 1.08,
                color: '#ffffff',
                bgcolor: BIMAL_PRINT.brand,
                borderBottom: `1.5px solid ${BIMAL_PRINT.brand}`,
                flexShrink: 0,
              }}
            >
              <Box className="bimal-footer-contact" sx={{ minWidth: 0, overflowWrap: 'anywhere' }}>
                {org.phone || '—'} &bull; {footerEmail}
              </Box>
              <Box className="bimal-footer-report-identity" sx={{ minWidth: 0, textAlign: 'center', overflowWrap: 'anywhere', lineHeight: 1 }}>
                <Box component="span" sx={{ display: 'block', fontSize: '0.60rem' }}>Bharatpur-7, Chitwan, Nepal</Box>
                <Box component="span" sx={{ display: 'block', fontSize: '0.45rem', lineHeight: 1, letterSpacing: '-0.01em', color: '#d9f3e4' }}>
                  Report: {reportNumber || '—'} &bull; v{version}{integrityHash ? ` [${integrityHash}]` : ''}
                </Box>
              </Box>
              <Box className="bimal-footer-page-number" sx={{ minWidth: 0, fontWeight: 800, color: '#ffffff', whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>
                Page {pageNumber} of {totalPageCount}
              </Box>
            </Box>
            </>
          </Box>
        );
      })}
    </Box>
  );
};
