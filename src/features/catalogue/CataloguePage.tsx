/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Master Test Catalogue Management (Tests, Parameters, Reference Ranges)
 * Full Supabase PostgreSQL CRUD with Row Level Security Enforcement (Phase 1)
 */

import React, { useState, useEffect, useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';
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
  Chip,
  IconButton,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Grid,
  MenuItem,
  FormControlLabel,
  Switch,
  Alert,
  CircularProgress,
  Divider,
  Tooltip,
  Tabs,
  Tab,
  Stack,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import AddIcon from '@mui/icons-material/Add';
import EditIcon from '@mui/icons-material/Edit';
import TuneIcon from '@mui/icons-material/Tune';
import RefreshIcon from '@mui/icons-material/Refresh';
import FileUploadIcon from '@mui/icons-material/FileUpload';
import RuleIcon from '@mui/icons-material/Rule';
import ArchiveIcon from '@mui/icons-material/Archive';
import RestoreIcon from '@mui/icons-material/Restore';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import FactCheckIcon from '@mui/icons-material/FactCheck';

import { PageHeader } from '@/components/common/PageHeader';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { paisaToRupees } from '@/lib/currency';
import { formatAdDate, getNepalTodayAd } from '@/lib/dateTime';
import { BulkReferenceRangeEditor } from './BulkReferenceRangeEditor';
import { ReferenceRangeCsvModal } from './ReferenceRangeCsvModal';
import { checkRangeOverlap, validateReferenceRange } from '@/lib/clinicalReferenceRange';
import { handleEnterKeyNavigation } from '@/lib/keyboardNav';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { CatalogueCategoriesSection, CataloguePanelsSection, CatalogueTemplateLibrarySection, CatalogueTestDatabaseSection } from './CatalogueMasterSections';
import { CataloguePriceMasterSection } from './CataloguePriceMasterSection';
import { PtInrReagentConfigSection } from './PtInrReagentConfigSection';
import { catalogueOperationalStatus, catalogueOperationalStatusColor } from './catalogueOperationalStatus';
import { EasyTestEditorDialog } from './EasyTestEditorDialog';

type LifecycleStatus = 'Draft' | 'Active' | 'Archived';
interface DbCategory { id: string; code: string; name: string; lifecycle_status: LifecycleStatus; }

interface DbTest {
  id: string;
  code: string;
  name: string;
  short_name?: string | null;
  department: string;
  category: string;
  reporting_type: string;
  outsource_lab_name?: string | null;
  price_paisa: number;
  sample_type: string;
  container: string;
  method?: string | null;
  tat_hours?: number | null;
  interpretation_template?: string | null;
  is_active: boolean;
  display_order: number;
  lifecycle_status: LifecycleStatus;
  row_version: number;
  test_kind: 'Individual' | 'Profile';
  category_id?: string | null;
  description?: string | null;
  sample_volume?: string | null;
  configuration_notes?: string | null;
  price_configured?: boolean;
  allow_zero_price_billing?: boolean;
  pricing_policy?: 'Fixed' | 'Negotiable' | 'PricePending' | 'Manual';
  search_aliases?: string[];
  clinical_configuration_status?: 'Configured' | 'Requires Clinical Validation' | 'Ready for Activation' | 'Workflow Not Supported';
  workflow_supported?: boolean;
  reporting_model?: 'NumericSingle' | 'NumericMultiParameter' | 'Qualitative' | 'MixedTyped' | 'StructuredNested' | 'NarrativeDocument' | 'Calculated' | 'Profile' | 'MicrobiologyWorkflow' | 'CytologyWorkflow' | 'MolecularWorkflow';
  billing_enabled?: boolean;
  clinical_reporting_enabled?: boolean;
  collection_required?: boolean;
  operational_state?: string;
  validation_status?: 'REQUIRES_VALIDATION' | 'VALIDATED' | string;
  parameters?: DbParameter[];
}

interface DbParameter {
  id: string;
  test_id: string;
  code: string;
  name: string;
  value_type: string;
  unit?: string | null;
  formula?: string | null;
  is_mandatory: boolean;
  is_active: boolean;
  display_order: number;
  lifecycle_status: LifecycleStatus;
  row_version: number;
  decimal_precision?: number | null;
  calculation_identifier?: string | null;
  option_set_id?: string | null;
  reference_ranges?: DbRefRange[];
}

interface DbOptionSet { id: string; code: string; name: string; lifecycle_status: LifecycleStatus; }

interface DbRefRange {
  id: string;
  parameter_id: string;
  gender: string;
  age_min_days: number;
  age_max_days: number;
  normal_min?: number | null;
  normal_max?: number | null;
  critical_low?: number | null;
  critical_high?: number | null;
  normal_text?: string | null;
  reference_text?: string | null;
  method?: string | null;
  unit?: string | null;
  is_active?: boolean;
  is_approved?: boolean;
  lifecycle_status?: LifecycleStatus;
  row_version?: number;
  validation_state?: 'Unclassified' | 'LegacyDefaultRequiresValidation' | 'ClinicallyValidated';
  validation_source?: string | null;
}

export const CataloguePage: React.FC = () => {
  const { can } = usePermissions();
  const canManage = can(PERMISSION_KEYS.CAN_MANAGE_CATALOGUE) || can(PERMISSION_KEYS.CAN_CONFIGURE_CATALOGUE_TECHNICAL);
  const [searchTerm, setSearchTerm] = useState('');
  const [lifecycleFilter, setLifecycleFilter] = useState<'All' | LifecycleStatus>('All');
  const [categoryFilter, setCategoryFilter] = useState('All');
  const [departmentFilter, setDepartmentFilter] = useState('All');
  const [modelFilter, setModelFilter] = useState('All');
  const [reportingFilter, setReportingFilter] = useState('All');
  const [incompleteOnly, setIncompleteOnly] = useState(false);
  const [categories, setCategories] = useState<DbCategory[]>([]);
  const [tests, setTests] = useState<DbTest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [authError, setAuthError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [confirmAction, setConfirmAction] = useState<{ message: string; guidance: string; run: () => Promise<void> } | null>(null);
  const [actionBusy, setActionBusy] = useState(false);
  const [searchParams, setSearchParams] = useSearchParams();
  const initialTab = (searchParams.get('tab') as any) || 'tests';
  const [catalogueSection, setCatalogueSectionState] = useState<'tests' | 'categories' | 'panels' | 'structures' | 'ranges' | 'prices' | 'pt_inr_reagents' | 'templates' | 'history' | 'legacy-tests'>(initialTab);

  useEffect(() => {
    const tab = searchParams.get('tab');
    if (tab && ['tests', 'categories', 'panels', 'structures', 'ranges', 'prices', 'pt_inr_reagents', 'templates', 'history', 'legacy-tests'].includes(tab)) {
      setCatalogueSectionState(tab as any);
    }
  }, [searchParams]);

  const setCatalogueSection = (section: any) => {
    setCatalogueSectionState(section);
    setSearchParams(section === 'tests' ? {} : { tab: section });
  };

  // Bulk Editor & CSV Modal States
  const [bulkEditorOpen, setBulkEditorOpen] = useState(false);
  const [selectedTestForBulk, setSelectedTestForBulk] = useState<DbTest | null>(null);
  const [csvModalOpen, setCsvModalOpen] = useState(false);

  // Test Dialog State
  const [testDialogOpen, setTestDialogOpen] = useState(false);
  const [editingTest, setEditingTest] = useState<DbTest | null>(null);

  // Parameters Sub-Dialog State
  const [paramDialogOpen, setParamDialogOpen] = useState(false);
  const [selectedTestForParams, setSelectedTestForParams] = useState<DbTest | null>(null);
  const [parameters, setParameters] = useState<DbParameter[]>([]);
  const [optionSets, setOptionSets] = useState<DbOptionSet[]>([]);
  const [paramLoading, setParamLoading] = useState(false);
  const [editingParam, setEditingParam] = useState<DbParameter | null>(null);
  const [paramForm, setParamForm] = useState({
    code: '',
    name: '',
    value_type: 'Numeric',
    unit: '',
    formula: '',
    display_order: 1,
    is_mandatory: true,
    is_active: true,
    decimal_precision: 2,
    calculation_identifier: '',
    option_set_id: '',
  });

  // Reference Ranges State
  const [selectedParamForRanges, setSelectedParamForRanges] = useState<DbParameter | null>(null);
  const [refRanges, setRefRanges] = useState<DbRefRange[]>([]);
  const [editingRange, setEditingRange] = useState<DbRefRange | null>(null);
  const [rangeForm, setRangeForm] = useState({
    gender: 'All',
    age_min_years: 0,
    age_max_years: 120,
    normal_min: '',
    normal_max: '',
    critical_low: '',
    critical_high: '',
    normal_text: '',
    method: '',
    unit: '',
  });

  // Clinical Validation & Formal Laboratory Approval Governance State
  const [validatingTest, setValidatingTest] = useState<DbTest | null>(null);
  const [bulkValidatingTests, setBulkValidatingTests] = useState<DbTest[] | null>(null);
  const [adoptPresetsDialogOpen, setAdoptPresetsDialogOpen] = useState(false);
  const [adoptPresetsTests, setAdoptPresetsTests] = useState<DbTest[] | null>(null);
  const [adoptApprovalNotes, setAdoptApprovalNotes] = useState('');
  const [adoptBusy, setAdoptBusy] = useState(false);
  const [approvalForm, setApprovalForm] = useState({
    analyzer_model: '',
    reagent_manufacturer: '',
    method: '',
    reference_range_source: '',
    critical_limit_source: '',
    effective_from: getNepalTodayAd(),
    approval_notes: '',
  });
  const [pastApprovals, setPastApprovals] = useState<any[]>([]);
  const [validationBusy, setValidationBusy] = useState(false);

  // Load tests from Supabase
  const loadTests = useCallback(async () => {
    setLoading(true);
    setError(null);
    setAuthError(null);
    try {
      const { data: { session }, error: sessionErr } = await supabase.auth.getSession();
      if (!session || sessionErr) {
        console.warn('[Catalogue] No authenticated Supabase session found in browser.');
        setAuthError('Your session has expired or you are not signed in. Please sign in to manage the test catalogue.');
        setLoading(false);
        return;
      }

      const [testResult, categoryResult, operationalResult] = await Promise.all([supabase
        .from('tests')
        .select('*, parameters(id, code, name, value_type, option_set_id, is_active, unit, display_order, lifecycle_status, reference_ranges(id, is_active, is_approved, lifecycle_status, validation_state))')
        .order('display_order', { ascending: true })
        .order('department', { ascending: true })
        .order('name', { ascending: true }), supabase.from('test_categories').select('*').order('display_order'),
        supabase.from('catalogue_test_operational_state').select('test_id,operational_state')]);
      const { data, error: fetchErr } = testResult;

      if (fetchErr) {
        console.error('[Catalogue] Tests fetch error:', fetchErr);
        if (fetchErr.code === '42501' || fetchErr.message?.includes('permission denied')) {
          setError('PERMISSION_ERROR: You do not have permission to view the test catalogue.');
        } else {
          setError(safeErrorMessage(fetchErr, 'Failed to load test catalogue.'));
        }
      } else if (operationalResult.error) {
        setError(safeErrorMessage(operationalResult.error, 'Failed to load server-authoritative catalogue states.'));
      } else {
        const operationalByTest = new Map((operationalResult.data || []).map((row) => [row.test_id, row.operational_state]));
        setTests((data || []).map((test) => ({ ...test, operational_state: operationalByTest.get(test.id) })));
      }
      if (!categoryResult.error) setCategories(categoryResult.data || []);
    } catch (err: any) {
      console.error('[Catalogue] Load error:', err);
      setError(safeErrorMessage(err, 'Failed to load test catalogue.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadTests();
  }, [loadTests]);

  const getTestRangeStatus = (test: DbTest): { label: 'Configured' | 'Needs Review' | 'Not Configured'; color: 'success' | 'warning' | 'default'; count: number; total: number } => {
    const clinicalParams = (test.parameters || []).filter(
      (p) => p.is_active && p.value_type !== 'Heading'
    );
    if (clinicalParams.length === 0) return { label: 'Not Configured', color: 'default', count: 0, total: 0 };

    let configuredCount = 0;
    let hasAnyRange = false;

    for (const param of clinicalParams) {
      const ranges = (param as any).reference_ranges || [];
      const approvedRanges = ranges.filter((r: any) =>
        r.is_active !== false &&
        r.is_approved === true &&
        r.validation_state === 'ClinicallyValidated'
      );
      if (approvedRanges.length > 0) {
        configuredCount++;
        hasAnyRange = true;
      }
    }

    if (configuredCount === clinicalParams.length) {
      return { label: 'Configured', color: 'success', count: configuredCount, total: clinicalParams.length };
    }
    if (hasAnyRange) {
      return { label: 'Needs Review', color: 'warning', count: configuredCount, total: clinicalParams.length };
    }
    return { label: 'Not Configured', color: 'default', count: 0, total: clinicalParams.length };
  };

  const handleOpenBulkRanges = (test: DbTest) => {
    setSelectedTestForBulk(test);
    setBulkEditorOpen(true);
  };

  // Handle opening Add / Edit Test modal
  const handleOpenTestModal = (test?: DbTest) => {
    setEditingTest(test || null);
    setTestDialogOpen(true);
  };

  // Safe error formatter for operator display and console diagnosis
  const formatPostgrestError = (err: any, entityName: string = 'test'): string => {
    console.error(`[Supabase Error: ${entityName}]`, {
      code: err?.code,
      message: err?.message,
      details: err?.details,
      hint: err?.hint,
    });

    const msg = err?.message || '';
    const code = err?.code || '';

    if (code === '42501' || msg.includes('row-level security') || msg.includes('permission denied')) {
      return 'You do not have permission to manage the test catalogue. Please sign in as the Lab Technician or Super Admin.';
    }

    if (code === '23505' || msg.includes('unique constraint') || msg.includes('tests_code_key')) {
      return 'Test code already exists in the master catalogue. Please use a unique code.';
    }

    if (code === '23514' || msg.includes('check constraint') || msg.includes('chk_')) {
      return 'Invalid field value or constraint violation. Please verify all inputs.';
    }

    if (msg.includes('Failed to fetch') || msg.includes('NetworkError') || msg.includes('fetch')) {
      return 'Network connection error. Unable to reach the laboratory database.';
    }

    return msg || `Failed to save ${entityName}. Please check inputs and try again.`;
  };



  // Load parameters for selected test
  const handleOpenParameters = async (test: DbTest) => {
    setSelectedTestForParams(test);
    setSelectedParamForRanges(null);
    setParamDialogOpen(true);
    setParamLoading(true);

    try {
      const [{ data, error: pErr }, optionResult] = await Promise.all([
        supabase.from('parameters').select('*').eq('test_id', test.id).order('display_order', { ascending: true }),
        supabase.from('catalogue_option_sets').select('id,code,name,lifecycle_status').eq('lifecycle_status', 'Active').order('name'),
      ]);

      if (pErr) throw pErr;
      setParameters(data || []);
      if (optionResult.error) throw optionResult.error;
      setOptionSets(optionResult.data || []);
    } catch (err: any) {
      setError(formatPostgrestError(err, 'parameter list'));
    } finally {
      setParamLoading(false);
    }
  };

  // Save Parameter
  const handleEditParameter = (parameter: DbParameter) => {
    setEditingParam(parameter);
    setParamForm({
      code: parameter.code,
      name: parameter.name,
      value_type: parameter.value_type,
      unit: parameter.unit || '',
      formula: parameter.formula || '',
      display_order: parameter.display_order,
      is_mandatory: parameter.is_mandatory,
      is_active: parameter.is_active,
      decimal_precision: parameter.decimal_precision ?? 2,
      calculation_identifier: parameter.calculation_identifier || '',
      option_set_id: parameter.option_set_id || '',
    });
  };

  const handleSaveParameter = async () => {
    if (!selectedTestForParams || !paramForm.code.trim() || !paramForm.name.trim()) return;

    const payload = {
      test_id: selectedTestForParams.id,
      code: paramForm.code.trim().toUpperCase(),
      name: paramForm.name.trim(),
      value_type: paramForm.value_type,
      unit: paramForm.unit.trim() || null,
      formula: paramForm.formula.trim() || null,
      is_mandatory: paramForm.is_mandatory,
      is_active: paramForm.is_active,
      display_order: Number(paramForm.display_order) || parameters.length + 1,
      decimal_precision: Number(paramForm.decimal_precision),
      calculation_identifier: paramForm.calculation_identifier.trim() || null,
    };

    try {
      const { data: savedParameterId, error: paramErr } = await supabase.rpc('catalogue_save_parameter', { p_parameter: { ...payload, id: editingParam?.id }, p_expected_version: editingParam?.row_version ?? null });
      if (paramErr) throw paramErr;
      if (['Select', 'Boolean'].includes(paramForm.value_type) && paramForm.option_set_id) {
        const parameterId = editingParam?.id || savedParameterId;
        const expectedVersion = editingParam ? editingParam.row_version + 1 : 1;
        const { error: optionErr } = await supabase.rpc('catalogue_set_parameter_option_set', {
          p_parameter_id: parameterId,
          p_option_set_id: paramForm.option_set_id,
          p_expected_version: expectedVersion,
        });
        if (optionErr) throw optionErr;
      }

      setEditingParam(null);
      setParamForm({
        code: '',
        name: '',
        value_type: 'Numeric',
        unit: '',
        formula: '',
        display_order: parameters.length + 1,
        is_mandatory: true,
        is_active: true,
        decimal_precision: 2,
        calculation_identifier: '',
        option_set_id: '',
      });

      // Reload
      const { data } = await supabase
        .from('parameters')
        .select('*')
        .eq('test_id', selectedTestForParams.id)
        .order('display_order', { ascending: true });
      setParameters(data || []);
      loadTests();
    } catch (err: any) {
      setError(formatPostgrestError(err, 'parameter'));
    }
  };

  // Load reference ranges for parameter
  const handleSelectParamForRanges = async (param: DbParameter) => {
    setSelectedParamForRanges(param);
    setEditingRange(null);
    setRangeForm({
      gender: 'All',
      age_min_years: 0,
      age_max_years: 120,
      normal_min: '',
      normal_max: '',
      critical_low: '',
      critical_high: '',
      normal_text: '',
      method: '',
      unit: param.unit || '',
    });

    try {
      const { data, error: rErr } = await supabase
        .from('reference_ranges')
        .select('*')
        .eq('parameter_id', param.id);

      if (rErr) throw rErr;
      setRefRanges(data || []);
    } catch (err: any) {
      setError(formatPostgrestError(err, 'reference ranges'));
    }
  };

  const handleEditRange = (range: DbRefRange) => {
    setEditingRange(range);
    setRangeForm({
      gender: range.gender || 'All',
      age_min_years: Number(range.age_min_days || 0) / 365,
      age_max_years: Number(range.age_max_days || 43800) / 365,
      normal_min: range.normal_min == null ? '' : String(range.normal_min),
      normal_max: range.normal_max == null ? '' : String(range.normal_max),
      critical_low: range.critical_low == null ? '' : String(range.critical_low),
      critical_high: range.critical_high == null ? '' : String(range.critical_high),
      normal_text: range.normal_text || '',
      method: range.method || '',
      unit: range.unit || selectedParamForRanges?.unit || '',
    });
  };

  // Save Reference Range
  const handleSaveRange = async () => {
    if (!selectedParamForRanges) return;

    const payload = {
      parameter_id: selectedParamForRanges.id,
      gender: rangeForm.gender,
      age_min_days: Math.round((rangeForm.age_min_years || 0) * 365),
      age_max_days: Math.round((rangeForm.age_max_years || 120) * 365),
      normal_min: rangeForm.normal_min ? parseFloat(rangeForm.normal_min) : null,
      normal_max: rangeForm.normal_max ? parseFloat(rangeForm.normal_max) : null,
      critical_low: rangeForm.critical_low ? parseFloat(rangeForm.critical_low) : null,
      critical_high: rangeForm.critical_high ? parseFloat(rangeForm.critical_high) : null,
      normal_text: rangeForm.normal_text.trim() || null,
      method: rangeForm.method.trim() || null,
      unit: rangeForm.unit.trim() || null,
    };

    const validation = validateReferenceRange(payload);
    if (!validation.isValid) {
      setError(validation.error || 'Invalid reference interval.');
      return;
    }
    const overlap = checkRangeOverlap(refRanges, payload, editingRange?.id);
    if (overlap.hasOverlap) {
      setError('This age/sex interval overlaps an existing active reference range.');
      return;
    }

    try {
      const { error: rangeErr } = await supabase.rpc('catalogue_save_range', {
        p_range: {
          ...payload,
          id: editingRange?.id,
          // Any interval edit requires a fresh, explicit clinical validation.
          // Never inherit or manufacture approval provenance in this form.
          is_approved: false,
          validation_state: 'Unclassified',
          validation_source: editingRange ? 'Edited in Catalogue; requires clinical validation' : null,
        },
        p_expected_version: editingRange?.row_version ?? null,
      });

      if (rangeErr) throw rangeErr;

      // Reload
      const { data } = await supabase
        .from('reference_ranges')
        .select('*')
        .eq('parameter_id', selectedParamForRanges.id);
      setRefRanges(data || []);
      setEditingRange(null);
      setSuccess(editingRange ? 'Reference range updated and returned to clinical-validation review.' : 'Reference range interval added as an unvalidated Draft.');
    } catch (err: any) {
      setError(formatPostgrestError(err, 'reference range'));
    }
  };

  const setRangeLifecycle = async (range: DbRefRange, status: LifecycleStatus) => {
    const { error: rpcError } = await supabase.rpc('catalogue_set_range_lifecycle', {
      p_range_id: range.id,
      p_status: status,
      p_expected_version: range.row_version,
    });
    if (rpcError) { setError(formatPostgrestError(rpcError, 'reference range lifecycle')); return; }
    if (selectedParamForRanges) await handleSelectParamForRanges(selectedParamForRanges);
    await loadTests();
  };

  const requestDeleteRange = (range: DbRefRange) => setConfirmAction({
    message: 'Permanently delete this unused reference range?',
    guidance: 'The database permits deletion only when safe. Otherwise archive the interval so historical clinical records remain intact.',
    run: async () => {
      const { error: rpcError } = await supabase.rpc('catalogue_delete_range', {
        p_range_id: range.id,
        p_expected_version: range.row_version,
      });
      if (rpcError) throw rpcError;
      if (selectedParamForRanges) await handleSelectParamForRanges(selectedParamForRanges);
    },
  });

  const filteredTests = tests.filter(
    (t) =>
      t.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      t.code.toLowerCase().includes(searchTerm.toLowerCase()) ||
      t.department.toLowerCase().includes(searchTerm.toLowerCase()) ||
      (t.short_name || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (t.search_aliases || []).some((alias) => alias.toLowerCase().includes(searchTerm.toLowerCase()))
  ).filter((t) => lifecycleFilter === 'All' || t.lifecycle_status === lifecycleFilter)
    .filter((t) => departmentFilter === 'All' || t.department === departmentFilter)
    .filter((t) => categoryFilter === 'All' || t.category_id === categoryFilter)
    .filter((t) => reportingFilter === 'All' || t.reporting_type === reportingFilter)
    .filter((t) => modelFilter === 'All' || t.reporting_model === modelFilter)
    .filter((t) => !incompleteOnly || getTestRangeStatus(t).label !== 'Configured');

  const runConfirmed = async () => {
    if (!confirmAction) return; setActionBusy(true);
    try { await confirmAction.run(); setConfirmAction(null); await loadTests(); }
    catch (err: any) { setConfirmAction(null); setError(formatPostgrestError(err, 'catalogue lifecycle')); }
    finally { setActionBusy(false); }
  };

  const requestLifecycle = (test: DbTest, status: LifecycleStatus) => {
    setConfirmAction({
      message: `${status === 'Archived' ? 'Archive' : status === 'Active' ? 'Activate' : 'Return'} ${test.code}?`,
      guidance: status === 'Active' ? 'Activating will enable this investigation for ordering, accessioning, and reporting.' : 'Historical bills, orders, results, and signed snapshots remain unchanged.',
      run: async () => {
        const { error: rpcError } = await supabase.rpc('catalogue_set_test_lifecycle', {
          p_test_id: test.id,
          p_status: status,
          p_expected_version: test.row_version,
        });
        if (rpcError) throw rpcError;
        setSuccess(`${test.code} status updated to ${status}.`);
      },
    });
  };

  const openValidationDialog = async (test: DbTest) => {
    setValidatingTest(test);
    setApprovalForm({
      analyzer_model: '',
      reagent_manufacturer: '',
      method: test.method || '',
      reference_range_source: '',
      critical_limit_source: '',
      effective_from: getNepalTodayAd(),
      approval_notes: test.configuration_notes || '',
    });
    try {
      const { data } = await supabase
        .from('catalogue_lab_approvals')
        .select('*')
        .eq('test_id', test.id)
        .order('created_at', { ascending: false });
      setPastApprovals(data || []);
    } catch {
      setPastApprovals([]);
    }
  };

  const handleApproveConfirm = async () => {
    if (!validatingTest) return;
    if (!approvalForm.reference_range_source.trim() && validatingTest.test_kind !== 'Profile' && validatingTest.reporting_type !== 'NoReporting') {
      setError('Documented biological reference range source or clinical policy is required for laboratory approval.');
      return;
    }
    setValidationBusy(true);
    setError(null);
    try {
      const { error: appErr } = await supabase.rpc('catalogue_submit_lab_approval', {
        p_test_id: validatingTest.id,
        p_analyzer_model: approvalForm.analyzer_model.trim() || null,
        p_reagent_manufacturer: approvalForm.reagent_manufacturer.trim() || null,
        p_method: approvalForm.method.trim() || null,
        p_reference_range_source: approvalForm.reference_range_source.trim() || null,
        p_critical_limit_source: approvalForm.critical_limit_source.trim() || null,
        p_effective_from: approvalForm.effective_from || null,
        p_approval_notes: approvalForm.approval_notes.trim() || null,
        p_expected_version: validatingTest.row_version,
      });
      if (appErr) throw appErr;
      setSuccess(`${validatingTest.code} (${validatingTest.name}) formally approved by laboratory leadership and marked VALIDATED.`);
      setValidatingTest(null);
      await loadTests();
    } catch (err: any) {
      setError(formatPostgrestError(err, 'laboratory approval'));
    } finally {
      setValidationBusy(false);
    }
  };

  const handleRevertConfirm = async () => {
    if (!validatingTest) return;
    setValidationBusy(true);
    setError(null);
    try {
      const { error: revErr } = await supabase.rpc('catalogue_revert_to_proposed', {
        p_test_id: validatingTest.id,
        p_reason: approvalForm.approval_notes.trim() || 'Reverted to unapproved proposed draft for laboratory review',
        p_expected_version: validatingTest.row_version,
      });
      if (revErr) throw revErr;
      setSuccess(`${validatingTest.code} reverted to unapproved PROPOSED draft (REQUIRES_VALIDATION & INACTIVE).`);
      setValidatingTest(null);
      await loadTests();
    } catch (err: any) {
      setError(formatPostgrestError(err, 'reversion to proposed'));
    } finally {
      setValidationBusy(false);
    }
  };

  const handleBulkValidate = (selected: any[]) => {
    if (!selected || selected.length === 0) return;
    setBulkValidatingTests(selected as DbTest[]);
    setApprovalForm({
      analyzer_model: '',
      reagent_manufacturer: '',
      method: selected[0]?.method || '',
      reference_range_source: '',
      critical_limit_source: '',
      effective_from: getNepalTodayAd(),
      approval_notes: '',
    });
  };

  const handleBulkApproveConfirm = async () => {
    if (!bulkValidatingTests || bulkValidatingTests.length === 0) return;
    if (!approvalForm.reference_range_source.trim()) {
      setError('Documented biological reference range source or clinical policy is required for laboratory approval.');
      return;
    }
    setValidationBusy(true);
    setError(null);
    try {
      const testIds = bulkValidatingTests.map((t) => t.id);
      const { data, error: appErr } = await supabase.rpc('catalogue_bulk_submit_lab_approval', {
        p_test_ids: testIds,
        p_analyzer_model: approvalForm.analyzer_model.trim() || null,
        p_reagent_manufacturer: approvalForm.reagent_manufacturer.trim() || null,
        p_method: approvalForm.method.trim() || null,
        p_reference_range_source: approvalForm.reference_range_source.trim() || null,
        p_critical_limit_source: approvalForm.critical_limit_source.trim() || null,
        p_effective_from: approvalForm.effective_from || null,
        p_approval_notes: approvalForm.approval_notes.trim() || null,
      });
      if (appErr) throw appErr;
      const count = (data as any)?.approved_count || testIds.length;
      setSuccess(`Successfully approved and validated ${count} tests! They are now ready for activation.`);
      setBulkValidatingTests(null);
      await loadTests();
    } catch (err: any) {
      setError(formatPostgrestError(err, 'bulk laboratory approval'));
    } finally {
      setValidationBusy(false);
    }
  };

  const handleAdoptStandardPresets = (selected: any[]) => {
    if (!selected || selected.length === 0) return;
    setAdoptPresetsTests(selected as DbTest[]);
    setAdoptApprovalNotes('Adopted from Standard Clinical Presets Library v1.0. Clinical laboratory responsibility assumed by authorized director.');
    setAdoptPresetsDialogOpen(true);
  };

  const handleAdoptPresetsConfirm = async () => {
    if (!adoptPresetsTests || adoptPresetsTests.length === 0) return;
    setAdoptBusy(true);
    setError(null);
    try {
      const testIds = adoptPresetsTests.map((t) => t.id);
      const { data, error: adoptErr } = await supabase.rpc('catalogue_adopt_standard_presets', {
        p_test_ids: testIds,
        p_approval_notes: adoptApprovalNotes.trim() || null,
      });
      if (adoptErr) throw adoptErr;
      const count = (data as any)?.adopted_count || testIds.length;
      setSuccess(`Successfully adopted standard presets for ${count} tests! Status changed to VALIDATED. Separate explicit activation is required before clinical ordering.`);
      setAdoptPresetsDialogOpen(false);
      setAdoptPresetsTests(null);
      await loadTests();
    } catch (err: any) {
      setError(formatPostgrestError(err, 'adopt standard presets'));
    } finally {
      setAdoptBusy(false);
    }
  };

  const handleBulkActivate = (selected: any[]) => {
    const unvalidated = selected.filter((t) => t.validation_status !== 'VALIDATED');
    if (unvalidated.length > 0) {
      setError(`Cannot bulk activate: ${unvalidated.length} selected tests are not yet clinically VALIDATED (e.g. ${unvalidated[0].code}).`);
      return;
    }
    setConfirmAction({
      message: `Activate ${selected.length} validated tests for patient ordering and clinical reporting?`,
      guidance: 'Activation enables is_active, billing_enabled, and clinical_reporting_enabled across all selected tests.',
      run: async () => {
        const testIds = selected.map((t) => t.id);
        const { data, error: actErr } = await supabase.rpc('catalogue_bulk_activate', {
          p_test_ids: testIds,
        });
        if (actErr) throw actErr;
        const count = (data as any)?.activated_count || testIds.length;
        setSuccess(`Successfully activated ${count} tests for patient ordering!`);
      },
    });
  };

  const requestDelete = (test: DbTest) => setConfirmAction({ message: `Permanently delete unused test ${test.code}?`, guidance: 'The database permits this only when no billing or clinical history references the test.', run: async () => { const { error: rpcError } = await supabase.rpc('catalogue_delete_test', { p_test_id: test.id, p_expected_version: test.row_version }); if (rpcError) throw rpcError; } });

  const cloneTest = async (test: DbTest) => { const code = `${test.code}_COPY`; const { error: rpcError } = await supabase.rpc('catalogue_clone_test', { p_test_id: test.id, p_code: code, p_name: `${test.name} Copy` }); if (rpcError) setError(formatPostgrestError(rpcError, 'test clone')); else { setSuccess(`${code} created as Draft; price, parameters, and clinical configuration require review.`); loadTests(); } };

  const setParameterLifecycle = async (parameter: DbParameter, status: LifecycleStatus) => {
    const { error: rpcError } = await supabase.rpc('catalogue_set_parameter_lifecycle', { p_parameter_id: parameter.id, p_status: status, p_expected_version: parameter.row_version });
    if (rpcError) { setError(formatPostgrestError(rpcError, 'parameter lifecycle')); return; }
    if (selectedTestForParams) await handleOpenParameters(selectedTestForParams);
  };

  const deleteParameter = async (parameter: DbParameter) => {
    const { error: rpcError } = await supabase.rpc('catalogue_delete_parameter', { p_parameter_id: parameter.id, p_expected_version: parameter.row_version });
    if (rpcError) { setError(formatPostgrestError(rpcError, 'parameter delete')); return; }
    if (selectedTestForParams) await handleOpenParameters(selectedTestForParams);
  };

  return (
    <Box>
      <PageHeader
        title="Test Catalogue"
        subtitle="Operational test database, laboratory categories, and clinical panels"
        action={
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              variant="outlined"
              startIcon={<RefreshIcon />}
              onClick={loadTests}
              disabled={loading}
            >
              Refresh
            </Button>
            {canManage && (
              <>
                <Button
                  variant="outlined"
                  color="secondary"
                  startIcon={<FileUploadIcon />}
                  onClick={() => setCsvModalOpen(true)}
                >
                  Ranges CSV
                </Button>
                <Button
                  variant="contained"
                  color="primary"
                  startIcon={<AddIcon />}
                  onClick={() => handleOpenTestModal()}
                >
                  Add Master Test
                </Button>
              </>
            )}
          </Box>
        }
      />

      {authError && (
        <Alert
          severity="warning"
          sx={{ mb: 2 }}
          action={
            <Button color="inherit" size="small" onClick={() => window.location.assign('/login')}>
              Sign In
            </Button>
          }
        >
          {authError}
        </Alert>
      )}

      {error && (
        <Alert severity="error" onClose={() => setError(null)} sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}

      {success && (
        <Alert severity="success" onClose={() => setSuccess(null)} sx={{ mb: 2 }}>
          {success}
        </Alert>
      )}

      <Card sx={{ mb: 2 }}><Tabs
        value={catalogueSection}
        onChange={(_, value) => setCatalogueSection(value)}
        variant="scrollable"
        scrollButtons="auto"
        aria-label="Catalogue sections"
      >
        <Tab value="tests" label="Test Database" />
        <Tab value="categories" label="Categories" />
        <Tab value="panels" label="Test Panels" />
        <Tab value="structures" label="Parameters / Ranges" />
        <Tab value="prices" label="Prices / Ratelist" />
        <Tab value="pt_inr_reagents" label="PT/INR Reagents" />
        <Tab value="templates" label="Templates" />
      </Tabs></Card>

      {catalogueSection === 'categories' && <CatalogueCategoriesSection categories={categories} tests={tests} onView={(name) => { setDepartmentFilter('All'); setSearchTerm(name === 'Haematology' ? 'hemat' : name === 'Biochemistry' ? 'biochem' : name); setCatalogueSection('tests'); }} />}
      {catalogueSection === 'panels' && <CataloguePanelsSection
        tests={tests}
        categories={categories}
        canEdit={canManage}
        onEdit={(test) => handleOpenTestModal(test as DbTest)}
        onConfigure={(test) => handleOpenParameters(test as DbTest)}
      />}

      {catalogueSection === 'tests' && (
        <CatalogueTestDatabaseSection
          tests={tests}
          canEdit={canManage}
          canConfigure={canManage}
          onEdit={(test) => handleOpenTestModal(test as DbTest)}
          onConfigure={(test) => handleOpenParameters(test as DbTest)}
          onValidate={(test) => openValidationDialog(test as DbTest)}
          onActivate={(test) => requestLifecycle(test as DbTest, 'Active')}
          onDeactivate={(test) => requestLifecycle(test as DbTest, 'Draft')}
          onBulkValidate={handleBulkValidate}
          onBulkActivate={handleBulkActivate}
          onAdoptStandardPresets={handleAdoptStandardPresets}
        />
      )}
      {catalogueSection === 'structures' && <Card><CardContent><Typography variant="h6" fontWeight={800}>Parameters / Result Structures</Typography><Typography color="text.secondary" sx={{mb:2}}>Configure canonical parameters, result types, units, ordering and structured qualitative option sets. Readiness is recalculated by the server after every explicit audited change.</Typography><Button variant="contained" onClick={()=>setCatalogueSection('tests')}>Choose a test to configure</Button></CardContent></Card>}
      {catalogueSection === 'prices' && <CataloguePriceMasterSection canManage={canManage} />}
      {catalogueSection === 'pt_inr_reagents' && <PtInrReagentConfigSection isAdmin={canManage} />}
      {/* View & Copy Library is canonical-template authoring, never a second catalogue. */}
      {catalogueSection === 'templates' && <CatalogueTemplateLibrarySection canCopy={canManage} />}

      {catalogueSection === 'legacy-tests' && <Card>
        <CardContent>
          <Box sx={{ mb: 2, display: 'grid', gridTemplateColumns: { xs: '1fr', md: '2fr repeat(6, 1fr)' }, gap: 1 }}>
            <TextField
              fullWidth
              size="small"
              placeholder="Search by code, name, short name, alias, or department..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" />
                  </InputAdornment>
                ),
              }}
            />
            <TextField select size="small" label="Lifecycle" value={lifecycleFilter} onChange={(e) => setLifecycleFilter(e.target.value as any)}>
              {['All', 'Draft', 'Active', 'Archived'].map((value) => <MenuItem key={value} value={value}>{value}</MenuItem>)}
            </TextField>
            <TextField select size="small" label="Department" value={departmentFilter} onChange={(e) => setDepartmentFilter(e.target.value)}>
              <MenuItem value="All">All departments</MenuItem>{[...new Set(tests.map((test) => test.department))].sort().map((department) => <MenuItem key={department} value={department}>{department}</MenuItem>)}
            </TextField>
            <TextField select size="small" label="Category" value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)}>
              <MenuItem value="All">All categories</MenuItem>{categories.map((category) => <MenuItem key={category.id} value={category.id}>{category.name}</MenuItem>)}
            </TextField>
            <TextField select size="small" label="Reporting tier" value={reportingFilter} onChange={(e) => setReportingFilter(e.target.value)}>
              {['All', 'InHouse', 'OutsourceWithBimalReport', 'NoReporting'].map((value) => <MenuItem key={value} value={value}>{value}</MenuItem>)}
            </TextField>
            <TextField select size="small" label="Reporting model" value={modelFilter} onChange={(e) => setModelFilter(e.target.value)}>
              <MenuItem value="All">All models</MenuItem>{[...new Set(tests.map((test) => test.reporting_model).filter(Boolean))].sort().map((model) => <MenuItem key={model} value={model}>{model}</MenuItem>)}
            </TextField>
            <FormControlLabel control={<Switch checked={incompleteOnly} onChange={(e) => setIncompleteOnly(e.target.checked)} />} label="Incomplete" />
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
                    <TableCell>Order</TableCell>
                    <TableCell>Test Name</TableCell>
                    <TableCell>Type</TableCell>
                    <TableCell>Short Name / Code</TableCell>
                    <TableCell>Category</TableCell>
                    <TableCell align="center">Status</TableCell>
                    <TableCell align="center">Edit / View</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredTests.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={7} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                        No tests match your search criteria.
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredTests.filter((test) => test.test_kind !== 'Profile').map((test) => {
                      return (
                        <TableRow key={test.id} hover>
                          <TableCell>{test.display_order}</TableCell>
                          <TableCell>
                            <Typography variant="body2" fontWeight={600}>
                              {test.name}
                            </Typography>
                          </TableCell>
                          <TableCell>{test.reporting_model === 'NarrativeDocument' ? 'Document' : test.reporting_model === 'StructuredNested' ? 'Multi parameter nested' : ['NumericMultiParameter', 'MixedTyped'].includes(test.reporting_model || '') ? 'Multi parameter' : 'Single parameter'}</TableCell>
                          <TableCell>{test.short_name || test.code}</TableCell>
                          <TableCell>{categories.find((category) => category.id === test.category_id)?.name || test.category}</TableCell>
                          <TableCell align="center">
                            <Chip label={catalogueOperationalStatus(test)} color={catalogueOperationalStatusColor(catalogueOperationalStatus(test))} size="small" />
                          </TableCell>
                          <TableCell align="center">
                            {canManage && (
                              <Box sx={{ display: 'flex', gap: 0.5, justifyContent: 'center' }}>
                                <Tooltip title="Edit Test Master Info">
                                  <IconButton
                                    size="small"
                                    color="primary"
                                    onClick={() => handleOpenTestModal(test)}
                                  >
                                    <EditIcon fontSize="small" />
                                  </IconButton>
                                </Tooltip>
                                <Tooltip title="Configure & Approve Reference Ranges (Bulk)">
                                  <IconButton
                                    size="small"
                                    color="secondary"
                                    onClick={() => handleOpenBulkRanges(test)}
                                  >
                                    <RuleIcon fontSize="small" />
                                  </IconButton>
                                </Tooltip>
                                <Tooltip title="Manage Parameters List">
                                  <IconButton
                                    size="small"
                                    color="inherit"
                                    onClick={() => handleOpenParameters(test)}
                                  >
                                    <TuneIcon fontSize="small" />
                                  </IconButton>
                                </Tooltip>
                                <Tooltip title="Laboratory Clinical Approval & Governance">
                                  <IconButton
                                    size="small"
                                    color={test.validation_status === 'VALIDATED' ? 'success' : 'warning'}
                                    onClick={() => openValidationDialog(test)}
                                  >
                                    <FactCheckIcon fontSize="small" />
                                  </IconButton>
                                </Tooltip>
                                <Tooltip title="Clone as Draft"><IconButton size="small" onClick={() => cloneTest(test)}><ContentCopyIcon fontSize="small" /></IconButton></Tooltip>
                                {test.lifecycle_status === 'Archived' ? <Tooltip title="Restore to Draft"><IconButton size="small" onClick={() => requestLifecycle(test, 'Draft')}><RestoreIcon fontSize="small" /></IconButton></Tooltip> : <Tooltip title="Archive"><IconButton size="small" onClick={() => requestLifecycle(test, 'Archived')}><ArchiveIcon fontSize="small" /></IconButton></Tooltip>}
                                {test.lifecycle_status === 'Draft' && <Button size="small" onClick={() => requestLifecycle(test, 'Active')}>Activate</Button>}
                                {test.lifecycle_status !== 'Active' && <Tooltip title="Safe delete if never referenced"><IconButton color="error" size="small" onClick={() => requestDelete(test)}><DeleteOutlineIcon fontSize="small" /></IconButton></Tooltip>}
                              </Box>
                            )}
                          </TableCell>
                        </TableRow>
                      );
                    })
                  )}
                </TableBody>
              </Table>
            </TableContainer>
          )}
        </CardContent>
      </Card>}

      {/* Easy Test Master Editor Dialog (All 7 Tabs: General, Parameters, Reference Ranges, Price, Aliases, Analyzer, History) */}
      <EasyTestEditorDialog
        open={testDialogOpen}
        test={editingTest}
        categories={categories}
        allTests={tests}
        onClose={() => {
          setTestDialogOpen(false);
          setEditingTest(null);
        }}
        onSaved={(_savedTest) => {
          setTestDialogOpen(false);
          setEditingTest(null);
          setSuccess('Test catalogue successfully saved.');
          loadTests();
        }}
      />

      {/* Dialog 2: Configure Parameters & Reference Intervals */}
      <Dialog
        open={paramDialogOpen}
        onClose={() => setParamDialogOpen(false)}
        maxWidth="lg"
        fullWidth
      >
        <DialogTitle>
          Configure Parameters & Reference Intervals: {selectedTestForParams?.name} ({selectedTestForParams?.code})
        </DialogTitle>
        <DialogContent dividers data-keyboard-form="true" onKeyDown={handleEnterKeyNavigation}>
          {paramLoading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', p: 3 }}>
              <CircularProgress />
            </Box>
          ) : (
            <Grid container spacing={3}>
              {/* Left Column: Parameters List & Add Form */}
              <Grid item xs={12} md={6}>
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>
                  Parameters ({parameters.length})
                </Typography>
                <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', mb: 2, maxHeight: 260 }}>
                  <Table size="small">
                    <TableHead>
                      <TableRow>
                        <TableCell>Code & Name</TableCell>
                        <TableCell>Type</TableCell>
                        <TableCell>Unit</TableCell>
                        <TableCell align="center">Action</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {parameters.length === 0 ? (
                        <TableRow>
                          <TableCell colSpan={4} align="center" sx={{ color: 'text.secondary', py: 2 }}>
                            No parameters configured.
                          </TableCell>
                        </TableRow>
                      ) : (
                        parameters.map((p) => {
                          const isSelected = selectedParamForRanges?.id === p.id;
                          return (
                            <TableRow key={p.id} hover selected={isSelected}>
                              <TableCell>
                                <Typography variant="body2" fontWeight={600}>{p.name}</Typography>
                                <Typography variant="caption" color="text.secondary">{p.code}</Typography>
                              </TableCell>
                              <TableCell><Chip label={p.value_type} size="small" /></TableCell>
                              <TableCell>{p.unit || '-'}</TableCell>
                              <TableCell align="center">
                                <IconButton size="small" onClick={() => handleEditParameter(p)} aria-label={`Edit ${p.name}`}>
                                  <EditIcon fontSize="small" />
                                </IconButton>
                                <Button
                                  size="small"
                                  variant={isSelected ? 'contained' : 'outlined'}
                                  onClick={() => handleSelectParamForRanges(p)}
                                >
                                  Ranges
                                </Button>
                                {p.lifecycle_status === 'Archived' ? <IconButton size="small" aria-label={`Restore ${p.name}`} onClick={() => setParameterLifecycle(p, 'Draft')}><RestoreIcon fontSize="small" /></IconButton> : <IconButton size="small" aria-label={`Archive ${p.name}`} onClick={() => setParameterLifecycle(p, 'Archived')}><ArchiveIcon fontSize="small" /></IconButton>}
                                {p.lifecycle_status === 'Draft' && <Button size="small" onClick={() => setParameterLifecycle(p, 'Active')}>Activate</Button>}
                                {p.lifecycle_status !== 'Active' && <IconButton color="error" size="small" aria-label={`Delete ${p.name}`} onClick={() => deleteParameter(p)}><DeleteOutlineIcon fontSize="small" /></IconButton>}
                              </TableCell>
                            </TableRow>
                          );
                        })
                      )}
                    </TableBody>
                  </Table>
                </TableContainer>

                {/* Parameter Form */}
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>
                  {editingParam ? 'Edit Parameter' : 'Add New Parameter'}
                </Typography>
                <Grid container spacing={1.5}>
                  <Grid item xs={6}>
                    <TextField
                      fullWidth
                      size="small"
                      label="Param Code"
                      value={paramForm.code}
                      onChange={(e) => setParamForm({ ...paramForm, code: e.target.value })}
                      placeholder="e.g. HB, WBC, SGPT"
                    />
                  </Grid>
                  {['Select', 'Boolean'].includes(paramForm.value_type) && <Grid item xs={12}>
                    <TextField
                      fullWidth
                      size="small"
                      select
                      required
                      label="Approved Option Set"
                      value={paramForm.option_set_id}
                      onChange={(e) => setParamForm({ ...paramForm, option_set_id: e.target.value })}
                      helperText={paramForm.option_set_id ? 'The selected vocabulary is stored explicitly and audited.' : 'Option Set Required — select an approved vocabulary before Result Entry is ready.'}
                    >
                      <MenuItem value=""><em>Select Option Set</em></MenuItem>
                      {optionSets.map((optionSet) => <MenuItem key={optionSet.id} value={optionSet.id}>{optionSet.name} ({optionSet.code})</MenuItem>)}
                    </TextField>
                  </Grid>}
                  <Grid item xs={6}>
                    <TextField
                      fullWidth
                      size="small"
                      type="number"
                      label="Display Order"
                      value={paramForm.display_order}
                      onChange={(e) => setParamForm({ ...paramForm, display_order: Number(e.target.value) })}
                      inputProps={{ min: 0, step: 1 }}
                    />
                  </Grid>
                  <Grid item xs={6}>
                    <FormControlLabel control={<Switch checked={paramForm.is_mandatory} onChange={(e) => setParamForm({ ...paramForm, is_mandatory: e.target.checked })} />} label="Required" />
                  </Grid>
                  <Grid item xs={6}>
                    <TextField
                      fullWidth
                      size="small"
                      label="Param Name"
                      value={paramForm.name}
                      onChange={(e) => setParamForm({ ...paramForm, name: e.target.value })}
                      placeholder="e.g. Hemoglobin"
                    />
                  </Grid>
                  <Grid item xs={6}>
                    <TextField
                      fullWidth
                      size="small"
                      select
                      label="Value Type"
                      value={paramForm.value_type}
                      onChange={(e) => setParamForm({ ...paramForm, value_type: e.target.value })}
                    >
                      <MenuItem value="Numeric">Numeric</MenuItem>
                      <MenuItem value="Text">Text / Qualitative</MenuItem>
                      <MenuItem value="Select">Select Dropdown</MenuItem>
                      <MenuItem value="Calculated">Calculated Formula</MenuItem>
                      <MenuItem value="Boolean">Boolean</MenuItem>
                      <MenuItem value="Heading">Heading / Section</MenuItem>
                    </TextField>
                  </Grid>
                  <Grid item xs={6}>
                    <TextField
                      fullWidth
                      size="small"
                      label="Unit"
                      value={paramForm.unit}
                      onChange={(e) => setParamForm({ ...paramForm, unit: e.target.value })}
                      placeholder="e.g. g/dL, mg/dL, /cumm"
                    />
                  </Grid>
                  {(paramForm.value_type === 'Numeric' || paramForm.value_type === 'Calculated') && <Grid item xs={6}><TextField fullWidth size="small" type="number" label="Decimal Precision" value={paramForm.decimal_precision} inputProps={{ min: 0, max: 8 }} onChange={(e) => setParamForm({ ...paramForm, decimal_precision: Number(e.target.value) })} /></Grid>}
                  {paramForm.value_type === 'Calculated' && (
                    <><Grid item xs={12}>
                      <TextField fullWidth size="small" label="Approved Calculation Identifier" value={paramForm.calculation_identifier} onChange={(e) => setParamForm({ ...paramForm, calculation_identifier: e.target.value })} placeholder="Must correspond to server-authoritative implementation" />
                    </Grid><Grid item xs={12}>
                      <TextField
                        fullWidth
                        size="small"
                        label="Calculation Formula"
                        value={paramForm.formula}
                        onChange={(e) => setParamForm({ ...paramForm, formula: e.target.value })}
                        placeholder="e.g. TOTAL_PROTEIN - ALBUMIN"
                      />
                    </Grid></>
                  )}
                  <Grid item xs={12}>
                    <Button variant="contained" size="small" onClick={handleSaveParameter}>
                      {editingParam ? 'Update Parameter' : 'Add Parameter'}
                    </Button>
                  </Grid>
                </Grid>
              </Grid>

              {/* Right Column: Reference Intervals for Selected Parameter */}
              <Grid item xs={12} md={6}>
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>
                  Reference Intervals: {selectedParamForRanges ? selectedParamForRanges.name : '(Select a parameter)'}
                </Typography>
                {selectedParamForRanges ? (
                  <>
                    <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', mb: 2, maxHeight: 200 }}>
                      <Table size="small">
                        <TableHead>
                          <TableRow>
                            <TableCell>Gender / Age</TableCell>
                            <TableCell>Normal Range</TableCell>
                            <TableCell>Critical Alert</TableCell>
                            <TableCell>Validation</TableCell>
                            <TableCell align="center">Actions</TableCell>
                          </TableRow>
                        </TableHead>
                        <TableBody>
                          {refRanges.length === 0 ? (
                            <TableRow>
                              <TableCell colSpan={5} align="center" sx={{ color: 'text.secondary', py: 2 }}>
                                No specific ranges defined (Defaults to open qualitative text).
                              </TableCell>
                            </TableRow>
                          ) : (
                            refRanges.map((r) => (
                              <TableRow key={r.id} hover>
                                <TableCell>
                                  {r.gender} ({Math.round(r.age_min_days / 365)} - {Math.round(r.age_max_days / 365)}Y)
                                </TableCell>
                                <TableCell>
                                  {r.normal_min !== null && r.normal_max !== null
                                    ? `${r.normal_min} - ${r.normal_max} ${r.unit || ''}`
                                    : r.normal_text || '-'}
                                </TableCell>
                                <TableCell>
                                  {r.critical_low || r.critical_high
                                    ? `< ${r.critical_low ?? '-'} | > ${r.critical_high ?? '-'}`
                                    : '-'}
                                </TableCell>
                                <TableCell>
                                  <Chip
                                    size="small"
                                    color={r.validation_state === 'ClinicallyValidated' ? 'success' : 'warning'}
                                    variant={r.validation_state === 'ClinicallyValidated' ? 'filled' : 'outlined'}
                                    label={r.validation_state === 'ClinicallyValidated' ? 'Clinically validated' : r.validation_state === 'LegacyDefaultRequiresValidation' ? 'Legacy — validate' : 'Validation required'}
                                  />
                                </TableCell>
                                <TableCell align="center" sx={{ whiteSpace: 'nowrap' }}>
                                  <Tooltip title="Edit; clinical approval will be cleared">
                                    <IconButton size="small" onClick={() => handleEditRange(r)} aria-label="Edit reference range"><EditIcon fontSize="small" /></IconButton>
                                  </Tooltip>
                                  {r.lifecycle_status === 'Archived' ? (
                                    <Tooltip title="Restore as Draft"><IconButton size="small" onClick={() => setRangeLifecycle(r, 'Draft')} aria-label="Restore reference range"><RestoreIcon fontSize="small" /></IconButton></Tooltip>
                                  ) : (
                                    <Tooltip title="Archive"><IconButton size="small" onClick={() => setRangeLifecycle(r, 'Archived')} aria-label="Archive reference range"><ArchiveIcon fontSize="small" /></IconButton></Tooltip>
                                  )}
                                  {r.lifecycle_status === 'Draft' && r.validation_state === 'ClinicallyValidated' && r.is_approved === true && <Button size="small" onClick={() => setRangeLifecycle(r, 'Active')}>Activate</Button>}
                                  {r.lifecycle_status !== 'Active' && (
                                    <Tooltip title="Safe delete if unused"><IconButton color="error" size="small" onClick={() => requestDeleteRange(r)} aria-label="Delete reference range"><DeleteOutlineIcon fontSize="small" /></IconButton></Tooltip>
                                  )}
                                </TableCell>
                              </TableRow>
                            ))
                          )}
                        </TableBody>
                      </Table>
                    </TableContainer>

                    <Divider sx={{ my: 1.5 }} />
                    <Typography variant="caption" fontWeight={700} sx={{ display: 'block', mb: 1 }}>
                      {editingRange ? 'Edit Age & Gender Reference Interval' : 'Add Age & Gender Reference Interval'}
                    </Typography>
                    <Grid container spacing={1}>
                      <Grid item xs={4}>
                        <TextField
                          fullWidth
                          size="small"
                          select
                          label="Gender"
                          value={rangeForm.gender}
                          onChange={(e) => setRangeForm({ ...rangeForm, gender: e.target.value })}
                        >
                          <MenuItem value="All">All</MenuItem>
                          <MenuItem value="Male">Male</MenuItem>
                          <MenuItem value="Female">Female</MenuItem>
                        </TextField>
                      </Grid>
                      <Grid item xs={4}>
                        <TextField fullWidth size="small" label="Age Min (Years)" type="number" value={rangeForm.age_min_years} onChange={(e) => setRangeForm({ ...rangeForm, age_min_years: Number(e.target.value) })} inputProps={{ min: 0, step: 0.1 }} />
                      </Grid>
                      <Grid item xs={4}>
                        <TextField fullWidth size="small" label="Age Max (Years)" type="number" value={rangeForm.age_max_years} onChange={(e) => setRangeForm({ ...rangeForm, age_max_years: Number(e.target.value) })} inputProps={{ min: 0, step: 0.1 }} />
                      </Grid>
                      <Grid item xs={4}>
                        <TextField
                          fullWidth
                          size="small"
                          label="Normal Min"
                          type="number"
                          value={rangeForm.normal_min}
                          onChange={(e) => setRangeForm({ ...rangeForm, normal_min: e.target.value })}
                        />
                      </Grid>
                      <Grid item xs={4}>
                        <TextField
                          fullWidth
                          size="small"
                          label="Normal Max"
                          type="number"
                          value={rangeForm.normal_max}
                          onChange={(e) => setRangeForm({ ...rangeForm, normal_max: e.target.value })}
                        />
                      </Grid>
                      <Grid item xs={6}>
                        <TextField
                          fullWidth
                          size="small"
                          label="Critical Low Alert"
                          type="number"
                          value={rangeForm.critical_low}
                          onChange={(e) => setRangeForm({ ...rangeForm, critical_low: e.target.value })}
                        />
                      </Grid>
                      <Grid item xs={6}>
                        <TextField fullWidth size="small" label="Unit" value={rangeForm.unit} onChange={(e) => setRangeForm({ ...rangeForm, unit: e.target.value })} />
                      </Grid>
                      <Grid item xs={6}>
                        <TextField fullWidth size="small" label="Method" value={rangeForm.method} onChange={(e) => setRangeForm({ ...rangeForm, method: e.target.value })} />
                      </Grid>
                      <Grid item xs={12}>
                        <TextField fullWidth size="small" label="Qualitative / Reference Text" value={rangeForm.normal_text} onChange={(e) => setRangeForm({ ...rangeForm, normal_text: e.target.value })} placeholder="e.g. Negative or laboratory-defined interpretive range" />
                      </Grid>
                      <Grid item xs={6}>
                        <TextField
                          fullWidth
                          size="small"
                          label="Critical High Alert"
                          type="number"
                          value={rangeForm.critical_high}
                          onChange={(e) => setRangeForm({ ...rangeForm, critical_high: e.target.value })}
                        />
                      </Grid>
                      <Grid item xs={12}>
                        <Button variant="outlined" size="small" onClick={handleSaveRange}>
                          {editingRange ? 'Update as Unvalidated Draft' : 'Add Unvalidated Draft'}
                        </Button>
                        {editingRange && <Button size="small" onClick={() => handleSelectParamForRanges(selectedParamForRanges)}>Cancel Edit</Button>}
                      </Grid>
                    </Grid>
                  </>
                ) : (
                  <Alert severity="info">Click "Ranges" on any parameter to view or add biological reference intervals.</Alert>
                )}
              </Grid>
            </Grid>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setParamDialogOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>

      {/* Dialog 3: Bulk Profile Reference Range Editor */}
      <BulkReferenceRangeEditor
        open={bulkEditorOpen}
        onClose={() => setBulkEditorOpen(false)}
        test={selectedTestForBulk}
        onSaved={loadTests}
      />

      {/* Dialog 4: CSV Import / Export Modal */}
      <ReferenceRangeCsvModal
        open={csvModalOpen}
        onClose={() => setCsvModalOpen(false)}
        onImportCompleted={loadTests}
      />

      {/* Dialog 5: Laboratory Clinical Approval Governance Dialog */}
      <Dialog
        open={Boolean(validatingTest)}
        onClose={() => !validationBusy && setValidatingTest(null)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle sx={{ fontWeight: 800 }}>
          Laboratory Clinical Approval &amp; Governance: {validatingTest?.code} — {validatingTest?.name}
        </DialogTitle>
        <DialogContent dividers>
          {validatingTest && (
            <Stack spacing={2.5}>
              <Box sx={{ display: 'flex', gap: 1, alignItems: 'center', flexWrap: 'wrap' }}>
                <Chip
                  label={validatingTest.validation_status === 'VALIDATED' ? 'LAB APPROVED & VALIDATED' : 'PROPOSED DRAFT / AWAITING LAB APPROVAL'}
                  color={validatingTest.validation_status === 'VALIDATED' ? 'success' : 'warning'}
                />
                <Chip
                  label={validatingTest.is_active && validatingTest.lifecycle_status === 'Active' ? 'OPERATIONAL: ACTIVE' : 'OPERATIONAL: INACTIVE / NON-ORDERABLE'}
                  color={validatingTest.is_active && validatingTest.lifecycle_status === 'Active' ? 'success' : 'default'}
                />
                <Chip label={`Department: ${validatingTest.department}`} variant="outlined" />
                <Chip label={`Price: NPR ${paisaToRupees(validatingTest.price_paisa || 0)}`} variant="outlined" />
              </Box>

              <Card variant="outlined">
                <CardContent sx={{ py: 1.5, '&:last-child': { pb: 1.5 } }}>
                  <Typography variant="subtitle2" fontWeight={700} color="text.secondary" gutterBottom>
                    Proposed Clinical Configuration (Awaiting Lab Authorization)
                  </Typography>
                  <Grid container spacing={2}>
                    <Grid item xs={12} sm={4}>
                      <Typography variant="caption" color="text.secondary">Specimen Type</Typography>
                      <Typography variant="body2" fontWeight={600}>{validatingTest.sample_type || '—'}</Typography>
                    </Grid>
                    <Grid item xs={12} sm={4}>
                      <Typography variant="caption" color="text.secondary">Container</Typography>
                      <Typography variant="body2" fontWeight={600}>{validatingTest.container || '—'}</Typography>
                    </Grid>
                    <Grid item xs={12} sm={4}>
                      <Typography variant="caption" color="text.secondary">Analytical Method</Typography>
                      <Typography variant="body2" fontWeight={600}>{validatingTest.method || 'Standard Clinical Method'}</Typography>
                    </Grid>
                    <Grid item xs={12} sm={4}>
                      <Typography variant="caption" color="text.secondary">Turnaround Time</Typography>
                      <Typography variant="body2" fontWeight={600}>{validatingTest.tat_hours || 24} Hours</Typography>
                    </Grid>
                    <Grid item xs={12} sm={4}>
                      <Typography variant="caption" color="text.secondary">Reporting Tier</Typography>
                      <Typography variant="body2" fontWeight={600}>{validatingTest.reporting_type}</Typography>
                    </Grid>
                    <Grid item xs={12} sm={4}>
                      <Typography variant="caption" color="text.secondary">Test Kind</Typography>
                      <Typography variant="body2" fontWeight={600}>{validatingTest.test_kind}</Typography>
                    </Grid>
                  </Grid>
                </CardContent>
              </Card>

              <Box>
                <Typography variant="subtitle2" fontWeight={700} gutterBottom>
                  Parameters &amp; Calculation Definitions ({validatingTest.parameters?.length || 0})
                </Typography>
                <TableContainer component={Paper} variant="outlined">
                  <Table size="small">
                    <TableHead>
                      <TableRow sx={{ bgcolor: 'action.hover' }}>
                        <TableCell>Code</TableCell>
                        <TableCell>Parameter Name</TableCell>
                        <TableCell>Result Type</TableCell>
                        <TableCell>Unit</TableCell>
                        <TableCell>Calculation / Formula</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {(validatingTest.parameters || []).map((p) => (
                        <TableRow key={p.id}>
                          <TableCell sx={{ fontWeight: 600 }}>{p.code}</TableCell>
                          <TableCell>{p.name}</TableCell>
                          <TableCell><Chip size="small" label={p.value_type} variant="outlined" /></TableCell>
                          <TableCell>{p.unit || '—'}</TableCell>
                          <TableCell>
                            {p.value_type === 'Calculated' ? (
                              <Typography variant="caption" color="primary.main" fontWeight={600}>
                                {p.formula || p.calculation_identifier || 'Governed calculation engine'}
                              </Typography>
                            ) : (
                              'Direct Measurement'
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                      {(!validatingTest.parameters || validatingTest.parameters.length === 0) && (
                        <TableRow>
                          <TableCell colSpan={5} align="center" sx={{ color: 'text.secondary', py: 2 }}>
                            No parameters attached.
                          </TableCell>
                        </TableRow>
                      )}
                    </TableBody>
                  </Table>
                </TableContainer>
              </Box>

              {/* Formal Laboratory Approval Form */}
              <Card variant="outlined" sx={{ bgcolor: '#f8fafc', borderColor: '#cbd5e1' }}>
                <CardContent sx={{ py: 2, '&:last-child': { pb: 2 } }}>
                  <Typography variant="subtitle2" fontWeight={800} color="primary.main" gutterBottom>
                    Formal Laboratory Clinical Sign-Off &amp; Metadata
                  </Typography>
                  <Typography variant="caption" color="text.secondary" display="block" sx={{ mb: 2 }}>
                    Authorized laboratory leadership must document analyzer, reagent, reference range authority, and clinical policy before activation.
                  </Typography>
                  <Grid container spacing={2}>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        fullWidth
                        size="small"
                        label="Analyzer / Instrument Model"
                        placeholder="e.g. Sysmex XN-350 / Cobas c311 / Mindray BS-240"
                        value={approvalForm.analyzer_model}
                        onChange={(e) => setApprovalForm({ ...approvalForm, analyzer_model: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        fullWidth
                        size="small"
                        label="Reagent / Kit Manufacturer"
                        placeholder="e.g. Roche Diagnostics / ERBA / Bio-Rad"
                        value={approvalForm.reagent_manufacturer}
                        onChange={(e) => setApprovalForm({ ...approvalForm, reagent_manufacturer: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        fullWidth
                        size="small"
                        label="Analytical Method Specification"
                        placeholder="e.g. GOD-POD / ISE / Westergren / CLIA"
                        value={approvalForm.method}
                        onChange={(e) => setApprovalForm({ ...approvalForm, method: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        fullWidth
                        size="small"
                        type="date"
                        label="Effective From Date"
                        InputLabelProps={{ shrink: true }}
                        value={approvalForm.effective_from}
                        onChange={(e) => setApprovalForm({ ...approvalForm, effective_from: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12}>
                      <TextField
                        fullWidth
                        size="small"
                        required
                        label="Reference Range Source / Authority"
                        placeholder="e.g. Reagent Kit Insert (Lot #12345), Tietz Textbook, WHO Guidelines 2024"
                        value={approvalForm.reference_range_source}
                        onChange={(e) => setApprovalForm({ ...approvalForm, reference_range_source: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12}>
                      <TextField
                        fullWidth
                        size="small"
                        label="Critical Limit (Panic Value) Policy / Source"
                        placeholder="e.g. Bimal Lab Standard Critical Notification SOP-CL-04"
                        value={approvalForm.critical_limit_source}
                        onChange={(e) => setApprovalForm({ ...approvalForm, critical_limit_source: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12}>
                      <TextField
                        fullWidth
                        multiline
                        rows={2}
                        size="small"
                        label="Laboratory Director / Pathologist Approval Notes"
                        placeholder="Document verification evidence, correlation studies, or approval justifications..."
                        value={approvalForm.approval_notes}
                        onChange={(e) => setApprovalForm({ ...approvalForm, approval_notes: e.target.value })}
                      />
                    </Grid>
                  </Grid>
                </CardContent>
              </Card>

              {/* Past Approvals History */}
              {pastApprovals.length > 0 && (
                <Box>
                  <Typography variant="subtitle2" fontWeight={700} gutterBottom>
                    Laboratory Approval Audit History
                  </Typography>
                  <TableContainer component={Paper} variant="outlined">
                    <Table size="small">
                      <TableHead>
                        <TableRow sx={{ bgcolor: 'action.hover' }}>
                          <TableCell>Version</TableCell>
                          <TableCell>Approved By</TableCell>
                          <TableCell>Date</TableCell>
                          <TableCell>Analyzer</TableCell>
                          <TableCell>Reference Source</TableCell>
                          <TableCell>Status</TableCell>
                        </TableRow>
                      </TableHead>
                      <TableBody>
                        {pastApprovals.map((app) => (
                          <TableRow key={app.id}>
                            <TableCell>v{app.version}</TableCell>
                            <TableCell>{app.approved_by_name}</TableCell>
                            <TableCell>{formatAdDate(app.approved_at)}</TableCell>
                            <TableCell>{app.analyzer_model || '—'}</TableCell>
                            <TableCell>{app.reference_range_source || '—'}</TableCell>
                            <TableCell>
                              <Chip
                                size="small"
                                label={app.approval_status}
                                color={app.approval_status === 'APPROVED' ? 'success' : 'default'}
                                variant="outlined"
                              />
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </TableContainer>
                </Box>
              )}

              {validatingTest.validation_status === 'REQUIRES_VALIDATION' ? (
                <Alert severity="warning">
                  <strong>Clinical Status: PROPOSED DRAFT (Requires Lab Approval)</strong><br />
                  This test cannot be enabled for patient billing or clinical reporting until laboratory leadership formally signs off with documented reference sources and analytical methods.
                </Alert>
              ) : (
                <Alert severity="success">
                  <strong>Clinical Status: LAB APPROVED &amp; VALIDATED</strong><br />
                  This test configuration is certified by laboratory leadership. It can be activated for routine patient ordering.
                </Alert>
              )}
            </Stack>
          )}
        </DialogContent>
        <DialogActions sx={{ px: 3, py: 2 }}>
          <Button onClick={() => setValidatingTest(null)} disabled={validationBusy}>
            Close
          </Button>
          {validatingTest?.validation_status === 'VALIDATED' ? (
            <Button
              variant="outlined"
              color="error"
              onClick={handleRevertConfirm}
              disabled={validationBusy}
            >
              Revert to Unapproved Draft (Requires Lab Review)
            </Button>
          ) : (
            <Button
              variant="contained"
              color="primary"
              onClick={handleApproveConfirm}
              disabled={validationBusy}
            >
              Authorize &amp; Approve for Activation
            </Button>
          )}
        </DialogActions>
      </Dialog>

      {/* Dialog 6: Bulk Laboratory Clinical Approval Governance Dialog */}
      <Dialog
        open={Boolean(bulkValidatingTests && bulkValidatingTests.length > 0)}
        onClose={() => !validationBusy && setBulkValidatingTests(null)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle sx={{ fontWeight: 800 }}>
          Bulk Laboratory Clinical Approval ({bulkValidatingTests?.length || 0} Tests Selected)
        </DialogTitle>
        <DialogContent dividers>
          {bulkValidatingTests && (
            <Stack spacing={2.5}>
              <Alert severity="info">
                You are performing formal clinical sign-off for <strong>{bulkValidatingTests.length} tests</strong> simultaneously. The database will enforce result-type readiness on every test before advancing state to <strong>VALIDATED</strong>.
              </Alert>

              <Box sx={{ display: 'flex', gap: 0.5, flexWrap: 'wrap', maxHeight: 100, overflowY: 'auto', p: 1, border: '1px solid #e2e8f0', borderRadius: 1 }}>
                {bulkValidatingTests.map((t) => (
                  <Chip key={t.id} size="small" label={`${t.code} (${t.name})`} />
                ))}
              </Box>

              <Card variant="outlined" sx={{ bgcolor: '#f8fafc', borderColor: '#cbd5e1' }}>
                <CardContent sx={{ py: 2, '&:last-child': { pb: 2 } }}>
                  <Typography variant="subtitle2" fontWeight={800} color="primary.main" gutterBottom>
                    Laboratory Clinical Metadata to Apply
                  </Typography>
                  <Grid container spacing={2}>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        fullWidth
                        size="small"
                        label="Analyzer / Instrument Model"
                        placeholder="e.g. Sysmex XN-350 / Cobas c311 / Mindray BS-240"
                        value={approvalForm.analyzer_model}
                        onChange={(e) => setApprovalForm({ ...approvalForm, analyzer_model: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        fullWidth
                        size="small"
                        label="Reagent / Kit Manufacturer"
                        placeholder="e.g. Roche Diagnostics / ERBA / Bio-Rad"
                        value={approvalForm.reagent_manufacturer}
                        onChange={(e) => setApprovalForm({ ...approvalForm, reagent_manufacturer: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        fullWidth
                        size="small"
                        label="Analytical Method Specification"
                        placeholder="e.g. Standard Spectrophotometry / ISE / Automated Hematology"
                        value={approvalForm.method}
                        onChange={(e) => setApprovalForm({ ...approvalForm, method: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        fullWidth
                        size="small"
                        type="date"
                        label="Effective From Date"
                        InputLabelProps={{ shrink: true }}
                        value={approvalForm.effective_from}
                        onChange={(e) => setApprovalForm({ ...approvalForm, effective_from: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12}>
                      <TextField
                        fullWidth
                        size="small"
                        required
                        label="Reference Range Source / Authority"
                        placeholder="e.g. Manufacturer Kit Insert, Tietz Textbook of Clinical Chemistry 7th Ed, WHO 2024"
                        value={approvalForm.reference_range_source}
                        onChange={(e) => setApprovalForm({ ...approvalForm, reference_range_source: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12}>
                      <TextField
                        fullWidth
                        size="small"
                        label="Critical Limit (Panic Value) Policy / Source"
                        placeholder="e.g. Bimal Lab Standard Critical Notification SOP-CL-04"
                        value={approvalForm.critical_limit_source}
                        onChange={(e) => setApprovalForm({ ...approvalForm, critical_limit_source: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12}>
                      <TextField
                        fullWidth
                        multiline
                        rows={2}
                        size="small"
                        label="Laboratory Director / Pathologist Approval Notes"
                        placeholder="Document batch verification evidence, correlation studies, or approval notes..."
                        value={approvalForm.approval_notes}
                        onChange={(e) => setApprovalForm({ ...approvalForm, approval_notes: e.target.value })}
                      />
                    </Grid>
                  </Grid>
                </CardContent>
              </Card>
            </Stack>
          )}
        </DialogContent>
        <DialogActions sx={{ px: 3, py: 2 }}>
          <Button onClick={() => setBulkValidatingTests(null)} disabled={validationBusy}>
            Cancel
          </Button>
          <Button
            variant="contained"
            color="warning"
            onClick={handleBulkApproveConfirm}
            disabled={validationBusy || !approvalForm.reference_range_source.trim()}
          >
            Formally Approve All {bulkValidatingTests?.length || 0} Selected Tests
          </Button>
        </DialogActions>
      </Dialog>

      {/* Dialog 7: Adopt Standard Clinical Presets Dialog (Requirement #5) */}
      <Dialog
        open={adoptPresetsDialogOpen}
        onClose={() => !adoptBusy && setAdoptPresetsDialogOpen(false)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle sx={{ fontWeight: 800 }}>
          Adopt Standard Clinical Presets ({adoptPresetsTests?.length || 0} Tests Selected)
        </DialogTitle>
        <DialogContent dividers>
          {adoptPresetsTests && (
            <Stack spacing={2.5}>
              <Alert severity="warning">
                <strong>Clinical Responsibility Warning:</strong> Adopting standard presets certifies that the laboratory assumes responsibility for these baseline reference intervals, standardized analytical methods, specimen requirements, and critical limit policies.
                <br />
                <strong>Post-Adoption State:</strong> Tests will transition from <code>STANDARD_PRESET</code> &rarr; <code>LAB_APPROVED</code> &rarr; <code>VALIDATED</code>. Tests will remain <strong>INACTIVE / Non-orderable</strong> until explicitly activated in a separate step.
              </Alert>

              <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0' }}>
                <Typography variant="subtitle2" fontWeight={800} color="primary.main" gutterBottom>
                  Standard Preset Specification &amp; Equipment Baseline
                </Typography>
                <Grid container spacing={2}>
                  <Grid item xs={12} sm={6}>
                    <Typography variant="caption" color="text.secondary">Configuration Source</Typography>
                    <Typography variant="body2" fontWeight={700}>STANDARD_PRESET (Library v1.0)</Typography>
                  </Grid>
                  <Grid item xs={12} sm={6}>
                    <Typography variant="caption" color="text.secondary">Biological Reference Range Source</Typography>
                    <Typography variant="body2" fontWeight={700}>Standard Clinical Presets Library</Typography>
                  </Grid>
                  <Grid item xs={12} sm={6}>
                    <Typography variant="caption" color="text.secondary">Analyzer Instrument Model</Typography>
                    <Typography variant="body2" sx={{ color: 'text.secondary', fontStyle: 'italic' }}>
                      NULL (Unresolved — To be confirmed with physical lab equipment)
                    </Typography>
                  </Grid>
                  <Grid item xs={12} sm={6}>
                    <Typography variant="caption" color="text.secondary">Reagent Kit Manufacturer</Typography>
                    <Typography variant="body2" sx={{ color: 'text.secondary', fontStyle: 'italic' }}>
                      NULL (Unresolved — To be confirmed with kit lot numbers)
                    </Typography>
                  </Grid>
                </Grid>
              </Box>

              <Typography variant="subtitle2" fontWeight={700}>
                Selected Tests for Standard Preset Adoption ({adoptPresetsTests.length}):
              </Typography>
              <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', maxHeight: 250 }}>
                <Table size="small" stickyHeader>
                  <TableHead sx={{ bgcolor: '#f1f5f9' }}>
                    <TableRow>
                      <TableCell>Code</TableCell>
                      <TableCell>Test Name</TableCell>
                      <TableCell>Department</TableCell>
                      <TableCell>Preset Method</TableCell>
                      <TableCell>Specimen / Container</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {adoptPresetsTests.map((t) => (
                      <TableRow key={t.id} hover>
                        <TableCell sx={{ fontWeight: 700 }}>{t.code}</TableCell>
                        <TableCell>{t.name}</TableCell>
                        <TableCell>{t.department}</TableCell>
                        <TableCell>{t.method || 'Standardized Method'}</TableCell>
                        <TableCell>{t.sample_type || 'Standard'} / {t.container || 'Standard'}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>

              <TextField
                fullWidth
                multiline
                rows={2}
                size="small"
                label="Laboratory Approver Adoption Notes"
                value={adoptApprovalNotes}
                onChange={(e) => setAdoptApprovalNotes(e.target.value)}
                placeholder="Enter clinical adoption notes..."
              />
            </Stack>
          )}
        </DialogContent>
        <DialogActions sx={{ px: 3, py: 2 }}>
          <Button onClick={() => setAdoptPresetsDialogOpen(false)} disabled={adoptBusy}>
            Cancel
          </Button>
          <Button
            variant="contained"
            color="primary"
            onClick={handleAdoptPresetsConfirm}
            disabled={adoptBusy || !adoptApprovalNotes.trim()}
          >
            Adopt Standard Presets &amp; Validate ({adoptPresetsTests?.length || 0})
          </Button>
        </DialogActions>
      </Dialog>

      <SmartMessageDialog open={Boolean(confirmAction)} variant="confirm" message={confirmAction?.message || ''} guidance={confirmAction?.guidance} primaryLabel="Confirm" onPrimary={runConfirmed} onSecondary={() => setConfirmAction(null)} busy={actionBusy} />
    </Box>
  );
};
