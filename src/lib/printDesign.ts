/** Canonical physical-document design tokens shared by every print surface. */
export const BIMAL_PRINT = {
  pageWidth: '210mm',
  pageHeight: '297mm',
  contentWidth: '190mm',
  marginVertical: '10mm',
  marginHorizontal: '10mm',
  fontStack: "'Inter', 'Mukta', 'Noto Sans Devanagari', 'Segoe UI', Arial, sans-serif",
  ink: '#0f172a',
  muted: '#475569',
  brand: '#0b6b3a',
  brandDeep: '#07562f',
  brandSoft: '#edf7f1',
  border: '#9eb8aa',
  watermarkOpacity: 0.045,
  logoPath: '/pathology-logo.png',
} as const;

/** Included both in previews and in the isolated iframe print document. */
export const BIMAL_PRINT_CSS = `
  @page { size: A4 portrait; margin: 0; }
  *, *::before, *::after {
    box-sizing: border-box;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }
  html, body {
    margin: 0 !important;
    padding: 0 !important;
    background: #fff !important;
    color: #0f172a !important;
    font-family: ${BIMAL_PRINT.fontStack} !important;
  }
  .bimal-print-document {
    width: 100%;
    max-width: none !important;
    margin: 0;
    background: #fff;
    transform: none !important;
    zoom: 1 !important;
  }
  .a4-page, .report-page, .bimal-a4-page {
    width: 210mm !important;
    height: 297mm !important;
    min-height: 297mm !important;
    margin: 0 auto !important;
    max-width: none !important;
    padding: 10mm !important;
    position: relative !important;
    overflow: hidden !important;
    background: #fff !important;
    box-shadow: none !important;
    border: 0 !important;
    display: flex !important;
    flex-direction: column !important;
    transform: none !important;
    zoom: 1 !important;
    page-break-after: always !important;
    break-after: page !important;
  }
  .a4-page:last-child, .report-page:last-child, .bimal-a4-page:last-child {
    page-break-after: auto !important;
    break-after: auto !important;
  }
  .watermark-container, .bimal-page-watermark {
    position: absolute !important;
    left: 50% !important;
    top: 38% !important;
    transform: translate(-50%, -50%) !important;
    width: min(110mm, 100%) !important;
    height: auto !important;
    opacity: 0.045 !important;
    z-index: 0 !important;
    pointer-events: none !important;
  }
  .watermark-container > img, .bimal-page-watermark > img {
    display: block !important;
    width: 100% !important;
    height: auto !important;
    max-width: 110mm !important;
    object-fit: contain !important;
  }
  .bimal-workspace-texture {
    position: absolute !important;
    inset: 0 !important;
    z-index: 0 !important;
    pointer-events: none !important;
    background-repeat: repeat !important;
    background-size: 74mm 63.5mm !important;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }
  .page-content, .bimal-page-content {
    display: block !important;
    position: relative !important;
    z-index: 1 !important;
  }
  .page-content th, .page-content td, .bimal-page-content th, .bimal-page-content td {
    background: rgba(255, 255, 255, 0.88) !important;
  }
  .report-header, .patient-info-box, .department-header-block, .clinical-end-marker, .signature-block, .report-clinical-note, .bimal-footer-strip {
    page-break-inside: avoid !important;
    break-inside: avoid !important;
  }
  .report-identity-header { position: relative !important; height: 68mm !important; min-height: 68mm !important; max-height: 68mm !important; overflow: hidden !important; isolation: isolate !important; flex-shrink: 0 !important; }
  .patient-identity-strip { height: 32mm !important; min-height: 32mm !important; max-height: 32mm !important; overflow: hidden !important; }
  .clinical-workspace { position: relative !important; display: flex !important; flex-direction: column !important; height: 189mm !important; min-height: 189mm !important; max-height: 189mm !important; overflow: hidden !important; }
  .report-header-diagonal-accent {
    position: absolute !important;
    inset: 0 22mm 0 0 !important;
    z-index: 0 !important;
    pointer-events: none !important;
    overflow: hidden !important;
    background: none !important;
    -webkit-mask-image: linear-gradient(to top right, #000 0%, rgba(0,0,0,0.72) 40%, transparent 72%) !important;
    mask-image: linear-gradient(to top right, #000 0%, rgba(0,0,0,0.72) 40%, transparent 72%) !important;
  }
  .report-header-background-wordmark, .report-header-background-logo {
    print-color-adjust: exact !important;
    -webkit-print-color-adjust: exact !important;
  }
  .report-header, .patient-info-box { position: relative !important; z-index: 1 !important; }
  .report-identity-header, .patient-identity-strip, .department-header-block,
  .signature-block, .report-clinical-note, .bimal-footer-strip {
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }
  .signature-block { page-break-after: avoid !important; break-after: avoid !important; }
  .report-interpretation { page-break-inside: auto !important; break-inside: auto !important; }
  .report-clinical-note { height: 7mm !important; min-height: 7mm !important; max-height: 7mm !important; }
  .bimal-footer-strip { page-break-before: avoid !important; break-before: avoid !important; height: 13mm !important; min-height: 13mm !important; max-height: 13mm !important; margin-top: 0 !important; }
  @media screen {
    .printable-report-wrapper .report-page { margin: 0 auto 24px !important; }
    .printable-report-wrapper .report-page:last-child { margin-bottom: 0 !important; }
  }
  @media print {
    html, body, .printable-report-wrapper {
      width: 210mm !important;
      min-width: 210mm !important;
      max-width: 210mm !important;
      transform: none !important;
      zoom: 1 !important;
    }
    .printable-report-wrapper .report-page { margin: 0 !important; }
  }
  table { width: 100% !important; border-collapse: collapse !important; }
  thead { display: table-header-group !important; }
  tr { page-break-inside: avoid !important; break-inside: avoid !important; }
  .screen-only, .no-print, nav, header, aside, button,
  .MuiButton-root, .MuiIconButton-root, .MuiDialogActions-root, .MuiDialogTitle-root {
    display: none !important;
  }
`;
