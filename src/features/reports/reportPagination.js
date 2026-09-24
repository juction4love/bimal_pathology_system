/** Canonical A4 report pagination expressed in physical millimetres. */
export const REPORT_PAGINATION_MM = Object.freeze({
  printableHeight: 277,
  // Full bilingual branding, QR, and patient/report identity are repeated on
  // every sheet. Reserve their measured browser height plus font-fallback room.
  fullPageHeader: 68,
  clinicalNote: 7,
  footer: 13,
  clinicalEndMarker: 6,
  signatoryBlock: 23,
  signatoryFooterGap: 2,
  safetyGap: 2.5,
  normalPageGeometryTolerance: 4,
  investigationHeader: 10,
  tableHeader: 5,
  investigationTitleWrapLine: 4.5,
  compactSingleInvestigationHeader: 16,
  continuedInvestigationHeader: 11,
  resultLine: 2.8,
  resultRowBase: 4.8,
  interpretationBase: 6,
  interpretationLine: 3.5,
});

function lineCount(value, charactersPerLine) {
  return Math.max(1, Math.ceil(String(value ?? '').trim().length / charactersPerLine));
}

export function normalizeReferencePrecision(value) {
  return String(value ?? '').replace(/-?\d+\.\d+/g, (token) => token.replace(/(\.\d*?[1-9])0+$|\.0+$/, '$1'));
}

export function formatReportReferenceRange(rawText) {
  if (!rawText) return '—';
  const trimmed = String(rawText).trim();
  if (
    trimmed === '' ||
    trimmed.toLowerCase() === 'not configured' ||
    trimmed.toLowerCase() === 'standard' ||
    trimmed === '-'
  ) {
    return '—';
  }
  return normalizeReferencePrecision(trimmed);
}

function referenceText(result) {
  const text = result?.reference_range ?? result?.reference_text ??
    [result?.normal_min, result?.normal_max].filter((value) => value !== null && value !== undefined).join(' - ');
  return formatReportReferenceRange(text);
}

export function resultHeightMm(result) {
  const lines = Math.max(
    // Chromium measurements at the canonical 39% parameter column show that
    // 40-character labels fit when the trailing index is one digit, while the
    // corresponding 41-character labels wrap. Keep this physical threshold
    // aligned with the current print font instead of a report-type row limit.
    lineCount(result?.name, 40),
    lineCount(result?.unit, 18),
    lineCount(referenceText(result), 30),
    lineCount(`${result?.display_value ?? ''} ${result?.flag ?? ''}`, 18),
  );
  return REPORT_PAGINATION_MM.resultRowBase + (lines - 1) * REPORT_PAGINATION_MM.resultLine;
}

export function interpretationHeightMm(value) {
  if (!value) return 0;
  return REPORT_PAGINATION_MM.interpretationBase +
    lineCount(value, 92) * REPORT_PAGINATION_MM.interpretationLine;
}

export function investigationHeaderHeightMm(investigation, continued) {
  if (continued) return REPORT_PAGINATION_MM.continuedInvestigationHeader;
  if (!continued && investigation?.results?.length === 1 && !investigation?.interpretation_template) {
    return REPORT_PAGINATION_MM.compactSingleInvestigationHeader;
  }
  const titleLines = lineCount(investigation?.test_name, 70);
  return REPORT_PAGINATION_MM.investigationHeader +
    REPORT_PAGINATION_MM.tableHeader +
    (titleLines - 1) * REPORT_PAGINATION_MM.investigationTitleWrapLine;
}

export function signatoryReserveMm() {
  return REPORT_PAGINATION_MM.signatoryBlock +
    REPORT_PAGINATION_MM.signatoryFooterGap +
    REPORT_PAGINATION_MM.safetyGap;
}

function contentCapacityMm(pageIndex, finalPageIndex) {
  // Every physical sheet owns the same signature zone. Only the final sheet
  // additionally reserves the clinical end marker. This capacity is the
  // actual 212 mm workspace, not a report-type or row-count allowance.
  const finalReserve = pageIndex === finalPageIndex ? REPORT_PAGINATION_MM.clinicalEndMarker : 0;
  return REPORT_PAGINATION_MM.printableHeight -
    REPORT_PAGINATION_MM.fullPageHeader -
    REPORT_PAGINATION_MM.clinicalNote -
    REPORT_PAGINATION_MM.footer -
    signatoryReserveMm() -
    finalReserve;
}

function packForPageCount(investigations, expectedPageCount) {
  const pages = [];
  let pageIndex = 0;
  let usedMm = 0;
  let chunks = [];

  const flush = () => {
    if (chunks.length === 0) return;
    pages.push({ investigations: chunks, usedMm, capacityMm: contentCapacityMm(pageIndex, expectedPageCount - 1) });
    pageIndex += 1;
    usedMm = 0;
    chunks = [];
  };

  for (let investigationIndex = 0; investigationIndex < investigations.length; investigationIndex += 1) {
    const investigation = investigations[investigationIndex];
    const results = investigation?.results ?? [];
    const previousInvestigation = investigations[investigationIndex - 1];
    const compactSeriesContinuation = results.length === 1 && !investigation?.interpretation_template &&
      previousInvestigation?.results?.length === 1 && !previousInvestigation?.interpretation_template;
    let cursor = 0;
    let emittedEmpty = false;

    while (cursor < results.length || (!emittedEmpty && results.length === 0)) {
      if (pageIndex >= expectedPageCount) return null;
      const continued = cursor > 0;
      let headerMm = compactSeriesContinuation && !continued ? 6.5 : investigationHeaderHeightMm(investigation, continued);
      let capacityMm = contentCapacityMm(pageIndex, expectedPageCount - 1);
      const firstRowMm = results.length > 0
        ? resultHeightMm(results[cursor])
        : interpretationHeightMm(investigation?.interpretation_template);
      if (chunks.length > 0 && usedMm + headerMm + firstRowMm > capacityMm) {
        flush();
        if (pageIndex >= expectedPageCount) return null;
        headerMm = compactSeriesContinuation && !continued ? 6.5 : investigationHeaderHeightMm(investigation, continued);
        capacityMm = contentCapacityMm(pageIndex, expectedPageCount - 1);
      }

      const chunkResults = [];
      let chunkMm = headerMm;
      if (results.length === 0) {
        const commentMm = interpretationHeightMm(investigation?.interpretation_template);
        if (chunks.length > 0 && usedMm + chunkMm + commentMm > capacityMm) {
          flush();
          if (pageIndex >= expectedPageCount) return null;
          capacityMm = contentCapacityMm(pageIndex, expectedPageCount - 1);
        }
        chunkMm += commentMm;
        emittedEmpty = true;
      } else {
        while (cursor + chunkResults.length < results.length) {
          const index = cursor + chunkResults.length;
          const isLast = index === results.length - 1;
          const isLastReportResult = isLast && investigationIndex === investigations.length - 1;
          if (isLastReportResult && pageIndex < expectedPageCount - 1 && (chunkResults.length > 0 || chunks.length > 0)) {
            break;
          }
          const nextMm = resultHeightMm(results[index]) +
            (isLast ? interpretationHeightMm(investigation?.interpretation_template) : 0);
          if (usedMm + chunkMm + nextMm > capacityMm && chunkResults.length > 0) break;
          if (usedMm + chunkMm + nextMm > capacityMm && chunks.length > 0) {
            flush();
            break;
          }
          chunkResults.push(results[index]);
          chunkMm += nextMm;
        }
        if (chunkResults.length === 0) {
          flush();
          continue;
        }
      }

      chunks.push({
        ...investigation,
        source_result_count: results.length,
        is_continuation: continued,
        results: chunkResults,
        interpretation_template: cursor + chunkResults.length >= results.length
          ? investigation?.interpretation_template
          : null,
      });
      cursor += chunkResults.length;
      usedMm += chunkMm;
      if (cursor < results.length) flush();
    }
  }

  flush();
  return pages.length === expectedPageCount ? pages : null;
}

export function isReportableParameter(result, investigation) {
  if (!result) return false;
  const unit = String(result.unit || '').trim().toLowerCase();
  if (unit === 'panel') return false;
  const valType = String(result.value_type || '').trim().toLowerCase();
  if (valType === 'panel' || valType === 'profile') return false;
  if (
    investigation &&
    investigation.results &&
    investigation.results.length > 1 &&
    (result.code === investigation.test_code || result.name === investigation.test_name) &&
    (unit === 'panel' || unit === '' || !result.reference_range)
  ) {
    const hasOtherParams = investigation.results.some(
      (other) => other !== result && String(other.unit || '').trim().toLowerCase() !== 'panel'
    );
    if (hasOtherParams) return false;
  }
  return true;
}

export function paginateInvestigations(investigations) {
  const rawSource = investigations ?? [];
  const source = rawSource.map((inv) => ({
    ...inv,
    results: (inv.results ?? []).filter((r) => isReportableParameter(r, inv)),
  }));
  if (source.length === 0) {
    return [{ pageNumber: 1, isFirstPage: true, isFinalPage: true, investigations: [], usedMm: 0, capacityMm: contentCapacityMm(0, 0) }];
  }

  // Retry with a successively later final page. No page-count-specific branch
  // exists: N is the first page count whose normal and reserved final geometry fits.
  for (let expectedPageCount = 1; expectedPageCount < 1000; expectedPageCount += 1) {
    const packed = packForPageCount(source, expectedPageCount);
    if (!packed) continue;
    return packed.map((page, index) => ({
      ...page,
      pageNumber: index + 1,
      isFirstPage: index === 0,
      isFinalPage: index === packed.length - 1,
    }));
  }
  throw new Error('Report exceeds the supported pagination safety limit.');
}
