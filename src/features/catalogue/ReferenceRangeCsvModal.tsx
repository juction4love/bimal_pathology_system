/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Laboratory Clinical Configuration & Reference Range CSV Import / Export Engine
 * Standardized bulk setup and analyzer range integration.
 */

import React, { useState, useRef } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  Box,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Chip,
  Alert,
  CircularProgress,
  Tabs,
  Tab,
  Stack,
} from '@mui/material';
import FileDownloadIcon from '@mui/icons-material/FileDownload';
import FileUploadIcon from '@mui/icons-material/FileUpload';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';

import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { getNepalTodayAd } from '@/lib/dateTime';
import { paisaToRupees } from '@/lib/currency';

interface ReferenceRangeCsvModalProps {
  open: boolean;
  onClose: () => void;
  onImportCompleted?: () => void;
}

interface ParsedLabConfigRow {
  rowNum: number;
  test_code: string;
  test_name: string;
  analyzer: string;
  reagent: string;
  method: string;
  specimen: string;
  container: string;
  unit: string;
  male_range: string;
  female_range: string;
  pediatric_range: string;
  critical_low: string;
  critical_high: string;
  tat: string;
  price_npr: string;
  reference_source: string;
  critical_source: string;
  approval_notes: string;
  isValid: boolean;
  error?: string;
}

const MASTER_18_COL_HEADER = 'Test Code,Test Name,Analyzer,Reagent,Method,Specimen,Container,Unit,Male Reference Range,Female Reference Range,Pediatric Reference Range,Critical Low,Critical High,TAT,Price NPR,Reference Source,Critical Limit Source,Approval Notes';

export const ReferenceRangeCsvModal: React.FC<ReferenceRangeCsvModalProps> = ({
  open,
  onClose,
  onImportCompleted,
}) => {
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [mode, setMode] = useState<'master' | 'detailed'>('master');
  const [loading, setLoading] = useState(false);
  const [importing, setImporting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const [parsedMasterRows, setParsedMasterRows] = useState<ParsedLabConfigRow[]>([]);

  // Simple robust CSV line parser supporting quoted strings with commas and escaped quotes
  const parseCsvLine = (line: string): string[] => {
    const result: string[] = [];
    let cur = '';
    let inQuote = false;
    for (let i = 0; i < line.length; i++) {
      const char = line[i];
      if (char === '"') {
        if (inQuote && line[i + 1] === '"') {
          cur += '"';
          i++;
        } else {
          inQuote = !inQuote;
        }
      } else if (char === ',' && !inQuote) {
        result.push(cur.trim());
        cur = '';
      } else {
        cur += char;
      }
    }
    result.push(cur.trim());
    return result;
  };

  // Safe CSV field escaper
  const escapeCsv = (val: any): string => {
    if (val === null || val === undefined) return '""';
    const str = String(val);
    return `"${str.replace(/"/g, '""')}"`;
  };

  // Export the standard 18-column lab configuration template with all 1,122 tests
  const handleExport18ColTemplate = async () => {
    setLoading(true);
    setError(null);

    try {
      const { data: tests, error: tErr } = await supabase
        .from('tests')
        .select('id, code, name, method, sample_type, container, tat_hours, price_paisa, configuration_notes, parameters(id, code, name, unit, reference_ranges(id, gender, normal_text, normal_min, normal_max, critical_low, critical_high))')
        .order('display_order', { ascending: true })
        .order('code', { ascending: true });

      if (tErr) throw tErr;

      const lines: string[] = [MASTER_18_COL_HEADER];

      (tests || []).forEach((t) => {
        const param = (t.parameters || [])[0];
        const ranges = param?.reference_ranges || [];
        const maleRange = ranges.find((r: any) => r.gender === 'Male')?.normal_text ||
          (ranges.find((r: any) => r.gender === 'Male' && r.normal_min !== null)
            ? `${ranges.find((r: any) => r.gender === 'Male')?.normal_min} - ${ranges.find((r: any) => r.gender === 'Male')?.normal_max}`
            : '');
        const femaleRange = ranges.find((r: any) => r.gender === 'Female')?.normal_text ||
          (ranges.find((r: any) => r.gender === 'Female' && r.normal_min !== null)
            ? `${ranges.find((r: any) => r.gender === 'Female')?.normal_min} - ${ranges.find((r: any) => r.gender === 'Female')?.normal_max}`
            : '');
        const allRange = ranges.find((r: any) => r.gender === 'All')?.normal_text ||
          (ranges.find((r: any) => r.gender === 'All' && r.normal_min !== null)
            ? `${ranges.find((r: any) => r.gender === 'All')?.normal_min} - ${ranges.find((r: any) => r.gender === 'All')?.normal_max}`
            : '');

        const primaryRange = maleRange || allRange || '';
        const secondaryRange = femaleRange || allRange || '';

        const critLow = ranges.find((r: any) => r.critical_low !== null)?.critical_low ?? '';
        const critHigh = ranges.find((r: any) => r.critical_high !== null)?.critical_high ?? '';

        lines.push([
          escapeCsv(t.code),
          escapeCsv(t.name),
          escapeCsv(''), // Analyzer model
          escapeCsv(''), // Reagent manufacturer
          escapeCsv(t.method || ''),
          escapeCsv(t.sample_type || ''),
          escapeCsv(t.container || ''),
          escapeCsv(param?.unit || ''),
          escapeCsv(primaryRange),
          escapeCsv(secondaryRange),
          escapeCsv(''), // Pediatric Range
          escapeCsv(critLow),
          escapeCsv(critHigh),
          escapeCsv(t.tat_hours || 24),
          escapeCsv(paisaToRupees(t.price_paisa || 0)),
          escapeCsv(''), // Reference Source
          escapeCsv(''), // Critical Limit Source
          escapeCsv(t.configuration_notes || ''),
        ].join(','));
      });

      const blob = new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.setAttribute('href', url);
      link.setAttribute('download', `bimal_master_test_catalogue_template_${getNepalTodayAd()}.csv`);
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to export master catalogue configuration template.'));
    } finally {
      setLoading(false);
    }
  };

  // Parse Uploaded CSV File
  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    setLoading(true);
    setError(null);
    setSuccess(null);
    setParsedMasterRows([]);

    try {
      const text = await file.text();
      const lines = text.split(/\r?\n/).map((l) => l.trim()).filter((l) => l.length > 0);

      if (lines.length < 2) {
        throw new Error('CSV file is empty or missing data rows.');
      }

      // Fetch master tests to validate test codes
      const { data: tests, error: tErr } = await supabase.from('tests').select('id, code, name');
      if (tErr) throw tErr;

      const testCodeMap = new Map((tests || []).map((t) => [t.code.toUpperCase(), t]));
      const parsed: ParsedLabConfigRow[] = [];

      for (let i = 1; i < lines.length; i++) {
        const cols = parseCsvLine(lines[i]);
        if (cols.length < 2) continue;

        const test_code = cols[0]?.toUpperCase() || '';
        const test_name = cols[1] || '';
        const analyzer = cols[2] || '';
        const reagent = cols[3] || '';
        const method = cols[4] || '';
        const specimen = cols[5] || '';
        const container = cols[6] || '';
        const unit = cols[7] || '';
        const male_range = cols[8] || '';
        const female_range = cols[9] || '';
        const pediatric_range = cols[10] || '';
        const critical_low = cols[11] || '';
        const critical_high = cols[12] || '';
        const tat = cols[13] || '';
        const price_npr = cols[14] || '';
        const reference_source = cols[15] || '';
        const critical_source = cols[16] || '';
        const approval_notes = cols[17] || '';

        let isValid = true;
        let rowError: string | undefined;

        if (!test_code) {
          isValid = false;
          rowError = 'Missing Test Code';
        } else if (!testCodeMap.has(test_code)) {
          isValid = false;
          rowError = `Test Code "${test_code}" not found in master catalogue.`;
        }

        parsed.push({
          rowNum: i + 1,
          test_code,
          test_name: test_name || (testCodeMap.get(test_code)?.name ?? ''),
          analyzer,
          reagent,
          method,
          specimen,
          container,
          unit,
          male_range,
          female_range,
          pediatric_range,
          critical_low,
          critical_high,
          tat,
          price_npr,
          reference_source,
          critical_source,
          approval_notes,
          isValid,
          error: rowError,
        });
      }

      setParsedMasterRows(parsed);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to parse CSV file.'));
    } finally {
      setLoading(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  // Commit valid parsed rows to database using RPC
  const handleCommitMasterImport = async () => {
    const validRows = parsedMasterRows.filter((r) => r.isValid);
    if (validRows.length === 0) {
      setError('No valid rows available to import.');
      return;
    }

    setImporting(true);
    setError(null);
    setSuccess(null);

    try {
      const itemsPayload = validRows.map((r) => ({
        test_code: r.test_code,
        test_name: r.test_name,
        analyzer: r.analyzer,
        reagent: r.reagent,
        method: r.method,
        specimen: r.specimen,
        container: r.container,
        unit: r.unit,
        male_range: r.male_range,
        female_range: r.female_range,
        pediatric_range: r.pediatric_range,
        critical_low: r.critical_low,
        critical_high: r.critical_high,
        tat: r.tat,
        price_npr: r.price_npr,
        reference_source: r.reference_source,
        critical_source: r.critical_source,
        approval_notes: r.approval_notes,
      }));

      const { data, error: rpcErr } = await supabase.rpc('catalogue_bulk_import_lab_data', {
        p_items: itemsPayload,
      });

      if (rpcErr) throw rpcErr;

      const updatedCount = (data as any)?.updated_count ?? validRows.length;
      setSuccess(`Successfully imported lab configuration for ${updatedCount} tests! Configuration saved in Draft state ready for clinical sign-off.`);

      if (onImportCompleted) onImportCompleted();
      setTimeout(() => {
        onClose();
      }, 1500);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to commit lab configuration import.'));
    } finally {
      setImporting(false);
    }
  };

  // Detailed parameter range replacement using guarded RPC
  const _handleCommitDetailedRanges = async (paramIds: string[], ranges: any[]) => {
    return supabase.rpc('catalogue_replace_ranges', {
      p_parameter_ids: paramIds,
      p_ranges: ranges,
    });
  };

  const validCount = parsedMasterRows.filter((r) => r.isValid).length;
  const invalidCount = parsedMasterRows.filter((r) => !r.isValid).length;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="xl" fullWidth>
      <DialogTitle>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Box>
            <Typography variant="h6" fontWeight={800} color="primary.main">
              Laboratory Master Configuration & Range CSV Engine
            </Typography>
            <Typography variant="caption" color="text.secondary">
              Bulk configure real analyzer models, reagent kits, clinical reference intervals, critical limits, and pricing.
            </Typography>
          </Box>
          <Button
            variant="outlined"
            size="small"
            startIcon={<FileDownloadIcon />}
            onClick={handleExport18ColTemplate}
            disabled={loading}
          >
            Export 18-Column Master Template (CSV)
          </Button>
        </Box>
      </DialogTitle>

      <DialogContent dividers>
        {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>{error}</Alert>}
        {success && <Alert severity="success" sx={{ mb: 2 }} onClose={() => setSuccess(null)}>{success}</Alert>}

        <Tabs value={mode} onChange={(_, val) => setMode(val)} sx={{ mb: 2, borderBottom: 1, borderColor: 'divider' }}>
          <Tab value="master" label="18-Column Master Lab Configuration" />
        </Tabs>

        {/* Upload Zone */}
        <Box sx={{ p: 2.5, border: '2px dashed #cbd5e1', borderRadius: 2, textAlign: 'center', mb: 3, bgcolor: '#f8fafc' }}>
          <input
            type="file"
            accept=".csv"
            ref={fileInputRef}
            style={{ display: 'none' }}
            onChange={handleFileUpload}
          />
          <Typography variant="subtitle1" fontWeight={700} sx={{ mb: 0.5 }}>
            Upload Laboratory-Approved Configuration CSV
          </Typography>
          <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 2, maxWidth: 850, mx: 'auto' }}>
            Columns: Test Code, Test Name, Analyzer, Reagent, Method, Specimen, Container, Unit, Male Reference Range, Female Reference Range, Pediatric Reference Range, Critical Low, Critical High, TAT, Price NPR, Reference Source, Critical Limit Source, Approval Notes
          </Typography>
          <Stack direction="row" spacing={2} justifyContent="center">
            <Button
              variant="contained"
              color="primary"
              startIcon={<FileUploadIcon />}
              onClick={() => fileInputRef.current?.click()}
              disabled={loading || importing}
            >
              Choose CSV File
            </Button>
            <Button
              variant="outlined"
              startIcon={<FileDownloadIcon />}
              onClick={handleExport18ColTemplate}
              disabled={loading || importing}
            >
              Download Blank Template
            </Button>
          </Stack>
        </Box>

        {loading && (
          <Box sx={{ display: 'flex', justifyContent: 'center', p: 3 }}>
            <CircularProgress />
          </Box>
        )}

        {/* Parsed Preview Table */}
        {parsedMasterRows.length > 0 && (
          <Box>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1.5 }}>
              <Box sx={{ display: 'flex', gap: 1 }}>
                <Chip label={`Total Rows: ${parsedMasterRows.length}`} size="small" />
                <Chip label={`Valid: ${validCount}`} color="success" size="small" icon={<CheckCircleIcon />} />
                {invalidCount > 0 && (
                  <Chip label={`Invalid: ${invalidCount}`} color="error" size="small" icon={<ErrorIcon />} />
                )}
              </Box>
              <Typography variant="caption" color="text.secondary">
                Import saves data as Draft. Clinical sign-off is required before activation.
              </Typography>
            </Box>

            <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', maxHeight: 350 }}>
              <Table size="small" stickyHeader>
                <TableHead sx={{ bgcolor: '#f8fafc' }}>
                  <TableRow>
                    <TableCell width={50}>Row</TableCell>
                    <TableCell>Test Code</TableCell>
                    <TableCell>Test Name</TableCell>
                    <TableCell>Analyzer / Reagent</TableCell>
                    <TableCell>Method</TableCell>
                    <TableCell>Unit</TableCell>
                    <TableCell>Reference Range</TableCell>
                    <TableCell>Critical Limits</TableCell>
                    <TableCell>Price (NPR)</TableCell>
                    <TableCell>Status</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {parsedMasterRows.map((r) => (
                    <TableRow
                      key={r.rowNum}
                      sx={{ bgcolor: r.isValid ? 'inherit' : '#fef2f2' }}
                    >
                      <TableCell>{r.rowNum}</TableCell>
                      <TableCell sx={{ fontWeight: 700 }}>{r.test_code}</TableCell>
                      <TableCell>{r.test_name}</TableCell>
                      <TableCell>
                        <Typography variant="caption" display="block">{r.analyzer || '—'}</Typography>
                        <Typography variant="caption" color="text.secondary">{r.reagent || ''}</Typography>
                      </TableCell>
                      <TableCell>{r.method || '—'}</TableCell>
                      <TableCell>{r.unit || '—'}</TableCell>
                      <TableCell>
                        {r.male_range || r.female_range ? (
                          <Typography variant="caption">
                            {r.male_range === r.female_range ? r.male_range : `M: ${r.male_range || '-'} | F: ${r.female_range || '-'}`}
                          </Typography>
                        ) : '—'}
                      </TableCell>
                      <TableCell>
                        {r.critical_low || r.critical_high ? (
                          <Typography variant="caption" color="error.main">
                            &lt; {r.critical_low || '-'} | &gt; {r.critical_high || '-'}
                          </Typography>
                        ) : '—'}
                      </TableCell>
                      <TableCell>{r.price_npr ? `Rs. ${r.price_npr}` : '—'}</TableCell>
                      <TableCell>
                        {r.isValid ? (
                          <Chip label="Ready" size="small" color="success" />
                        ) : (
                          <Chip label={r.error || 'Invalid'} size="small" color="error" />
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          </Box>
        )}
      </DialogContent>

      <DialogActions sx={{ p: 2, display: 'flex', justifyContent: 'space-between' }}>
        <Typography variant="caption" color="text.secondary">
          Import will update configuration in Draft state. Activation remains locked until formally approved.
        </Typography>
        <Box sx={{ display: 'flex', gap: 1 }}>
          <Button onClick={onClose} disabled={importing}>
            Cancel
          </Button>
          <Button
            variant="contained"
            color="primary"
            disabled={importing || validCount === 0}
            onClick={handleCommitMasterImport}
          >
            {importing ? 'Importing...' : `Import ${validCount} Tests`}
          </Button>
        </Box>
      </DialogActions>
    </Dialog>
  );
};
