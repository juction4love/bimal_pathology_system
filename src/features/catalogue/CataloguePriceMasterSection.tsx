import { useCallback, useEffect, useState, useMemo, useRef } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControl,
  Grid,
  InputLabel,
  MenuItem,
  Paper,
  Select,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TablePagination,
  TableRow,
  TextField,
  ToggleButton,
  ToggleButtonGroup,
  Tooltip,
  Typography,
  LinearProgress,
} from '@mui/material';
import CloudUploadIcon from '@mui/icons-material/CloudUpload';
import SaveIcon from '@mui/icons-material/Save';
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline';
import ErrorOutlineIcon from '@mui/icons-material/ErrorOutline';
import WarningAmberIcon from '@mui/icons-material/WarningAmber';
import PriceCheckIcon from '@mui/icons-material/PriceCheck';

import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { formatAdDate, getNepalTodayAd } from '@/lib/dateTime';
import { formatPaisa, parseRupeesToPaisa, isValidMoneyIntermediate } from '@/lib/currency';
import { MoneyInputField } from '@/components/common/MoneyInputField';

type EntityType = 'Test' | 'Panel' | 'Package';

type RateRow = {
  entity_id: string;
  entity_type: EntityType;
  code: string;
  name: string;
  category_id?: string | null;
  category: string;
  entity_status: 'Draft' | 'Active' | 'Archived';
  rate_id?: string | null;
  price_paisa?: number | null;
  effective_from?: string | null;
  rate_status?: string | null;
  rate_row_version?: number | null;
  updated_at?: string | null;
};

type HistoryRow = {
  id: string;
  version_number: number;
  price_paisa: number | null;
  effective_from: string | null;
  status: string;
  row_version: number;
  used_by_bill_count: number;
};

type Category = { id: string; name: string };

type CsvValidationRow = {
  rowNumber: number;
  code: string;
  name: string;
  rateNpr: string;
  effectiveFrom: string;
  parsedPaisa: number | null;
  entityId: string | null;
  entityType: EntityType;
  currentRateId: string | null;
  currentRateRowVersion: number | null;
  isValid: boolean;
  error?: string;
};

export function CataloguePriceMasterSection({ canManage }: { canManage: boolean }) {
  const [rows, setRows] = useState<RateRow[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [total, setTotal] = useState(0);

  // KPIs
  const [kpiTotal, setKpiTotal] = useState<number>(0);
  const [kpiConfigured, setKpiConfigured] = useState<number>(0);
  const [kpiMissing, setKpiMissing] = useState<number>(0);

  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [loading, setLoading] = useState(false);

  // Filters
  const [viewMode, setViewMode] = useState<'all' | 'missing'>('all');
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState('');
  const [lifecycle, setLifecycle] = useState('Active');
  const [entityType, setEntityType] = useState('');
  const [sort, setSort] = useState('name');
  const [descending, setDescending] = useState(false);
  const [page, setPage] = useState(0);
  const [pageSize, setPageSize] = useState(25);

  // Inline edited rates for batch save: entity_id -> { paisa, reason, row }
  const [stagedRates, setStagedRates] = useState<
    Record<string, { pricePaisa: number; reason: string; row: RateRow }>
  >({});

  // Single edit modal state
  const [selected, setSelected] = useState<RateRow | null>(null);
  const [price, setPrice] = useState('');
  const [reason, setReason] = useState('');

  // History modal state
  const [historyFor, setHistoryFor] = useState<RateRow | null>(null);
  const [history, setHistory] = useState<HistoryRow[]>([]);

  // CSV Import state
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [csvModalOpen, setCsvModalOpen] = useState(false);
  const [csvRows, setCsvRows] = useState<CsvValidationRow[]>([]);
  const [csvImporting, setCsvImporting] = useState(false);

  const entityArgs = (row: RateRow) => ({
    p_entity_type: row.entity_type,
    p_entity_id: row.entity_id,
    p_other_service_code: null,
  });

  // Fetch KPI coverage metrics dynamically
  const fetchKpis = useCallback(async () => {
    try {
      const [testsRes, configuredRes] = await Promise.all([
        supabase
          .from('tests')
          .select('id, price_paisa', { count: 'exact', head: false })
          .eq('is_active', true)
          .eq('lifecycle_status', 'Active'),
        supabase
          .from('catalogue_rate_versions')
          .select('test_id, price_paisa', { count: 'exact', head: false })
          .eq('status', 'Active')
          .gt('price_paisa', 0)
          .or('effective_to.is.null,effective_to.gt.now()'),
      ]);

      const totalActive = testsRes.count ?? (testsRes.data?.length || 0);
      const configuredRateCount = configuredRes.count ?? (configuredRes.data?.length || 0);
      const missingRateCount = Math.max(0, totalActive - configuredRateCount);

      setKpiTotal(totalActive);
      setKpiConfigured(configuredRateCount);
      setKpiMissing(missingRateCount);
    } catch {
      // Gracefully continue if network error
    }
  }, []);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');

    const isPriced = viewMode === 'missing' ? false : null;

    const result = await supabase.rpc('catalogue_search_rate_list', {
      p_query: query.trim() || null,
      p_category_id: category || null,
      p_lifecycle: lifecycle || null,
      p_priced: isPriced,
      p_entity_type: entityType || null,
      p_sort: sort,
      p_desc: descending,
      p_offset: page * pageSize,
      p_limit: pageSize,
    });

    setLoading(false);
    if (result.error) {
      setError(safeErrorMessage(result.error, 'Rate list could not be loaded.'));
      return;
    }

    const data = (result.data || []) as Array<{ item: RateRow; total_count: number }>;
    setRows(data.map((x) => x.item));
    setTotal(Number(data[0]?.total_count || 0));
  }, [query, category, lifecycle, viewMode, entityType, sort, descending, page, pageSize]);

  useEffect(() => {
    void supabase
      .from('test_categories')
      .select('id,name')
      .order('display_order')
      .then((result) => {
        if (!result.error) setCategories((result.data || []) as Category[]);
      });
    void fetchKpis();
  }, [fetchKpis]);

  useEffect(() => {
    const timer = setTimeout(() => void load(), 250);
    return () => clearTimeout(timer);
  }, [load]);

  const reset = () => setPage(0);

  // Single Rate Save
  const save = async () => {
    if (!selected) return;
    const paisa = parseRupeesToPaisa(price);
    if (paisa === null || paisa <= 0) {
      setError('Enter a positive NPR rate with no more than two decimal places.');
      return;
    }
    if (!reason.trim()) {
      setError('A rate-change reason is required.');
      return;
    }
    setError('');
    const result = await supabase.rpc('catalogue_set_current_rate', {
      p_entity_type: selected.entity_type,
      p_entity_id: selected.entity_id,
      p_price_paisa: paisa,
      p_expected_rate_id: selected.rate_id || null,
      p_expected_rate_version: selected.rate_row_version || null,
      p_reason: reason.trim(),
    });

    if (result.error) {
      setError(
        safeErrorMessage(
          result.error,
          'Rate was not changed. Refresh if another administrator updated it.'
        )
      );
      return;
    }

    setMessage(`Rate updated to ${formatPaisa(paisa)}. Existing bills and orders were not changed.`);
    setSelected(null);
    setPrice('');
    setReason('');
    await Promise.all([load(), fetchKpis()]);
  };

  // Staging inline rate update
  const handleStageRate = (row: RateRow, paisa: number | null) => {
    if (paisa === null || paisa <= 0) {
      setStagedRates((prev) => {
        const next = { ...prev };
        delete next[row.entity_id];
        return next;
      });
      return;
    }
    setStagedRates((prev) => ({
      ...prev,
      [row.entity_id]: {
        pricePaisa: paisa,
        reason: 'Master rate configuration in missing rates workspace',
        row,
      },
    }));
  };

  // Batch Save Staged Rates
  const handleSaveStagedRates = async () => {
    const entries = Object.values(stagedRates);
    if (entries.length === 0) return;

    setError('');
    setMessage('');
    setLoading(true);

    const changes = entries.map(({ pricePaisa, reason: changeReason, row }) => ({
      entity_type: row.entity_type,
      entity_id: row.entity_id,
      price_paisa: pricePaisa,
      expected_rate_id: row.rate_id || null,
      expected_rate_version: row.rate_row_version || null,
      reason: changeReason || 'Batch rate configuration',
    }));

    try {
      // Chunk into batches of up to 100
      let totalUpdated = 0;
      for (let i = 0; i < changes.length; i += 100) {
        const chunk = changes.slice(i, i + 100);
        const { data, error: bulkErr } = await supabase.rpc('catalogue_bulk_set_current_rates', {
          p_changes: chunk,
        });
        if (bulkErr) throw bulkErr;
        const resObj = data as { updated_count?: number };
        totalUpdated += resObj?.updated_count || chunk.length;
      }

      setMessage(`Successfully committed ${totalUpdated} configured rate(s). Historical bills remain intact.`);
      setStagedRates({});
      await Promise.all([load(), fetchKpis()]);
    } catch (err) {
      setError(safeErrorMessage(err, 'Failed to save batch rate updates.'));
    } finally {
      setLoading(false);
    }
  };

  const openHistory = async (row: RateRow) => {
    setHistoryFor(row);
    const result = await supabase.rpc('catalogue_rate_history', entityArgs(row));
    if (result.error) setError(safeErrorMessage(result.error));
    else setHistory(((result.data || []) as Array<{ item: HistoryRow }>).map((x) => x.item));
  };

  const removeRate = async (rate: HistoryRow) => {
    const result = await supabase.rpc('catalogue_delete_or_archive_rate', {
      p_rate_id: rate.id,
      p_expected_version: rate.row_version,
    });
    if (result.error) {
      setError(safeErrorMessage(result.error));
      return;
    }
    setMessage(
      result.data === 'Deleted'
        ? 'Unused draft rate deleted.'
        : 'Rate archived; historical billing remains unchanged.'
    );
    if (historyFor) await openHistory(historyFor);
    await Promise.all([load(), fetchKpis()]);
  };

  // CSV Import handling
  const handleCsvFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setError('');
    const text = await file.text();
    const lines = text.split(/\r?\n/).filter((l) => l.trim().length > 0);

    if (lines.length <= 1) {
      setError('CSV file is empty or missing data rows.');
      return;
    }

    // Header check
    const header = lines[0].toLowerCase().split(',').map((h) => h.trim());
    const codeIdx = header.indexOf('code');
    const nameIdx = header.indexOf('name');
    const rateIdx = header.indexOf('rate_npr');
    const effectiveIdx = header.indexOf('effective_from');

    if (codeIdx === -1 || rateIdx === -1) {
      setError('CSV must include "code" and "rate_npr" column headers (e.g. code,name,rate_npr,effective_from).');
      return;
    }

    // Fetch active tests map for validation
    const { data: allTests, error: testErr } = await supabase
      .from('tests')
      .select('id, code, name, price_configured')
      .eq('is_active', true)
      .eq('lifecycle_status', 'Active');

    if (testErr || !allTests) {
      setError('Could not verify catalogue tests for CSV validation.');
      return;
    }

    const testMap = new Map<string, { id: string; name: string; price_configured?: boolean }>();
    for (const t of allTests) {
      testMap.set(t.code.toUpperCase().trim(), t);
    }

    const seenCodes = new Set<string>();
    const parsedRows: CsvValidationRow[] = [];

    for (let i = 1; i < lines.length; i++) {
      const parts = lines[i].split(',').map((p) => p.trim());
      const rawCode = (parts[codeIdx] || '').toUpperCase();
      const rawName = nameIdx !== -1 ? parts[nameIdx] || '' : '';
      const rawRate = parts[rateIdx] || '';
      const rawEff = effectiveIdx !== -1 ? parts[effectiveIdx] || '' : getNepalTodayAd();

      if (!rawCode) continue;

      let isValid = true;
      let rowError: string | undefined;

      if (seenCodes.has(rawCode)) {
        isValid = false;
        rowError = 'Duplicate test code in CSV';
      }
      seenCodes.add(rawCode);

      const targetTest = testMap.get(rawCode);
      if (!targetTest) {
        isValid = false;
        rowError = `Unknown or inactive test code: ${rawCode}`;
      }

      const paisa = parseRupeesToPaisa(rawRate);
      if (paisa === null || paisa <= 0) {
        isValid = false;
        rowError = rowError || 'Invalid rate: must be positive amount with at most 2 decimal places';
      }

      parsedRows.push({
        rowNumber: i + 1,
        code: rawCode,
        name: rawName || targetTest?.name || '',
        rateNpr: rawRate,
        effectiveFrom: rawEff || getNepalTodayAd(),
        parsedPaisa: paisa,
        entityId: targetTest?.id || null,
        entityType: 'Test',
        currentRateId: null,
        currentRateRowVersion: null,
        isValid,
        error: rowError,
      });
    }

    setCsvRows(parsedRows);
    setCsvModalOpen(true);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const handleApplyCsv = async () => {
    const validRows = csvRows.filter((r) => r.isValid && r.entityId && r.parsedPaisa);
    if (validRows.length === 0) return;

    setCsvImporting(true);
    setError('');

    const changes = validRows.map((r) => ({
      entity_type: r.entityType,
      entity_id: r.entityId,
      price_paisa: r.parsedPaisa,
      expected_rate_id: null,
      expected_rate_version: null,
      reason: 'Bulk CSV rate import',
    }));

    try {
      let totalImported = 0;
      for (let i = 0; i < changes.length; i += 100) {
        const chunk = changes.slice(i, i + 100);
        const { data, error: bulkErr } = await supabase.rpc('catalogue_bulk_set_current_rates', {
          p_changes: chunk,
        });
        if (bulkErr) throw bulkErr;
        const resObj = data as { updated_count?: number };
        totalImported += resObj?.updated_count || chunk.length;
      }

      setMessage(`CSV Import complete: ${totalImported} rates imported successfully.`);
      setCsvModalOpen(false);
      setCsvRows([]);
      await Promise.all([load(), fetchKpis()]);
    } catch (err) {
      setError(safeErrorMessage(err, 'Failed to import CSV rates.'));
    } finally {
      setCsvImporting(false);
    }
  };

  const coveragePercent = useMemo(() => {
    if (kpiTotal === 0) return 0;
    return Math.round((kpiConfigured / kpiTotal) * 1000) / 10;
  }, [kpiTotal, kpiConfigured]);

  const stagedCount = Object.keys(stagedRates).length;

  if (!canManage) {
    return (
      <Card>
        <CardContent>
          <Alert severity="error">
            Access Denied. You do not have permission to view or manage laboratory price tariffs.
          </Alert>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardContent>
        {/* Header & KPI Dashboard */}
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 2, mb: 3 }}>
          <Box>
            <Typography variant="h6" fontWeight={800} display="flex" alignItems="center" gap={1}>
              <PriceCheckIcon color="primary" /> Price & Tariff Master
            </Typography>
            <Typography variant="body2" color="text.secondary">
              Canonical rate management with effective-dated versions and integer paisa precision.
            </Typography>
          </Box>
          <Stack direction="row" spacing={1.5}>
            <input
              type="file"
              accept=".csv"
              ref={fileInputRef}
              style={{ display: 'none' }}
              onChange={(e) => void handleCsvFileUpload(e)}
            />
            <Button
              variant="outlined"
              startIcon={<CloudUploadIcon />}
              onClick={() => fileInputRef.current?.click()}
            >
              Import Rates CSV
            </Button>
            {stagedCount > 0 && (
              <Button
                variant="contained"
                color="primary"
                startIcon={<SaveIcon />}
                onClick={() => void handleSaveStagedRates()}
              >
                Commit Staged Rates ({stagedCount})
              </Button>
            )}
          </Stack>
        </Box>

        {/* Dynamic Rate Coverage KPI Cards */}
        <Grid container spacing={2} sx={{ mb: 3 }}>
          <Grid item xs={12} sm={6} md={3}>
            <Paper variant="outlined" sx={{ p: 2, bgcolor: 'background.default' }}>
              <Typography variant="caption" color="text.secondary" fontWeight={600}>
                TOTAL ACTIVE BILLABLE
              </Typography>
              <Typography variant="h5" fontWeight={800} sx={{ mt: 0.5 }}>
                {kpiTotal.toLocaleString()}
              </Typography>
              <Typography variant="caption" color="text.secondary">
                Orderable catalogue items
              </Typography>
            </Paper>
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Paper variant="outlined" sx={{ p: 2, bgcolor: 'background.default' }}>
              <Typography variant="caption" color="success.main" fontWeight={600}>
                CONFIGURED RATES
              </Typography>
              <Typography variant="h5" fontWeight={800} color="success.main" sx={{ mt: 0.5 }}>
                {kpiConfigured.toLocaleString()}
              </Typography>
              <Typography variant="caption" color="text.secondary">
                Auto-populates in Billing
              </Typography>
            </Paper>
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Paper variant="outlined" sx={{ p: 2, bgcolor: 'background.default' }}>
              <Typography variant="caption" color="warning.main" fontWeight={600}>
                MISSING / UNPRICED
              </Typography>
              <Typography variant="h5" fontWeight={800} color="warning.main" sx={{ mt: 0.5 }}>
                {kpiMissing.toLocaleString()}
              </Typography>
              <Typography variant="caption" color="text.secondary">
                Requires price entry
              </Typography>
            </Paper>
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Paper variant="outlined" sx={{ p: 2, bgcolor: 'background.default' }}>
              <Typography variant="caption" color="primary.main" fontWeight={600}>
                RATE COVERAGE
              </Typography>
              <Typography variant="h5" fontWeight={800} color="primary.main" sx={{ mt: 0.5 }}>
                {coveragePercent}%
              </Typography>
              <LinearProgress
                variant="determinate"
                value={Math.min(100, coveragePercent)}
                sx={{ height: 6, borderRadius: 1, mt: 1 }}
              />
            </Paper>
          </Grid>
        </Grid>

        {error && (
          <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>
            {error}
          </Alert>
        )}
        {message && (
          <Alert severity="success" sx={{ mb: 2 }} onClose={() => setMessage('')}>
            {message}
          </Alert>
        )}

        {/* View Mode & Filter Controls */}
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 1.5, mb: 2 }}>
          <ToggleButtonGroup
            value={viewMode}
            exclusive
            onChange={(_, val) => {
              if (val) {
                setViewMode(val);
                reset();
              }
            }}
            size="small"
          >
            <ToggleButton value="all">All Items ({kpiTotal})</ToggleButton>
            <ToggleButton value="missing" sx={{ color: 'warning.main' }}>
              <WarningAmberIcon fontSize="small" sx={{ mr: 0.5 }} /> Missing Rates Only ({kpiMissing})
            </ToggleButton>
          </ToggleButtonGroup>
        </Box>

        <Box
          sx={{
            display: 'grid',
            gridTemplateColumns: { xs: '1fr', md: '2fr repeat(4, 1fr)' },
            gap: 1.5,
            mb: 2,
          }}
        >
          <TextField
            size="small"
            label="Search code or name"
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              reset();
            }}
          />
          <FormControl size="small">
            <InputLabel>Category</InputLabel>
            <Select
              label="Category"
              value={category}
              onChange={(e) => {
                setCategory(e.target.value);
                reset();
              }}
            >
              <MenuItem value="">All Categories</MenuItem>
              {categories.map((c) => (
                <MenuItem key={c.id} value={c.id}>
                  {c.name}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
          <FormControl size="small">
            <InputLabel>Status</InputLabel>
            <Select
              label="Status"
              value={lifecycle}
              onChange={(e) => {
                setLifecycle(e.target.value);
                reset();
              }}
            >
              <MenuItem value="">All Statuses</MenuItem>
              <MenuItem value="Active">Active</MenuItem>
              <MenuItem value="Draft">Draft / Inactive</MenuItem>
              <MenuItem value="Archived">Archived</MenuItem>
            </Select>
          </FormControl>
          <FormControl size="small">
            <InputLabel>Type</InputLabel>
            <Select
              label="Type"
              value={entityType}
              onChange={(e) => {
                setEntityType(e.target.value);
                reset();
              }}
            >
              <MenuItem value="">All Types</MenuItem>
              <MenuItem value="Test">Tests</MenuItem>
              <MenuItem value="Panel">Panels</MenuItem>
              <MenuItem value="Package">Packages</MenuItem>
            </Select>
          </FormControl>
          <FormControl size="small">
            <InputLabel>Sort</InputLabel>
            <Select
              label="Sort"
              value={`${sort}:${descending ? 'desc' : 'asc'}`}
              onChange={(e) => {
                const [s, d] = e.target.value.split(':');
                setSort(s);
                setDescending(d === 'desc');
                reset();
              }}
            >
              <MenuItem value="name:asc">Name A–Z</MenuItem>
              <MenuItem value="name:desc">Name Z–A</MenuItem>
              <MenuItem value="code:asc">Code A–Z</MenuItem>
              <MenuItem value="rate:asc">Rate low–high</MenuItem>
              <MenuItem value="rate:desc">Rate high–low</MenuItem>
              <MenuItem value="updated_at:desc">Recently updated</MenuItem>
            </Select>
          </FormControl>
        </Box>

        {/* Rates Table with Inline Editing in Missing Workspace */}
        <TableContainer>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Test Code</TableCell>
                <TableCell>Test Name</TableCell>
                <TableCell>Category</TableCell>
                <TableCell>Current Rate</TableCell>
                {viewMode === 'missing' && <TableCell sx={{ width: 180 }}>New Rate (NPR)</TableCell>}
                <TableCell>Status</TableCell>
                <TableCell>Last Updated</TableCell>
                <TableCell align="right">Actions</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {!loading && rows.length === 0 && (
                <TableRow>
                  <TableCell colSpan={viewMode === 'missing' ? 8 : 7} align="center" sx={{ py: 3 }}>
                    {viewMode === 'missing'
                      ? 'No missing rates found! All matching items have configured prices.'
                      : 'No matching catalogue items found.'}
                  </TableCell>
                </TableRow>
              )}
              {rows.map((row) => {
                const stagedPaisa = stagedRates[row.entity_id]?.pricePaisa;
                return (
                  <TableRow key={`${row.entity_type}-${row.entity_id}`} hover>
                    <TableCell>
                      <Typography variant="body2" fontWeight={700}>
                        {row.code}
                      </Typography>
                      <Typography variant="caption" color="text.secondary">
                        {row.entity_type}
                      </Typography>
                    </TableCell>
                    <TableCell>{row.name}</TableCell>
                    <TableCell>{row.category || 'Unassigned'}</TableCell>
                    <TableCell>
                      {row.rate_status === 'Active' && row.price_paisa != null ? (
                        <Typography variant="body2" fontWeight={600}>
                          {formatPaisa(row.price_paisa)}
                        </Typography>
                      ) : (
                        <Chip
                          size="small"
                          color="warning"
                          label="Unpriced"
                          variant="outlined"
                        />
                      )}
                    </TableCell>
                    {viewMode === 'missing' && (
                      <TableCell>
                        <MoneyInputField
                          size="small"
                          placeholder="e.g. 250.00"
                          valuePaisa={stagedPaisa ?? null}
                          onCommitPaisa={(paisa) => handleStageRate(row, paisa)}
                          allowZero={false}
                          sx={{ maxWidth: 160 }}
                        />
                      </TableCell>
                    )}
                    <TableCell>
                      <Chip
                        size="small"
                        label={row.entity_status}
                        color={row.entity_status === 'Active' ? 'success' : 'default'}
                      />
                      {row.rate_status && (
                        <Typography variant="caption" display="block" color="text.secondary">
                          Rate: {row.rate_status}
                        </Typography>
                      )}
                    </TableCell>
                    <TableCell>
                      {row.updated_at ? formatAdDate(row.updated_at) : '—'}
                    </TableCell>
                    <TableCell align="right">
                      <Stack direction="row" spacing={1} justifyContent="flex-end">
                        <Button size="small" onClick={() => void openHistory(row)}>
                          History
                        </Button>
                        <Button
                          size="small"
                          variant={row.rate_status === 'Active' ? 'outlined' : 'contained'}
                          color={row.rate_status === 'Active' ? 'primary' : 'warning'}
                          onClick={() => {
                            setSelected(row);
                            setPrice(
                              row.price_paisa == null
                                ? ''
                                : (row.price_paisa / 100).toFixed(2)
                            );
                            setReason('');
                          }}
                        >
                          {row.rate_status === 'Active' ? 'Edit Rate' : 'Set Price'}
                        </Button>
                      </Stack>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </TableContainer>

        <TablePagination
          component="div"
          count={total}
          page={page}
          rowsPerPage={pageSize}
          rowsPerPageOptions={[10, 25, 50, 100]}
          onPageChange={(_, next) => setPage(next)}
          onRowsPerPageChange={(e) => {
            setPageSize(Number(e.target.value));
            setPage(0);
          }}
        />
      </CardContent>

      {/* Single Rate Edit Modal */}
      <Dialog
        open={Boolean(selected)}
        onClose={() => setSelected(null)}
        maxWidth="xs"
        fullWidth
      >
        <DialogTitle>{selected?.name}</DialogTitle>
        <DialogContent dividers>
          <Alert severity="info" sx={{ mb: 2 }}>
            This rate applies to all new bills. Saved historical bills remain unchanged.
          </Alert>
          <TextField
            fullWidth
            label="Rate (NPR)"
            value={price}
            onChange={(e) => {
              if (isValidMoneyIntermediate(e.target.value)) setPrice(e.target.value);
            }}
            inputProps={{ inputMode: 'decimal' }}
            sx={{ mb: 2 }}
          />
          <TextField
            fullWidth
            required
            label="Reason for change"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            multiline
            minRows={2}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSelected(null)}>Cancel</Button>
          <Button variant="contained" onClick={() => void save()}>
            Commit Rate
          </Button>
        </DialogActions>
      </Dialog>

      {/* Rate History Modal */}
      <Dialog
        open={Boolean(historyFor)}
        onClose={() => setHistoryFor(null)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>Rate History · {historyFor?.name}</DialogTitle>
        <DialogContent dividers>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Version</TableCell>
                <TableCell>Rate</TableCell>
                <TableCell>Effective From</TableCell>
                <TableCell>Status</TableCell>
                <TableCell>Historical Bills</TableCell>
                <TableCell align="right">Action</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {history.map((rate) => (
                <TableRow key={rate.id}>
                  <TableCell>{rate.version_number}</TableCell>
                  <TableCell>
                    {rate.price_paisa == null
                      ? 'Not configured'
                      : formatPaisa(rate.price_paisa)}
                  </TableCell>
                  <TableCell>
                    {rate.effective_from ? formatAdDate(rate.effective_from) : '—'}
                  </TableCell>
                  <TableCell>{rate.status}</TableCell>
                  <TableCell>{rate.used_by_bill_count}</TableCell>
                  <TableCell align="right">
                    {canManage && rate.status !== 'Active' && (
                      <Button
                        size="small"
                        color="warning"
                        onClick={() => void removeRate(rate)}
                      >
                        {rate.status === 'Draft' && rate.used_by_bill_count === 0
                          ? 'Delete Draft'
                          : 'Archive'}
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setHistoryFor(null)}>Close</Button>
        </DialogActions>
      </Dialog>

      {/* CSV Import Dry-Run Modal */}
      <Dialog
        open={csvModalOpen}
        onClose={() => !csvImporting && setCsvModalOpen(false)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>CSV Rate Import · Dry-Run Validation</DialogTitle>
        <DialogContent dividers>
          <Box sx={{ mb: 2 }}>
            <Typography variant="body2" color="text.secondary">
              Review parsed rows before committing. Only valid rows with matching active tests and valid NPR rates will be imported.
            </Typography>
          </Box>

          <Stack direction="row" spacing={2} sx={{ mb: 2 }}>
            <Chip
              icon={<CheckCircleOutlineIcon />}
              color="success"
              label={`Valid Rows: ${csvRows.filter((r) => r.isValid).length}`}
            />
            <Chip
              icon={<ErrorOutlineIcon />}
              color="error"
              label={`Errors: ${csvRows.filter((r) => !r.isValid).length}`}
            />
            <Chip label={`Total CSV Rows: ${csvRows.length}`} />
          </Stack>

          <TableContainer sx={{ maxHeight: 350 }}>
            <Table size="small" stickyHeader>
              <TableHead>
                <TableRow>
                  <TableCell>Row</TableCell>
                  <TableCell>Code</TableCell>
                  <TableCell>Test Name</TableCell>
                  <TableCell>Rate (NPR)</TableCell>
                  <TableCell>Status</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {csvRows.map((row) => (
                  <TableRow
                    key={row.rowNumber}
                    sx={{
                      bgcolor: row.isValid ? 'inherit' : 'action.hover',
                    }}
                  >
                    <TableCell>{row.rowNumber}</TableCell>
                    <TableCell sx={{ fontWeight: 700 }}>{row.code}</TableCell>
                    <TableCell>{row.name}</TableCell>
                    <TableCell>
                      {row.parsedPaisa ? formatPaisa(row.parsedPaisa) : row.rateNpr}
                    </TableCell>
                    <TableCell>
                      {row.isValid ? (
                        <Chip size="small" color="success" label="Ready" />
                      ) : (
                        <Tooltip title={row.error || 'Invalid'}>
                          <Chip size="small" color="error" label={row.error} />
                        </Tooltip>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </DialogContent>
        <DialogActions>
          <Button disabled={csvImporting} onClick={() => setCsvModalOpen(false)}>
            Cancel
          </Button>
          <Button
            variant="contained"
            disabled={
              csvImporting || csvRows.filter((r) => r.isValid).length === 0
            }
            onClick={() => void handleApplyCsv()}
          >
            {csvImporting
              ? 'Importing...'
              : `Commit ${csvRows.filter((r) => r.isValid).length} Valid Rates`}
          </Button>
        </DialogActions>
      </Dialog>
    </Card>
  );
}
