/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Metadata-Driven Clinical Result Entry & Pathologist Verification Engine
 * Ultra-clear Order-Level Report Status, Sibling Navigation, Review, and Sign-Off Workflow
 */

import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
  Box,
  Card,
  CardContent,
  Grid,
  Typography,
  TextField,
  Button,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Alert,
  Chip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  CircularProgress,
  Snackbar,
  MenuItem,
  Divider,
} from '@mui/material';
import SaveIcon from '@mui/icons-material/Save';
import FactCheckIcon from '@mui/icons-material/FactCheck';
import VerifiedIcon from '@mui/icons-material/Verified';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import ReplayIcon from '@mui/icons-material/Replay';
import DrawIcon from '@mui/icons-material/Draw';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import EditIcon from '@mui/icons-material/Edit';
import PrintIcon from '@mui/icons-material/Print';
import ArrowForwardIcon from '@mui/icons-material/ArrowForward';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';

import { StatusChip } from '@/components/common/StatusChip';
import { RESULT_FLAGS, RESULT_STATUSES, ResultFlag, ResultStatus } from '@/config/constants';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { supabase } from '@/lib/supabase';
import { generateRawToken, hashToken } from '@/lib/sms/tokenHelper';
import { ReportingPersonnel } from '@/types/database';
import { formatAdDateTime } from '@/lib/dateTime';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import {
  resolvePatientReferenceRange,
  formatReferenceRangeText,
  evaluateResultFlag,
  DbReferenceRange,
} from '@/lib/clinicalReferenceRange';
import { recalculateInvestigationParameters } from '@/lib/clinicalMath';
import { useGlobalShortcuts } from '@/lib/keyboardNav';
import { publishWorkflowInvalidation } from '@/lib/workflowInvalidation';
import { AstCultureResultEntry } from './AstCultureResultEntry';
import { validateMinSec } from './timeResult';
import {
  getNextOrderAction,
  getHighestPriorityOrderItem,
  scheduleOrderNavigation,
} from '@/lib/orderWorkflowNavigation';
import {
  buildAnalyzerLookup,
  resolveConfiguredParameterSource,
} from '@/lib/testSourceResolver';
import { isReportableParameter } from '@/features/reports/reportPagination';

const CANONICAL_FORMULA_MAP: Record<string, string> = {
  LFT_INDIRECT_BILIRUBIN_V1: 'TBIL - DBIL',
  BILIRUBIN_TD_INDIRECT_V1: 'TOTAL_BILIRUBIN - DIRECT_BILIRUBIN',
  LFT_GLOBULIN_V1: 'TP - ALB',
  LFT_AG_RATIO_V1: 'ALB / GLOB',
  LIPID_VLDL_V1: 'TRIG / 5',
  LIPID_CHOL_HDL_RATIO_V1: 'CHOL / HDL',
  LIPID_NON_HDL_V1: 'CHOL - HDL',
  PT_INR_V1: '(PT / MNPT) ^ ISI',
  COAG_PROFILE_INR_V1: '(PT / MNPT) ^ ISI',
  HIGH_DOSE_DST_SUPPRESSION_V1: '((BASELINE - POST) / BASELINE) * 100',
};

function resolveParameterFormula(code: string, calculationIdentifier?: string | null, rawFormula?: string | null): string | null {
  if (calculationIdentifier && CANONICAL_FORMULA_MAP[calculationIdentifier]) {
    return CANONICAL_FORMULA_MAP[calculationIdentifier];
  }
  const upperCode = (code || '').toUpperCase();
  if (upperCode === 'IBIL' || upperCode === 'INDIRECT_BILIRUBIN') return 'TBIL - DBIL';
  if (upperCode === 'GLOB' || upperCode === 'GLOBULIN') return 'TP - ALB';
  if (upperCode === 'AG_RATIO' || upperCode === 'A_G_RATIO') return 'ALB / GLOB';
  if (upperCode === 'VLDL') return 'TRIG / 5';
  if (upperCode === 'TC_HDL_RATIO') return 'CHOL / HDL';
  if (upperCode === 'NON_HDL') return 'CHOL - HDL';
  if (upperCode === 'INR' || upperCode === 'COA-0002') return '(PT / MNPT) ^ ISI';
  if (upperCode === 'END-0061-03' || upperCode.includes('SUPPRESSION_PERCENT')) return '((BASELINE - POST) / BASELINE) * 100';

  if (rawFormula && /^[A-Za-z0-9_\s+\-*/^()]+$/.test(rawFormula)) {
    return rawFormula;
  }
  return null;
}

interface ParamResultState {
  id?: string; // test_result_id
  parameter_id: string;
  code: string;
  name: string;
  value_type: string;
  unit?: string | null;
  formula?: string | null;
  options?: string[];
  multiline?: boolean;
  timeControl?: boolean;
  display_value: string;
  numeric_value?: number | null;
  text_value?: string | null;
  flag: ResultFlag;
  is_critical: boolean;
  critical_acknowledged?: boolean;
  normal_min?: number | null;
  normal_max?: number | null;
  critical_low?: number | null;
  critical_high?: number | null;
  normal_text?: string | null;
  reference_text?: string | null;
  resolved_range_text: string;
  resolved_range?: DbReferenceRange | null;
  result_source?: 'ANALYZER' | 'CALCULATED' | 'MANUAL';
  status: ResultStatus;
  is_mandatory?: boolean;
}

interface SiblingItem {
  id: string;
  test_name: string;
  department: string;
  status: string;
  reporting_type: string;
  results?: Array<{ id: string; status: string }>;
  report_group_id?: string;
  report_group_title?: string;
  report_group_key?: string;
  execution_route?: 'INTERNAL' | 'OUTSOURCE';
  outsource_state?: string | null;
  outsource_lab_name?: string | null;
  report_state?: string | null;
  pdf_state?: string | null;
}

export const ResultEntryPage: React.FC = () => {
  const { id: legacyOrderItemId, orderId: routeOrderId } = useParams<{ id?: string; orderId?: string }>();
  const [searchParams] = useSearchParams();
  const [resolvedOrderItemId, setResolvedOrderItemId] = useState<string | null>(legacyOrderItemId || searchParams.get('item'));
  const orderItemId = legacyOrderItemId || searchParams.get('item') || resolvedOrderItemId;
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canEnterResults = can(PERMISSION_KEYS.CAN_ENTER_RESULTS);

  const amendReportId = searchParams.get('amendReportId');
  const initialAmendReason = searchParams.get('reason') || '';

  const [orderItem, setOrderItem] = useState<any | null>(null);
  // Maps parameter_id → analyzer display names (e.g. ["CounCell 23 Excel"])
  const [analyzerLookup, setAnalyzerLookup] = useState<Map<string, string[]>>(new Map());
  const [results, setResults] = useState<ParamResultState[]>([]);
  const [siblings, setSiblings] = useState<SiblingItem[]>([]);
  const [readiness, setReadiness] = useState<any | null>(null);
  const [signatories, setSignatories] = useState<ReportingPersonnel[]>([]);
  const [existingReport, setExistingReport] = useState<any | null>(null);
  const [verifiedMeta, setVerifiedMeta] = useState<{ verifiedBy?: string; verifiedAt?: string } | null>(null);
  const [calculationBlockers, setCalculationBlockers] = useState<string[]>([]);
  const [reportGroup, setReportGroup] = useState<any | null>(null);

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reloadLatestRequired, setReloadLatestRequired] = useState(false);
  const [toastMsg, setToastMsg] = useState<string | null>(null);

  // Critical Value Acknowledgment State
  const [criticalModalOpen, setCriticalModalOpen] = useState(false);
  const [notifiedPerson, setNotifiedPerson] = useState('');
  const [notificationMethod, setNotificationMethod] = useState('Direct Phone Call');
  const [notificationComment, setNotificationComment] = useState('');

  // Sign-Off Modal State
  const [signOffModalOpen, setSignOffModalOpen] = useState(false);
  const [signOffConfirmOpen, setSignOffConfirmOpen] = useState(false);
  const [performedById, setPerformedById] = useState('');
  const [signedById, setSignedById] = useState('');
  const [amendmentReason, setAmendmentReason] = useState(initialAmendReason);
  const [isSigning, setIsSigning] = useState(false);

  // Pending Configuration Modal State
  const [configModalOpen, setConfigModalOpen] = useState(false);
  const [configAnalyzerModel, setConfigAnalyzerModel] = useState('');
  const [configReagentManufacturer, setConfigReagentManufacturer] = useState('');
  const [configMethod, setConfigMethod] = useState('');
  const [configUnit, setConfigUnit] = useState('');
  const [configNormalMin, setConfigNormalMin] = useState('');
  const [configNormalMax, setConfigNormalMax] = useState('');
  const [configCriticalLow, setConfigCriticalLow] = useState('');
  const [configCriticalHigh, setConfigCriticalHigh] = useState('');
  const [configNormalText, setConfigNormalText] = useState('');
  const [configNotes, setConfigNotes] = useState('');
  const [savingConfig, setSavingConfig] = useState(false);

  // Active PT/INR Reagent Configuration State (MNPT & ISI)
  const [ptInrConfig, setPtInrConfig] = useState<{
    reagent_name?: string;
    mnpt?: number;
    isi?: number;
    lot_number?: string;
    is_active?: boolean;
  } | null>(null);

  // Input ref map for rapid keyboard navigation
  const inputRefs = useRef<(HTMLInputElement | null)[]>([]);
  const saveDraftButtonRef = useRef<HTMLButtonElement | null>(null);
  const hasAutoFocused = useRef(false);
  const handledRouteAction = useRef<string | null>(null);

  // Auto-focus first editable parameter on mount or after data loads
  useEffect(() => {
    if (!loading && results.length > 0 && !hasAutoFocused.current) {
      const firstEditableIndex = results.findIndex(
        (r) => r.value_type !== 'Calculated' && r.value_type !== 'Heading'
      );
      if (firstEditableIndex !== -1) {
        hasAutoFocused.current = true;
        const timer = setTimeout(() => {
          inputRefs.current[firstEditableIndex]?.focus();
          inputRefs.current[firstEditableIndex]?.select();
        }, 80);
        return () => clearTimeout(timer);
      }
    }
  }, [loading, results]);

  // Global F2/F6/F8/F9/Ctrl+S Shortcuts
  useGlobalShortcuts({
    onNewBill: () => navigate('/billing/new'),
    onWorklist: () => navigate('/worklist'),
    onSave: () => {
      if (!saving && (!isCurrentVerified || amendReportId)) {
        handleSaveResults(RESULT_STATUSES.DRAFT);
      }
    },
    onVerify: () => {
      if (!saving && can(PERMISSION_KEYS.CAN_VERIFY_RESULTS) && !isCurrentVerified && results.length > 0 && !hasUnackCritical) {
        handleSaveResults(RESULT_STATUSES.VERIFIED);
      }
    },
    onSign: () => {
      if (!saving && can(PERMISSION_KEYS.CAN_SIGN_REPORTS) && isOrderFullyReady && !hasExistingReport) {
        setSignOffModalOpen(true);
      }
    },
    onEscape: () => {
      setCriticalModalOpen(false);
      setSignOffModalOpen(false);
      setConfigModalOpen(false);
    },
  });

  const handleNextPendingPatient = async () => {
    try {
      const { data, error: fetchErr } = await supabase.rpc('search_laboratory_worklist', {
        p_search: null,
        p_department: null,
        p_sample_status: null,
        p_order_date: null,
        p_view: 'Pending',
        p_cursor_created_at: null,
        p_cursor_id: null,
        p_limit: 5,
      });
      if (!fetchErr && data && (data as any[]).length > 0) {
        const list = (data as any[]).map((d) => d.item || d);
        const nextTarget = list.find((it) => it.id !== orderItemId);
        if (nextTarget) {
          navigate(`/worklist/order/${nextTarget.order_id}?item=${nextTarget.id}`);
          return;
        }
      }
      navigate('/worklist');
    } catch {
      navigate('/worklist');
    }
  };

  // Load Master Personnel, Order Item, Sibling Tests, Readiness & Results
  const loadItemAndResults = useCallback(async () => {
    if (!orderItemId && routeOrderId) {
      try {
        const [{ data: wsData }, { data: clItems }] = await Promise.all([
          supabase.from('order_report_group_workspace' as any).select('*').eq('order_id', routeOrderId).order('display_order').order('item_display_order'),
          supabase.from('clinical_order_items').select('id,order_id,status,results:test_results(id,is_critical,critical_acknowledged,status)').eq('order_id', routeOrderId),
        ]);
        const targetItemId = getHighestPriorityOrderItem((wsData || []) as any, (clItems || []) as any);
        if (targetItemId) {
          setResolvedOrderItemId(targetItemId);
          return;
        }
        const { data: first, error: firstError } = await supabase
          .from('clinical_order_items')
          .select('id')
          .eq('order_id', routeOrderId)
          .eq('clinical_reporting_enabled', true)
          .order('created_at')
          .limit(1)
          .maybeSingle();
        if (firstError) {
          setError(safeErrorMessage(firstError, 'Unable to open this order workspace.'));
          return;
        }
        if (first?.id) setResolvedOrderItemId(first.id);
      } catch (err) {
        setError(safeErrorMessage(err, 'Unable to resolve the active investigation for this order.'));
      }
      return;
    }
    if (!orderItemId) return;
    setLoading(true);
    setError(null);

    try {
      // 1. Fetch clinical order item with order & patient details
      const { data: itemData, error: itemErr } = await supabase
        .from('clinical_order_items')
        .select(`
          *,
          order:clinical_orders(
            id,
            bill_id,
            order_number,
            order_date_ad,
            order_date_bs,
            patient:patients(id, uhid, full_name, mobile, address, dob, gender, age_years, age_months, age_days)
          ),
          sample:samples(barcode, status, specimen_type, container_type),
          test:tests(code, workflow_type, validation_status, configuration_status, method)
        `)
        .eq('id', orderItemId)
        .eq('clinical_reporting_enabled', true)
        .single();

      if (itemErr) throw itemErr;
      setOrderItem(itemData);

      const orderId = itemData.order_id;
      const patientGender = itemData.order?.patient?.gender || 'All';
      const patientAgeYears = itemData.order?.patient?.age_years;
      const patientAgeMonths = itemData.order?.patient?.age_months ?? 0;
      const patientAdditionalDays = itemData.order?.patient?.age_days ?? 0;
      const patientAgeDays = patientAgeYears == null
        ? null
        : Math.round((patientAgeYears * 365.25) + (patientAgeMonths * 30.4375) + patientAdditionalDays);

      // 2. Fetch all sibling investigations with result statuses for this clinical order
      const { data: sibData } = await supabase
        .from('clinical_order_items')
        .select(`
          id,
          test_name,
          department,
          status,
          reporting_type,
          results:test_results(id, status)
        `)
        .eq('order_id', orderId)
        .eq('clinical_reporting_enabled', true)
        .in('reporting_type', ['InHouse', 'OutsourceWithBimalReport'])
        .order('created_at', { ascending: true });

      setSiblings((sibData || []) as SiblingItem[]);

      const { data: workspaceData } = await supabase
        .from('order_report_group_workspace' as any)
        .select('*')
        .eq('order_id', orderId)
        .order('display_order')
        .order('item_display_order');
      const workspaceRows = (workspaceData || []) as any[];
      setSiblings((sibData || []).map((s:any)=>{const row=workspaceRows.find((w)=>w.order_item_id===s.id);return {...s,report_group_id:row?.report_group_id,report_group_title:row?.title,report_group_key:row?.group_key,execution_route:row?.execution_route,outsource_state:row?.outsource_state,outsource_lab_name:row?.outsource_lab_name,report_state:row?.report_state,pdf_state:row?.pdf_state}}));
      const currentGroup=workspaceRows.find((row)=>row.order_item_id===orderItemId) || null;
      setReportGroup(currentGroup);

      // 3. Fetch authoritative readiness check from RPC
      const { data: readyData } = currentGroup ? await (supabase.rpc as any)('check_report_group_readiness', {
        p_report_group_id: currentGroup.report_group_id,
      }) : await supabase.rpc('check_order_report_readiness', { p_order_id: orderId });
      setReadiness(readyData);

      // 4. Fetch any existing signed report for this order
      const { data: repData } = await supabase
        .from('diagnostic_reports')
        .select('*')
        .eq('order_id', orderId)
        .eq('report_group_id', currentGroup?.report_group_id || '00000000-0000-0000-0000-000000000000')
        .order('version', { ascending: false })
        .limit(1)
        .maybeSingle();

      setExistingReport(repData || null);

      // 5. Fetch active reporting personnel
      const { data: personnelData } = await supabase
        .from('reporting_personnel')
        .select('*')
        .eq('is_active', true)
        .order('full_name', { ascending: true });

      if (personnelData) {
        const mappedPersonnel: ReportingPersonnel[] = personnelData.map((p) => ({
          id: p.id,
          userId: p.user_id,
          fullName: p.full_name,
          professionalType: p.professional_type,
          qualification: p.qualification,
          registrationCouncil: p.registration_council,
          registrationNumber: p.registration_number,
          specialization: p.specialization,
          phone: p.phone,
          email: p.email,
          signatureUrl: p.signature_url,
          canEnterResults: p.can_enter_results,
          canVerifyResults: p.can_verify_results,
          canAcknowledgeCritical: p.can_acknowledge_critical,
          canSignReports: p.can_sign_reports,
          isActive: p.is_active,
          displayOrder: p.display_order,
          createdAt: p.created_at,
          updatedAt: p.updated_at,
        }));
        setSignatories(mappedPersonnel);
        if (mappedPersonnel.length > 0) {
          setPerformedById(mappedPersonnel[0].id);
          const signer = mappedPersonnel.find((p) => p.canSignReports && p.id !== mappedPersonnel[0].id);
          if (signer) setSignedById(signer.id);
          else setSignedById('');
        }
      }

      // 6. Fetch master parameters for this test:
      // Supports direct parameters and profile components resolution (e.g., PRO-0001 LFT)
      let reportableMasterParams: any[] = [];
      const testIdsForLookup = [itemData.test_id];

      // 6a. Query direct parameters
      const { data: directParams, error: directParamErr } = await supabase
        .from('parameters')
        .select('id, test_id, code, name, value_type, unit, formula, calculation_identifier, display_order, options, interpretation_config, is_mandatory')
        .eq('test_id', itemData.test_id)
        .eq('is_active', true)
        .order('display_order', { ascending: true });

      if (directParamErr) throw directParamErr;

      const directReportable = (directParams || []).filter((mp) =>
        isReportableParameter(mp, {
          test_code: itemData.test?.code,
          test_name: itemData.test_name,
          results: directParams,
        })
      );

      if (directReportable.length > 0) {
        reportableMasterParams = directReportable;
      } else {
        // Check catalogue_panel_components for profile/panel definitions
        const { data: panelComps } = await supabase
          .from('catalogue_panel_components')
          .select('display_order, is_required, component_test_id, component_parameter_id')
          .eq('panel_test_id', itemData.test_id)
          .order('display_order', { ascending: true });

        if (panelComps && panelComps.length > 0) {
          const compTestIds = panelComps.map((c) => c.component_test_id).filter(Boolean);
          testIdsForLookup.push(...compTestIds);

          const { data: childParams } = await supabase
            .from('parameters')
            .select('id, test_id, code, name, value_type, unit, formula, calculation_identifier, display_order, options, interpretation_config, is_mandatory')
            .in('test_id', compTestIds)
            .eq('is_active', true)
            .order('display_order', { ascending: true });

          const childParamsByTest = new Map<string, any[]>();
          for (const cp of childParams || []) {
            if (!childParamsByTest.has(cp.test_id)) {
              childParamsByTest.set(cp.test_id, []);
            }
            childParamsByTest.get(cp.test_id)!.push(cp);
          }

          const assembledPanelParams: any[] = [];
          for (const comp of panelComps) {
            if (comp.component_test_id) {
              const params = childParamsByTest.get(comp.component_test_id) || [];
              for (const p of params) {
                if (isReportableParameter(p, { test_code: itemData.test?.code, test_name: itemData.test_name, results: params })) {
                  assembledPanelParams.push(p);
                }
              }
            } else if (comp.component_parameter_id) {
              const matched = (childParams || []).find((p) => p.id === comp.component_parameter_id);
              if (matched) assembledPanelParams.push(matched);
            }
          }

          reportableMasterParams = assembledPanelParams;
        }
      }

      // 6b. Fetch analyzer mappings for this test & component tests to power the Source chip
      const { data: mappingRows } = await supabase
        .from('analyzer_parameter_mappings')
        .select('parameter_id, analyzer_id, analyzers(name, code, lifecycle_status)')
        .in('test_id', testIdsForLookup);

      setAnalyzerLookup(buildAnalyzerLookup(
        ((mappingRows ?? []) as unknown as Array<{
          parameter_id: string;
          analyzer_id?: string;
          is_active?: boolean;
          analyzers: Array<{ name: string; code?: string; lifecycle_status?: string }> | { name: string; code?: string; lifecycle_status?: string } | null;
        }>).map((m) => ({
          parameter_id: m.parameter_id,
          analyzer_id: m.analyzer_id,
          is_active: m.is_active,
          analyzers: Array.isArray(m.analyzers) ? (m.analyzers[0] ?? null) : m.analyzers,
        }))
      ));

      // 8. Fetch approved reference ranges for these parameters
      const paramIds = reportableMasterParams.map((p) => p.id);
      let allRanges: DbReferenceRange[] = [];

      if (paramIds.length > 0) {
        const { data: rangeData } = await supabase
          .from('reference_ranges')
          .select('*')
          .in('parameter_id', paramIds)
          .eq('is_active', true)
          .eq('is_approved', true);

        allRanges = (rangeData || []) as DbReferenceRange[];
      }

      // 9. Fetch existing test_results rows
      const { data: existingResults, error: resErr } = await supabase
        .from('test_results')
        .select('*')
        .eq('order_item_id', orderItemId);

      if (resErr) throw resErr;

      if (existingResults && existingResults.length > 0) {
        const firstWithVerified = existingResults.find((r) => r.verified_by_name || r.verified_at);
        if (firstWithVerified) {
          setVerifiedMeta({
            verifiedBy: firstWithVerified.verified_by_name,
            verifiedAt: firstWithVerified.verified_at,
          });
        }
      }

      const existingMap = new Map((existingResults || []).map((r) => [r.parameter_id, r]));

      // 10. Assemble state with authoritative patient-specific reference range
      const assembled: ParamResultState[] = reportableMasterParams.map((mp) => {
        const existing = existingMap.get(mp.id);
        const paramRanges = allRanges.filter((r) => r.parameter_id === mp.id);
        const resolvedRange = patientAgeDays == null
          ? null
          : resolvePatientReferenceRange(paramRanges, patientAgeDays, patientGender);
        const resolvedRangeText = formatReferenceRangeText(resolvedRange);

        const interpretation = mp.interpretation_config && typeof mp.interpretation_config === 'object'
          ? mp.interpretation_config as Record<string, unknown>
          : {};
        const defaultValue = typeof interpretation.default_value === 'string'
          ? interpretation.default_value
          : '';
        const val = existing?.display_value ?? defaultValue;
        const { flag, isCritical } = evaluateResultFlag(val, mp.value_type, resolvedRange);

        return {
          id: existing?.id,
          parameter_id: mp.id,
          code: mp.code,
          name: mp.name,
          value_type: mp.value_type,
          unit: mp.unit,
          formula: resolveParameterFormula(mp.code, mp.calculation_identifier, mp.formula),
          options: Array.isArray(mp.options)
            ? (mp.options as unknown[]).filter((option: unknown): option is string => typeof option === 'string')
            : [],
          multiline: interpretation.control === 'Text Multi-line',
          timeControl: ['Time','Time/Duration'].includes(String(interpretation.control||'')) && mp.unit === 'Min:Sec',
          display_value: val,
          numeric_value: existing?.numeric_value ?? null,
          text_value: existing?.text_value ?? null,
          flag: existing?.flag ? (existing.flag as ResultFlag) : flag,
          is_critical: existing?.is_critical ?? isCritical,
          critical_acknowledged: existing?.critical_acknowledged || false,
          normal_min: resolvedRange?.normal_min ?? null,
          normal_max: resolvedRange?.normal_max ?? null,
          critical_low: resolvedRange?.critical_low ?? null,
          critical_high: resolvedRange?.critical_high ?? null,
          normal_text: resolvedRange?.normal_text ?? null,
          reference_text: resolvedRange?.reference_text ?? null,
          resolved_range_text: resolvedRangeText,
          resolved_range: resolvedRange,
          result_source: (existing as any)?.result_source || (mp.value_type === 'Calculated' ? 'CALCULATED' : 'MANUAL'),
          status: (existing?.status as ResultStatus) || RESULT_STATUSES.DRAFT,
          is_mandatory: mp.is_mandatory !== false,
        };
      });

      // 10. Fetch active PT/INR reagent configuration
      const { data: ptConfigData } = await (supabase.rpc as any)('get_active_pt_inr_config');
      const loadedPtConfig = ptConfigData || null;
      setPtInrConfig(loadedPtConfig);

      const ptContext = loadedPtConfig && loadedPtConfig.mnpt > 0 && loadedPtConfig.isi > 0
        ? { MNPT: loadedPtConfig.mnpt, ISI: loadedPtConfig.isi }
        : undefined;

      // Recalculate automatic formulas in topological order
      const calculatedAssembled = recalculateInvestigationParameters(assembled, evaluateResultFlag, ptContext);
      setResults(calculatedAssembled);
      const blockerResponse = await (supabase.rpc as any)('calculation_dependency_blockers', { p_order_item_id: orderItemId });
      if (!blockerResponse.error) {
        const blockers = Array.isArray(blockerResponse.data) ? blockerResponse.data : [];
        setCalculationBlockers(blockers.map((blocker: any) => {
          const missing = Array.isArray(blocker.missing_dependencies) ? blocker.missing_dependencies.map((item: any) => item.source_identifier || item.input_key).join(', ') : '';
          return `${blocker.parameter_name || blocker.parameter_code}: ${missing ? `waiting for ${missing}` : blocker.error_code || 'calculation pending'}`;
        }));
      }
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load test details.'));
    } finally {
      setLoading(false);
    }
  }, [orderItemId, routeOrderId]);

  useEffect(() => {
    loadItemAndResults();
  }, [loadItemAndResults]);

  const hasUnackCritical = results.some((r) => r.is_critical && !r.critical_acknowledged);

  useEffect(() => {
    const action = searchParams.get('action');
    const key = `${orderItemId || ''}:${action || ''}:${searchParams.get('group') || ''}`;
    if (!action || loading || handledRouteAction.current === key) return;
    handledRouteAction.current = key;
    if (action === 'sign' && readiness?.is_ready && reportGroup?.report_group_id === searchParams.get('group')) {
      setSignOffModalOpen(true);
    } else if (action === 'critical' && hasUnackCritical && can(PERMISSION_KEYS.CAN_ACKNOWLEDGE_CRITICAL)) {
      setCriticalModalOpen(true);
    } else {
      window.setTimeout(() => document.querySelector<HTMLElement>(`[data-workflow-action="${action}"]`)?.focus(), 80);
    }
  }, [can, hasUnackCritical, loading, orderItemId, readiness?.is_ready, reportGroup?.report_group_id, searchParams]);

  // Recalculate automatic formulas when parameter values change
  const handleValueChange = (index: number, val: string) => {
    const previous = results;
    const updated = results.map((result) => ({ ...result }));
    const param = updated[index];
    param.display_value = val;

    if (param.value_type === 'Numeric') {
      const num = parseFloat(val);
      param.numeric_value = isNaN(num) ? null : num;
    } else {
      param.text_value = val;
    }

    const { flag, isCritical } = evaluateResultFlag(val, param.value_type, param.resolved_range);
    param.flag = flag;
    param.is_critical = isCritical;

    const ptContext = ptInrConfig && typeof ptInrConfig.mnpt === 'number' && ptInrConfig.mnpt > 0 && typeof ptInrConfig.isi === 'number' && ptInrConfig.isi > 0
      ? { MNPT: ptInrConfig.mnpt, ISI: ptInrConfig.isi }
      : undefined;

    // Run full topological recalculation across all parameters
    const fullyRecalculated = recalculateInvestigationParameters(updated, evaluateResultFlag, ptContext)
      .map((next) => {
        const prior = previous.find((candidate) => candidate.parameter_id === next.parameter_id);
        const materialValueChanged = prior && (
          prior.display_value !== next.display_value
          || prior.numeric_value !== next.numeric_value
          || prior.text_value !== next.text_value
          || prior.flag !== next.flag
          || prior.is_critical !== next.is_critical
        );
        return materialValueChanged ? { ...next, critical_acknowledged: false } : next;
      });
    setResults(fullyRecalculated);
  };

  // Critical Value Notification Documentation
  const handleConfirmCriticalAcknowledgment = async () => {
    if (!notifiedPerson.trim()) {
      setError('Please specify the clinician or ward staff who received the panic alert notification.');
      return;
    }

    try {
      const updated = results.map((r) => (r.is_critical ? { ...r, critical_acknowledged: true } : r));
      setResults(updated);

      if (orderItem) {
        const { error: acknowledgementError } = await supabase.rpc(
          'record_critical_value_acknowledgement',
          {
            p_order_item_id: orderItemId,
            p_notification_method: notificationMethod,
            p_notified_person: notifiedPerson.trim(),
            p_comment: notificationComment.trim() || null,
          }
        );
        if (acknowledgementError) throw acknowledgementError;
      }

      setCriticalModalOpen(false);
      setToastMsg('Critical panic value notification documented and audited.');
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to acknowledge critical value.'));
    }
  };

  // Save / Submit / Verify Results
  const handleSaveResults = async (targetStatus: ResultStatus) => {
    if (!orderItem || !orderItemId) return;

    if (targetStatus === RESULT_STATUSES.VERIFIED && results.some((r) => r.is_critical && !r.critical_acknowledged)) {
      setError('Cannot verify results: Critical panic alerts must be documented and acknowledged first.');
      return;
    }
    const invalidTime=results.find(result=>result.timeControl&&validateMinSec(result.display_value));
    if(invalidTime){setError(`${invalidTime.name}: ${validateMinSec(invalidTime.display_value)}`);return;}

    const ptContext = ptInrConfig && typeof ptInrConfig.mnpt === 'number' && ptInrConfig.mnpt > 0 && typeof ptInrConfig.isi === 'number' && ptInrConfig.isi > 0
      ? { MNPT: ptInrConfig.mnpt, ISI: ptInrConfig.isi }
      : undefined;

    // Browser calculations are previews only. The database owns every
    // clinically persisted Calculated/DerivedInterpretation value.
    const finalCalculatedResults = recalculateInvestigationParameters(results, evaluateResultFlag, ptContext);

    // Direct Bilirubin cannot exceed Total Bilirubin validation
    const tbil = results.find(r => ['TBIL', 'TOTAL_BILIRUBIN'].includes(r.code.toUpperCase()));
    const dbil = results.find(r => ['DBIL', 'DIRECT_BILIRUBIN'].includes(r.code.toUpperCase()));
    if (tbil && dbil && tbil.numeric_value !== null && dbil.numeric_value !== null && tbil.numeric_value !== undefined && dbil.numeric_value !== undefined) {
      if (dbil.numeric_value > tbil.numeric_value) {
        setError('Direct Bilirubin cannot exceed Total Bilirubin.');
        return;
      }
    }

    // Required dependency and input validation before verification
    if (targetStatus === RESULT_STATUSES.VERIFIED) {
      const hasGlob = results.some(r => ['GLOB', 'GLOBULIN'].includes(r.code.toUpperCase()));
      const tp = results.find(r => ['TP', 'TOTAL_PROTEIN'].includes(r.code.toUpperCase()));
      if (hasGlob && (!tp || tp.display_value.trim() === '')) {
        setError('Cannot verify: Total Protein is required for Globulin calculation.');
        return;
      }

      const hasAg = results.some(r => ['AG_RATIO', 'A_G_RATIO'].includes(r.code.toUpperCase()));
      const alb = results.find(r => ['ALB', 'ALBUMIN'].includes(r.code.toUpperCase()));
      if (hasAg && (!alb || alb.display_value.trim() === '')) {
        setError('Cannot verify: Albumin is required for A:G Ratio calculation.');
        return;
      }

      // Check if any required editable parameter is missing
      const emptyRequired = results.find(r =>
        r.value_type !== 'Calculated' &&
        r.value_type !== 'Heading' &&
        r.is_mandatory !== false &&
        r.display_value.trim() === ''
      );
      if (emptyRequired) {
        setError(`Cannot verify: "${emptyRequired.name}" is required.`);
        const idx = results.findIndex(r => r.parameter_id === emptyRequired.parameter_id);
        if (idx !== -1 && inputRefs.current[idx]) {
          inputRefs.current[idx]?.focus();
        }
        return;
      }
    }

    // 2. Clinical Error Gate: If verification or submission, reject if divide-by-zero or calculation error
    if (targetStatus === RESULT_STATUSES.VERIFIED || targetStatus === RESULT_STATUSES.SUBMITTED_FOR_VERIFICATION) {
      const errorParam = finalCalculatedResults.find(
        (r) => r.value_type === 'Calculated' && r.display_value === 'Calculation Error'
      );
      if (errorParam) {
        setError(
          `Cannot proceed: Calculated parameter "${errorParam.name}" has a mathematical calculation error (e.g. division by zero). Please correct the input values.`
        );
        return;
      }
    }

    setSaving(true);
    setError(null);

    try {
      const resultPayload = finalCalculatedResults
        .filter((r) => r.value_type !== 'Calculated' && r.value_type !== 'Heading')
        .map((r) => ({
          parameter_id: r.parameter_id,
          numeric_value: r.numeric_value,
          text_value: r.text_value,
          display_value: r.display_value.trim(),
          flag: r.flag,
          is_critical: r.is_critical,
          critical_acknowledged: r.critical_acknowledged || false,
          result_source: r.result_source || (r.value_type === 'Calculated' ? 'CALCULATED' : 'MANUAL'),
          normal_range_text: r.resolved_range_text,
          normal_min: r.normal_min,
          normal_max: r.normal_max,
          critical_low: r.critical_low,
          critical_high: r.critical_high,
      }));

      const { error: saveError } = await supabase.rpc('save_test_results', {
        p_order_item_id: orderItemId,
        p_results: resultPayload,
        p_target_status: targetStatus,
        p_amended_from_report_id: amendReportId || null,
        p_amendment_reason: amendReportId ? amendmentReason.trim() : null,
        p_expected_revision: orderItem.result_revision,
      });
      if (saveError) throw saveError;

      const toastMessage =
        targetStatus === RESULT_STATUSES.DRAFT
          ? 'Draft results successfully saved.'
          : targetStatus === RESULT_STATUSES.SUBMITTED_FOR_VERIFICATION
          ? 'Results submitted for verification.'
          : targetStatus === RESULT_STATUSES.VERIFIED
          ? 'Results successfully verified.'
          : `Status updated: ${targetStatus}`;

      setToastMsg(toastMessage);
      publishWorkflowInvalidation('result-changed',['worklist','dashboard'],orderItem.id);
      await loadItemAndResults();
      if (targetStatus !== RESULT_STATUSES.DRAFT) {
        const nextAction = await getNextOrderAction(supabase, orderItem.order_id);
        setToastMsg(nextAction.message);
        scheduleOrderNavigation(navigate, nextAction);
      }
    } catch (err: any) {
      setReloadLatestRequired(String(err?.message || '').includes('RESULT_REVISION_CONFLICT'));
      setError(safeErrorMessage(err, 'Failed to save results.'));
    } finally {
      setSaving(false);
    }
  };

  // Submit Pending Technical / Equipment Configuration
  const handleSubmitPendingConfiguration = async () => {
    if (!orderItem?.test_id) return;
    setSavingConfig(true);
    try {
      const { error: cfgErr } = await (supabase.rpc as any)('catalogue_submit_pending_configuration', {
        p_test_id: orderItem.test_id,
        p_analyzer_model: configAnalyzerModel.trim() || null,
        p_reagent_manufacturer: configReagentManufacturer.trim() || null,
        p_method: configMethod.trim() || null,
        p_unit: configUnit.trim() || null,
        p_normal_min: configNormalMin ? parseFloat(configNormalMin) : null,
        p_normal_max: configNormalMax ? parseFloat(configNormalMax) : null,
        p_critical_low: configCriticalLow ? parseFloat(configCriticalLow) : null,
        p_critical_high: configCriticalHigh ? parseFloat(configCriticalHigh) : null,
        p_normal_text: configNormalText.trim() || null,
        p_notes: configNotes.trim() || null,
      });
      if (cfgErr) throw cfgErr;
      setConfigModalOpen(false);
      setToastMsg('Clinical equipment & range configuration saved as PENDING_APPROVAL.');
      await loadItemAndResults();
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to save pending configuration.'));
    } finally {
      setSavingConfig(false);
    }
  };

  // Sign-Off & Generate Final Report
  const handleConfirmSignOff = async () => {
    if (!orderItem?.order_id) return;
    if (!performedById) {
      setError('Please select the Reporting Personnel who performed the report.');
      return;
    }
    if (amendReportId && !amendmentReason.trim()) {
      setError('A clinical justification is required to issue an amended report.');
      return;
    }

    setIsSigning(true);
    setError(null);

    try {
      const rawToken = generateRawToken();
      const tokenHash = await hashToken(rawToken);
      const publicUrl = 'https://dashboard.bimalpathology.com.np/o/' + rawToken;

      if (!reportGroup?.report_group_id) throw new Error('REPORT_GROUP_CONTEXT_MISSING');
      const { data, error: signErr } = await (supabase.rpc as any)('sign_and_queue_report_group', {
        p_report_group_id: reportGroup.report_group_id,
        p_performed_by_id: performedById,
        p_signed_by_id: signedById || null,
        p_amendment_reason: amendReportId ? amendmentReason.trim() : null,
        p_amended_from_report_id: amendReportId || null,
        p_token_hash: tokenHash,
        p_order_public_url: publicUrl,
      });

      if (signErr) throw signErr;

      const smsStatus = data?.sms_status || 'Notification status unavailable';

      setSignOffModalOpen(false);

      setToastMsg(`${reportGroup.title} report ${data.report_number} created. ${smsStatus}. Other report groups remain independent.`);
      publishWorkflowInvalidation('report-changed',['worklist','reports','dashboard'],data.report_id);

      await loadItemAndResults();
      const nextAction = await getNextOrderAction(supabase, orderItem.order_id);
      setToastMsg(nextAction.message);
      scheduleOrderNavigation(navigate, nextAction, 850);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to sign and generate final report.'));
    } finally {
      setIsSigning(false);
    }
  };

  const currentOverallStatus = useMemo(() => {
    if (orderItem?.status === 'Verified' || orderItem?.status === 'SignedOff') {
      return RESULT_STATUSES.VERIFIED;
    }
    if (results.length > 0 && results.every((r) => r.status === RESULT_STATUSES.VERIFIED)) {
      return RESULT_STATUSES.VERIFIED;
    }
    if (results.some((r) => r.status === RESULT_STATUSES.SUBMITTED_FOR_VERIFICATION)) {
      return RESULT_STATUSES.SUBMITTED_FOR_VERIFICATION;
    }
    if (results.some((r) => r.status === RESULT_STATUSES.RETURNED_FOR_CORRECTION)) {
      return RESULT_STATUSES.RETURNED_FOR_CORRECTION;
    }
    return RESULT_STATUSES.DRAFT;
  }, [orderItem, results]);

  const isCurrentVerified = currentOverallStatus === RESULT_STATUSES.VERIFIED;
  const isOrderFullyReady = Boolean(readiness?.is_ready);
  const verifiedCount = readiness?.verified_count || 0;
  const reportableCount = readiness?.reportable_count || siblings.length;
  const waitingCount = Math.max(0, reportableCount - verifiedCount);
  const hasExistingReport = Boolean(existingReport);
  const completedInvestigationCount = siblings.filter((sib) => ['Verified', 'SignedOff'].includes(sib.status)).length;
  const reportGroups = [...new Map(siblings.filter((sib) => sib.report_group_id).map((sib) => [sib.report_group_id!, sib])).values()];
  const signedGroupCount = reportGroups.filter((group) => ['SignedOff', 'Amended'].includes(group.report_state || '')).length;
  const isOutsource = orderItem?.execution_route === 'OUTSOURCE';

  const isWaitingExternal =
    searchParams.get('summary') === 'waiting' ||
    (siblings.length > 0 &&
      siblings.filter((s) => s.execution_route !== 'OUTSOURCE').every((s) => ['Verified', 'SignedOff'].includes(s.status)) &&
      siblings.some((s) => s.execution_route === 'OUTSOURCE' && ['Dispatched', 'AwaitingExternalResult', 'ProcessingAtReferenceLab'].includes(s.outsource_state || '')));

  const activeStepLabel = useMemo(() => {
    if (signedGroupCount === reportGroups.length && reportGroups.length > 0) {
      return 'Delivery';
    }
    if (isOrderFullyReady) {
      return 'Report';
    }
    if (isOutsource) {
      if (orderItem?.outsource_state === 'Dispatched' || orderItem?.outsource_state === 'AwaitingExternalResult') {
        return 'External Result';
      }
      if (orderItem?.outsource_state === 'ResultReceived' || orderItem?.outsource_state === 'InternalReview') {
        return 'Review';
      }
      if (orderItem?.outsource_state === 'AwaitingDispatch') {
        return 'Dispatch';
      }
    }
    if (currentOverallStatus === RESULT_STATUSES.SUBMITTED_FOR_VERIFICATION || isCurrentVerified) {
      return 'Verify';
    }
    if (currentOverallStatus === RESULT_STATUSES.DRAFT) {
      return 'Result';
    }
    if (orderItem?.sample?.status === 'Pending' || orderItem?.sample?.status === 'Collected') {
      return 'Sample';
    }
    return 'Result';
  }, [currentOverallStatus, isCurrentVerified, isOrderFullyReady, isOutsource, orderItem, reportGroups.length, signedGroupCount]);

  return (
    <Box>
      <Box sx={{ mb: 2, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <Button startIcon={<ArrowBackIcon />} onClick={() => navigate('/worklist')}>
          Back to Laboratory Worklist
        </Button>
      </Box>

      <SmartMessageDialog
        open={Boolean(error)}
        message={error || ''}
        primaryLabel={reloadLatestRequired ? 'Reload Latest' : undefined}
        onPrimary={() => {
          setError(null);
          if (reloadLatestRequired) {
            setReloadLatestRequired(false);
            void loadItemAndResults();
          }
        }}
      />

      {calculationBlockers.length > 0 && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          <strong>Calculated results waiting for required inputs:</strong>
          <Box component="ul" sx={{ my: 0.5, pl: 2.5 }}>
            {calculationBlockers.map((blocker) => <li key={blocker}>{blocker}</li>)}
          </Box>
        </Alert>
      )}

      {/* Critical Panic Value Alert */}
      {hasUnackCritical && (
        <Alert
          severity="error"
          sx={{ mb: 3 }}
          action={
            can(PERMISSION_KEYS.CAN_ACKNOWLEDGE_CRITICAL) && (
              <Button color="error" variant="contained" size="small" onClick={() => setCriticalModalOpen(true)}>
                Acknowledge Panic Alert
              </Button>
            )
          }
        >
          <strong>Critical Pathological Value Detected:</strong> Immediate clinician notification and audit acknowledgment required prior to verification or sign-off.
        </Alert>
      )}

      {/* Outsource Waiting State Banner */}
      {isWaitingExternal && (
        <Paper
          elevation={0}
          sx={{
            p: 2.5,
            mb: 2.5,
            border: '1px solid #93c5fd',
            bgcolor: '#eff6ff',
            borderRadius: 2,
          }}
        >
          <Typography variant="subtitle1" fontWeight={800} color="primary.main" sx={{ mb: 0.5 }}>
            Order Status: Internal Investigations Complete · Awaiting External Reference Laboratory
          </Typography>
          <Typography variant="body2" sx={{ mb: 2, color: 'text.secondary' }}>
            <strong>Internal Reports:</strong> Ready / Signed &bull;{' '}
            <strong>Outsource:</strong> Awaiting External Result &bull;{' '}
            <strong>Next Action:</strong> No laboratory action required until external result is received.
          </Typography>
          <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
            <Button size="small" variant="contained" onClick={() => navigate('/worklist')}>
              Back to Worklist
            </Button>
            <Button size="small" variant="outlined" onClick={() => navigate('/')}>
              Dashboard
            </Button>
            {orderItem?.order_id && (
              <>
                <Button size="small" variant="outlined" onClick={() => navigate(`/outsource?orderId=${orderItem.order_id}`)}>
                  Outsource Tracking
                </Button>
                <Button size="small" variant="outlined" onClick={() => navigate(`/reports?orderId=${orderItem.order_id}`)}>
                  Delivery Summary
                </Button>
              </>
            )}
          </Box>
        </Paper>
      )}



      {/* ==================================================================== */}
      {/* 1. TOP PATIENT & INVESTIGATION WORKSPACE OVERVIEW                    */}
      {/* ==================================================================== */}
      <Paper
        elevation={0}
        sx={{
          mb: 2.5,
          p: 2,
          border: '1px solid #e2e8f0',
          bgcolor: '#ffffff',
          borderRadius: 2,
        }}
      >
        <Grid container spacing={2} alignItems="center">
          <Grid item xs={12} sm={6} md={2.5}>
            <Typography variant="caption" color="text.secondary" fontWeight={600} sx={{ textTransform: 'uppercase' }}>
              Patient
            </Typography>
            <Typography variant="body1" fontWeight={700} color="text.primary">
              {orderItem?.order?.patient?.full_name || '-'}
            </Typography>
            {can(PERMISSION_KEYS.CAN_EDIT_PATIENT) && !hasExistingReport && orderItem?.order?.patient?.id && (
              <Button
                size="small"
                startIcon={<EditIcon />}
                onClick={() => navigate(`/patients?edit=${orderItem.order.patient.id}&returnTo=${encodeURIComponent(`/worklist/entry/${orderItemId}`)}`)}
                sx={{ mt: 0.5, px: 0 }}
              >
                Correct demographics
              </Button>
            )}
          </Grid>

          <Grid item xs={6} sm={3} md={1.5}>
            <Typography variant="caption" color="text.secondary" fontWeight={600} sx={{ textTransform: 'uppercase' }}>
              UHID
            </Typography>
            <Typography variant="body2" fontWeight={700} sx={{ fontFamily: 'monospace' }} color="primary.main">
              {orderItem?.order?.patient?.uhid || '-'}
            </Typography>
          </Grid>

          <Grid item xs={6} sm={3} md={1.8}>
            <Typography variant="caption" color="text.secondary" fontWeight={600} sx={{ textTransform: 'uppercase' }}>
              Lab No.
            </Typography>
            <Typography variant="body2" fontWeight={700} sx={{ fontFamily: 'monospace' }}>
              {orderItem?.order?.order_number || '-'}
            </Typography>
          </Grid>

          <Grid item xs={6} sm={3} md={1.4}>
            <Typography variant="caption" color="text.secondary" fontWeight={600} sx={{ textTransform: 'uppercase' }}>
              Age / Sex
            </Typography>
            <Typography variant="body2" fontWeight={600}>
              {orderItem?.order?.patient?.age_years ? `${orderItem.order.patient.age_years} Y` : '-'} / {orderItem?.order?.patient?.gender || '-'}
            </Typography>
          </Grid>

          <Grid item xs={6} sm={4} md={2.8}>
            <Typography variant="caption" color="text.secondary" fontWeight={600} sx={{ textTransform: 'uppercase' }}>
              Investigation & Dept
            </Typography>
            <Typography variant="body2" fontWeight={700} color="text.primary">
              {orderItem?.test_name || '-'}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              {orderItem?.department || 'Clinical Pathology'}
            </Typography>
          </Grid>

          <Grid item xs={12} sm={5} md={2}>
            <Typography variant="caption" color="text.secondary" fontWeight={600} sx={{ textTransform: 'uppercase' }}>
              Sample & Status
            </Typography>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mt: 0.25 }}>
              <Typography variant="caption" sx={{ fontFamily: 'monospace', fontWeight: 600, color: 'text.secondary' }}>
                {orderItem?.sample?.barcode || '-'}
              </Typography>
              <StatusChip status={currentOverallStatus} />
            </Box>
          </Grid>
        </Grid>

        <Box sx={{ mt: 1.5, pt: 1.25, borderTop: '1px solid #e2e8f0', display: 'flex', gap: 1, flexWrap: 'wrap', alignItems: 'center' }}>
          <Typography variant="caption" fontWeight={800} color="text.primary">
            Progress: {completedInvestigationCount} / {siblings.length} investigations completed &bull; {signedGroupCount} / {reportGroups.length} report groups signed
          </Typography>
          {(isOutsource
            ? ['Billing', 'Sample', 'Dispatch', 'External Result', 'Review', 'Report', 'Delivery']
            : ['Billing', 'Sample', 'Result', 'Verify', 'Report', 'Delivery']
          ).map((step) => {
            const isActive = step === activeStepLabel;
            return (
              <Chip
                key={step}
                size="small"
                label={step}
                variant={isActive ? 'filled' : 'outlined'}
                color={isActive ? 'primary' : 'default'}
                sx={{
                  fontWeight: isActive ? 800 : 500,
                  fontSize: '0.68rem',
                  height: 22,
                }}
              />
            );
          })}
        </Box>

        {/* Verification meta tag if verified */}
        {isCurrentVerified && (
          <Box sx={{ mt: 1.5, pt: 1, borderTop: '1px solid #f1f5f9', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap' }}>
            <Typography variant="caption" fontWeight={700} color="success.main">
              ✓ Verified Investigation Result
            </Typography>
            <Typography variant="caption" color="text.secondary">
              Verified By: <strong>{verifiedMeta?.verifiedBy || 'Pathologist / Lab Technologist'}</strong>
              {verifiedMeta?.verifiedAt && ` • ${formatAdDateTime(verifiedMeta.verifiedAt)}`}
            </Typography>
          </Box>
        )}
      </Paper>

      {/* ==================================================================== */}
      {/* 2. ORDER READINESS & INVESTIGATION SIBLINGS                          */}
      {/* ==================================================================== */}
      <Paper
        elevation={0}
        sx={{
          mb: 2.5,
          p: 2,
          border: '1px solid #e2e8f0',
          bgcolor: '#ffffff',
          borderRadius: 2,
        }}
      >
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 1.5 }}>
          {/* Order Readiness Summary */}
          <Box>
            <Typography variant="body2" fontWeight={800} color="text.primary" sx={{ display: 'flex', alignItems: 'center', gap: 0.75 }}>
              {hasExistingReport ? (
                <>
                  <CheckCircleIcon color="success" fontSize="small" /> Final Report Generated ({existingReport.report_number} • v{existingReport.version})
                </>
              ) : isOrderFullyReady ? (
                <>
                  <CheckCircleIcon color="success" fontSize="small" /> All investigations verified &bull; Ready for final report
                </>
              ) : (
                <>
                  Final Report: Waiting for {waitingCount} investigation{waitingCount > 1 ? 's' : ''}
                </>
              )}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              {hasExistingReport
                ? existingReport.signed_by_personnel_name
                  ? `Authorized by ${existingReport.signed_by_personnel_name} on ${formatAdDateTime(existingReport.signed_at)}.`
                  : `Final report issued on ${formatAdDateTime(existingReport.signed_at)}.`
                : `${verifiedCount} of ${reportableCount} investigations verified in this Lab Order.`}
            </Typography>
          </Box>

          {/* Quick Action Buttons */}
          <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', alignItems: 'center' }}>
            {hasExistingReport ? (
              <>
                <Button
                  variant="outlined"
                  size="small"
                  startIcon={<PrintIcon />}
                  onClick={() => navigate(`/reports?reportId=${existingReport.id}`)}
                  sx={{ fontWeight: 600 }}
                >
                  Open Report (Print)
                </Button>
                <Button
                  variant="contained"
                  size="small"
                  color="primary"
                  startIcon={<ArrowForwardIcon />}
                  onClick={handleNextPendingPatient}
                  sx={{ fontWeight: 600 }}
                >
                  Next Pending Patient →
                </Button>
                <Button
                  variant="outlined"
                  size="small"
                  color="secondary"
                  onClick={() => navigate('/billing/new')}
                  sx={{ fontWeight: 600 }}
                >
                  + New Bill (F2)
                </Button>
              </>
            ) : (
              can(PERMISSION_KEYS.CAN_SIGN_REPORTS) && (
                <Button
                  data-workflow-action="sign"
                  variant="contained"
                  color="success"
                  size="small"
                  startIcon={<DrawIcon />}
                  disabled={!isOrderFullyReady}
                  onClick={() => setSignOffModalOpen(true)}
                  sx={{ fontWeight: 700, px: 2 }}
                >
                  {amendReportId ? `Sign ${reportGroup?.title || 'Group'} Amendment (F9)` : `Sign ${reportGroup?.title || 'Report Group'} Report (F9)`}
                </Button>
              )
            )}
          </Box>
        </Box>

        {/* Sibling Investigation Pills */}
        <Divider sx={{ my: 1.5 }} />
        <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', alignItems: 'center' }}>
          <Typography variant="caption" fontWeight={700} color="text.secondary" sx={{ mr: 0.5, textTransform: 'uppercase' }}>
            Order workspace{reportGroup?.title ? ` · ${reportGroup.title}` : ''}:
          </Typography>
          {siblings.map((sib) => {
            const isCurrent = sib.id === orderItemId;
            const sibResults = sib.results || [];
            const isSibVerified =
              sib.status === 'Verified' ||
              sib.status === 'SignedOff' ||
              (sibResults.length > 0 && sibResults.every((r) => r.status === 'Verified' || r.status === 'SignedOff'));
            const isSibSubmitted =
              !isSibVerified && sibResults.some((r) => r.status === 'SubmittedForVerification');
            const sibStatus = isSibVerified
              ? 'Verified'
              : isSibSubmitted
              ? 'SubmittedForVerification'
              : 'Draft';

            return (
              <Button
                key={sib.id}
                size="small"
                variant={isCurrent ? 'contained' : 'outlined'}
                color={isCurrent ? 'primary' : 'inherit'}
                onClick={() => {
                  if (!isCurrent) navigate(`/worklist/order/${orderItem.order_id}?item=${sib.id}`);
                }}
                sx={{
                  py: 0.4,
                  px: 1.25,
                  fontSize: '0.75rem',
                  textTransform: 'none',
                  borderColor: isCurrent ? 'primary.main' : '#e2e8f0',
                  bgcolor: isCurrent ? 'primary.main' : '#f8fafc',
                  color: isCurrent ? '#ffffff' : 'text.primary',
                  display: 'flex',
                  gap: 0.75,
                  alignItems: 'center',
                }}
              >
                <span>{sib.report_group_title ? `${sib.report_group_title} · ` : ''}{sib.test_name}</span>
                {sib.execution_route === 'OUTSOURCE' && <Chip size="small" label={sib.outsource_state ? `Outsource · ${sib.outsource_state}` : 'Outsource'} variant="outlined" color="info" />}
                <StatusChip status={sibStatus} />
              </Button>
            );
          })}
        </Box>
      </Paper>

      {/* ==================================================================== */}
      {/* 3. PARAMETER RESULT ENTRY & REVIEW TABLE                             */}
      {/* ==================================================================== */}
      {orderItem?.test?.code === 'PUS_CULTURE_AND_SENSITIVITY' && orderItemId && <AstCultureResultEntry orderItemId={orderItemId} canEnter={canEnterResults} />}
      
      {/* PT / INR Reagent Configuration Notice Banner */}
      {results.some(r => r.code.toUpperCase() === 'INR' || r.code.toUpperCase() === 'COA-0001' || r.name.toUpperCase().includes('PROTHROMBIN')) && (
        <Box sx={{ mb: 2 }}>
          {ptInrConfig && ptInrConfig.mnpt && ptInrConfig.mnpt > 0 && ptInrConfig.isi && ptInrConfig.isi > 0 ? (
            <Alert severity="info" sx={{ py: 0.5, px: 2, borderRadius: 1.5 }}>
              <strong>Active PT/INR Reagent:</strong> {ptInrConfig.reagent_name || 'Commercial PT Reagent'} (MNPT: {ptInrConfig.mnpt} sec, ISI: {ptInrConfig.isi}{ptInrConfig.lot_number ? `, Lot: ${ptInrConfig.lot_number}` : ''}) &bull; Automated INR calculation active: <code>INR = (PT / {ptInrConfig.mnpt})^{ptInrConfig.isi}</code>
            </Alert>
          ) : (
            <Alert severity="warning" sx={{ py: 0.5, px: 2, borderRadius: 1.5 }}>
              <strong>PT/INR Reagent Configuration Notice:</strong> MNPT or ISI is not configured by Administrator. INR automated calculation is disabled, but Prothrombin Time result can still be entered, saved, and reported.
            </Alert>
          )}
        </Box>
      )}

      <Card sx={{ mb: 3, display: orderItem?.test?.code === 'PUS_CULTURE_AND_SENSITIVITY' ? 'none' : 'block' }}>
        <CardContent>
          {loading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
              <CircularProgress />
            </Box>
          ) : (
            <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0' }}>
              <Table size="small">
                <TableHead>
                  <TableRow sx={{ bgcolor: '#f8fafc' }}>
                    <TableCell sx={{ fontWeight: 800, color: '#1e293b' }}>TEST / PARAMETER</TableCell>
                    <TableCell width={220} sx={{ fontWeight: 800, color: '#1e293b' }}>RESULT VALUE</TableCell>
                    <TableCell sx={{ fontWeight: 800, color: '#1e293b' }}>UNIT</TableCell>
                    <TableCell sx={{ fontWeight: 800, color: '#1e293b' }}>REFERENCE RANGE</TableCell>
                    <TableCell align="center" width={100} sx={{ fontWeight: 800, color: '#1e293b' }}>SOURCE</TableCell>
                    <TableCell align="center" width={90} sx={{ fontWeight: 800, color: '#1e293b' }}>FLAG</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {results.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={6} sx={{ py: 5, textAlign: 'center' }}>
                        <Alert severity="info" sx={{ display: 'inline-flex', alignItems: 'center' }}>
                          Clinical parameters are not configured for this test.
                        </Alert>
                      </TableCell>
                    </TableRow>
                  ) : (
                    results.map((param, index) => {
                    const isCalc = param.value_type === 'Calculated';
                    const isHeading = param.value_type === 'Heading';

                    if (isHeading) {
                      return (
                        <TableRow key={param.parameter_id} sx={{ bgcolor: '#f1f5f9' }}>
                          <TableCell colSpan={6}>
                            <Typography variant="subtitle2" fontWeight={800} color="primary.main">
                              {param.name}
                            </Typography>
                          </TableCell>
                        </TableRow>
                      );
                    }

                    // Render abnormal flag badge only (NO badge for Normal / NoRange)
                    let flagBadge: React.ReactNode = null;
                    if (param.flag === RESULT_FLAGS.LOW) {
                      flagBadge = (
                        <Chip
                          label="L"
                          size="small"
                          sx={{ bgcolor: '#dbeafe', color: '#1e40af', fontWeight: 800, fontSize: '0.75rem', height: 22 }}
                        />
                      );
                    } else if (param.flag === RESULT_FLAGS.HIGH) {
                      flagBadge = (
                        <Chip
                          label="H"
                          size="small"
                          sx={{ bgcolor: '#ffedd5', color: '#c2410c', fontWeight: 800, fontSize: '0.75rem', height: 22 }}
                        />
                      );
                    } else if (param.flag === RESULT_FLAGS.CRITICAL_LOW) {
                      flagBadge = (
                        <Chip
                          label="LL"
                          size="small"
                          sx={{ bgcolor: '#fee2e2', color: '#991b1b', fontWeight: 800, fontSize: '0.75rem', height: 22 }}
                        />
                      );
                    } else if (param.flag === RESULT_FLAGS.CRITICAL_HIGH) {
                      flagBadge = (
                        <Chip
                          label="HH"
                          size="small"
                          sx={{ bgcolor: '#fee2e2', color: '#991b1b', fontWeight: 800, fontSize: '0.75rem', height: 22 }}
                        />
                      );
                    } else if (param.flag === RESULT_FLAGS.ABNORMAL) {
                      flagBadge = (
                        <Chip
                          label="A"
                          size="small"
                          sx={{ bgcolor: '#fef3c7', color: '#92400e', fontWeight: 800, fontSize: '0.75rem', height: 22 }}
                        />
                      );
                    }

                    const isNotConfigured = !param.resolved_range_text || param.resolved_range_text === 'Not configured' || param.resolved_range_text === '—';

                    return (
                      <TableRow key={param.parameter_id} hover>
                        <TableCell>
                          <Typography variant="body2" fontWeight={600}>
                            {param.name}
                          </Typography>
                          {isCalc && (
                            <Typography variant="caption" color="secondary.main" sx={{ display: 'block' }}>
                              Server-calculated preview ({param.formula})
                            </Typography>
                          )}
                        </TableCell>
                        <TableCell>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <TextField
                              inputRef={(el) => {
                                inputRefs.current[index] = el;
                              }}
                              size="small"
                              fullWidth
                              value={param.display_value}
                              select={param.value_type === 'Select' && Boolean(param.options?.length)}
                              multiline={param.multiline}
                              minRows={param.multiline ? 3 : undefined}
                              error={Boolean(param.timeControl&&validateMinSec(param.display_value))}
                              helperText={param.timeControl?(validateMinSec(param.display_value)||'Min:Sec, for example 4:30'):undefined}
                              inputProps={param.timeControl?{inputMode:'numeric',pattern:'[0-9]{1,3}:[0-5][0-9]'}:undefined}
                              disabled={isCalc || !canEnterResults || (isCurrentVerified && !amendReportId)}
                              onChange={(e) => handleValueChange(index, e.target.value)}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') {
                                  if (e.shiftKey || e.ctrlKey || e.metaKey || e.altKey) return;
                                  e.preventDefault();
                                  for (let i = index + 1; i < results.length; i++) {
                                    if (results[i].value_type !== 'Calculated' && results[i].value_type !== 'Heading') {
                                      inputRefs.current[i]?.focus();
                                      inputRefs.current[i]?.select();
                                      return;
                                    }
                                  }
                                  saveDraftButtonRef.current?.focus();
                                }
                              }}
                              placeholder={isCalc ? 'Auto-Calculated' : param.value_type === 'Select' ? 'Select result...' : 'Enter result...'}
                              InputProps={{
                                readOnly: isCalc,
                                tabIndex: isCalc ? -1 : 0,
                                sx: {
                                  fontWeight: 700,
                                  bgcolor: isCalc ? '#f0f9ff' : isCurrentVerified && !amendReportId ? '#f8fafc' : '#ffffff',
                                  color: isCalc ? (param.display_value === 'Calculation Error' ? '#dc2626' : '#0369a1') : 'inherit',
                                },
                              }}
                            >
                              {param.value_type === 'Select' && param.options?.map((option) => (
                                <MenuItem key={option} value={option}>{option}</MenuItem>
                              ))}
                            </TextField>
                            {isCalc && (
                              <Chip
                                label="AUTO"
                                size="small"
                                sx={{
                                  bgcolor: param.display_value === 'Calculation Error' ? '#fee2e2' : '#e0f2fe',
                                  color: param.display_value === 'Calculation Error' ? '#991b1b' : '#0369a1',
                                  fontWeight: 800,
                                  fontSize: '0.68rem',
                                  height: 24,
                                  border: param.display_value === 'Calculation Error' ? '1px solid #fca5a5' : '1px solid #bae6fd',
                                }}
                              />
                            )}
                          </Box>
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2" color="text.secondary">
                            {param.unit || '-'}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Typography
                            variant="body2"
                            sx={{
                              fontWeight: isNotConfigured ? 400 : 600,
                              color: isNotConfigured ? 'text.secondary' : 'text.primary',
                              fontStyle: isNotConfigured ? 'italic' : 'normal',
                            }}
                          >
                            {isNotConfigured ? '—' : param.resolved_range_text}
                          </Typography>
                          {param.critical_high !== null && (
                            <Typography variant="caption" color="error.main" sx={{ display: 'block' }}>
                              Critical High: ≥ {param.critical_high}
                            </Typography>
                          )}
                          {param.critical_low !== null && (
                            <Typography variant="caption" color="error.main" sx={{ display: 'block' }}>
                              Critical Low: ≤ {param.critical_low}
                            </Typography>
                          )}
                        </TableCell>
                        <TableCell align="center">
                          {(() => {
                            const src = resolveConfiguredParameterSource({
                              valueType: param.value_type,
                              parameterId: param.parameter_id,
                              analyzerLookup,
                            });
                            return (
                              <Chip
                                label={src.label}
                                size="small"
                                sx={{
                                  bgcolor: src.bgcolor,
                                  color: src.color,
                                  fontWeight: 700,
                                  fontSize: '0.68rem',
                                  height: 22,
                                  maxWidth: 140,
                                  '& .MuiChip-label': { overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' },
                                }}
                              />
                            );
                          })()}
                        </TableCell>
                        <TableCell align="center">
                          {flagBadge}
                        </TableCell>
                      </TableRow>
                    );
                  }))}
                </TableBody>
              </Table>
            </TableContainer>
          )}

          {/* Workflow Action Bar */}
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mt: 3, pt: 2, borderTop: '1px solid #e2e8f0' }}>
            {canEnterResults ? (
              <Button
                ref={saveDraftButtonRef}
                data-keyboard-action="true"
                variant="outlined"
                color="inherit"
                startIcon={<SaveIcon />}
                disabled={saving || results.length === 0 || (isCurrentVerified && !amendReportId)}
                onClick={() => handleSaveResults(RESULT_STATUSES.DRAFT)}
              >
                {saving ? 'Saving...' : 'Save Draft (Ctrl+S)'}
              </Button>
            ) : <Box />}

            <Box sx={{ display: 'flex', gap: 1.5, alignItems: 'center' }}>
              {hasExistingReport ? (
                <>
                  <Button
                    variant="outlined"
                    color="primary"
                    startIcon={<PrintIcon />}
                    onClick={() => navigate(`/reports?reportId=${existingReport.id}`)}
                  >
                    Print / View Report
                  </Button>
                  <Button
                    variant="contained"
                    color="primary"
                    startIcon={<ArrowForwardIcon />}
                    onClick={handleNextPendingPatient}
                  >
                    Next Pending Patient →
                  </Button>
                  <Button
                    variant="outlined"
                    color="secondary"
                    onClick={() => navigate('/billing/new')}
                  >
                    + New Bill (F2)
                  </Button>
                </>
              ) : isCurrentVerified && !amendReportId ? (
                <>
                  {can(PERMISSION_KEYS.CAN_SIGN_REPORTS) && (
                    <Button
                      data-workflow-action="sign"
                      variant="contained"
                      color="success"
                      startIcon={<DrawIcon />}
                      disabled={!isOrderFullyReady || saving}
                      onClick={() => setSignOffModalOpen(true)}
                      sx={{ fontWeight: 700, px: 2.5 }}
                    >
                      Sign Report (F9)
                    </Button>
                  )}
                  <Button
                    variant="outlined"
                    color="primary"
                    startIcon={<ArrowForwardIcon />}
                    onClick={handleNextPendingPatient}
                  >
                    Next Pending Patient →
                  </Button>
                </>
              ) : can(PERMISSION_KEYS.CAN_VERIFY_RESULTS) ? (
                <>
                  {currentOverallStatus === RESULT_STATUSES.SUBMITTED_FOR_VERIFICATION && (
                    <Button
                      variant="outlined"
                      color="warning"
                      startIcon={<ReplayIcon />}
                      disabled={saving}
                      onClick={() => handleSaveResults(RESULT_STATUSES.RETURNED_FOR_CORRECTION)}
                    >
                      Return for Correction
                    </Button>
                  )}
                  <Button
                    data-workflow-action="verify"
                    variant="contained"
                    color="success"
                    startIcon={<VerifiedIcon />}
                    disabled={
                      saving ||
                      results.length === 0 ||
                      hasUnackCritical ||
                      (isCurrentVerified && !amendReportId)
                    }
                    onClick={() => handleSaveResults(RESULT_STATUSES.VERIFIED)}
                    sx={{ fontWeight: 700 }}
                  >
                    Verify Results (F8)
                  </Button>
                </>
              ) : (
                can(PERMISSION_KEYS.CAN_ENTER_RESULTS) && (currentOverallStatus === RESULT_STATUSES.DRAFT || amendReportId) && (
                  <Button
                    variant="contained"
                    color="primary"
                    startIcon={<FactCheckIcon />}
                    disabled={saving || results.length === 0}
                    onClick={() => handleSaveResults(RESULT_STATUSES.SUBMITTED_FOR_VERIFICATION)}
                  >
                    Submit for Verification
                  </Button>
                )
              )}
            </Box>
          </Box>
        </CardContent>
      </Card>

      {/* Critical Value Acknowledgment Modal */}
      <Dialog open={criticalModalOpen} onClose={() => setCriticalModalOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 700, color: 'error.main' }}>
          Document Critical Value Notification
        </DialogTitle>
        <DialogContent dividers>
          <Typography variant="body2" sx={{ mb: 2 }}>
            Document the clinical communication of this critical panic alert. This is an audited medicolegal record.
          </Typography>
          <TextField
            fullWidth
            size="small"
            required
            label="Notified Clinician / Ward Staff *"
            placeholder="e.g. Dr. Ramesh Shrestha (Attending)"
            value={notifiedPerson}
            onChange={(e) => setNotifiedPerson(e.target.value)}
            sx={{ mb: 2 }}
          />
          <TextField
            select
            fullWidth
            size="small"
            label="Communication Method"
            value={notificationMethod}
            onChange={(e) => setNotificationMethod(e.target.value)}
            sx={{ mb: 2 }}
          >
            {['Direct Phone Call', 'In-Person Verbal Alert', 'Hospital Intercom', 'Official WhatsApp / SMS'].map((m) => (
              <MenuItem key={m} value={m}>{m}</MenuItem>
            ))}
          </TextField>
          <TextField
            fullWidth
            size="small"
            multiline
            rows={2}
            label="Notification Clinical Notes"
            placeholder="Document immediate alert time and recipient acknowledgment..."
            value={notificationComment}
            onChange={(e) => setNotificationComment(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setCriticalModalOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="error"
            onClick={handleConfirmCriticalAcknowledgment}
          >
            Confirm & Document Panic Alert
          </Button>
        </DialogActions>
      </Dialog>

      {/* Sign-Off Authorization Modal */}
      <Dialog open={signOffModalOpen} onClose={() => setSignOffModalOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 700, color: 'primary.main', display: 'flex', alignItems: 'center', gap: 1 }}>
          <DrawIcon /> {amendReportId ? 'Issue Diagnostic Report Amendment (v2+)' : 'Issue Final Diagnostic Report'}
        </DialogTitle>
        <DialogContent dividers>
          <Typography variant="body2" sx={{ mb: 2.5 }}>
            You are issuing the immutable <strong>{reportGroup?.title || 'selected report group'}</strong> report for <strong>{orderItem?.order?.patient?.full_name}</strong> (Lab No: <strong>{orderItem?.order?.order_number}</strong>).
            Sibling report groups are not included or signed by this action.
          </Typography>

          <TextField
            select
            fullWidth
            size="small"
            required
            label="Performing Technologist (Reported By) *"
            value={performedById}
            onChange={(e) => {
              setPerformedById(e.target.value);
              if (e.target.value === signedById) setSignedById('');
            }}
            sx={{ mb: 2.5 }}
          >
            {signatories.map((p) => (
              <MenuItem key={p.id} value={p.id}>
                {p.fullName} ({p.professionalType} • {p.qualification || 'Technical Staff'})
              </MenuItem>
            ))}
          </TextField>

          <TextField
            select
            fullWidth
            size="small"
            label="Verified / Authorized By (optional)"
            value={signedById}
            onChange={(e) => setSignedById(e.target.value)}
            sx={{ mb: 2.5 }}
          >
            {signatories
              .filter((p) => p.canSignReports && p.id !== performedById)
              .map((p) => (
                <MenuItem key={p.id} value={p.id}>
                  {p.fullName} ({p.professionalType})
                </MenuItem>
              ))}
          </TextField>

          {amendReportId && (
            <TextField
              fullWidth
              size="small"
              required
              multiline
              rows={2}
              label="Amendment Clinical Reason *"
              placeholder="e.g. Corrected specimen dilution factor per clinician recheck..."
              value={amendmentReason}
              onChange={(e) => setAmendmentReason(e.target.value)}
            />
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSignOffModalOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="success"
            disabled={isSigning || !performedById || (Boolean(amendReportId) && !amendmentReason.trim())}
            onClick={() => setSignOffConfirmOpen(true)}
            startIcon={isSigning ? <CircularProgress size={18} /> : <DrawIcon />}
          >
            {isSigning ? 'Issuing Final Report...' : 'Issue Final Report'}
          </Button>
        </DialogActions>
      </Dialog>

      <SmartMessageDialog
        open={signOffConfirmOpen}
        variant="confirm"
        message={amendReportId ? `Issue the immutable ${reportGroup?.title || 'selected group'} report amendment?` : `Sign and finalize the ${reportGroup?.title || 'selected group'} report?`}
        guidance="The current results and patient demographics will be frozen into the signed report. Future profile edits will not change it."
        primaryLabel={amendReportId ? 'Issue amendment' : 'Sign report'}
        onPrimary={() => { setSignOffConfirmOpen(false); void handleConfirmSignOff(); }}
        onSecondary={() => setSignOffConfirmOpen(false)}
        busy={isSigning}
      />

      {/* Pending Equipment / Range Configuration Modal */}
      <Dialog open={configModalOpen} onClose={() => setConfigModalOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle sx={{ fontWeight: 700, color: 'primary.main', display: 'flex', alignItems: 'center', gap: 1 }}>
          <FactCheckIcon /> Enter Technical & Clinical Configuration
        </DialogTitle>
        <DialogContent dividers>
          <Alert severity="info" sx={{ mb: 2.5 }}>
            Staff may enter technical equipment details, reagents, and reference limits during result entry.
            Configurations entered here will be saved as <strong>PENDING_APPROVAL</strong> until formally validated by an authorized clinical approver.
          </Alert>

          <Grid container spacing={2}>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Analyzer Model"
                placeholder="e.g. Sysmex XN-350 / Erba Chem 5X"
                value={configAnalyzerModel}
                onChange={(e) => setConfigAnalyzerModel(e.target.value)}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Reagent Manufacturer"
                placeholder="e.g. Roche / Bio-Rad / Erba"
                value={configReagentManufacturer}
                onChange={(e) => setConfigReagentManufacturer(e.target.value)}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Analytical Method"
                placeholder="e.g. Hexokinase / CLIA / Flow Cytometry"
                value={configMethod}
                onChange={(e) => setConfigMethod(e.target.value)}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Primary Unit"
                placeholder="e.g. mg/dL, g/dL, %"
                value={configUnit}
                onChange={(e) => setConfigUnit(e.target.value)}
              />
            </Grid>

            <Grid item xs={6} sm={3}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Normal Min"
                value={configNormalMin}
                onChange={(e) => setConfigNormalMin(e.target.value)}
              />
            </Grid>
            <Grid item xs={6} sm={3}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Normal Max"
                value={configNormalMax}
                onChange={(e) => setConfigNormalMax(e.target.value)}
              />
            </Grid>
            <Grid item xs={6} sm={3}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Critical Panic Low"
                value={configCriticalLow}
                onChange={(e) => setConfigCriticalLow(e.target.value)}
              />
            </Grid>
            <Grid item xs={6} sm={3}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Critical Panic High"
                value={configCriticalHigh}
                onChange={(e) => setConfigCriticalHigh(e.target.value)}
              />
            </Grid>

            <Grid item xs={12}>
              <TextField
                fullWidth
                size="small"
                label="Qualitative / Text Reference Interpretation"
                placeholder="e.g. Negative, Non-Reactive, Absent"
                value={configNormalText}
                onChange={(e) => setConfigNormalText(e.target.value)}
              />
            </Grid>

            <Grid item xs={12}>
              <TextField
                fullWidth
                size="small"
                multiline
                rows={2}
                label="Configuration Notes / Evidence Reference"
                placeholder="e.g. Configured per kit insert lot #4892 valid through 2026..."
                value={configNotes}
                onChange={(e) => setConfigNotes(e.target.value)}
              />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setConfigModalOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="primary"
            disabled={savingConfig}
            onClick={() => void handleSubmitPendingConfiguration()}
            startIcon={savingConfig ? <CircularProgress size={18} /> : <SaveIcon />}
          >
            {savingConfig ? 'Saving...' : 'Submit Configuration for Approval'}
          </Button>
        </DialogActions>
      </Dialog>

      {/* Toast Notification */}
      <Snackbar
        open={Boolean(toastMsg)}
        autoHideDuration={4000}
        onClose={() => setToastMsg(null)}
        message={toastMsg}
      />
    </Box>
  );
};
