import React, { useState, useEffect, useCallback } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Tabs,
  Tab,
  Box,
  Typography,
  TextField,
  Button,
  Grid,
  MenuItem,
  FormControlLabel,
  Switch,
  Alert,
  IconButton,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Chip,
  Stack,
  Divider,
  CircularProgress,
} from '@mui/material';
import CloseIcon from '@mui/icons-material/Close';
import SaveIcon from '@mui/icons-material/Save';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import ArchiveIcon from '@mui/icons-material/Archive';
import UnarchiveIcon from '@mui/icons-material/Unarchive';
import DeleteForeverIcon from '@mui/icons-material/DeleteForever';
import AddIcon from '@mui/icons-material/Add';
import EditIcon from '@mui/icons-material/Edit';
import ArrowUpwardIcon from '@mui/icons-material/ArrowUpward';
import ArrowDownwardIcon from '@mui/icons-material/ArrowDownward';
import HistoryIcon from '@mui/icons-material/History';
import TuneIcon from '@mui/icons-material/Tune';
import ScienceIcon from '@mui/icons-material/Science';
import MonetizationOnIcon from '@mui/icons-material/MonetizationOn';
import LabelIcon from '@mui/icons-material/Label';
import ViewListIcon from '@mui/icons-material/ViewList';
import DevicesIcon from '@mui/icons-material/Devices';

import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { rupeesToPaisa, paisaToRupees } from '@/lib/currency';
import { formatAdDate } from '@/lib/dateTime';

export interface DbTestForEditor {
  id: string;
  code: string;
  name: string;
  short_name?: string | null;
  department: string;
  category: string;
  category_id?: string | null;
  test_kind: 'Individual' | 'Profile';
  reporting_type: string;
  outsource_lab_name?: string | null;
  price_paisa: number;
  sample_type: string;
  container: string;
  sample_volume?: string | null;
  method?: string | null;
  tat_hours?: number | null;
  display_order: number;
  description?: string | null;
  configuration_notes?: string | null;
  is_active: boolean;
  lifecycle_status: 'Draft' | 'Active' | 'Archived';
  billing_enabled?: boolean;
  price_configured?: boolean;
  allow_zero_price_billing?: boolean;
  allow_manual_price?: boolean;
  pricing_policy?: 'Fixed' | 'Negotiable' | 'PricePending' | 'Manual';
  search_aliases?: string[];
  row_version: number;
}

export interface DbParameterForEditor {
  id: string;
  test_id: string;
  code: string;
  name: string;
  value_type: 'Numeric' | 'Text' | 'Select' | 'Calculated' | 'Heading';
  unit?: string | null;
  options?: any;
  formula?: string | null;
  calculation_identifier?: string | null;
  decimal_precision?: number | null;
  display_order: number;
  is_mandatory: boolean;
  is_active: boolean;
  lifecycle_status: 'Draft' | 'Active' | 'Archived';
  row_version: number;
  interpretation_config?: any;
}

export interface DbRefRangeForEditor {
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
  row_version?: number;
}

interface EasyTestEditorDialogProps {
  open: boolean;
  test: DbTestForEditor | null; // null for creating a new test
  categories: Array<{ id: string; name: string; department?: string }>;
  allTests: Array<{ id: string; code: string; name: string; department: string }>;
  onClose: () => void;
  onSaved: (savedTest: any) => void;
}

const DEPARTMENTS = [
  'Hematology',
  'Clinical Biochemistry',
  'Immunology & Serology',
  'Clinical Pathology',
  'Microbiology',
  'Histopathology',
  'Cytology',
  'Molecular Biology',
];

const SPECIMEN_TYPES = [
  'Whole Blood',
  'Blood / Serum',
  'Plasma (Citrate)',
  'Plasma (EDTA)',
  'Plasma (Heparin)',
  'Urine (Spot / Routine)',
  'Urine (24 Hours)',
  'Stool',
  'Sputum',
  'Synovial Fluid',
  'Pleural Fluid',
  'CSF',
  'Swab',
  'Tissue / Biopsy',
  'Semen',
];

const CONTAINER_TYPES = [
  'EDTA / Lavender Top',
  'Yellow Top (SST / Gel)',
  'Red Top (Plain Tube)',
  'Blue Top (Sodium Citrate)',
  'Grey Top (Sodium Fluoride)',
  'Green Top (Sodium Heparin)',
  'Sterile Urine Container',
  'Sterile Stool Container',
  'Sterile Swab Container',
  'Formalin Container (10%)',
];

export const EasyTestEditorDialog: React.FC<EasyTestEditorDialogProps> = ({
  open,
  test,
  categories,
  allTests: _allTests,
  onClose,
  onSaved,
}) => {
  const [activeTab, setActiveTab] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  // General Master Form State
  const [generalForm, setGeneralForm] = useState({
    code: '',
    name: '',
    short_name: '',
    department: 'Hematology',
    category: 'Routine Hematology',
    category_id: '',
    test_kind: 'Individual' as 'Individual' | 'Profile',
    reporting_type: 'InHouse',
    outsource_lab_name: '',
    price_npr: '0',
    sample_type: 'Whole Blood',
    container: 'EDTA / Lavender Top',
    sample_volume: '',
    method: '',
    tat_hours: 24,
    display_order: 0,
    description: '',
    configuration_notes: '',
    is_active: true,
    billing_enabled: true,
    allow_zero_price_billing: false,
    allow_manual_price: false,
    pricing_policy: 'Fixed' as 'Fixed' | 'Negotiable' | 'PricePending' | 'Manual',
  });

  // Aliases State
  const [aliases, setAliases] = useState<string[]>([]);
  const [newAliasInput, setNewAliasInput] = useState('');

  // Parameters State
  const [parameters, setParameters] = useState<DbParameterForEditor[]>([]);
  const [paramLoading, setParamLoading] = useState(false);
  const [paramDialogOpen, setParamDialogOpen] = useState(false);
  const [editingParam, setEditingParam] = useState<DbParameterForEditor | null>(null);
  const [paramForm, setParamForm] = useState({
    code: '',
    name: '',
    value_type: 'Numeric' as 'Numeric' | 'Text' | 'Select' | 'Calculated' | 'Heading',
    unit: '',
    formula: '',
    calculation_identifier: '',
    decimal_precision: 2,
    display_order: 1,
    is_mandatory: true,
    is_active: true,
    options: [] as string[],
    newOptionInput: '',
  });

  // Reference Ranges State
  const [refRanges, setRefRanges] = useState<DbRefRangeForEditor[]>([]);
  const [rangeDialogOpen, setRangeDialogOpen] = useState(false);
  const [editingRange, setEditingRange] = useState<DbRefRangeForEditor | null>(null);
  const [rangeFilterParamId, setRangeFilterParamId] = useState<string>('All');
  const [rangeForm, setRangeForm] = useState({
    parameter_id: '',
    gender: 'All',
    age_min_years: '0',
    age_max_years: '120',
    normal_min: '',
    normal_max: '',
    critical_low: '',
    critical_high: '',
    normal_text: '',
    reference_text: '',
    method: '',
    unit: '',
    is_active: true,
  });

  // Rate History State
  const [rateHistory, setRateHistory] = useState<any[]>([]);

  // Analyzer Mapping State
  const [analyzers, setAnalyzers] = useState<any[]>([]);
  const [analyzerMappings, setAnalyzerMappings] = useState<any[]>([]);
  const [mappingDialogOpen, setMappingDialogOpen] = useState(false);
  const [mappingForm, setMappingForm] = useState({
    id: '',
    analyzer_id: '',
    channel_code: '',
    channel_name: '',
    parameter_id: '',
    measurement_type: 'DIRECT_MEASURED',
    analytical_method: 'Automated',
    unit: '',
    differential_type: 'Not Applicable',
  });

  // Audit History State
  const [auditHistory, setAuditHistory] = useState<any[]>([]);

  // Duplicate / Clone Dialog State
  const [cloneDialogOpen, setCloneDialogOpen] = useState(false);
  const [cloneForm, setCloneForm] = useState({ code: '', name: '', price_npr: '0' });

  // Delete Confirmation State
  const [deleteConfirmOpen, setDeleteConfirmOpen] = useState(false);

  const loadTestData = useCallback(async (testId: string) => {
    setParamLoading(true);
    try {
      const [pRes, rateRes, analyzerRes, mappingsRes, auditRes] = await Promise.all([
        supabase
          .from('parameters')
          .select('*, reference_ranges(*)')
          .eq('test_id', testId)
          .order('display_order', { ascending: true }),
        supabase
          .from('catalogue_rate_versions')
          .select('*')
          .eq('test_id', testId)
          .order('created_at', { ascending: false }),
        supabase.from('analyzers').select('*').order('name'),
        supabase.from('analyzer_parameter_mappings').select('*, analyzers(name, code)').eq('test_id', testId),
        supabase.rpc('catalogue_get_test_history', { p_test_id: testId }),
      ]);

      if (pRes.data) {
        setParameters(pRes.data);
        const allRanges: DbRefRangeForEditor[] = [];
        pRes.data.forEach((p: any) => {
          if (p.reference_ranges) {
            allRanges.push(...p.reference_ranges);
          }
        });
        setRefRanges(allRanges);
      }
      if (rateRes.data) setRateHistory(rateRes.data);
      if (analyzerRes.data) setAnalyzers(analyzerRes.data);
      if (mappingsRes.data) setAnalyzerMappings(mappingsRes.data);
      if (auditRes.data) setAuditHistory(auditRes.data);
    } catch (err: any) {
      console.error('[EasyTestEditor] Error loading child data:', err);
    } finally {
      setParamLoading(false);
    }
  }, []);

  // Initialize or reset form when test changes
  useEffect(() => {
    if (!open) return;
    setError(null);
    setSuccess(null);
    setActiveTab(0);

    if (test) {
      setGeneralForm({
        code: test.code,
        name: test.name,
        short_name: test.short_name || '',
        department: test.department || 'Hematology',
        category: test.category || 'General',
        category_id: test.category_id || '',
        test_kind: test.test_kind || 'Individual',
        reporting_type: test.reporting_type || 'InHouse',
        outsource_lab_name: test.outsource_lab_name || '',
        price_npr: String(paisaToRupees(test.price_paisa)),
        sample_type: test.sample_type || 'Whole Blood',
        container: test.container || 'EDTA / Lavender Top',
        sample_volume: test.sample_volume || '',
        method: test.method || '',
        tat_hours: test.tat_hours ?? 24,
        display_order: test.display_order ?? 0,
        description: test.description || '',
        configuration_notes: test.configuration_notes || '',
        is_active: test.is_active !== false,
        billing_enabled: test.billing_enabled !== false,
        allow_zero_price_billing: Boolean(test.allow_zero_price_billing),
        allow_manual_price: Boolean(test.allow_manual_price),
        pricing_policy: test.pricing_policy || 'Fixed',
      });
      setAliases(test.search_aliases || []);
      loadTestData(test.id);
    } else {
      setGeneralForm({
        code: '',
        name: '',
        short_name: '',
        department: 'Hematology',
        category: 'Routine Hematology',
        category_id: categories[0]?.id || '',
        test_kind: 'Individual',
        reporting_type: 'InHouse',
        outsource_lab_name: '',
        price_npr: '0',
        sample_type: 'Whole Blood',
        container: 'EDTA / Lavender Top',
        sample_volume: '',
        method: '',
        tat_hours: 24,
        display_order: 0,
        description: '',
        configuration_notes: '',
        is_active: true,
        billing_enabled: true,
        allow_zero_price_billing: false,
        allow_manual_price: false,
        pricing_policy: 'Fixed',
      });
      setAliases([]);
      setParameters([]);
      setRefRanges([]);
      setRateHistory([]);
      setAnalyzerMappings([]);
      setAuditHistory([]);
    }
  }, [open, test, categories, loadTestData]);

  const handleSaveMapping = async () => {
    if (!test?.id) return;
    if (!mappingForm.analyzer_id || !mappingForm.channel_code.trim() || !mappingForm.channel_name.trim()) {
      setError('Analyzer, Channel Code, and Channel Name are required.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const payload = {
        id: mappingForm.id || null,
        analyzer_id: mappingForm.analyzer_id,
        channel_code: mappingForm.channel_code.trim().toUpperCase(),
        channel_name: mappingForm.channel_name.trim(),
        test_id: test.id,
        parameter_id: mappingForm.parameter_id || null,
        measurement_type: mappingForm.measurement_type,
        analytical_method: mappingForm.analytical_method.trim() || 'Automated',
        unit: mappingForm.unit.trim() || null,
        differential_type: mappingForm.differential_type,
      };
      const { error: mapErr } = await supabase.rpc('catalogue_save_analyzer_mapping_easy', {
        p_mapping: payload,
      });
      if (mapErr) throw mapErr;
      setSuccess('Analyzer channel mapping saved.');
      setMappingDialogOpen(false);
      loadTestData(test.id);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to save analyzer channel mapping.'));
    } finally {
      setBusy(false);
    }
  };

  // Save General Master Test
  const handleSaveGeneral = async () => {
    if (!generalForm.code.trim()) {
      setError('Test code is required.');
      return;
    }
    if (!generalForm.name.trim()) {
      setError('Test name is required.');
      return;
    }

    setBusy(true);
    setError(null);
    try {
      const payload = {
        id: test?.id || null,
        code: generalForm.code.trim().toUpperCase(),
        name: generalForm.name.trim(),
        short_name: generalForm.short_name.trim() || null,
        department: generalForm.department,
        category: generalForm.category,
        category_id: generalForm.category_id || null,
        test_kind: generalForm.test_kind,
        reporting_type: generalForm.reporting_type,
        outsource_lab_name: generalForm.reporting_type === 'OutsourceWithBimalReport' ? generalForm.outsource_lab_name.trim() : null,
        price_paisa: rupeesToPaisa(generalForm.price_npr),
        sample_type: generalForm.sample_type,
        container: generalForm.container,
        sample_volume: generalForm.sample_volume.trim() || null,
        method: generalForm.method.trim() || null,
        tat_hours: parseInt(String(generalForm.tat_hours), 10) || 24,
        display_order: parseInt(String(generalForm.display_order), 10) || 0,
        description: generalForm.description.trim() || null,
        configuration_notes: generalForm.configuration_notes.trim() || null,
        is_active: generalForm.is_active,
        billing_enabled: generalForm.billing_enabled,
        allow_zero_price_billing: generalForm.allow_zero_price_billing,
        allow_manual_price: generalForm.allow_manual_price,
        pricing_policy: generalForm.pricing_policy,
        search_aliases: aliases,
      };

      const { data, error: saveErr } = await supabase.rpc('catalogue_save_test_easy', {
        p_test: payload,
        p_expected_version: test?.row_version ?? null,
      });

      if (saveErr) throw saveErr;

      setSuccess('Test master configuration saved successfully.');
      onSaved(data);
      if (!test?.id && data?.id) {
        loadTestData(data.id);
      }
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to save test.'));
    } finally {
      setBusy(false);
    }
  };

  // Aliases Management
  const handleAddAlias = () => {
    const val = newAliasInput.trim().toLowerCase();
    if (!val) return;
    if (aliases.includes(val)) {
      setError('This alias is already added.');
      return;
    }
    setAliases([...aliases, val]);
    setNewAliasInput('');
  };

  const handleRemoveAlias = (aliasToRemove: string) => {
    setAliases(aliases.filter((a) => a !== aliasToRemove));
  };

  // Parameters Management
  const handleOpenAddParam = () => {
    setEditingParam(null);
    setParamForm({
      code: '',
      name: '',
      value_type: 'Numeric',
      unit: '',
      formula: '',
      calculation_identifier: '',
      decimal_precision: 2,
      display_order: parameters.length + 1,
      is_mandatory: true,
      is_active: true,
      options: [],
      newOptionInput: '',
    });
    setParamDialogOpen(true);
  };

  const handleOpenEditParam = (p: DbParameterForEditor) => {
    setEditingParam(p);
    let optList: string[] = [];
    if (Array.isArray(p.options)) {
      optList = p.options.map((o: any) => (typeof o === 'string' ? o : o.label || o.value || ''));
    }
    setParamForm({
      code: p.code,
      name: p.name,
      value_type: p.value_type,
      unit: p.unit || '',
      formula: p.formula || '',
      calculation_identifier: p.calculation_identifier || '',
      decimal_precision: p.decimal_precision ?? 2,
      display_order: p.display_order,
      is_mandatory: p.is_mandatory,
      is_active: p.is_active,
      options: optList,
      newOptionInput: '',
    });
    setParamDialogOpen(true);
  };

  const handleSaveParam = async () => {
    if (!test?.id) {
      setError('Please save the Test master first before adding parameters.');
      return;
    }
    if (!paramForm.code.trim() || !paramForm.name.trim()) {
      setError('Parameter code and name are required.');
      return;
    }

    setBusy(true);
    setError(null);
    try {
      const payload: any = {
        id: editingParam?.id || null,
        test_id: test.id,
        code: paramForm.code.trim().toUpperCase(),
        name: paramForm.name.trim(),
        value_type: paramForm.value_type,
        unit: paramForm.unit.trim() || null,
        formula: paramForm.value_type === 'Calculated' ? paramForm.formula.trim() : null,
        calculation_identifier: paramForm.value_type === 'Calculated' ? paramForm.calculation_identifier.trim() : null,
        decimal_precision: paramForm.value_type === 'Numeric' ? paramForm.decimal_precision : null,
        display_order: paramForm.display_order,
        is_mandatory: paramForm.is_mandatory,
        is_active: paramForm.is_active,
        options: paramForm.value_type === 'Select' ? paramForm.options : null,
      };

      const { error: pErr } = await supabase.rpc('catalogue_save_parameter_easy', {
        p_parameter: payload,
        p_expected_version: editingParam?.row_version ?? null,
      });
      if (pErr) throw pErr;

      setSuccess('Parameter saved successfully.');
      setParamDialogOpen(false);
      loadTestData(test.id);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to save parameter.'));
    } finally {
      setBusy(false);
    }
  };

  const handleMoveParam = async (index: number, direction: 'up' | 'down') => {
    if (!test?.id) return;
    const targetIdx = direction === 'up' ? index - 1 : index + 1;
    if (targetIdx < 0 || targetIdx >= parameters.length) return;

    const newParams = [...parameters];
    const [moved] = newParams.splice(index, 1);
    newParams.splice(targetIdx, 0, moved);

    const orderedIds = newParams.map((p) => p.id);
    setParameters(newParams);

    try {
      await supabase.rpc('catalogue_reorder_parameters_easy', {
        p_test_id: test.id,
        p_parameter_ids: orderedIds,
      });
      loadTestData(test.id);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to reorder parameters.'));
    }
  };

  const handleDeleteParam = async (p: DbParameterForEditor) => {
    if (!confirm(`Are you sure you want to delete parameter "${p.name}" (${p.code})?`)) return;
    setBusy(true);
    try {
      const { error: delErr } = await supabase.rpc('catalogue_delete_parameter_guarded', {
        p_parameter_id: p.id,
        p_expected_version: p.row_version,
      });
      if (delErr) throw delErr;
      setSuccess(`Parameter ${p.code} deleted.`);
      loadTestData(test!.id);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to delete parameter.'));
    } finally {
      setBusy(false);
    }
  };

  // Reference Ranges Management
  const handleOpenAddRange = (presetParamId?: string) => {
    setEditingRange(null);
    setRangeForm({
      parameter_id: presetParamId || (parameters[0]?.id || ''),
      gender: 'All',
      age_min_years: '0',
      age_max_years: '120',
      normal_min: '',
      normal_max: '',
      critical_low: '',
      critical_high: '',
      normal_text: '',
      reference_text: '',
      method: generalForm.method || '',
      unit: '',
      is_active: true,
    });
    setRangeDialogOpen(true);
  };

  const handleOpenEditRange = (r: DbRefRangeForEditor) => {
    setEditingRange(r);
    setRangeForm({
      parameter_id: r.parameter_id,
      gender: r.gender || 'All',
      age_min_years: String(Math.floor(r.age_min_days / 365)),
      age_max_years: String(Math.floor(r.age_max_days / 365)),
      normal_min: r.normal_min !== null && r.normal_min !== undefined ? String(r.normal_min) : '',
      normal_max: r.normal_max !== null && r.normal_max !== undefined ? String(r.normal_max) : '',
      critical_low: r.critical_low !== null && r.critical_low !== undefined ? String(r.critical_low) : '',
      critical_high: r.critical_high !== null && r.critical_high !== undefined ? String(r.critical_high) : '',
      normal_text: r.normal_text || '',
      reference_text: r.reference_text || '',
      method: r.method || '',
      unit: r.unit || '',
      is_active: r.is_active !== false,
    });
    setRangeDialogOpen(true);
  };

  const handleSaveRange = async () => {
    if (!rangeForm.parameter_id) {
      setError('Please select a parameter for this reference range.');
      return;
    }

    const minYears = parseFloat(rangeForm.age_min_years) || 0;
    const maxYears = parseFloat(rangeForm.age_max_years) || 120;
    if (minYears > maxYears) {
      setError('Minimum age cannot exceed maximum age.');
      return;
    }

    const normMin = rangeForm.normal_min ? parseFloat(rangeForm.normal_min) : null;
    const normMax = rangeForm.normal_max ? parseFloat(rangeForm.normal_max) : null;
    if (normMin !== null && normMax !== null && normMin > normMax) {
      setError('Normal minimum cannot exceed normal maximum.');
      return;
    }

    setBusy(true);
    setError(null);
    try {
      const payload = {
        id: editingRange?.id || null,
        parameter_id: rangeForm.parameter_id,
        gender: rangeForm.gender,
        age_min_days: Math.round(minYears * 365),
        age_max_days: Math.round(maxYears * 365),
        normal_min: normMin,
        normal_max: normMax,
        critical_low: rangeForm.critical_low ? parseFloat(rangeForm.critical_low) : null,
        critical_high: rangeForm.critical_high ? parseFloat(rangeForm.critical_high) : null,
        normal_text: rangeForm.normal_text.trim() || null,
        reference_text: rangeForm.reference_text.trim() || null,
        method: rangeForm.method.trim() || null,
        unit: rangeForm.unit.trim() || null,
        is_active: rangeForm.is_active,
      };

      const { error: rErr } = await supabase.rpc('catalogue_save_range_easy', {
        p_range: payload,
        p_expected_version: editingRange?.row_version ?? null,
      });
      if (rErr) throw rErr;

      setSuccess('Reference range saved.');
      setRangeDialogOpen(false);
      loadTestData(test!.id);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to save reference range.'));
    } finally {
      setBusy(false);
    }
  };

  const handleDeleteRange = async (r: DbRefRangeForEditor) => {
    if (!confirm('Are you sure you want to delete this reference range?')) return;
    setBusy(true);
    try {
      const { error: delErr } = await supabase.rpc('catalogue_delete_range_guarded', {
        p_range_id: r.id,
        p_expected_version: r.row_version ?? null,
      });
      if (delErr) throw delErr;
      setSuccess('Reference range deleted.');
      loadTestData(test!.id);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to delete reference range.'));
    } finally {
      setBusy(false);
    }
  };

  // Duplicate / Clone Action
  const handleOpenClone = () => {
    if (!test) return;
    setCloneForm({
      code: `${test.code}_COPY`,
      name: `${test.name} (Copy)`,
      price_npr: String(paisaToRupees(test.price_paisa)),
    });
    setCloneDialogOpen(true);
  };

  const handleExecuteClone = async () => {
    if (!cloneForm.code.trim() || !cloneForm.name.trim()) {
      setError('Please provide a unique code and name for the cloned test.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const { data: newId, error: cloneErr } = await supabase.rpc('catalogue_clone_test_easy', {
        p_source_test_id: test!.id,
        p_new_code: cloneForm.code.trim().toUpperCase(),
        p_new_name: cloneForm.name.trim(),
        p_new_price_paisa: rupeesToPaisa(cloneForm.price_npr),
      });
      if (cloneErr) throw cloneErr;

      setSuccess(`Test duplicated successfully as ${cloneForm.code}.`);
      setCloneDialogOpen(false);
      onSaved({ id: newId });
      loadTestData(newId);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to duplicate test.'));
    } finally {
      setBusy(false);
    }
  };

  // Hard Delete vs Archive Action
  const handleExecuteDelete = async () => {
    if (!test) return;
    setBusy(true);
    setError(null);
    try {
      const { error: delErr } = await supabase.rpc('catalogue_delete_test_guarded', {
        p_test_id: test.id,
        p_expected_version: test.row_version,
      });

      if (delErr) {
        if (delErr.code === '23503' || delErr.message.includes('Referenced')) {
          setError('Cannot delete permanently: This test is referenced in historical bills/orders/results. Archiving instead preserves audit immutability.');
          return;
        }
        throw delErr;
      }

      setSuccess(`Test ${test.code} deleted permanently.`);
      setDeleteConfirmOpen(false);
      onClose();
      onSaved(null);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to delete test.'));
    } finally {
      setBusy(false);
    }
  };

  const handleToggleArchive = async () => {
    if (!test) return;
    const newStatus = test.lifecycle_status === 'Active' ? 'Archived' : 'Active';
    setBusy(true);
    try {
      const { error: statusErr } = await supabase.rpc('catalogue_set_test_lifecycle', {
        p_test_id: test.id,
        p_status: newStatus,
        p_expected_version: test.row_version,
      });
      if (statusErr) throw statusErr;
      setSuccess(`Test ${test.code} ${newStatus === 'Active' ? 'activated' : 'archived'}.`);
      onSaved({ ...test, lifecycle_status: newStatus, is_active: newStatus === 'Active' });
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to update test lifecycle.'));
    } finally {
      setBusy(false);
    }
  };

  const filteredRanges = refRanges.filter((r) =>
    rangeFilterParamId === 'All' ? true : r.parameter_id === rangeFilterParamId
  );

  return (
    <Dialog open={open} onClose={onClose} maxWidth="lg" fullWidth PaperProps={{ sx: { minHeight: '85vh', borderRadius: 2 } }}>
      {/* Header Bar */}
      <DialogTitle sx={{ p: 2, bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
          <ScienceIcon color="primary" sx={{ fontSize: 28 }} />
          <Box>
            <Typography variant="h6" fontWeight={800} color="#0f172a">
              {test ? `Edit Test: ${test.code} — ${test.name}` : '+ New Test Master'}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              {test ? `Version: ${test.row_version} | Status: ${test.lifecycle_status}` : 'Create a new laboratory test definition'}
            </Typography>
          </Box>
        </Box>

        <Stack direction="row" spacing={1} alignItems="center">
          {test && (
            <>
              <Button
                size="small"
                variant="outlined"
                color="secondary"
                startIcon={<ContentCopyIcon />}
                onClick={handleOpenClone}
              >
                Duplicate
              </Button>
              <Button
                size="small"
                variant="outlined"
                color={test.lifecycle_status === 'Active' ? 'warning' : 'success'}
                startIcon={test.lifecycle_status === 'Active' ? <ArchiveIcon /> : <UnarchiveIcon />}
                onClick={handleToggleArchive}
              >
                {test.lifecycle_status === 'Active' ? 'Archive' : 'Activate'}
              </Button>
              <Button
                size="small"
                variant="outlined"
                color="error"
                startIcon={<DeleteForeverIcon />}
                onClick={() => setDeleteConfirmOpen(true)}
              >
                Delete
              </Button>
            </>
          )}
          <Button
            size="small"
            variant="contained"
            color="primary"
            startIcon={busy ? <CircularProgress size={16} color="inherit" /> : <SaveIcon />}
            disabled={busy}
            onClick={handleSaveGeneral}
            sx={{ fontWeight: 700 }}
          >
            Save Test
          </Button>
          <IconButton onClick={onClose} size="small">
            <CloseIcon />
          </IconButton>
        </Stack>
      </DialogTitle>

      {/* Alerts */}
      {error && (
        <Alert severity="error" onClose={() => setError(null)} sx={{ m: 2, mb: 0 }}>
          {error}
        </Alert>
      )}
      {success && (
        <Alert severity="success" onClose={() => setSuccess(null)} sx={{ m: 2, mb: 0 }}>
          {success}
        </Alert>
      )}

      {/* Tabs */}
      <Box sx={{ borderBottom: 1, borderColor: 'divider', px: 2, bgcolor: '#f1f5f9' }}>
        <Tabs value={activeTab} onChange={(_, val) => setActiveTab(val)} variant="scrollable" scrollButtons="auto">
          <Tab icon={<ScienceIcon fontSize="small" />} iconPosition="start" label="1. General & Master" />
          <Tab icon={<TuneIcon fontSize="small" />} iconPosition="start" label={`2. Parameters (${parameters.length})`} />
          <Tab icon={<ViewListIcon fontSize="small" />} iconPosition="start" label={`3. Reference Ranges (${refRanges.length})`} />
          <Tab icon={<MonetizationOnIcon fontSize="small" />} iconPosition="start" label="4. Price & Ratelist" />
          <Tab icon={<LabelIcon fontSize="small" />} iconPosition="start" label={`5. Aliases (${aliases.length})`} />
          <Tab icon={<DevicesIcon fontSize="small" />} iconPosition="start" label={`6. Analyzer Mapping (${analyzerMappings.length})`} />
          <Tab icon={<HistoryIcon fontSize="small" />} iconPosition="start" label="7. History & Audit" />
        </Tabs>
      </Box>

      {/* Content Area */}
      <DialogContent sx={{ p: 3, bgcolor: '#ffffff' }}>
        {/* TAB 0: General & Master */}
        {activeTab === 0 && (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2.5 }}>
            <Typography variant="subtitle2" color="primary.main" fontWeight={700}>
              CORE IDENTIFICATION & CLINICAL ROUTING
            </Typography>

            <Grid container spacing={2}>
              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  size="small"
                  label="Test Code (Unique)"
                  required
                  value={generalForm.code}
                  onChange={(e) => setGeneralForm({ ...generalForm, code: e.target.value.toUpperCase() })}
                  helperText="e.g. HEM-0001, BIO-0012, SER-0005"
                />
              </Grid>
              <Grid item xs={12} sm={5}>
                <TextField
                  fullWidth
                  size="small"
                  label="Test Name"
                  required
                  value={generalForm.name}
                  onChange={(e) => setGeneralForm({ ...generalForm, name: e.target.value })}
                  helperText="e.g. Complete Blood Count (CBC), Lipid Profile"
                />
              </Grid>
              <Grid item xs={12} sm={3}>
                <TextField
                  fullWidth
                  size="small"
                  label="Short Name / Abbr"
                  value={generalForm.short_name}
                  onChange={(e) => setGeneralForm({ ...generalForm, short_name: e.target.value })}
                />
              </Grid>

              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  select
                  size="small"
                  label="Department"
                  value={generalForm.department}
                  onChange={(e) => setGeneralForm({ ...generalForm, department: e.target.value })}
                >
                  {DEPARTMENTS.map((d) => (
                    <MenuItem key={d} value={d}>{d}</MenuItem>
                  ))}
                </TextField>
              </Grid>

              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  select
                  size="small"
                  label="Category"
                  value={generalForm.category_id}
                  onChange={(e) => {
                    const sel = categories.find((c) => c.id === e.target.value);
                    setGeneralForm({ ...generalForm, category_id: e.target.value, category: sel?.name || generalForm.category });
                  }}
                >
                  {categories.map((c) => (
                    <MenuItem key={c.id} value={c.id}>{c.name}</MenuItem>
                  ))}
                </TextField>
              </Grid>

              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  select
                  size="small"
                  label="Test Type"
                  value={generalForm.test_kind}
                  onChange={(e) => setGeneralForm({ ...generalForm, test_kind: e.target.value as any })}
                >
                  <MenuItem value="Individual">Individual Test</MenuItem>
                  <MenuItem value="Profile">Profile / Panel (Multi-test bundle)</MenuItem>
                </TextField>
              </Grid>

              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  select
                  size="small"
                  label="Reporting Workflow"
                  value={generalForm.reporting_type}
                  onChange={(e) => setGeneralForm({ ...generalForm, reporting_type: e.target.value })}
                >
                  <MenuItem value="InHouse">In-House Lab Report</MenuItem>
                  <MenuItem value="OutsourceWithBimalReport">Outsource with Bimal Report</MenuItem>
                  <MenuItem value="NoReporting">No Reporting (Billing Only Service)</MenuItem>
                </TextField>
              </Grid>

              {generalForm.reporting_type === 'OutsourceWithBimalReport' && (
                <Grid item xs={12} sm={8}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Outsource Lab Name / Partner"
                    value={generalForm.outsource_lab_name}
                    onChange={(e) => setGeneralForm({ ...generalForm, outsource_lab_name: e.target.value })}
                  />
                </Grid>
              )}
            </Grid>

            <Divider />
            <Typography variant="subtitle2" color="primary.main" fontWeight={700}>
              SPECIMEN, METHOD & TURNAROUND
            </Typography>

            <Grid container spacing={2}>
              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  size="small"
                  label="Specimen / Sample Type"
                  value={generalForm.sample_type}
                  onChange={(e) => setGeneralForm({ ...generalForm, sample_type: e.target.value })}
                  inputProps={{ list: 'specimen-options' }}
                  helperText="Select or type custom specimen"
                />
                <datalist id="specimen-options">
                  {SPECIMEN_TYPES.map((s) => (
                    <option key={s} value={s} />
                  ))}
                </datalist>
              </Grid>
              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  size="small"
                  label="Container / Tube"
                  value={generalForm.container}
                  onChange={(e) => setGeneralForm({ ...generalForm, container: e.target.value })}
                  inputProps={{ list: 'container-options' }}
                  helperText="e.g. EDTA Lavender Top, SST Gel"
                />
                <datalist id="container-options">
                  {CONTAINER_TYPES.map((c) => (
                    <option key={c} value={c} />
                  ))}
                </datalist>
              </Grid>
              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  size="small"
                  label="Sample Volume"
                  value={generalForm.sample_volume}
                  onChange={(e) => setGeneralForm({ ...generalForm, sample_volume: e.target.value })}
                  helperText="e.g. 2 mL, 500 µL"
                />
              </Grid>

              <Grid item xs={12} sm={6}>
                <TextField
                  fullWidth
                  size="small"
                  label="Analytical Method / Instrument Technique"
                  value={generalForm.method}
                  onChange={(e) => setGeneralForm({ ...generalForm, method: e.target.value })}
                  helperText="e.g. Electrical Impedance, Cyanide-Free Colorimetry, FIA"
                />
              </Grid>

              <Grid item xs={12} sm={3}>
                <TextField
                  fullWidth
                  size="small"
                  type="number"
                  label="Turnaround Time (Hours)"
                  value={generalForm.tat_hours}
                  onChange={(e) => setGeneralForm({ ...generalForm, tat_hours: parseInt(e.target.value, 10) || 0 })}
                />
              </Grid>

              <Grid item xs={12} sm={3}>
                <TextField
                  fullWidth
                  size="small"
                  type="number"
                  label="Display Sort Order"
                  value={generalForm.display_order}
                  onChange={(e) => setGeneralForm({ ...generalForm, display_order: parseInt(e.target.value, 10) || 0 })}
                />
              </Grid>

              <Grid item xs={12}>
                <TextField
                  fullWidth
                  multiline
                  rows={2}
                  size="small"
                  label="Clinical Description / Patient Preparation Notes"
                  value={generalForm.description}
                  onChange={(e) => setGeneralForm({ ...generalForm, description: e.target.value })}
                />
              </Grid>
            </Grid>

            <Divider />
            <Typography variant="subtitle2" color="primary.main" fontWeight={700}>
              STATUS & BILLING SETTINGS
            </Typography>

            <Grid container spacing={2} alignItems="center">
              <Grid item xs={12} sm={3}>
                <FormControlLabel
                  control={
                    <Switch
                      checked={generalForm.is_active}
                      onChange={(e) => setGeneralForm({ ...generalForm, is_active: e.target.checked })}
                      color="success"
                    />
                  }
                  label={generalForm.is_active ? 'Active / Orderable' : 'Inactive'}
                />
              </Grid>
              <Grid item xs={12} sm={3}>
                <FormControlLabel
                  control={
                    <Switch
                      checked={generalForm.billing_enabled}
                      onChange={(e) => setGeneralForm({ ...generalForm, billing_enabled: e.target.checked })}
                      color="primary"
                    />
                  }
                  label={generalForm.billing_enabled ? 'Billing Enabled' : 'Billing Disabled'}
                />
              </Grid>
              <Grid item xs={12} sm={3}>
                <FormControlLabel
                  control={
                    <Switch
                      checked={generalForm.allow_zero_price_billing}
                      onChange={(e) => setGeneralForm({ ...generalForm, allow_zero_price_billing: e.target.checked })}
                    />
                  }
                  label="Allow Free / NPR 0"
                />
              </Grid>
              <Grid item xs={12} sm={3}>
                <FormControlLabel
                  control={
                    <Switch
                      checked={generalForm.allow_manual_price}
                      onChange={(e) => setGeneralForm({ ...generalForm, allow_manual_price: e.target.checked })}
                    />
                  }
                  label="Allow Manual Rate Override"
                />
              </Grid>
            </Grid>
          </Box>
        )}

        {/* TAB 1: Parameters */}
        {activeTab === 1 && (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <Typography variant="subtitle1" fontWeight={700}>
                Test Parameters / Analytes ({parameters.length})
              </Typography>
              <Button
                size="small"
                variant="contained"
                startIcon={<AddIcon />}
                onClick={handleOpenAddParam}
                disabled={!test?.id}
              >
                + Add Parameter
              </Button>
            </Box>

            {!test?.id ? (
              <Alert severity="info">Please save the test master first to configure parameters.</Alert>
            ) : paramLoading ? (
              <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}><CircularProgress /></Box>
            ) : parameters.length === 0 ? (
              <Paper sx={{ p: 4, textAlign: 'center', bgcolor: '#f8fafc' }}>
                <Typography color="text.secondary">No parameters configured for this test.</Typography>
                <Button size="small" variant="outlined" sx={{ mt: 1 }} onClick={handleOpenAddParam}>
                  Add First Parameter
                </Button>
              </Paper>
            ) : (
              <TableContainer component={Paper} variant="outlined">
                <Table size="small">
                  <TableHead sx={{ bgcolor: '#f8fafc' }}>
                    <TableRow>
                      <TableCell width={60} align="center">Order</TableCell>
                      <TableCell>Code</TableCell>
                      <TableCell>Parameter Name</TableCell>
                      <TableCell>Type</TableCell>
                      <TableCell>Unit</TableCell>
                      <TableCell align="center">Ranges</TableCell>
                      <TableCell align="center">Active</TableCell>
                      <TableCell align="right">Actions</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {parameters.map((p, idx) => {
                      const paramRangeCount = refRanges.filter((r) => r.parameter_id === p.id).length;
                      return (
                        <TableRow key={p.id} hover>
                          <TableCell align="center">
                            <Stack direction="row" spacing={0.5} justifyContent="center">
                              <IconButton
                                size="small"
                                disabled={idx === 0}
                                onClick={() => handleMoveParam(idx, 'up')}
                              >
                                <ArrowUpwardIcon fontSize="inherit" />
                              </IconButton>
                              <IconButton
                                size="small"
                                disabled={idx === parameters.length - 1}
                                onClick={() => handleMoveParam(idx, 'down')}
                              >
                                <ArrowDownwardIcon fontSize="inherit" />
                              </IconButton>
                            </Stack>
                          </TableCell>
                          <TableCell sx={{ fontWeight: 700 }}>{p.code}</TableCell>
                          <TableCell>{p.name}</TableCell>
                          <TableCell>
                            <Chip size="small" label={p.value_type} color={p.value_type === 'Calculated' ? 'info' : 'default'} />
                          </TableCell>
                          <TableCell>{p.unit || '—'}</TableCell>
                          <TableCell align="center">
                            <Chip
                              size="small"
                              label={`${paramRangeCount} ranges`}
                              color={paramRangeCount > 0 ? 'success' : 'default'}
                              variant="outlined"
                              onClick={() => {
                                setRangeFilterParamId(p.id);
                                setActiveTab(2);
                              }}
                            />
                          </TableCell>
                          <TableCell align="center">
                            <Chip size="small" label={p.is_active ? 'Active' : 'Inactive'} color={p.is_active ? 'success' : 'default'} />
                          </TableCell>
                          <TableCell align="right">
                            <IconButton size="small" color="primary" onClick={() => handleOpenEditParam(p)}>
                              <EditIcon fontSize="small" />
                            </IconButton>
                            <IconButton size="small" color="error" onClick={() => handleDeleteParam(p)}>
                              <DeleteForeverIcon fontSize="small" />
                            </IconButton>
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </TableContainer>
            )}
          </Box>
        )}

        {/* TAB 2: Reference Ranges */}
        {activeTab === 2 && (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 1 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Typography variant="subtitle1" fontWeight={700}>
                  Reference Ranges ({filteredRanges.length})
                </Typography>
                <TextField
                  select
                  size="small"
                  label="Filter Parameter"
                  value={rangeFilterParamId}
                  onChange={(e) => setRangeFilterParamId(e.target.value)}
                  sx={{ minWidth: 200 }}
                >
                  <MenuItem value="All">All Parameters ({refRanges.length})</MenuItem>
                  {parameters.map((p) => (
                    <MenuItem key={p.id} value={p.id}>
                      {p.name} ({p.code})
                    </MenuItem>
                  ))}
                </TextField>
              </Box>

              <Button
                size="small"
                variant="contained"
                startIcon={<AddIcon />}
                onClick={() => handleOpenAddRange(rangeFilterParamId !== 'All' ? rangeFilterParamId : undefined)}
                disabled={parameters.length === 0}
              >
                + Add Reference Range
              </Button>
            </Box>

            {parameters.length === 0 ? (
              <Alert severity="warning">Please add at least one parameter before configuring reference ranges.</Alert>
            ) : filteredRanges.length === 0 ? (
              <Paper sx={{ p: 4, textAlign: 'center', bgcolor: '#f8fafc' }}>
                <Typography color="text.secondary">No reference ranges found.</Typography>
                <Button size="small" variant="outlined" sx={{ mt: 1 }} onClick={() => handleOpenAddRange()}>
                  Add Reference Range
                </Button>
              </Paper>
            ) : (
              <TableContainer component={Paper} variant="outlined">
                <Table size="small">
                  <TableHead sx={{ bgcolor: '#f8fafc' }}>
                    <TableRow>
                      <TableCell>Parameter</TableCell>
                      <TableCell>Sex</TableCell>
                      <TableCell>Age Range</TableCell>
                      <TableCell>Normal Range</TableCell>
                      <TableCell>Panic / Critical Range</TableCell>
                      <TableCell>Text Display / Notes</TableCell>
                      <TableCell>Method / Unit</TableCell>
                      <TableCell align="right">Actions</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {filteredRanges.map((r) => {
                      const pObj = parameters.find((p) => p.id === r.parameter_id);
                      return (
                        <TableRow key={r.id} hover>
                          <TableCell sx={{ fontWeight: 700 }}>{pObj?.name || '—'}</TableCell>
                          <TableCell><Chip size="small" label={r.gender} /></TableCell>
                          <TableCell>{`${Math.floor(r.age_min_days / 365)} - ${Math.floor(r.age_max_days / 365)} yrs`}</TableCell>
                          <TableCell sx={{ fontWeight: 600, color: 'success.dark' }}>
                            {r.normal_min !== null && r.normal_max !== null
                              ? `${r.normal_min} - ${r.normal_max}`
                              : r.normal_min !== null
                              ? `>= ${r.normal_min}`
                              : r.normal_max !== null
                              ? `<= ${r.normal_max}`
                              : '—'}
                          </TableCell>
                          <TableCell sx={{ color: 'error.main', fontWeight: 600 }}>
                            {r.critical_low !== null || r.critical_high !== null
                              ? `< ${r.critical_low ?? '—'} | > ${r.critical_high ?? '—'}`
                              : '—'}
                          </TableCell>
                          <TableCell>{r.normal_text || r.reference_text || '—'}</TableCell>
                          <TableCell>{r.method || r.unit || '—'}</TableCell>
                          <TableCell align="right">
                            <IconButton size="small" color="primary" onClick={() => handleOpenEditRange(r)}>
                              <EditIcon fontSize="small" />
                            </IconButton>
                            <IconButton size="small" color="error" onClick={() => handleDeleteRange(r)}>
                              <DeleteForeverIcon fontSize="small" />
                            </IconButton>
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </TableContainer>
            )}
          </Box>
        )}

        {/* TAB 3: Price & Ratelist */}
        {activeTab === 3 && (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2.5 }}>
            <Typography variant="subtitle1" fontWeight={700}>
              Patient Tariff & Versioned Ratelist History
            </Typography>

            <Paper sx={{ p: 2.5, bgcolor: '#f8fafc', border: '1px solid #e2e8f0' }}>
              <Grid container spacing={2} alignItems="center">
                <Grid item xs={12} sm={4}>
                  <TextField
                    fullWidth
                    size="small"
                    type="number"
                    label="Current Patient Rate (NPR)"
                    value={generalForm.price_npr}
                    onChange={(e) => setGeneralForm({ ...generalForm, price_npr: e.target.value })}
                    helperText={`Stored server-side as ${rupeesToPaisa(generalForm.price_npr)} Paisa`}
                  />
                </Grid>
                <Grid item xs={12} sm={4}>
                  <TextField
                    fullWidth
                    select
                    size="small"
                    label="Pricing Policy"
                    value={generalForm.pricing_policy}
                    onChange={(e) => setGeneralForm({ ...generalForm, pricing_policy: e.target.value as any })}
                  >
                    <MenuItem value="Fixed">Fixed Rate</MenuItem>
                    <MenuItem value="Negotiable">Negotiable / Discountable</MenuItem>
                    <MenuItem value="PricePending">Price Pending</MenuItem>
                    <MenuItem value="Manual">Manual Rate on Entry</MenuItem>
                  </TextField>
                </Grid>
                <Grid item xs={12} sm={4}>
                  <Button
                    variant="contained"
                    color="primary"
                    startIcon={<SaveIcon />}
                    onClick={handleSaveGeneral}
                  >
                    Update Tariff Rate
                  </Button>
                </Grid>
              </Grid>
            </Paper>

            <Typography variant="subtitle2" fontWeight={700} color="text.secondary">
              Immutable Tariff Rate History
            </Typography>

            <TableContainer component={Paper} variant="outlined">
              <Table size="small">
                <TableHead sx={{ bgcolor: '#f8fafc' }}>
                  <TableRow>
                    <TableCell>Rate List Name</TableCell>
                    <TableCell>Price (NPR)</TableCell>
                    <TableCell>Price (Paisa)</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell>Effective From</TableCell>
                    <TableCell>Effective To</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {rateHistory.length === 0 ? (
                    <TableRow><TableCell colSpan={6} align="center">No rate history recorded.</TableCell></TableRow>
                  ) : (
                    rateHistory.map((rh) => (
                      <TableRow key={rh.id}>
                        <TableCell sx={{ fontWeight: 600 }}>{rh.ratelist_name}</TableCell>
                        <TableCell sx={{ fontWeight: 700, color: 'primary.main' }}>
                          NPR {paisaToRupees(rh.price_paisa)}
                        </TableCell>
                        <TableCell>{rh.price_paisa}</TableCell>
                        <TableCell>
                          <Chip size="small" label={rh.status} color={rh.status === 'Active' ? 'success' : 'default'} />
                        </TableCell>
                        <TableCell>{formatAdDate(rh.effective_from)}</TableCell>
                        <TableCell>{rh.effective_to ? formatAdDate(rh.effective_to) : 'Present (Active)'}</TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </TableContainer>
          </Box>
        )}

        {/* TAB 4: Aliases */}
        {activeTab === 4 && (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2.5 }}>
            <Typography variant="subtitle1" fontWeight={700}>
              Search Terms & Alternative Names (Aliases)
            </Typography>
            <Typography variant="body2" color="text.secondary">
              Add common synonyms, abbreviations, and clinical alternate names so billing staff can find this test instantly.
            </Typography>

            <Box sx={{ display: 'flex', gap: 1 }}>
              <TextField
                size="small"
                label="Add new alias (e.g. Hemogram, HbA1C, Dengue NS1)"
                value={newAliasInput}
                onChange={(e) => setNewAliasInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    handleAddAlias();
                  }
                }}
                sx={{ flex: 1 }}
              />
              <Button variant="contained" onClick={handleAddAlias}>
                + Add Alias
              </Button>
            </Box>

            <Paper sx={{ p: 2, display: 'flex', flexWrap: 'wrap', gap: 1, minHeight: 100, bgcolor: '#f8fafc' }}>
              {aliases.length === 0 ? (
                <Typography color="text.secondary">No search aliases configured.</Typography>
              ) : (
                aliases.map((a) => (
                  <Chip
                    key={a}
                    label={a}
                    onDelete={() => handleRemoveAlias(a)}
                    color="primary"
                    variant="outlined"
                    sx={{ fontWeight: 600 }}
                  />
                ))
              )}
            </Paper>
          </Box>
        )}

        {/* TAB 5: Analyzer Mapping */}
        {activeTab === 5 && (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <Typography variant="subtitle1" fontWeight={700}>
                Laboratory Instrument Channel Mappings ({analyzerMappings.length})
              </Typography>
              <Button
                size="small"
                variant="contained"
                startIcon={<AddIcon />}
                onClick={() => {
                  setMappingForm({
                    id: '',
                    analyzer_id: analyzers[0]?.id || '',
                    channel_code: '',
                    channel_name: '',
                    parameter_id: parameters[0]?.id || '',
                    measurement_type: 'DIRECT_MEASURED',
                    analytical_method: generalForm.method || 'Automated',
                    unit: '',
                    differential_type: 'Not Applicable',
                  });
                  setMappingDialogOpen(true);
                }}
                disabled={!test?.id}
              >
                + Map Analyzer Channel
              </Button>
            </Box>

            {analyzerMappings.length === 0 ? (
              <Paper sx={{ p: 4, textAlign: 'center', bgcolor: '#f8fafc' }}>
                <Typography color="text.secondary">No analyzer channels mapped to this test.</Typography>
              </Paper>
            ) : (
              <TableContainer component={Paper} variant="outlined">
                <Table size="small">
                  <TableHead sx={{ bgcolor: '#f8fafc' }}>
                    <TableRow>
                      <TableCell>Analyzer</TableCell>
                      <TableCell>Channel Code</TableCell>
                      <TableCell>Channel Name</TableCell>
                      <TableCell>Measurement Type</TableCell>
                      <TableCell>Method</TableCell>
                      <TableCell>Unit</TableCell>
                      <TableCell align="right">Actions</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {analyzerMappings.map((m) => (
                      <TableRow key={m.id} hover>
                        <TableCell sx={{ fontWeight: 700 }}>{m.analyzers?.name || m.analyzer_id}</TableCell>
                        <TableCell><Chip size="small" label={m.channel_code} color="primary" variant="outlined" /></TableCell>
                        <TableCell>{m.channel_name}</TableCell>
                        <TableCell>{m.measurement_type}</TableCell>
                        <TableCell>{m.analytical_method}</TableCell>
                        <TableCell>{m.unit || '—'}</TableCell>
                        <TableCell align="right">
                          <IconButton
                            size="small"
                            color="error"
                            onClick={async () => {
                              if (!confirm(`Remove mapping for channel ${m.channel_code}?`)) return;
                              await supabase.rpc('catalogue_delete_analyzer_mapping_easy', { p_mapping_id: m.id });
                              loadTestData(test!.id);
                            }}
                          >
                            <DeleteForeverIcon fontSize="small" />
                          </IconButton>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
            )}
          </Box>
        )}

        {/* TAB 6: History & Audit */}
        {activeTab === 6 && (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <Typography variant="subtitle1" fontWeight={700}>
              Catalogue Audit Trail & Timeline
            </Typography>

            <TableContainer component={Paper} variant="outlined">
              <Table size="small">
                <TableHead sx={{ bgcolor: '#f8fafc' }}>
                  <TableRow>
                    <TableCell>Timestamp (AD)</TableCell>
                    <TableCell>User / Staff</TableCell>
                    <TableCell>Action</TableCell>
                    <TableCell>Entity</TableCell>
                    <TableCell>Changes</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {auditHistory.length === 0 ? (
                    <TableRow><TableCell colSpan={5} align="center">No audit history recorded.</TableCell></TableRow>
                  ) : (
                    auditHistory.map((ah) => (
                      <TableRow key={ah.id} hover>
                        <TableCell>{formatAdDate(ah.timestamp)}</TableCell>
                        <TableCell sx={{ fontWeight: 600 }}>{ah.user_name || 'System'}</TableCell>
                        <TableCell><Chip size="small" label={ah.action} color="info" variant="outlined" /></TableCell>
                        <TableCell>{ah.entity_type}</TableCell>
                        <TableCell sx={{ fontSize: '0.75rem', fontFamily: 'monospace' }}>
                          {JSON.stringify(ah.new_data || {})}
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </TableContainer>
          </Box>
        )}
      </DialogContent>

      {/* Parameter Dialog Modal */}
      <Dialog open={paramDialogOpen} onClose={() => setParamDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 800 }}>
          {editingParam ? `Edit Parameter: ${editingParam.name}` : '+ Add Parameter'}
        </DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
          <Grid container spacing={2}>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Parameter Code"
                required
                value={paramForm.code}
                onChange={(e) => setParamForm({ ...paramForm, code: e.target.value.toUpperCase() })}
                helperText="e.g. WBC, RBC, GLU_F"
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Parameter Name"
                required
                value={paramForm.name}
                onChange={(e) => setParamForm({ ...paramForm, name: e.target.value })}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                select
                size="small"
                label="Result Value Type"
                value={paramForm.value_type}
                onChange={(e) => setParamForm({ ...paramForm, value_type: e.target.value as any })}
              >
                <MenuItem value="Numeric">Numeric (Quantitative)</MenuItem>
                <MenuItem value="Text">Text (Qualitative / Narrative)</MenuItem>
                <MenuItem value="Select">Select / Dropdown Choice</MenuItem>
                <MenuItem value="Calculated">Calculated (Governed Formula)</MenuItem>
                <MenuItem value="Heading">Heading / Section Header</MenuItem>
              </TextField>
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Unit of Measurement"
                value={paramForm.unit}
                onChange={(e) => setParamForm({ ...paramForm, unit: e.target.value })}
                helperText="e.g. mg/dL, 10^3/µL, %, U/L"
              />
            </Grid>

            {paramForm.value_type === 'Numeric' && (
              <Grid item xs={12} sm={6}>
                <TextField
                  fullWidth
                  size="small"
                  type="number"
                  label="Decimal Precision"
                  value={paramForm.decimal_precision}
                  onChange={(e) => setParamForm({ ...paramForm, decimal_precision: parseInt(e.target.value, 10) || 0 })}
                />
              </Grid>
            )}

            {paramForm.value_type === 'Calculated' && (
              <>
                <Grid item xs={12} sm={6}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Calculation Identifier"
                    value={paramForm.calculation_identifier}
                    onChange={(e) => setParamForm({ ...paramForm, calculation_identifier: e.target.value })}
                  />
                </Grid>
                <Grid item xs={12}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Formula"
                    value={paramForm.formula}
                    onChange={(e) => setParamForm({ ...paramForm, formula: e.target.value })}
                    helperText="e.g. (HGB * 3)"
                  />
                </Grid>
              </>
            )}

            {paramForm.value_type === 'Select' && (
              <Grid item xs={12}>
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>
                  Dropdown Options List (e.g. Negative, Reactive, Trace)
                </Typography>
                <Box sx={{ display: 'flex', gap: 1, mb: 1 }}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Add Option"
                    value={paramForm.newOptionInput}
                    onChange={(e) => setParamForm({ ...paramForm, newOptionInput: e.target.value })}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        if (paramForm.newOptionInput.trim()) {
                          setParamForm({
                            ...paramForm,
                            options: [...paramForm.options, paramForm.newOptionInput.trim()],
                            newOptionInput: '',
                          });
                        }
                      }
                    }}
                  />
                  <Button
                    variant="contained"
                    size="small"
                    onClick={() => {
                      if (paramForm.newOptionInput.trim()) {
                        setParamForm({
                          ...paramForm,
                          options: [...paramForm.options, paramForm.newOptionInput.trim()],
                          newOptionInput: '',
                        });
                      }
                    }}
                  >
                    Add
                  </Button>
                </Box>
                <Paper sx={{ p: 1, display: 'flex', flexWrap: 'wrap', gap: 0.5, bgcolor: '#f8fafc' }}>
                  {paramForm.options.map((opt, i) => (
                    <Chip
                      key={i}
                      label={opt}
                      size="small"
                      onDelete={() => {
                        const next = [...paramForm.options];
                        next.splice(i, 1);
                        setParamForm({ ...paramForm, options: next });
                      }}
                    />
                  ))}
                </Paper>
              </Grid>
            )}

            <Grid item xs={12} sm={6}>
              <FormControlLabel
                control={
                  <Switch
                    checked={paramForm.is_mandatory}
                    onChange={(e) => setParamForm({ ...paramForm, is_mandatory: e.target.checked })}
                  />
                }
                label="Mandatory Result"
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <FormControlLabel
                control={
                  <Switch
                    checked={paramForm.is_active}
                    onChange={(e) => setParamForm({ ...paramForm, is_active: e.target.checked })}
                  />
                }
                label="Active Parameter"
              />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setParamDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" onClick={handleSaveParam} disabled={busy}>
            Save Parameter
          </Button>
        </DialogActions>
      </Dialog>

      {/* Reference Range Dialog Modal */}
      <Dialog open={rangeDialogOpen} onClose={() => setRangeDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 800 }}>
          {editingRange ? 'Edit Reference Range' : '+ Add Reference Range'}
        </DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
          <Grid container spacing={2}>
            <Grid item xs={12}>
              <TextField
                fullWidth
                select
                size="small"
                label="Parameter"
                required
                value={rangeForm.parameter_id}
                onChange={(e) => setRangeForm({ ...rangeForm, parameter_id: e.target.value })}
              >
                {parameters.map((p) => (
                  <MenuItem key={p.id} value={p.id}>{p.name} ({p.code})</MenuItem>
                ))}
              </TextField>
            </Grid>
            <Grid item xs={12} sm={4}>
              <TextField
                fullWidth
                select
                size="small"
                label="Gender / Sex"
                value={rangeForm.gender}
                onChange={(e) => setRangeForm({ ...rangeForm, gender: e.target.value })}
              >
                <MenuItem value="All">All (Any Sex)</MenuItem>
                <MenuItem value="Male">Male</MenuItem>
                <MenuItem value="Female">Female</MenuItem>
              </TextField>
            </Grid>
            <Grid item xs={12} sm={4}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Age Min (Years)"
                value={rangeForm.age_min_years}
                onChange={(e) => setRangeForm({ ...rangeForm, age_min_years: e.target.value })}
              />
            </Grid>
            <Grid item xs={12} sm={4}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Age Max (Years)"
                value={rangeForm.age_max_years}
                onChange={(e) => setRangeForm({ ...rangeForm, age_max_years: e.target.value })}
              />
            </Grid>

            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Normal Minimum"
                value={rangeForm.normal_min}
                onChange={(e) => setRangeForm({ ...rangeForm, normal_min: e.target.value })}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Normal Maximum"
                value={rangeForm.normal_max}
                onChange={(e) => setRangeForm({ ...rangeForm, normal_max: e.target.value })}
              />
            </Grid>

            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Panic / Critical Low"
                value={rangeForm.critical_low}
                onChange={(e) => setRangeForm({ ...rangeForm, critical_low: e.target.value })}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Panic / Critical High"
                value={rangeForm.critical_high}
                onChange={(e) => setRangeForm({ ...rangeForm, critical_high: e.target.value })}
              />
            </Grid>

            <Grid item xs={12}>
              <TextField
                fullWidth
                size="small"
                label="Text Reference Range / Qualitative Expected"
                value={rangeForm.normal_text}
                onChange={(e) => setRangeForm({ ...rangeForm, normal_text: e.target.value })}
                helperText="e.g. Negative, Non-Reactive, Clear"
              />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setRangeDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" onClick={handleSaveRange} disabled={busy}>
            Save Reference Range
          </Button>
        </DialogActions>
      </Dialog>

      {/* Duplicate / Clone Modal */}
      <Dialog open={cloneDialogOpen} onClose={() => setCloneDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ fontWeight: 800 }}>Duplicate Test Configuration</DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
          <Typography variant="body2" color="text.secondary">
            This will copy all parameters, reference ranges, and specimen configurations to a new test.
          </Typography>
          <TextField
            fullWidth
            size="small"
            label="New Unique Test Code"
            required
            value={cloneForm.code}
            onChange={(e) => setCloneForm({ ...cloneForm, code: e.target.value.toUpperCase() })}
          />
          <TextField
            fullWidth
            size="small"
            label="New Test Name"
            required
            value={cloneForm.name}
            onChange={(e) => setCloneForm({ ...cloneForm, name: e.target.value })}
          />
          <TextField
            fullWidth
            size="small"
            type="number"
            label="Initial Rate (NPR)"
            value={cloneForm.price_npr}
            onChange={(e) => setCloneForm({ ...cloneForm, price_npr: e.target.value })}
          />
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setCloneDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" color="secondary" onClick={handleExecuteClone} disabled={busy}>
            Clone Test
          </Button>
        </DialogActions>
      </Dialog>

      {/* Delete Confirmation Modal */}
      <Dialog open={deleteConfirmOpen} onClose={() => setDeleteConfirmOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ fontWeight: 800, color: 'error.main' }}>
          Delete Test Permanently?
        </DialogTitle>
        <DialogContent>
          <Typography variant="body2" sx={{ mb: 2 }}>
            Are you sure you want to delete test <strong>{test?.code} — {test?.name}</strong>?
          </Typography>
          <Alert severity="warning">
            If this test has ever been billed or resulted, permanent deletion will be prevented by the system to preserve immutable records. You can Archive it instead.
          </Alert>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setDeleteConfirmOpen(false)}>Cancel</Button>
          <Button variant="contained" color="error" onClick={handleExecuteDelete} disabled={busy}>
            Delete Permanently
          </Button>
        </DialogActions>
      </Dialog>
      {/* Analyzer Mapping Dialog Modal */}
      <Dialog open={mappingDialogOpen} onClose={() => setMappingDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 800 }}>
          {mappingForm.id ? 'Edit Analyzer Channel Mapping' : '+ Map Analyzer Channel'}
        </DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
          <Grid container spacing={2}>
            <Grid item xs={12}>
              <TextField
                fullWidth
                select
                size="small"
                label="Laboratory Analyzer"
                required
                value={mappingForm.analyzer_id}
                onChange={(e) => setMappingForm({ ...mappingForm, analyzer_id: e.target.value })}
              >
                {analyzers.map((a) => (
                  <MenuItem key={a.id} value={a.id}>{a.name} ({a.code || a.model_name || 'Analyzer'})</MenuItem>
                ))}
              </TextField>
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Channel Code / ID"
                required
                value={mappingForm.channel_code}
                onChange={(e) => setMappingForm({ ...mappingForm, channel_code: e.target.value.toUpperCase() })}
                helperText="e.g. WBC, HGB, GLU"
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Channel Name"
                required
                value={mappingForm.channel_name}
                onChange={(e) => setMappingForm({ ...mappingForm, channel_name: e.target.value })}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                select
                size="small"
                label="Target Test Parameter"
                value={mappingForm.parameter_id}
                onChange={(e) => setMappingForm({ ...mappingForm, parameter_id: e.target.value })}
              >
                <MenuItem value="">— None / Direct Test Mapping —</MenuItem>
                {parameters.map((p) => (
                  <MenuItem key={p.id} value={p.id}>{p.name} ({p.code})</MenuItem>
                ))}
              </TextField>
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Channel Unit"
                value={mappingForm.unit}
                onChange={(e) => setMappingForm({ ...mappingForm, unit: e.target.value })}
              />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setMappingDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" onClick={handleSaveMapping} disabled={busy}>
            Save Mapping
          </Button>
        </DialogActions>
      </Dialog>
    </Dialog>
  );
};
