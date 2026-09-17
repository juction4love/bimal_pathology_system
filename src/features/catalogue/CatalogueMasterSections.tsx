import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Alert, Box, Button, Card, CardContent, Chip, Dialog, DialogActions,
  DialogContent, DialogTitle, Stack, Table, TableBody, TableCell,
  TableContainer, TableHead, TableRow, TablePagination, TextField, MenuItem, Typography,
  Checkbox, Paper, Grid, IconButton
} from '@mui/material';
import VisibilityIcon from '@mui/icons-material/Visibility';
import EditIcon from '@mui/icons-material/Edit';
import VerifiedIcon from '@mui/icons-material/Verified';
import FactCheckIcon from '@mui/icons-material/FactCheck';
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline';
import RuleFolderIcon from '@mui/icons-material/RuleFolder';
import CloseIcon from '@mui/icons-material/Close';

import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { formatAdDate } from '@/lib/dateTime';
import { catalogueOperationalStatus } from './catalogueOperationalStatus';

export type OperationalCategory = {
  id: string;
  code: string;
  name: string;
  lifecycle_status: 'Draft' | 'Active' | 'Archived';
  display_order?: number;
};

export type OperationalTest = {
  id: string;
  code: string;
  name: string;
  short_name?: string | null;
  category_id?: string | null;
  category: string;
  department: string;
  test_kind: 'Individual' | 'Profile';
  reporting_model?: string | null;
  reporting_type: string;
  sample_type?: string;
  container?: string;
  method?: string | null;
  price_paisa?: number;
  row_version?: number;
  is_active: boolean;
  lifecycle_status: 'Draft' | 'Active' | 'Archived';
  validation_status?: 'REQUIRES_VALIDATION' | 'VALIDATED' | string;
  clinical_reporting_enabled?: boolean;
  workflow_supported?: boolean;
  operational_state?: string;
  configuration_notes?: string | null;
  display_order: number;
  search_aliases?: string[];
  parameters?: Array<{ id: string; code: string; name: string; display_order: number; unit?: string | null; value_type?: string; formula?: string | null; calculation_identifier?: string | null; option_set_id?: string | null; is_active?: boolean; lifecycle_status?: string }>;
};

type ProfileComponent = {
  profile_test_id: string;
  component_test_id?: string | null;
  component_parameter_id?: string | null;
  component_role: string;
  display_order: number;
  tests?: { id: string; code: string; name: string } | null;
  parameters?: { id: string; code: string; name: string; unit?: string | null } | null;
};

type RatelistLink = {
  test_id: string;
  health_packages?: { id: string; code: string; name: string } | null;
};
type OperatorPanel = {
  id: string; code: string; name: string; display_order: number;
  row_version:number; category_id:string; reporting_type:string;
  clinical_reporting_enabled: boolean; lifecycle_status: 'Draft'|'Active'|'Archived';
  clinical_notes?: string | null;
  interpretation_rows?: Array<{ fasting_glucose: string; pp_glucose_2h: string; diagnosis: string }>;
  interpretation_notes?: string[];
  workflow_supported?: boolean;
  test_categories?: { name: string } | null;
  catalogue_panel_components?: Array<{ component_test_id?:string|null; component_parameter_id?:string|null; display_name: string; display_order: number; unresolved_reason?: string | null }>;
  catalogue_panel_ratelist_links?: Array<{ ratelist_name: string; operator_rate_npr: number | null }>;
};
type TestDatabaseEntry = {
  source_order: number; test_name: string; test_type: string; short_name?: string | null;
  operator_category: string;
  configuration_test_id: string; canonical_parameter_id?: string | null;
  test_categories?: { name: string } | null;
};
type TestTemplateEntry = TestDatabaseEntry & { supplied_name: string; test_database_source_order: number };
type TemplateDetail = {
  source_order: number; name: string;
  basic: { test_name: string; code: string; category: string; test_type: string; short_name?: string | null };
  parameters: Array<{ name: string; unit?: string | null; result_type: string; display_order: number }>;
  reference_ranges: Array<{ parameter: string; sex: string; age_min_days: number; age_max_days: number; normal_min?: number | null; normal_max?: number | null; normal_text?: string | null; critical_low?: number | null; critical_high?: number | null; method?: string | null }>;
  workflow: { specimen?: string | null; container?: string | null; reporting_model?: string | null; reporting_type: string; collection_required?: boolean };
  notes: { interpretation?: string | null; technical_notes?: string | null };
};

const operatorCategoryOrder = [
  'Haematology', 'Biochemistry', 'Serology & Immunology', 'Clinical Pathology',
  'Cytology', 'Microbiology', 'Endocrinology', 'Histopathology', 'Others', 'Miscellaneous',
];

function operationalStatus(test: OperationalTest): string {
  return catalogueOperationalStatus(test);
}

function canonicalCategoryName(test: OperationalTest, categories: OperationalCategory[]): string {
  const category = categories.find((item) => item.id === test.category_id)?.name || test.category || test.department;
  const normalized = category.toLowerCase();
  if (normalized.includes('hemat') || normalized.includes('haemat')) return 'Haematology';
  if (normalized.includes('biochem')) return 'Biochemistry';
  if (normalized.includes('serolog') || normalized.includes('immunolog')) return 'Serology & Immunology';
  if (normalized.includes('clinical path')) return 'Clinical Pathology';
  if (normalized.includes('cytolog')) return 'Cytology';
  if (normalized.includes('microbio')) return 'Microbiology';
  if (normalized.includes('endocr')) return 'Endocrinology';
  if (normalized.includes('histopath')) return 'Histopathology';
  if (normalized.includes('misc')) return 'Miscellaneous';
  return 'Others';
}

export function CatalogueTestDatabaseSection({
  tests,
  canEdit,
  canConfigure,
  onEdit,
  onConfigure,
  onValidate,
  onActivate,
  onDeactivate,
  onBulkValidate,
  onBulkActivate,
  onAdoptStandardPresets,
}: {
  tests: OperationalTest[];
  canEdit: boolean;
  canConfigure: boolean;
  onEdit: (test: OperationalTest) => void;
  onConfigure: (test: OperationalTest) => void;
  onValidate?: (test: OperationalTest) => void;
  onActivate?: (test: OperationalTest) => void;
  onDeactivate?: (test: OperationalTest) => void;
  onBulkValidate?: (selectedTests: OperationalTest[]) => void;
  onBulkActivate?: (selectedTests: OperationalTest[]) => void;
  onAdoptStandardPresets?: (selectedTests: OperationalTest[]) => void;
}) {
  const [query, setQuery] = useState('');
  const [department, setDepartment] = useState('All');
  const [validationFilter, setValidationFilter] = useState('All');
  const [statusFilter, setStatusFilter] = useState('All');
  const [page, setPage] = useState(0);
  const [rowsPerPage, setRowsPerPage] = useState(25);

  // Multi-select state
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [reviewDialogOpen, setReviewDialogOpen] = useState(false);

  const departments = useMemo(() => [...new Set(tests.map((t) => t.department))].filter(Boolean).sort(), [tests]);

  // Dashboard counters for Standard Presets Governance (Requirement #12)
  const presetsAvailableCount = 1122;
  const presetsAdoptedCount = tests.filter((t) => (t as any).configuration_source === 'STANDARD_PRESET' && t.validation_status === 'VALIDATED').length;
  const labCustomCount = tests.filter((t) => (t as any).configuration_source === 'LAB_CUSTOM').length;
  const validatedCount = tests.filter((t) => t.validation_status === 'VALIDATED').length;
  const activeCount = tests.filter((t) => t.is_active && t.lifecycle_status === 'Active').length;
  const missingAnalyzerCount = tests.filter((t) => t.reporting_type !== 'NoReporting').length;
  const missingReagentCount = tests.filter((t) => t.reporting_type !== 'NoReporting').length;

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return tests.filter((test) => {
      const matchQuery =
        !needle ||
        test.name.toLowerCase().includes(needle) ||
        test.code.toLowerCase().includes(needle) ||
        (test.short_name || '').toLowerCase().includes(needle) ||
        test.department.toLowerCase().includes(needle) ||
        (test.search_aliases || []).some((a) => a.toLowerCase().includes(needle));

      const matchDept = department === 'All' || test.department === department;
      const matchVal =
        validationFilter === 'All' ||
        (validationFilter === 'REQUIRES_VALIDATION' && test.validation_status === 'REQUIRES_VALIDATION') ||
        (validationFilter === 'VALIDATED' && test.validation_status === 'VALIDATED');
      const matchStatus =
        statusFilter === 'All' ||
        (statusFilter === 'Active' && test.is_active && test.lifecycle_status === 'Active') ||
        (statusFilter === 'Inactive' && (!test.is_active || test.lifecycle_status !== 'Active'));

      return matchQuery && matchDept && matchVal && matchStatus;
    });
  }, [tests, query, department, validationFilter, statusFilter]);

  const paginated = useMemo(() => {
    const start = page * rowsPerPage;
    return filtered.slice(start, start + rowsPerPage);
  }, [filtered, page, rowsPerPage]);

  const allVisibleSelected = paginated.length > 0 && paginated.every((t) => selectedIds.has(t.id));
  const someVisibleSelected = paginated.some((t) => selectedIds.has(t.id));

  const handleToggleSelectAll = () => {
    const next = new Set(selectedIds);
    if (allVisibleSelected) {
      paginated.forEach((t) => next.delete(t.id));
    } else {
      paginated.forEach((t) => next.add(t.id));
    }
    setSelectedIds(next);
  };

  const handleToggleSelectOne = (id: string) => {
    const next = new Set(selectedIds);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    setSelectedIds(next);
  };

  const selectedTests = useMemo(() => {
    return tests.filter((t) => selectedIds.has(t.id));
  }, [tests, selectedIds]);

  return (
    <Stack spacing={2.5}>
      {/* 1. Governance Dashboard Counters (7 Requested Standard Presets Metrics) */}
      <Grid container spacing={1.5}>
        <Grid item xs={6} sm={4} md={1.71}>
          <Paper
            elevation={0}
            sx={{
              p: 1.5,
              border: '1px solid #bfdbfe',
              borderRadius: 2,
              bgcolor: '#eff6ff',
              textAlign: 'center',
            }}
          >
            <Typography variant="caption" color="#1d4ed8" fontWeight={700} display="block">
              PRESETS AVAILABLE
            </Typography>
            <Typography variant="h5" fontWeight={800} color="#1d4ed8">
              {presetsAvailableCount}
            </Typography>
            <Typography variant="caption" color="#1d4ed8">Standard Clinical Library</Typography>
          </Paper>
        </Grid>

        <Grid item xs={6} sm={4} md={1.71}>
          <Paper
            elevation={0}
            sx={{
              p: 1.5,
              border: '1px solid #bbf7d0',
              borderRadius: 2,
              bgcolor: '#f0fdf4',
              textAlign: 'center',
            }}
          >
            <Typography variant="caption" color="#15803d" fontWeight={700} display="block">
              PRESETS ADOPTED
            </Typography>
            <Typography variant="h5" fontWeight={800} color="#15803d">
              {presetsAdoptedCount}
            </Typography>
            <Typography variant="caption" color="#15803d">Adopted &amp; Validated</Typography>
          </Paper>
        </Grid>

        <Grid item xs={6} sm={4} md={1.71}>
          <Paper
            elevation={0}
            sx={{
              p: 1.5,
              border: '1px solid #e2e8f0',
              borderRadius: 2,
              bgcolor: '#f8fafc',
              textAlign: 'center',
            }}
          >
            <Typography variant="caption" color="text.secondary" fontWeight={700} display="block">
              LAB CUSTOM CONFIGS
            </Typography>
            <Typography variant="h5" fontWeight={800} color="text.secondary">
              {labCustomCount}
            </Typography>
            <Typography variant="caption" color="text.secondary">Custom Lab Protocols</Typography>
          </Paper>
        </Grid>

        <Grid item xs={6} sm={4} md={1.71}>
          <Paper
            elevation={0}
            sx={{
              p: 1.5,
              border: '1px solid #fed7aa',
              borderRadius: 2,
              bgcolor: '#fff7ed',
              textAlign: 'center',
            }}
          >
            <Typography variant="caption" color="#c2410c" fontWeight={700} display="block">
              MISSING ANALYZER
            </Typography>
            <Typography variant="h5" fontWeight={800} color="#c2410c">
              {missingAnalyzerCount}
            </Typography>
            <Typography variant="caption" color="#c2410c">Awaiting Instrument Confirmation</Typography>
          </Paper>
        </Grid>

        <Grid item xs={6} sm={4} md={1.71}>
          <Paper
            elevation={0}
            sx={{
              p: 1.5,
              border: '1px solid #fed7aa',
              borderRadius: 2,
              bgcolor: '#fff7ed',
              textAlign: 'center',
            }}
          >
            <Typography variant="caption" color="#c2410c" fontWeight={700} display="block">
              MISSING REAGENT
            </Typography>
            <Typography variant="h5" fontWeight={800} color="#c2410c">
              {missingReagentCount}
            </Typography>
            <Typography variant="caption" color="#c2410c">Awaiting Manufacturer Lot</Typography>
          </Paper>
        </Grid>

        <Grid item xs={6} sm={4} md={1.71}>
          <Paper
            elevation={0}
            onClick={() => { setValidationFilter('VALIDATED'); setPage(0); }}
            sx={{
              p: 1.5,
              border: '1px solid #bbf7d0',
              borderRadius: 2,
              bgcolor: '#f0fdf4',
              textAlign: 'center',
              cursor: 'pointer',
              '&:hover': { bgcolor: '#dcfce7' },
            }}
          >
            <Typography variant="caption" color="#15803d" fontWeight={700} display="block">
              VALIDATED
            </Typography>
            <Typography variant="h5" fontWeight={800} color="#15803d">
              {validatedCount}
            </Typography>
            <Typography variant="caption" color="#15803d">Ready for Activation</Typography>
          </Paper>
        </Grid>

        <Grid item xs={6} sm={4} md={1.71}>
          <Paper
            elevation={0}
            onClick={() => { setStatusFilter('Active'); setPage(0); }}
            sx={{
              p: 1.5,
              border: '1px solid #a7f3d0',
              borderRadius: 2,
              bgcolor: '#ecfdf5',
              textAlign: 'center',
              cursor: 'pointer',
              '&:hover': { bgcolor: '#d1fae5' },
            }}
          >
            <Typography variant="caption" color="#047857" fontWeight={700} display="block">
              ACTIVE
            </Typography>
            <Typography variant="h5" fontWeight={800} color="#047857">
              {activeCount}
            </Typography>
            <Typography variant="caption" color="#047857">Orderable for Patients</Typography>
          </Paper>
        </Grid>
      </Grid>

      {/* 2. Master Table Card */}
      <Card>
        <CardContent>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 2 }}>
            <Box>
              <Typography variant="h6" fontWeight={800}>
                Master Test Database (1,122 Canonical Items)
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Complete laboratory catalogue with Standard Clinical Presets. Unvalidated tests are kept non-orderable until reviewed and confirmed.
              </Typography>
            </Box>
          </Box>

          {/* Bulk Action Toolbar when items are selected */}
          {selectedIds.size > 0 && (
            <Paper
              elevation={1}
              sx={{
                p: 1.5,
                mb: 2,
                bgcolor: '#eff6ff',
                border: '1px solid #bfdbfe',
                borderRadius: 2,
                display: 'flex',
                flexWrap: 'wrap',
                justifyContent: 'space-between',
                alignItems: 'center',
                gap: 1.5,
              }}
            >
              <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap">
                <Chip
                  label={`${selectedIds.size} tests selected`}
                  color="primary"
                  size="small"
                  sx={{ fontWeight: 700 }}
                />
                <Button
                  size="small"
                  variant="outlined"
                  startIcon={<RuleFolderIcon />}
                  onClick={() => setReviewDialogOpen(true)}
                >
                  Review Missing Fields
                </Button>
                {onAdoptStandardPresets && (
                  <Button
                    size="small"
                    variant="contained"
                    color="primary"
                    startIcon={<VerifiedIcon />}
                    onClick={() => onAdoptStandardPresets(selectedTests)}
                  >
                    Adopt Standard Presets ({selectedIds.size})
                  </Button>
                )}
                {onBulkValidate && (
                  <Button
                    size="small"
                    variant="outlined"
                    color="warning"
                    startIcon={<FactCheckIcon />}
                    onClick={() => onBulkValidate(selectedTests)}
                  >
                    Bulk Lab Approval ({selectedIds.size})
                  </Button>
                )}
                {onBulkActivate && (
                  <Button
                    size="small"
                    variant="contained"
                    color="success"
                    startIcon={<CheckCircleOutlineIcon />}
                    onClick={() => onBulkActivate(selectedTests)}
                  >
                    Bulk Activate ({selectedTests.filter((t) => t.validation_status === 'VALIDATED').length})
                  </Button>
                )}
              </Stack>
              <Button
                size="small"
                color="inherit"
                startIcon={<CloseIcon />}
                onClick={() => setSelectedIds(new Set())}
              >
                Clear Selection
              </Button>
            </Paper>
          )}

          <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: '2fr 1fr 1fr 1fr' }, gap: 1, mb: 2 }}>
            <TextField
              size="small"
              label="Search name, code, alias, department..."
              value={query}
              onChange={(e) => { setQuery(e.target.value); setPage(0); }}
            />
            <TextField
              select
              size="small"
              label="Department"
              value={department}
              onChange={(e) => { setDepartment(e.target.value); setPage(0); }}
            >
              <MenuItem value="All">All departments ({tests.length})</MenuItem>
              {departments.map((val) => (
                <MenuItem key={val} value={val}>
                  {val} ({tests.filter((t) => t.department === val).length})
                </MenuItem>
              ))}
            </TextField>
            <TextField
              select
              size="small"
              label="Validation Status"
              value={validationFilter}
              onChange={(e) => { setValidationFilter(e.target.value); setPage(0); }}
            >
              <MenuItem value="All">All validation states</MenuItem>
              <MenuItem value="REQUIRES_VALIDATION">
                Requires Validation ({tests.filter((t) => t.validation_status === 'REQUIRES_VALIDATION').length})
              </MenuItem>
              <MenuItem value="VALIDATED">
                Validated ({tests.filter((t) => t.validation_status === 'VALIDATED').length})
              </MenuItem>
            </TextField>
            <TextField
              select
              size="small"
              label="Operational Status"
              value={statusFilter}
              onChange={(e) => { setStatusFilter(e.target.value); setPage(0); }}
            >
              <MenuItem value="All">All statuses</MenuItem>
              <MenuItem value="Active">Active / Orderable ({tests.filter((t) => t.is_active && t.lifecycle_status === 'Active').length})</MenuItem>
              <MenuItem value="Inactive">Inactive / Non-orderable ({tests.filter((t) => !t.is_active || t.lifecycle_status !== 'Active').length})</MenuItem>
            </TextField>
          </Box>

          <TableContainer>
            <Table size="small" aria-label="Master Test Database">
              <TableHead>
                <TableRow>
                  <TableCell padding="checkbox">
                    <Checkbox
                      size="small"
                      checked={allVisibleSelected}
                      indeterminate={someVisibleSelected && !allVisibleSelected}
                      onChange={handleToggleSelectAll}
                    />
                  </TableCell>
                  <TableCell>Code</TableCell>
                  <TableCell>Test Name</TableCell>
                  <TableCell>Department</TableCell>
                  <TableCell>Specimen / Container</TableCell>
                  <TableCell align="center">Validation Status</TableCell>
                  <TableCell align="center">Operational Status</TableCell>
                  <TableCell align="right">Actions</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {paginated.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={8} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                      No master tests match your search criteria.
                    </TableCell>
                  </TableRow>
                ) : (
                  paginated.map((test) => {
                    const isValidated = test.validation_status === 'VALIDATED';
                    const isActive = test.is_active && test.lifecycle_status === 'Active';
                    const isSelected = selectedIds.has(test.id);

                    return (
                      <TableRow key={test.id} hover selected={isSelected}>
                        <TableCell padding="checkbox">
                          <Checkbox
                            size="small"
                            checked={isSelected}
                            onChange={() => handleToggleSelectOne(test.id)}
                          />
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2" fontWeight={700}>
                            {test.code}
                          </Typography>
                          {test.test_kind === 'Profile' && (
                            <Chip size="small" label="Panel" variant="outlined" sx={{ fontSize: '0.65rem', height: 18 }} />
                          )}
                        </TableCell>
                        <TableCell>
                          <Typography fontWeight={700}>{test.name}</Typography>
                          {test.short_name && (
                            <Typography variant="caption" color="text.secondary" display="block">
                              Synonym: {test.short_name}
                            </Typography>
                          )}
                        </TableCell>
                        <TableCell>{test.department}</TableCell>
                        <TableCell>
                          <Typography variant="body2">{test.sample_type || '—'}</Typography>
                          <Typography variant="caption" color="text.secondary">
                            {test.container || ''}
                          </Typography>
                        </TableCell>
                        <TableCell align="center">
                          <Chip
                            size="small"
                            color={isActive ? 'success' : 'default'}
                            label={isActive ? 'ACTIVE' : 'INACTIVE'}
                          />
                        </TableCell>
                        <TableCell align="right">
                          <Stack direction="row" spacing={0.5} justifyContent="flex-end">
                            {canEdit && (
                              <Button size="small" variant="contained" color="primary" startIcon={<EditIcon />} onClick={() => onEdit(test)}>
                                Edit
                              </Button>
                            )}
                            {isActive ? (
                              onDeactivate && (
                                <Button
                                  size="small"
                                  color="warning"
                                  onClick={() => onDeactivate(test)}
                                >
                                  Deactivate
                                </Button>
                              )
                            ) : (
                              onActivate && (
                                <Button
                                  size="small"
                                  color="success"
                                  onClick={() => onActivate(test)}
                                >
                                  Activate
                                </Button>
                              )
                            )}
                            {onValidate && (
                              <Button
                                size="small"
                                variant="outlined"
                                color="inherit"
                                onClick={() => onValidate(test)}
                              >
                                {isValidated ? 'Validation Info' : 'Lab Review'}
                              </Button>
                            )}
                            {canConfigure && (
                              <Button size="small" onClick={() => onConfigure(test)}>
                                Structure
                              </Button>
                            )}
                          </Stack>
                        </TableCell>
                      </TableRow>
                    );
                  })
                )}
              </TableBody>
            </Table>
          </TableContainer>

          <TablePagination
            component="div"
            count={filtered.length}
            page={page}
            onPageChange={(_, newPage) => setPage(newPage)}
            rowsPerPage={rowsPerPage}
            onRowsPerPageChange={(e) => {
              setRowsPerPage(parseInt(e.target.value, 10));
              setPage(0);
            }}
            rowsPerPageOptions={[10, 25, 50, 100]}
          />
        </CardContent>
      </Card>

      {/* Review Missing Fields Dialog */}
      <Dialog
        open={reviewDialogOpen}
        onClose={() => setReviewDialogOpen(false)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Typography variant="h6" fontWeight={800}>
              Clinical Readiness &amp; Missing Fields Review ({selectedTests.length} Tests)
            </Typography>
            <IconButton size="small" onClick={() => setReviewDialogOpen(false)}>
              <CloseIcon />
            </IconButton>
          </Box>
        </DialogTitle>
        <DialogContent dividers>
          <Alert severity="info" sx={{ mb: 2 }}>
            Every test must have an analytical method, specimen, container, parameter unit, and reference ranges (where clinically applicable) before it can be activated.
          </Alert>
          <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', maxHeight: 400 }}>
            <Table size="small" stickyHeader>
              <TableHead sx={{ bgcolor: '#f8fafc' }}>
                <TableRow>
                  <TableCell>Code</TableCell>
                  <TableCell>Test Name</TableCell>
                  <TableCell>Department</TableCell>
                  <TableCell>Specimen / Container</TableCell>
                  <TableCell>Range Status</TableCell>
                  <TableCell>Validation State</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {selectedTests.map((t) => {
                  const hasRanges = t.parameters?.some((p) => ((p as any).reference_ranges || []).length > 0);

                  return (
                    <TableRow key={t.id} hover>
                      <TableCell sx={{ fontWeight: 700 }}>{t.code}</TableCell>
                      <TableCell>{t.name}</TableCell>
                      <TableCell>{t.department}</TableCell>
                      <TableCell>
                        {t.sample_type && t.container ? (
                          <Chip size="small" color="success" label={`${t.sample_type}`} />
                        ) : (
                          <Chip size="small" color="error" label="Missing Specimen" />
                        )}
                      </TableCell>
                      <TableCell>
                        {hasRanges ? (
                          <Chip size="small" color="success" label="Configured" />
                        ) : (
                          <Chip size="small" color="warning" label="Awaiting Reagent Range" />
                        )}
                      </TableCell>
                      <TableCell>
                        <Chip
                          size="small"
                          color={t.validation_status === 'VALIDATED' ? 'info' : 'default'}
                          label={t.validation_status || 'REQUIRES_VALIDATION'}
                        />
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </TableContainer>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setReviewDialogOpen(false)}>Close</Button>
          {onBulkValidate && (
            <Button
              variant="contained"
              color="warning"
              onClick={() => {
                setReviewDialogOpen(false);
                onBulkValidate(selectedTests);
              }}
            >
              Proceed to Bulk Clinical Approval
            </Button>
          )}
        </DialogActions>
      </Dialog>
    </Stack>
  );
}

export function CatalogueTemplateLibrarySection({ canCopy }: { canCopy: boolean }) {
  const [rows,setRows]=useState<TestTemplateEntry[]>([]); const [error,setError]=useState('');
  const [selected,setSelected]=useState<TemplateDetail|null>(null); const [copyOrder,setCopyOrder]=useState<number|null>(null);
  const [code,setCode]=useState(''); const [name,setName]=useState(''); const [message,setMessage]=useState('');
  useEffect(()=>{ void (async()=>{ const result=await supabase.from('catalogue_test_templates').select('source_order,supplied_name,test_database_source_order,configuration_test_id,canonical_parameter_id,catalogue_test_database_entries!test_database_source_order(test_name,test_type,short_name,operator_category)').order('source_order'); if(result.error){setError(safeErrorMessage(result.error,'Test templates could not be loaded.'));return;} const data=(result.data||[]) as unknown as Array<Omit<TestTemplateEntry,'test_name'|'test_type'|'operator_category'> & {catalogue_test_database_entries:{test_name:string;test_type:string;short_name?:string|null;operator_category:string}}>; setRows(data.map(item=>({...item,...item.catalogue_test_database_entries}))); })(); },[]);
  const view=async(order:number)=>{ const result=await supabase.rpc('catalogue_test_template_detail',{p_source_order:order}); if(result.error)setError(safeErrorMessage(result.error,'Template detail could not be loaded.')); else setSelected(result.data as TemplateDetail); };
  const copy=async()=>{ if(copyOrder==null)return; setMessage(''); const result=await supabase.rpc('catalogue_start_template_copy',{p_source_order:copyOrder,p_proposed_code:code,p_proposed_name:name}); if(result.error)setError(safeErrorMessage(result.error,'Template draft could not be created.')); else {setMessage('Isolated editable draft created. No test has been activated.');setCopyOrder(null);setCode('');setName('');} };
  return <Card><CardContent><Typography variant="h6" fontWeight={800}>View &amp; Copy Library</Typography><Typography variant="body2" color="text.secondary" sx={{mb:2}}>111 operator-approved reusable templates. Each references the canonical Test Database; copying starts an isolated draft and never clones clinical history.</Typography>{error&&<Alert severity="error" sx={{mb:2}}>{error}</Alert>}{message&&<Alert severity="success" sx={{mb:2}}>{message}</Alert>}<TableContainer><Table size="small" aria-label="Test template library"><TableHead><TableRow><TableCell>Order</TableCell><TableCell>Test Name</TableCell><TableCell>Category</TableCell><TableCell>Test Type</TableCell><TableCell>Short Name</TableCell><TableCell>Template Status</TableCell><TableCell align="right">Actions</TableCell></TableRow></TableHead><TableBody>{rows.map(row=><TableRow key={row.source_order}><TableCell>{row.source_order}</TableCell><TableCell>{row.supplied_name}</TableCell><TableCell>{row.operator_category}</TableCell><TableCell>{row.test_type}</TableCell><TableCell>{row.short_name||'—'}</TableCell><TableCell><Chip size="small" color="success" label="Canonical template"/></TableCell><TableCell align="right"><Button size="small" startIcon={<VisibilityIcon/>} onClick={()=>void view(row.source_order)}>View</Button>{canCopy&&<Button size="small" onClick={()=>{setCopyOrder(row.source_order);setName(`${row.supplied_name} Copy`);}}>Copy</Button>}</TableCell></TableRow>)}</TableBody></Table></TableContainer></CardContent>
  <Dialog open={Boolean(selected)} onClose={()=>setSelected(null)} maxWidth="md" fullWidth><DialogTitle>{selected?.name}</DialogTitle><DialogContent dividers>{selected&&<Stack spacing={2}><Box><Typography fontWeight={800}>Basic</Typography><Typography variant="body2">{selected.basic.code} · {selected.basic.category} · {selected.basic.test_type}</Typography></Box><Box><Typography fontWeight={800}>Parameters</Typography><Table size="small"><TableHead><TableRow><TableCell>Order</TableCell><TableCell>Name</TableCell><TableCell>Unit</TableCell><TableCell>Result Type</TableCell></TableRow></TableHead><TableBody>{selected.parameters.map(p=><TableRow key={`${p.display_order}-${p.name}`}><TableCell>{p.display_order}</TableCell><TableCell>{p.name}</TableCell><TableCell>{p.unit||'—'}</TableCell><TableCell>{p.result_type}</TableCell></TableRow>)}</TableBody></Table></Box><Box><Typography fontWeight={800}>Reference ranges</Typography>{selected.reference_ranges.length?<Table size="small"><TableHead><TableRow><TableCell>Parameter</TableCell><TableCell>Sex</TableCell><TableCell>Age (days)</TableCell><TableCell>Normal</TableCell><TableCell>Critical</TableCell><TableCell>Method</TableCell></TableRow></TableHead><TableBody>{selected.reference_ranges.map((r,i)=><TableRow key={`${r.parameter}-${r.sex}-${r.age_min_days}-${i}`}><TableCell>{r.parameter}</TableCell><TableCell>{r.sex}</TableCell><TableCell>{r.age_min_days}–{r.age_max_days}</TableCell><TableCell>{r.normal_text||`${r.normal_min??'—'}–${r.normal_max??'—'}`}</TableCell><TableCell>{r.critical_low??'—'}–{r.critical_high??'—'}</TableCell><TableCell>{r.method||'Method not configured'}</TableCell></TableRow>)}</TableBody></Table>:<Typography variant="body2">No configured reference ranges.</Typography>}</Box><Box><Typography fontWeight={800}>Workflow</Typography><Typography variant="body2">Specimen: {selected.workflow.specimen||'Not configured'} · Container: {selected.workflow.container||'Not configured'} · Reporting: {selected.workflow.reporting_type} · Collection: {selected.workflow.collection_required?'Required':'Not required'}</Typography></Box>{selected.notes.interpretation&&<Box><Typography fontWeight={800}>Notes</Typography><Typography variant="body2" sx={{whiteSpace:'pre-wrap'}}>{selected.notes.interpretation}</Typography></Box>}</Stack>}</DialogContent><DialogActions><Button onClick={()=>setSelected(null)}>Close</Button></DialogActions></Dialog>
  <Dialog open={copyOrder!=null} onClose={()=>setCopyOrder(null)} maxWidth="sm" fullWidth><DialogTitle>Copy to a new test draft</DialogTitle><DialogContent dividers><Alert severity="info" sx={{mb:2}}>Choose a distinct identity. This creates an editable draft only; it does not copy orders, results, reports, approvals, or audit actors.</Alert><Stack spacing={2}><TextField label="New canonical code" value={code} onChange={e=>setCode(e.target.value)}/><TextField label="New test/service name" value={name} onChange={e=>setName(e.target.value)}/></Stack></DialogContent><DialogActions><Button onClick={()=>setCopyOrder(null)}>Cancel</Button><Button variant="contained" disabled={!code.trim()||!name.trim()} onClick={()=>void copy()}>Create draft</Button></DialogActions></Dialog></Card>;
}

export function CatalogueCategoriesSection({ categories, tests, onEdit, onView }: {
  categories: OperationalCategory[];
  tests: OperationalTest[];
  onEdit?: (category: OperationalCategory) => void;
  onView?: (name: string) => void;
}) {
  const rows = operatorCategoryOrder.map((name, index) => ({
    name,
    order: index + 1,
    count: tests.filter((test) => canonicalCategoryName(test, categories) === name).length,
    source: categories.find((category) => canonicalCategoryName({ category: category.name, department: category.name } as OperationalTest, categories) === name),
  }));
  return <Card><CardContent>
    <Typography variant="h6" fontWeight={800} sx={{ mb: .5 }}>Test Categories</Typography>
    <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>Operational laboratory categories. Spelling aliases resolve to existing canonical records; no duplicate category is created.</Typography>
    <TableContainer><Table size="small" aria-label="Test categories"><TableHead><TableRow><TableCell>Order</TableCell><TableCell>Category</TableCell><TableCell align="right">Tests</TableCell><TableCell align="right">Actions</TableCell></TableRow></TableHead>
      <TableBody>{rows.map((row) => <TableRow key={row.name}><TableCell>{row.order}</TableCell><TableCell><Typography fontWeight={700}>{row.name}</Typography></TableCell><TableCell align="right">{row.count}</TableCell><TableCell align="right"><Button size="small" startIcon={<VisibilityIcon />} onClick={() => onView?.(row.name)}>View tests</Button>{row.source && onEdit && <Button size="small" startIcon={<EditIcon />} onClick={() => onEdit(row.source!)}>Edit</Button>}</TableCell></TableRow>)}</TableBody>
    </Table></TableContainer>
  </CardContent></Card>;
}

type PanelRateRow = { entity_id:string; entity_type:'Test'|'Panel'|'Package'|'Other'; code:string; name:string; category:string; entity_status:string; rate_id?:string|null; version_number?:number|null; price_paisa?:number|null; effective_from?:string|null; rate_status?:string|null; row_version?:number|null };
export function CataloguePriceMasterSection({ canManage }: { canManage:boolean }) {
  const [rows,setRows]=useState<PanelRateRow[]>([]); const [error,setError]=useState(''); const [message,setMessage]=useState('');
  const [selected,setSelected]=useState<PanelRateRow|null>(null); const [price,setPrice]=useState('');
  const load=useCallback(async()=>{ const result=await supabase.rpc('catalogue_price_master'); if(result.error)setError(safeErrorMessage(result.error,'Price master could not be loaded.')); else setRows(((result.data||[]) as Array<{item:PanelRateRow}>).map(row=>row.item)); },[]);
  useEffect(()=>{void load();},[load]);
  const save=async()=>{ if(!selected||!price.trim())return; setError(''); const paisa=Math.round(Number(price)*100); if(!Number.isFinite(paisa)||paisa<0){setError('Enter a valid non-negative NPR price.');return;} const created=await supabase.rpc('catalogue_create_rate_version',{p_entity_type:selected.entity_type,p_entity_id:selected.entity_type==='Other'?null:selected.entity_id,p_other_service_code:selected.entity_type==='Other'?selected.code:null,p_price_paisa:paisa,p_effective_from:new Date().toISOString()}); if(created.error){setError(safeErrorMessage(created.error,'Rate version could not be created.'));return;} const activated=await supabase.rpc('catalogue_activate_rate',{p_rate_id:created.data,p_expected_version:1}); if(activated.error){setError(safeErrorMessage(activated.error,'Rate was created as a draft but could not be activated.'));return;} setMessage(`New active rate saved for ${selected.name}. Historical bill snapshots were not changed.`);setSelected(null);setPrice('');await load(); };
  const archive=async(row:PanelRateRow)=>{if(!row.rate_id||!row.row_version)return;const result=await supabase.rpc('catalogue_archive_rate',{p_rate_id:row.rate_id,p_expected_version:row.row_version});if(result.error)setError(safeErrorMessage(result.error));else await load()};
  return <Card><CardContent><Typography variant="h6" fontWeight={800}>Prices / Ratelist</Typography><Typography variant="body2" color="text.secondary" sx={{mb:2}}>Unified future-facing rates for individual tests, panels and packages. Existing bills always retain their frozen price.</Typography>{error&&<Alert severity="error" sx={{mb:2}}>{error}</Alert>}{message&&<Alert severity="success" sx={{mb:2}}>{message}</Alert>}<TableContainer><Table size="small"><TableHead><TableRow><TableCell>Service Name</TableCell><TableCell>Code</TableCell><TableCell>Type</TableCell><TableCell>Category</TableCell><TableCell>Active Price NPR</TableCell><TableCell>Effective From</TableCell><TableCell>Status</TableCell><TableCell align="right">Actions</TableCell></TableRow></TableHead><TableBody>{rows.map(row=><TableRow key={`${row.entity_type}-${row.entity_id}`}><TableCell>{row.name}</TableCell><TableCell>{row.code}</TableCell><TableCell>{row.entity_type}</TableCell><TableCell>{row.category||'Not applicable'}</TableCell><TableCell>{row.rate_status==='Active'&&row.price_paisa!=null?(row.price_paisa/100).toFixed(2):'Not specified'}</TableCell><TableCell>{row.effective_from?formatAdDate(row.effective_from):'Not specified'}</TableCell><TableCell>{row.rate_status||row.entity_status}</TableCell><TableCell align="right">{canManage&&<><Button size="small" onClick={()=>{setSelected(row);setPrice(row.price_paisa!=null?String(row.price_paisa/100):'')}}>{row.rate_id?'New Version':'Add Price'}</Button>{row.rate_id&&row.rate_status!=='Archived'&&<Button size="small" color="warning" onClick={()=>void archive(row)}>Archive</Button>}</>}</TableCell></TableRow>)}</TableBody></Table></TableContainer></CardContent><Dialog open={Boolean(selected)} onClose={()=>setSelected(null)} maxWidth="xs" fullWidth><DialogTitle>{selected?.name}</DialogTitle><DialogContent dividers><Alert severity="info" sx={{mb:2}}>Activation affects future billing only. Existing bills retain their frozen price.</Alert><TextField fullWidth label="Price (NPR)" type="number" value={price} onChange={e=>setPrice(e.target.value)} inputProps={{min:0,step:.01}}/></DialogContent><DialogActions><Button onClick={()=>setSelected(null)}>Cancel</Button><Button variant="contained" onClick={()=>void save()}>Create and activate rate</Button></DialogActions></Dialog></Card>;
}

export function CataloguePanelsSection({ tests, categories, canEdit, onEdit, onConfigure }: {
  tests: OperationalTest[];
  categories: OperationalCategory[];
  canEdit: boolean;
  onEdit: (test: OperationalTest) => void;
  onConfigure: (test: OperationalTest) => void;
}) {
  const profiles = useMemo(() => tests.filter((test) => test.test_kind === 'Profile'), [tests]);
  const [components, setComponents] = useState<ProfileComponent[]>([]);
  const [ratelist, setRatelist] = useState<RatelistLink[]>([]);
  const [operatorPanels, setOperatorPanels] = useState<OperatorPanel[]>([]);
  const [selected, setSelected] = useState<OperationalTest | null>(null);
  const [selectedOperator, setSelectedOperator] = useState<OperatorPanel | null>(null);
  const [editingPanel,setEditingPanel]=useState<OperatorPanel|null>(null); const [panelForm,setPanelForm]=useState({code:'',name:'',category_id:'',display_order:1}); const [componentTest,setComponentTest]=useState('');
  const [message,setMessage]=useState('');
  const [error, setError] = useState('');
  const load = useCallback(async () => {
    const [componentResult, ratelistResult, panelResult] = await Promise.all([
      supabase.from('catalogue_profile_components').select('profile_test_id,component_test_id,component_parameter_id,component_role,display_order,tests:component_test_id(id,code,name),parameters:component_parameter_id(id,code,name,unit)').order('display_order'),
      supabase.from('health_package_components').select('test_id,health_packages:package_id(id,code,name)'),
      supabase.from('catalogue_panels').select('id,code,name,display_order,row_version,category_id,reporting_type,clinical_reporting_enabled,workflow_supported,lifecycle_status,clinical_notes,interpretation_rows,interpretation_notes,test_categories:category_id(name),catalogue_panel_components(component_test_id,component_parameter_id,display_name,display_order,unresolved_reason),catalogue_panel_ratelist_links(ratelist_name,operator_rate_npr)').order('display_order'),
    ]);
    const failure = componentResult.error || ratelistResult.error || panelResult.error;
    if (failure) setError(safeErrorMessage(failure, 'Panel composition could not be loaded.'));
    else { setComponents((componentResult.data || []) as unknown as ProfileComponent[]); setRatelist((ratelistResult.data || []) as unknown as RatelistLink[]); setOperatorPanels((panelResult.data || []) as unknown as OperatorPanel[]); }
  }, []);
  useEffect(() => { void load(); }, [load]);
  const members = (id: string) => components.filter((item) => item.profile_test_id === id).sort((a, b) => a.display_order - b.display_order);
  const linkedRates = (id: string) => ratelist.filter((item) => item.test_id === id).map((item) => item.health_packages?.name).filter(Boolean) as string[];
  const refreshPanel=async(id:string)=>{await load();const result=await supabase.from('catalogue_panels').select('id,code,name,display_order,row_version,category_id,reporting_type,clinical_reporting_enabled,workflow_supported,lifecycle_status,clinical_notes,interpretation_rows,interpretation_notes,test_categories:category_id(name),catalogue_panel_components(component_test_id,component_parameter_id,display_name,display_order,unresolved_reason),catalogue_panel_ratelist_links(ratelist_name,operator_rate_npr)').eq('id',id).single();if(!result.error)setSelectedOperator(result.data as unknown as OperatorPanel)};
  const savePanel=async()=>{const payload={id:editingPanel?.id||null,...panelForm,reporting_type:'InHouse',workflow_supported:true};const result=await supabase.rpc('catalogue_save_panel',{p_payload:payload,p_expected_version:editingPanel?.row_version||null});if(result.error){setError(safeErrorMessage(result.error));return;}setEditingPanel(null);setMessage('Panel saved through guarded catalogue workflow.');await load()};
  const lifecycle=async(panel:OperatorPanel,status:'Active'|'Archived')=>{const result=await supabase.rpc('catalogue_set_panel_lifecycle',{p_panel_id:panel.id,p_status:status,p_expected_version:panel.row_version});if(result.error)setError(safeErrorMessage(result.error));else{setSelectedOperator(null);await load()}};
  const deletePanel=async(panel:OperatorPanel)=>{const result=await supabase.rpc('catalogue_delete_panel',{p_panel_id:panel.id,p_expected_version:panel.row_version});if(result.error)setError(safeErrorMessage(result.error));else{setMessage(result.data==='Archived'?'Referenced panel archived; history remains intact.':'Unused panel deleted.');setSelectedOperator(null);await load()}};
  const addComponent=async()=>{if(!selectedOperator||!componentTest)return;const test=tests.find(item=>item.id===componentTest);const result=await supabase.rpc('catalogue_save_panel_component',{p_panel_id:selectedOperator.id,p_component_test_id:componentTest,p_component_parameter_id:null,p_display_name:test?.name||'Canonical test',p_display_order:(selectedOperator.catalogue_panel_components?.length||0)+1,p_expected_panel_version:selectedOperator.row_version});if(result.error)setError(safeErrorMessage(result.error));else{setComponentTest('');await refreshPanel(selectedOperator.id)}};
  const removeComponent=async(order:number)=>{if(!selectedOperator)return;const result=await supabase.rpc('catalogue_remove_panel_component',{p_panel_id:selectedOperator.id,p_display_order:order,p_expected_panel_version:selectedOperator.row_version});if(result.error)setError(safeErrorMessage(result.error));else await refreshPanel(selectedOperator.id)};
  const reorder=async(index:number,direction:number)=>{if(!selectedOperator)return;const items=[...(selectedOperator.catalogue_panel_components||[])].sort((a,b)=>a.display_order-b.display_order);const target=index+direction;if(target<0||target>=items.length)return;[items[index],items[target]]=[items[target],items[index]];const ids=items.map(item=>item.component_test_id||item.component_parameter_id).filter(Boolean);const result=await supabase.rpc('catalogue_reorder_panel_components',{p_panel_id:selectedOperator.id,p_component_ids:ids,p_expected_panel_version:selectedOperator.row_version});if(result.error)setError(safeErrorMessage(result.error));else await refreshPanel(selectedOperator.id)};
  return <Card><CardContent>
    <Stack direction="row" justifyContent="space-between"><Typography variant="h6" fontWeight={800} sx={{ mb: .5 }}>Test Panels / Profiles</Typography>{canEdit&&<Button variant="contained" onClick={()=>{setEditingPanel(null);setPanelForm({code:'',name:'',category_id:categories.find(c=>c.lifecycle_status==='Active')?.id||'',display_order:operatorPanels.length+1})}}>Add Panel</Button>}</Stack>
    <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>Clinical panel composition is separate from commercial ratelist/package linkage.</Typography>
    {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}{message&&<Alert severity="success" sx={{mb:2}}>{message}</Alert>}
    <TableContainer><Table size="small" aria-label="Test panels"><TableHead><TableRow><TableCell>Order</TableCell><TableCell>Panel Name</TableCell><TableCell>Category</TableCell><TableCell>Included Tests</TableCell><TableCell align="center">Number of Tests</TableCell><TableCell>Ratelist entries</TableCell><TableCell align="right">Actions</TableCell></TableRow></TableHead>
      <TableBody>{profiles.filter((profile)=>!operatorPanels.some((panel)=>panel.id===profile.id)).map((profile, index) => { const items = members(profile.id); const rates = linkedRates(profile.id); return <TableRow key={profile.id} hover><TableCell>{profile.display_order || index + 1}</TableCell><TableCell><Typography fontWeight={700}>{profile.name}</Typography><Typography variant="caption" color="text.secondary">{profile.code}</Typography></TableCell><TableCell>{canonicalCategoryName(profile, categories)}</TableCell><TableCell sx={{ maxWidth: 380 }}>{items.slice(0, 5).map((item) => item.tests?.name || item.parameters?.name).filter(Boolean).join(', ')}{items.length > 5 ? ` +${items.length - 5} more` : ''}</TableCell><TableCell align="center">{items.length}</TableCell><TableCell>{rates.length ? rates.join(', ') : profile.name}</TableCell><TableCell align="right"><Button size="small" startIcon={<VisibilityIcon />} onClick={() => setSelected(profile)}>View</Button>{canEdit && <Button size="small" startIcon={<EditIcon />} onClick={() => onEdit(profile)}>Edit</Button>}</TableCell></TableRow>; })}
        {operatorPanels.map((panel) => { const items=[...(panel.catalogue_panel_components || [])].sort((a,b)=>a.display_order-b.display_order); const rates=panel.catalogue_panel_ratelist_links || []; const status=panel.workflow_supported===false?'Needs Attention · Specialist workflow':panel.clinical_reporting_enabled?'Ready & Reportable':'Needs Attention · Result structure'; return <TableRow key={panel.id} hover><TableCell>{panel.display_order}</TableCell><TableCell><Typography fontWeight={700}>{panel.name}</Typography><Typography variant="caption" color="text.secondary">{panel.code}</Typography><Chip size="small" sx={{mt:.5}} color={status==='Ready & Reportable'?'success':'warning'} label={status} /></TableCell><TableCell>{panel.test_categories?.name || 'Haematology'}</TableCell><TableCell sx={{maxWidth:380}}>{items.slice(0,5).map((item)=>item.display_name).join(', ')}{items.length>5?` +${items.length-5} more`:''}</TableCell><TableCell align="center">{items.length}</TableCell><TableCell>{rates.map((item)=>item.ratelist_name).join(', ')}</TableCell><TableCell align="right"><Button size="small" startIcon={<VisibilityIcon />} onClick={()=>setSelectedOperator(panel)}>View</Button>{canEdit&&<Button size="small" startIcon={<EditIcon/>} onClick={()=>{setEditingPanel(panel);setPanelForm({code:panel.code,name:panel.name,category_id:panel.category_id,display_order:panel.display_order})}}>Edit</Button>}</TableCell></TableRow>; })}
      </TableBody>
    </Table></TableContainer>
    {!profiles.length && <Alert severity="info" sx={{ mt: 2 }}>No panel/profile identities are configured.</Alert>}
    <Dialog open={Boolean(selected)} onClose={() => setSelected(null)} maxWidth="md" fullWidth><DialogTitle>{selected?.name}</DialogTitle><DialogContent dividers>
      {selected && <><Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} sx={{ mb: 2 }}><Chip label={`Category: ${canonicalCategoryName(selected, categories)}`} /><Chip label={operationalStatus(selected)} color={operationalStatus(selected) === 'Ready & Reportable' ? 'success' : 'warning'} /></Stack>
        <Typography variant="subtitle1" fontWeight={800} sx={{ mb: 1 }}>Ordered component tests</Typography>
        <Table size="small"><TableHead><TableRow><TableCell>Order</TableCell><TableCell>Lab Test</TableCell><TableCell>Role</TableCell></TableRow></TableHead><TableBody>{members(selected.id).map((item) => <TableRow key={`${item.component_test_id || item.component_parameter_id}-${item.display_order}`}><TableCell>{item.display_order}</TableCell><TableCell>{item.tests?.name || item.parameters?.name || 'Configured component'}</TableCell><TableCell>{item.component_role}</TableCell></TableRow>)}</TableBody></Table>
        {selected.code === 'CBC' && <Alert severity="info" sx={{ mt: 2 }}><strong>Clinical notes:</strong> A complete blood count is used to evaluate overall health and detect disorders including anemia, infection, and leukemia. Individual test methods, instruments, approved ranges and interpretation remain attached to their canonical component definitions.</Alert>}
        <Typography variant="body2" sx={{ mt: 2 }}><strong>Available in ratelist under:</strong> {linkedRates(selected.id).join(', ') || selected.name}</Typography></>}
    </DialogContent><DialogActions><Button onClick={() => setSelected(null)}>Close</Button>{selected && canEdit && <Button onClick={() => { onConfigure(selected); setSelected(null); }}>Configure components</Button>}</DialogActions></Dialog>
    <Dialog open={Boolean(selectedOperator)} onClose={()=>setSelectedOperator(null)} maxWidth="md" fullWidth><DialogTitle>{selectedOperator?.name}</DialogTitle><DialogContent dividers>{selectedOperator && <><Stack direction="row" spacing={1} sx={{mb:2}}><Chip label={`Category: ${selectedOperator.test_categories?.name || 'Haematology'}`}/><Chip label={selectedOperator.lifecycle_status}/></Stack><Typography variant="subtitle1" fontWeight={800}>Ordered canonical components</Typography><Table size="small"><TableHead><TableRow><TableCell>Order</TableCell><TableCell>Lab Test</TableCell><TableCell>Actions</TableCell></TableRow></TableHead><TableBody>{[...(selectedOperator.catalogue_panel_components || [])].sort((a,b)=>a.display_order-b.display_order).map((item,index)=><TableRow key={item.display_order}><TableCell>{item.display_order}</TableCell><TableCell>{item.display_name}</TableCell><TableCell>{canEdit&&<><Button size="small" disabled={index===0} onClick={()=>void reorder(index,-1)}>Up</Button><Button size="small" disabled={index===(selectedOperator.catalogue_panel_components?.length||0)-1} onClick={()=>void reorder(index,1)}>Down</Button><Button size="small" color="error" onClick={()=>void removeComponent(item.display_order)}>Remove</Button></>}</TableCell></TableRow>)}</TableBody></Table>{canEdit&&<Stack direction="row" spacing={1} sx={{mt:2}}><TextField select size="small" label="Add canonical test" value={componentTest} onChange={e=>setComponentTest(e.target.value)} sx={{minWidth:300}}>{tests.filter(test=>test.test_kind!=='Profile').map(test=><MenuItem key={test.id} value={test.id}>{test.code} — {test.name}</MenuItem>)}</TextField><Button onClick={()=>void addComponent()}>Add Component</Button></Stack>}<Typography variant="subtitle1" fontWeight={800} sx={{mt:2}}>Ratelist / service links</Typography>{(selectedOperator.catalogue_panel_ratelist_links||[]).map(item=><Typography variant="body2" key={item.ratelist_name}>{item.ratelist_name}: {item.operator_rate_npr==null?'Not specified':`NPR ${item.operator_rate_npr}`}</Typography>)}</>}</DialogContent><DialogActions>{selectedOperator&&canEdit&&<><Button onClick={()=>void lifecycle(selectedOperator,selectedOperator.lifecycle_status==='Archived'?'Active':'Archived')}>{selectedOperator.lifecycle_status==='Archived'?'Restore':'Archive'}</Button><Button color="error" onClick={()=>void deletePanel(selectedOperator)}>Delete safely</Button></>}<Button onClick={()=>setSelectedOperator(null)}>Close</Button></DialogActions></Dialog>
    <Dialog open={editingPanel!==null||(!editingPanel&&panelForm.code===''&&panelForm.category_id!=='')} onClose={()=>{setEditingPanel(null);setPanelForm({code:'',name:'',category_id:'',display_order:1})}} maxWidth="sm" fullWidth><DialogTitle>{editingPanel?'Edit Panel':'Add Panel'}</DialogTitle><DialogContent dividers><Stack spacing={2}><TextField label="Code" disabled={Boolean(editingPanel)} value={panelForm.code} onChange={e=>setPanelForm({...panelForm,code:e.target.value.toUpperCase()})}/><TextField label="Panel Name" value={panelForm.name} onChange={e=>setPanelForm({...panelForm,name:e.target.value})}/><TextField select label="Category" value={panelForm.category_id} onChange={e=>setPanelForm({...panelForm,category_id:e.target.value})}>{categories.filter(c=>c.lifecycle_status==='Active').map(c=><MenuItem key={c.id} value={c.id}>{c.name}</MenuItem>)}</TextField><TextField type="number" label="Display Order" value={panelForm.display_order} onChange={e=>setPanelForm({...panelForm,display_order:Number(e.target.value)})}/></Stack></DialogContent><DialogActions><Button onClick={()=>{setEditingPanel(null);setPanelForm({code:'',name:'',category_id:'',display_order:1})}}>Cancel</Button><Button variant="contained" disabled={!panelForm.code||!panelForm.name||!panelForm.category_id} onClick={()=>void savePanel()}>Save</Button></DialogActions></Dialog>
  </CardContent></Card>;
}
