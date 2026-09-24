/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * New Bill & Patient Booking Workflow (Phase 2)
 * Fast unified catalogue search with authoritative server-side clinical routing.
 */

import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import {
  Box,
  Card,
  CardContent,
  Grid,
  Typography,
  TextField,
  MenuItem,
  Button,
  Divider,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  IconButton,
  Alert,
  Chip,
  InputAdornment,
  CircularProgress,
  Snackbar,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Accordion,
  AccordionSummary,
  AccordionDetails,
} from '@mui/material';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import SearchIcon from '@mui/icons-material/Search';
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline';
import SaveIcon from '@mui/icons-material/Save';
import PersonAddIcon from '@mui/icons-material/PersonAdd';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import { useNavigate, useSearchParams } from 'react-router-dom';

import { PageHeader } from '@/components/common/PageHeader';
import { MoneyDisplay } from '@/components/common/MoneyDisplay';
import { MoneyInputField } from '@/components/common/MoneyInputField';
import { rupeesToPaisa, paisaToRupees, calculateBillTotals, parseRupeesToPaisa } from '@/lib/currency';
import { formatBsDateIso, formatDualDate } from '@/lib/dateTime';
import { PAYMENT_MODES, PaymentMode } from '@/config/constants';
import { TestMaster, ReferringDoctor } from '@/types/database';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { toTitleCase } from '@/lib/stringUtils';
import {
  BLANK_PATIENT_AGE,
  getGenderForTitle,
  normalizeNepalMobile,
  normalizePatientName,
  validateNepalMobile,
  validatePatientAge,
  validatePatientTitleAndGender,
} from '@/lib/patientEntry';
import { handleEnterKeyNavigation, useKeyboardShortcut, useGlobalShortcuts } from '@/lib/keyboardNav';
import { safeBillingDiagnosticCode, safeDiagnostic, safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { addSelectedBillTest, removeSelectedBillTest, type SelectedBillTest } from './mixedTierSelection';
import { publishWorkflowInvalidation } from '@/lib/workflowInvalidation';
import { getNextOrderAction } from '@/lib/orderWorkflowNavigation';

import { BillingCatalogueSearch, type CatalogueSearchResult } from './BillingCatalogueSearch';
import { BillViewerDialog } from './BillViewerDialog';
import type { BillSnapshot } from './BillDocument';

type BillItemEntry = SelectedBillTest;
type PricingPolicy = 'Fixed' | 'Negotiable' | 'PricePending' | 'Manual';
type BillPackage = { id: string; code: string; name: string; price_paisa: number; pricing_policy: PricingPolicy; health_package_components: { display_order: number; tests: any }[] };

export const NewBillPage: React.FC = () => {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { profile } = useAuth();

  // Master Data State
  const [doctors, setDoctors] = useState<ReferringDoctor[]>([]);
  const [selectedPackages, setSelectedPackages] = useState<{ package_id: string; code: string; name: string; component_ids: string[] }[]>([]);
  const [selectedPanel, setSelectedPanel] = useState<{ service_id: string; panel_version: number; name: string; component_ids: string[] } | null>(null);

  // Fast Simultaneous Patient Search State
  const [patientSearchTerm, setPatientSearchTerm] = useState('');
  const [patientSearchResults, setPatientSearchResults] = useState<any[]>([]);
  const [highlightedPatientIndex, setHighlightedPatientIndex] = useState(0);
  const [isSearchingPatient, setIsSearchingPatient] = useState(false);

  // Quick Patient Add Dialog State
  const [quickAddOpen, setQuickAddOpen] = useState(false);
  const [quickAddShowMore, setQuickAddShowMore] = useState(false);
  const [quickAddSaving, setQuickAddSaving] = useState(false);
  const [quickAddForm, setQuickAddForm] = useState({
    title: 'Mr.',
    full_name: '',
    gender: 'Male' as 'Male' | 'Female' | 'Other',
    dob: null as string | null,
    age_years: '' as number | '',
    age_months: '' as number | '',
    age_days: '' as number | '',
    mobile: '',
    address: 'Bharatpur, Chitwan',
    referring_doctor_id: '',
    email: '',
    identification_no: '',
  });

  // Patient Demographics State
  const [mobileQuery, setMobileQuery] = useState(searchParams.get('mobile') || '');
  const [isExistingPatient, setIsExistingPatient] = useState(false);
  const [existingPatientId, setExistingPatientId] = useState<string | null>(null);

  const [uhid, setUhid] = useState('10-DIGIT UHID GENERATED ON SAVE');
  const [title, setTitle] = useState('Mr.');
  const [fullName, setFullName] = useState('');
  const [gender, setGender] = useState<'Male' | 'Female' | 'Other'>('Male');
  const [ageYears, setAgeYears] = useState<number | ''>(BLANK_PATIENT_AGE.years);
  const [ageMonths, setAgeMonths] = useState<number | ''>(BLANK_PATIENT_AGE.months);
  const [ageDays, setAgeDays] = useState<number | ''>(BLANK_PATIENT_AGE.days);
  const [address, setAddress] = useState('Bharatpur, Chitwan');
  const [email, setEmail] = useState('');
  const [identificationNo, setIdentificationNo] = useState('');
  const [referringDoctorId, setReferringDoctorId] = useState('');
  const [referringDoctorName, setReferringDoctorName] = useState('Self / Walk-in');

  // Investigation Items State
  const [selectedItems, setSelectedItems] = useState<BillItemEntry[]>([]);
  const [testSearchTerm, setTestSearchTerm] = useState('');
  const [highlightedTestIndex, setHighlightedTestIndex] = useState(0);
  const [searchResults, setSearchResults] = useState<CatalogueSearchResult[]>([]);
  const [searchingCatalogue, setSearchingCatalogue] = useState(false);

  // Financial State
  const [customDiscountRupees, setCustomDiscountRupees] = useState<number | ''>('');
  const [discountReason, setDiscountReason] = useState('');
  const [paidRupees, setPaidRupees] = useState<number | ''>(0);
  const [paymentMode, setPaymentMode] = useState<PaymentMode>(PAYMENT_MODES.CASH);
  const [transactionRef, setTransactionRef] = useState('');
  const [remarks, setRemarks] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [catalogueError, setCatalogueError] = useState<string | null>(null);
  const [authError, setAuthError] = useState<string | null>(null);
  const [submitResult, setSubmitResult] = useState<any | null>(null);
  const [toastOpen, setToastOpen] = useState(false);
  const [zeroPriceTest, setZeroPriceTest] = useState<TestMaster | null>(null);
  const [pendingZeroRateTestId, setPendingZeroRateTestId] = useState<string | null>(null);
  const [zeroPriceAcknowledgedIds, setZeroPriceAcknowledgedIds] = useState<Set<string>>(new Set());
  const [viewerBill, setViewerBill] = useState<BillSnapshot | null>(null);
  const [billViewerOpen, setBillViewerOpen] = useState(false);
  const [postBillModalOpen, setPostBillModalOpen] = useState(false);

  // Keyboard Navigation Input Refs
  const patientSearchInputRef = useRef<HTMLInputElement>(null);
  const fullNameInputRef = useRef<HTMLInputElement>(null);
  const addressInputRef = useRef<HTMLInputElement>(null);
  const ageYearsInputRef = useRef<HTMLInputElement>(null);
  const ageMonthsInputRef = useRef<HTMLInputElement>(null);
  const ageDaysInputRef = useRef<HTMLInputElement>(null);
  const genderInputRef = useRef<HTMLInputElement>(null);
  const referredByInputRef = useRef<HTMLInputElement>(null);
  const emailInputRef = useRef<HTMLInputElement>(null);
  const identificationInputRef = useRef<HTMLInputElement>(null);
  const testSearchInputRef = useRef<HTMLInputElement>(null);
  const paidAmountInputRef = useRef<HTMLInputElement>(null);
  const catalogueSearchRequestRef = useRef(0);
  const billingRequestKeyRef = useRef(crypto.randomUUID());

  // Auto-focus Patient Search immediately on mount
  useEffect(() => {
    patientSearchInputRef.current?.focus();
  }, []);

  // Global F2/F4/F6/Ctrl+S Shortcuts
  useGlobalShortcuts({
    onNewBill: () => {
      resetFormForNextBill();
      patientSearchInputRef.current?.focus();
    },
    onSearch: () => {
      patientSearchInputRef.current?.focus();
      patientSearchInputRef.current?.select();
    },
    onSave: () => {
      if (!isSubmitting && selectedItems.length > 0 && fullName.trim()) {
        handleSaveBill();
      }
    },
    onEscape: () => {
      setPatientSearchResults([]);
      setQuickAddOpen(false);
    },
  });

  // Global Ctrl+F Shortcut to Focus Test Search
  useKeyboardShortcut('f', (e) => {
    e.preventDefault();
    testSearchInputRef.current?.focus();
  }, { ctrlOrCmd: true });

  // Load Test Catalogue and Referring Doctors
  const loadMasterData = useCallback(async () => {
    setCatalogueError(null);
    setAuthError(null);
    try {
      const { data: { session }, error: sessionErr } = await supabase.auth.getSession();
      if (!session || sessionErr) {
        console.warn('[Billing] No authenticated Supabase session found in browser.');
        setAuthError('Your session has expired or you are not signed in. Please sign in to access the billing catalogue.');
        return;
      }

      const [docsRes] = await Promise.all([
        supabase
          .from('referring_doctors')
          .select('*')
          .eq('is_active', true)
          .order('full_name', { ascending: true }),
      ]);

      if (docsRes.data) {
        const mappedDocs: ReferringDoctor[] = docsRes.data.map((d) => ({
          id: d.id,
          fullName: d.full_name,
          code: d.code,
          degree: d.degree,
          institution: d.institution,
          phone: d.phone,
          email: d.email,
          address: d.address,
          isActive: d.is_active,
          createdAt: d.created_at,
          updatedAt: d.updated_at,
        }));
        setDoctors(mappedDocs);
      }
    } catch (err: any) {
      console.error('[Billing] Master data load error:', err);
      setCatalogueError(safeErrorMessage(err, 'Unable to load investigations. Please retry.'));
    } finally {
    }
  }, []);

  useEffect(() => {
    loadMasterData();
  }, [loadMasterData]);

  useEffect(() => {
    setHighlightedTestIndex(0);
    const query = testSearchTerm.trim();
    const requestId = ++catalogueSearchRequestRef.current;
    if (query.length < 1) { setSearchResults([]); setSearchingCatalogue(false); return; }
    const timer = window.setTimeout(async () => {
      setSearchingCatalogue(true);
      const { data, error } = await supabase.rpc('search_billable_catalogue', { p_query: query, p_limit: 30 });
      if (requestId !== catalogueSearchRequestRef.current) return;
      if (error) {
        console.error('[Billing catalogue authorization]', { stage: 'search_billable_catalogue RPC/EXECUTE/guard', ...safeDiagnostic(error) });
        setCatalogueError(safeErrorMessage(error, 'Catalogue search failed.'));
      }
      else {
        const rows = (data || []) as CatalogueSearchResult[];
        const testIds = rows.filter((row) => row.entity_type === 'Test').map((row) => row.entity_id);
        const [gatesResult, readinessResult, paramsResult, panelComponentsResult] = testIds.length ? await Promise.all([
          supabase.from('tests').select('id,department,clinical_reporting_enabled,collection_required,workflow_type,workflow_supported,test_kind,reporting_model,reporting_type').in('id', testIds),
          supabase.from('catalogue_test_operational_state').select('test_id,readiness,operational_state').in('test_id', testIds),
          supabase.from('parameters').select('test_id').in('test_id', testIds),
          supabase.from('catalogue_panel_components').select('panel_test_id').in('panel_test_id', testIds),
        ]) : [{ data: [], error: null }, { data: [], error: null }, { data: [], error: null }, { data: [], error: null }];
        const { data: gates, error: gatesError } = gatesResult;
        if (requestId !== catalogueSearchRequestRef.current) return;
        if (gatesError || readinessResult.error) {
          const failure = gatesError || readinessResult.error;
          console.error('[Billing catalogue authorization]', { stage: gatesError ? 'tests table ACL/RLS' : 'catalogue_test_operational_state view ACL/RLS', ...safeDiagnostic(failure) });
          setCatalogueError(safeErrorMessage(failure, 'Catalogue workflow eligibility could not be verified.'));
        }
        else {
          const byId = new Map((gates || []).map((gate: any) => [gate.id, gate]));
          const readinessById = new Map((readinessResult.data || []).map((item: any) => [item.test_id, item]));
          const paramCountMap = new Map<string, number>();
          ((paramsResult as any).data || []).forEach((p: any) => {
            if (p.test_id) paramCountMap.set(p.test_id, (paramCountMap.get(p.test_id) || 0) + 1);
          });
          const panelComponentCountMap = new Map<string, number>();
          ((panelComponentsResult as any).data || []).forEach((c: any) => {
            if (c.panel_id) panelComponentCountMap.set(c.panel_id, (panelComponentCountMap.get(c.panel_id) || 0) + 1);
            if (c.panel_test_id) panelComponentCountMap.set(c.panel_test_id, (panelComponentCountMap.get(c.panel_test_id) || 0) + 1);
          });

          setSearchResults(rows.map((row) => {
            const gate: any = byId.get(row.entity_id) || {};
            const readiness: any = readinessById.get(row.entity_id) || {};
            const pCount = paramCountMap.get(row.entity_id) ?? 0;
            const cCount = panelComponentCountMap.get(row.entity_id) ?? 0;
            return {
              ...row,
              ...gate,
              approval_state: readiness.readiness === 'Ready' ? 'Approved' : 'ResultStructureIncomplete',
              readiness_classification: readiness.readiness,
              parameter_count: pCount,
              panel_component_count: cCount,
            };
          }));
        }
      }
      setSearchingCatalogue(false);
    }, 120);
    return () => window.clearTimeout(timer);
  }, [testSearchTerm]);

  // Fast Simultaneous Patient Search (UHID, Mobile, Name)
  useEffect(() => {
    const query = patientSearchTerm.trim();
    setHighlightedPatientIndex(0);
    if (query.length < 1) {
      setPatientSearchResults([]);
      setIsSearchingPatient(false);
      return;
    }
    const timer = window.setTimeout(async () => {
      setIsSearchingPatient(true);
      try {
        const { data, error } = await supabase.rpc('search_patient_registry', {
          p_search: query,
          p_active_state: 'Active',
          p_limit: 8,
        });
        if (!error && data) {
          setPatientSearchResults((data as any[]).map((r) => r.item || r));
        } else {
          const cleanMobile = normalizeNepalMobile(query);
          let q = supabase.from('patients').select('*').eq('is_active', true).limit(8);
          if (cleanMobile.length >= 7) {
            q = q.ilike('mobile', `%${cleanMobile}%`);
          } else {
            q = q.or(`full_name.ilike.%${query}%,uhid.ilike.%${query}%,mobile.ilike.%${query}%`);
          }
          const { data: directData } = await q;
          if (directData) setPatientSearchResults(directData);
        }
      } catch (err) {
        console.warn('[Billing] Patient search failure:', err);
      } finally {
        setIsSearchingPatient(false);
      }
    }, 100);
    return () => window.clearTimeout(timer);
  }, [patientSearchTerm]);

  const handleSelectPatient = (p: any) => {
    setIsExistingPatient(true);
    setExistingPatientId(p.id);
    setUhid(p.uhid);
    setTitle(p.title || 'Mr.');
    setFullName(p.full_name);
    setGender(p.gender || 'Male');
    setAgeYears(p.age_years ?? '');
    setAgeMonths(p.age_months ?? '');
    setAgeDays(p.age_days ?? '');
    setAddress(p.address || 'Bharatpur, Chitwan');
    setEmail(p.email || '');
    setIdentificationNo(p.identification_no || '');
    setMobileQuery(p.mobile || '');
    setPatientSearchTerm('');
    setPatientSearchResults([]);
    setHighlightedPatientIndex(0);
    window.setTimeout(() => {
      testSearchInputRef.current?.focus();
    }, 50);
  };

  const handleQuickAddSave = async () => {
    const normName = normalizePatientName(quickAddForm.full_name);
    if (!normName) {
      setErrorMsg('Patient full legal name is required.');
      return;
    }
    const mobErr = validateNepalMobile(quickAddForm.mobile);
    if (mobErr) {
      setErrorMsg(mobErr);
      return;
    }
    const ageErr = validatePatientAge({
      years: quickAddForm.age_years !== '' ? quickAddForm.age_years : null,
      months: quickAddForm.age_months !== '' ? quickAddForm.age_months : null,
      days: quickAddForm.age_days !== '' ? quickAddForm.age_days : null,
    }, false);
    if (ageErr) {
      setErrorMsg(ageErr);
      return;
    }
    const titleGenderErr = validatePatientTitleAndGender(quickAddForm.title, quickAddForm.gender);
    if (titleGenderErr) {
      setErrorMsg(titleGenderErr);
      return;
    }

    setQuickAddSaving(true);
    setErrorMsg(null);
    try {
      const payload = {
        title: quickAddForm.title,
        full_name: normName,
        mobile: normalizeNepalMobile(quickAddForm.mobile),
        gender: quickAddForm.gender,
        dob: quickAddForm.dob || null,
        age_years: quickAddForm.age_years !== '' ? Number(quickAddForm.age_years) : null,
        age_months: quickAddForm.age_months !== '' ? Number(quickAddForm.age_months) : null,
        age_days: quickAddForm.age_days !== '' ? Number(quickAddForm.age_days) : null,
        address: quickAddForm.address.trim() || 'Bharatpur, Chitwan',
        email: quickAddForm.email.trim() || null,
        identification_no: quickAddForm.identification_no.trim() || null,
      };

      const { data, error } = await supabase.rpc('create_patient', { p_patient_data: payload });
      if (error) throw error;

      handleSelectPatient(data);
      if (quickAddForm.referring_doctor_id) {
        setReferringDoctorId(quickAddForm.referring_doctor_id);
        const doc = doctors.find((d) => d.id === quickAddForm.referring_doctor_id);
        setReferringDoctorName(doc ? doc.fullName : 'Self / Walk-in');
      }
      setQuickAddOpen(false);
      setToastOpen(true);
    } catch (err: any) {
      setErrorMsg(safeErrorMessage(err, 'Failed to create patient record.'));
    } finally {
      setQuickAddSaving(false);
    }
  };

  // Handle Mobile Lookup against live patients table
  const handleMobileLookup = useCallback(async (mobileInput: string) => {
    const cleanMobile = normalizeNepalMobile(mobileInput);
    if (cleanMobile.length < 10) {
      if (cleanMobile.length === 0) {
        setIsExistingPatient(false);
        setExistingPatientId(null);
        setUhid('10-DIGIT UHID GENERATED ON SAVE');
      }
      return;
    }

    setIsSearchingPatient(true);
    setErrorMsg(null);

    try {
      const { data, error } = await supabase
        .from('patients')
        .select('*')
        .eq('mobile', cleanMobile)
        .maybeSingle();

      if (error) throw error;

      if (data) {
        setExistingPatientId(data.id);
        setAgeYears(data.age_years ?? '');
        handleSelectPatient(data);
      } else {
        setIsExistingPatient(false);
        setExistingPatientId(null);
        setUhid('NEW PATIENT (Sequential UHID on save)');
        setFullName('');
        setAgeYears(BLANK_PATIENT_AGE.years);
        setAgeMonths(BLANK_PATIENT_AGE.months);
        setAgeDays(BLANK_PATIENT_AGE.days);
      }
    } catch (err: any) {
      console.warn('[Billing] Patient search error:', safeDiagnostic(err));
    } finally {
      setIsSearchingPatient(false);
    }
  }, []);

  useEffect(() => {
    if (mobileQuery && mobileQuery.length >= 7) {
      handleMobileLookup(mobileQuery);
    }
  }, [mobileQuery, handleMobileLookup]);

  // Add Item to Bill
  const handleAddTest = (test: TestMaster, zeroAcknowledged = false) => {
    if (test.priceConfigured && test.pricePaisa === 0 && test.allowZeroPriceBilling && !zeroAcknowledged && !zeroPriceAcknowledgedIds.has(test.id)) { setZeroPriceTest(test); return; }
    setSelectedItems((current) => {
      const newItems = addSelectedBillTest(current, test);
      if (newItems === current) return current;
      const customDiscountPaisa = rupeesToPaisa(customDiscountRupees || 0);
      const newTotals = calculateBillTotals(newItems, customDiscountPaisa, 0);
      setPaidRupees(paisaToRupees(newTotals.netPaisa));
      return newItems;
    });
  };

  const handleAddPackage = (pkg: BillPackage) => {
    const ordered = [...pkg.health_package_components].sort((a, b) => a.display_order - b.display_order);
    if (ordered.some((component) => selectedItems.some((item) => item.test.id === component.tests.id))) { setErrorMsg('A package component is already selected. Remove the duplicate test before adding this package.'); return; }
    let next = selectedItems;
    ordered.forEach((component, index) => {
      const t = component.tests;
      const isPackageRateRow = index === 0;
      const mapped: TestMaster = { id: t.id, code: t.code, name: t.name, shortName: t.short_name, department: t.department, category: t.category, reportingType: t.reporting_type, outsourceLabName: t.outsource_lab_name, pricePaisa: isPackageRateRow ? pkg.price_paisa : 0, priceConfigured: isPackageRateRow ? pkg.price_paisa > 0 : true, pricingPolicy: isPackageRateRow ? pkg.pricing_policy : 'Fixed', allowManualPrice: isPackageRateRow, allowZeroPriceBilling: false, clinicalReportingEnabled: t.clinical_reporting_enabled, collectionRequired: t.collection_required, workflowType: t.workflow_type, sampleType: t.sample_type, container: t.container, method: t.method, tatHours: t.tat_hours, isActive: t.is_active, displayOrder: t.display_order, createdAt: t.created_at, updatedAt: t.updated_at };
      next = addSelectedBillTest(next, mapped).map((entry) => entry.test.id === mapped.id ? { ...entry, unitPricePaisa: isPackageRateRow ? pkg.price_paisa : 0, description: `Package: ${pkg.code}`, rateResolved: isPackageRateRow ? pkg.price_paisa > 0 : true } : entry);
    });
    setSelectedItems(next); setSelectedPackages((current) => [...current, { package_id: pkg.id, code: pkg.code, name: pkg.name, component_ids: ordered.map((x) => x.tests.id) }]);
    const newTotals = calculateBillTotals(next, rupeesToPaisa(customDiscountRupees || 0), 0); setPaidRupees(paisaToRupees(newTotals.netPaisa));
  };

  const selectCatalogueResult = async (result: CatalogueSearchResult) => {
    if (result.entity_type === 'Panel') {
      if (selectedPanel) { setErrorMsg('Only one bundled panel can be selected per bill; standalone tests and profiles may remain on this order.'); return; }
      if (!result.price_configured || result.price_paisa == null) { setErrorMsg('This panel needs a catalogue default before its bundled agreed rate can be billed.'); return; }
      const [{ data: expanded, error: expandError }, { data: service, error: serviceError }] = await Promise.all([
        supabase.rpc('catalogue_panel_service_components', { p_service_id: result.entity_id }),
        supabase.from('catalogue_panel_services').select('panel_id,catalogue_panels!panel_id(row_version)').eq('id', result.entity_id).single(),
      ]);
      if (expandError || serviceError || !expanded?.length) { setErrorMsg('Panel definition changed. Refresh the catalogue and try again.'); return; }
      if (expanded.some((item: any) => item.readiness !== 'Ready')) { setErrorMsg('Result Structure Incomplete. Configure Result Structure before billing this panel.'); return; }
      const componentIds = expanded.map((item: any) => item.test_id);
      if (componentIds.some((id: string) => selectedItems.some((item) => item.test.id === id))) {
        const conflictingNames = selectedItems.filter((item) => componentIds.includes(item.test.id)).map((item) => item.test.name).join(', ');
        setErrorMsg(`Component test "${conflictingNames}" is already in the bill. Remove that individual test before adding the complete ${result.name} panel to prevent duplicate charges.`);
        return;
      }
      const { data: componentTests, error: componentError } = await supabase.from('tests').select('*').in('id', componentIds);
      if (componentError || componentTests?.length !== componentIds.length) { setErrorMsg('Panel component identities are incomplete.'); return; }
      const byId = new Map((componentTests || []).map((item: any) => [item.id, item]));
      let next = selectedItems;
      expanded.forEach((component: any, index: number) => { const t: any = byId.get(component.test_id); const mapped: TestMaster = { id:t.id,code:t.code,name:t.name,shortName:t.short_name,department:t.department,category:t.category,reportingType:t.reporting_type,outsourceLabName:t.outsource_lab_name,pricePaisa:index===0?result.price_paisa:0,priceConfigured:true,pricingPolicy:'Fixed',allowManualPrice:index===0,allowZeroPriceBilling:index!==0,clinicalReportingEnabled:t.clinical_reporting_enabled,collectionRequired:t.collection_required,workflowType:t.workflow_type,sampleType:t.sample_type,container:t.container,method:t.method,tatHours:t.tat_hours,isActive:true,displayOrder:component.display_order,createdAt:t.created_at,updatedAt:t.updated_at }; next=addSelectedBillTest(next,mapped).map((entry)=>entry.test.id===mapped.id?{...entry,unitPricePaisa:mapped.pricePaisa,description:`Panel: ${result.code}`,rateResolved:true}:entry); });
      setSelectedItems(next); setSelectedPanel({ service_id:result.entity_id,panel_version:(service as any).catalogue_panels.row_version,name:result.name,component_ids:componentIds });
      const newTotals=calculateBillTotals(next,rupeesToPaisa(customDiscountRupees||0),0); setPaidRupees(paisaToRupees(newTotals.netPaisa));
    } else if (result.entity_type === 'Package') {
      const { data: expanded, error: expandError } = await supabase.rpc('catalogue_expand_package', { p_package_id: result.entity_id });
      if (expandError || !expanded?.length) { setErrorMsg('Package configuration changed. Refresh and search again.'); return; }
      const componentIds = expanded.map((row: any) => row.test_id);
      const { data: componentTests, error: componentError } = await supabase.from('tests').select('*').in('id', componentIds);
      if (componentError || componentTests?.length !== componentIds.length) { setErrorMsg('Package component configuration is incomplete.'); return; }
      const byId = new Map((componentTests || []).map((component: any) => [component.id, component]));
      handleAddPackage({
        id: expanded[0].package_id,
        code: expanded[0].package_code,
        name: expanded[0].package_name,
        price_paisa: expanded[0].package_price_paisa,
        pricing_policy: result.pricing_policy,
        health_package_components: expanded.map((row: any) => ({ display_order: row.display_order, tests: byId.get(row.test_id) })),
      });
    } else {
      if (selectedPanel && selectedPanel.component_ids.includes(result.entity_id)) {
        setErrorMsg(`"${result.name}" is already included in the selected panel "${selectedPanel.name}". It is covered under the panel rate and will not be charged separately.`);
        return;
      }
      const containingPackage = selectedPackages.find((pkg) => pkg.component_ids.includes(result.entity_id));
      if (containingPackage) {
        setErrorMsg(`"${result.name}" is already included in package "${containingPackage.name}". It is covered under the package rate and will not be charged separately.`);
        return;
      }
      const test: TestMaster = { id: result.entity_id, code: result.code, name: result.name, shortName: result.short_name, department: result.department || result.category || '', category: result.category || '', reportingType: (result.reporting_type as any) || 'In-House', pricePaisa: result.price_paisa || 0, priceConfigured: result.price_configured, allowZeroPriceBilling: result.allow_zero_price_billing, pricingPolicy: result.pricing_policy, allowManualPrice: true, clinicalReportingEnabled: result.clinical_reporting_enabled, collectionRequired: result.collection_required, workflowType: result.workflow_type, sampleType: result.specimen || '', container: result.container || '', isActive: true, displayOrder: 0, createdAt: '', updatedAt: '' };
      handleAddTest(test);
    }
    setTestSearchTerm(''); setSearchResults([]); setHighlightedTestIndex(0); window.setTimeout(() => testSearchInputRef.current?.focus(), 0);
  };

  const handleTestSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setHighlightedTestIndex((prev) => (prev < searchResults.length - 1 ? prev + 1 : 0));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setHighlightedTestIndex((prev) => (prev > 0 ? prev - 1 : searchResults.length - 1));
    } else if (e.key === 'Escape') {
      e.preventDefault();
      setTestSearchTerm('');
      setSearchResults([]);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      const match = searchResults[highlightedTestIndex];
      if (match) {
        selectCatalogueResult(match);
        testSearchInputRef.current?.focus();
      }
    }
  };

  // Commit Manual Price for Item (e.g. IHC or unconfigured rate)
  const handleCommitItemPrice = (testId: string, newPaisa: number | null) => {
    if (newPaisa === null) {
      setSelectedItems((prev) =>
        prev.map((item) =>
          item.test.id === testId ? { ...item, rateResolved: false, isManuallyEdited: true } : item
        )
      );
      return;
    }
    const selected = selectedItems.find((item) => item.test.id === testId);
    if (newPaisa === 0 && !selected?.test.allowZeroPriceBilling) {
      setSelectedItems((prev) =>
        prev.map((item) =>
          item.test.id === testId ? { ...item, rateResolved: false, isManuallyEdited: true } : item
        )
      );
      return;
    }
    if (newPaisa === 0 && !zeroPriceAcknowledgedIds.has(testId)) {
      setPendingZeroRateTestId(testId);
      return;
    }
    const updated = selectedItems.map((item) =>
      item.test.id === testId
        ? {
            ...item,
            unitPricePaisa: newPaisa,
            rateResolved: true,
            isManuallyEdited: Boolean(!item.test.priceConfigured || item.test.pricePaisa !== newPaisa),
          }
        : item
    );
    setSelectedItems(updated);
    const customDiscountPaisa = rupeesToPaisa(customDiscountRupees || 0);
    const newTotals = calculateBillTotals(updated, customDiscountPaisa, 0);
    setPaidRupees(paisaToRupees(newTotals.netPaisa));
  };

  // Update Manual Price for Item (programmatic / direct compatibility wrapper)
  const handleUpdateItemPrice = (testId: string, rupeesVal: string | number) => {
    const newPaisa = parseRupeesToPaisa(String(rupeesVal));
    if (newPaisa === null) {
      setErrorMsg('Rate must be a non-negative amount with no more than two decimal places.');
      return;
    }
    handleCommitItemPrice(testId, newPaisa);
  };
  void handleUpdateItemPrice;

  // Update Item Description for Invoice (e.g. IHC - ER/PR/HER2)
  const handleUpdateItemDescription = (testId: string, desc: string) => {
    setSelectedItems((prev) =>
      prev.map((item) => (item.test.id === testId ? { ...item, description: desc } : item))
    );
  };

  // Remove Item from Bill
  const handleRemoveItem = (testId: string) => {
    setSelectedItems((current) => {
      if (selectedPanel?.component_ids.includes(testId)) {
        const updated=current.filter((item)=>!selectedPanel.component_ids.includes(item.test.id)); setSelectedPanel(null);
        const newTotals=calculateBillTotals(updated,rupeesToPaisa(customDiscountRupees||0),0); setPaidRupees(paisaToRupees(newTotals.netPaisa)); return updated;
      }
      const containingPackage = selectedPackages.find((pkg) => pkg.component_ids.includes(testId));
      const idsToRemove = containingPackage?.component_ids || [testId];
      const updated = idsToRemove.reduce((items, id) => removeSelectedBillTest(items, id), current);
      if (containingPackage) setSelectedPackages((packages) => packages.filter((pkg) => pkg.package_id !== containingPackage.package_id));
      const customDiscountPaisa = rupeesToPaisa(customDiscountRupees || 0);
      const newTotals = calculateBillTotals(updated, customDiscountPaisa, 0);
      setPaidRupees(paisaToRupees(newTotals.netPaisa));
      return updated;
    });
  };

  // Financial Calculations
  const totals = useMemo(() => {
    const customDiscountPaisa = rupeesToPaisa(customDiscountRupees || 0);
    const paidPaisa = rupeesToPaisa(paidRupees || 0);
    return calculateBillTotals(selectedItems, customDiscountPaisa, paidPaisa);
  }, [selectedItems, customDiscountRupees, paidRupees]);

  // Filtered Catalogue for selection

  // Submit Bill & Create Order via Atomic PostgreSQL Function
  const handleSaveBill = async () => {
    const cleanMobile = normalizeNepalMobile(mobileQuery);
    const normalizedFullName = normalizePatientName(fullName);
    const mobileError = validateNepalMobile(mobileQuery);
    if (mobileError) {
      setErrorMsg(mobileError);
      return;
    }
    if (!normalizedFullName) {
      setErrorMsg('Patient full legal name is required.');
      return;
    }
    const ageError = validatePatientAge({ years: ageYears, months: ageMonths, days: ageDays }, true);
    if (ageError) {
      setErrorMsg(ageError);
      return;
    }
    const titleGenderError = validatePatientTitleAndGender(title, gender);
    if (titleGenderError) {
      setErrorMsg(titleGenderError);
      return;
    }
    if (selectedItems.length === 0) {
      setErrorMsg('At least one investigation must be added to the bill.');
      return;
    }
    if (selectedItems.some((item) => !item.rateResolved)) {
      setErrorMsg('Every selected service requires a valid agreed rate before finalizing.');
      return;
    }
    const enteredDiscountPaisa = rupeesToPaisa(customDiscountRupees || 0) + selectedItems.reduce((sum, item) => sum + Math.round(item.discountPaisa || 0), 0);
    const enteredPaidPaisa = rupeesToPaisa(paidRupees || 0);
    if (enteredDiscountPaisa > totals.grossPaisa) {
      setErrorMsg('Discount cannot exceed the gross bill amount.');
      return;
    }
    if (enteredPaidPaisa > totals.netPaisa) {
      setErrorMsg('Paid amount cannot exceed the final bill amount.');
      return;
    }
    if (enteredPaidPaisa > 0 && paymentMode !== PAYMENT_MODES.CASH && !transactionRef.trim()) {
      setErrorMsg('Transaction reference is required for non-cash payments.');
      return;
    }

    setIsSubmitting(true);
    setErrorMsg(null);

    const patientPayload = {
      patient_id: existingPatientId,
      mobile: cleanMobile,
      title,
      full_name: normalizedFullName,
      gender,
      dob: null,
      age_years: typeof ageYears === 'number' ? ageYears : null,
      age_months: typeof ageMonths === 'number' ? ageMonths : null,
      age_days: typeof ageDays === 'number' ? ageDays : null,
      address: address.trim() || 'Bharatpur, Chitwan',
      email: email.trim() || null,
      identification_no: identificationNo.trim() || null,
    };

    const billPayload = {
      referring_doctor_id: referringDoctorId || null,
      referring_doctor_name_snapshot: referringDoctorName,
      gross_amount_paisa: totals.grossPaisa,
      discount_amount_paisa: totals.totalDiscountPaisa,
      discount_reason: discountReason.trim() || null,
      paid_amount_paisa: totals.paidPaisa,
      order_date_bs: formatBsDateIso(),
      remarks: remarks.trim() || null,
    };

    const itemsPayload = selectedItems.map((item) => ({
      test_id: item.test.id,
      test_code: item.test.code,
      test_name: item.test.name,
      reporting_type: item.test.reportingType,
      outsource_lab_name: item.test.outsourceLabName || null,
      unit_price_paisa: item.unitPricePaisa,
      manual_price_paisa: item.unitPricePaisa,
      discount_paisa: item.discountPaisa || 0,
      net_price_paisa: item.unitPricePaisa - (item.discountPaisa || 0),
      specimen_type: item.test.sampleType,
      container_type: item.test.container,
      department: item.test.department,
      item_description: item.description?.trim() || null,
      zero_price_acknowledged: zeroPriceAcknowledgedIds.has(item.test.id),
    }));

    const paymentPayload = totals.paidPaisa > 0 ? {
      payment_mode: paymentMode,
      transaction_reference: transactionRef.trim() || null,
      remarks: remarks.trim() || 'Billing Payment',
      received_by_name: profile?.fullName || 'Reception Staff',
    } : null;

    try {
      const { data, error } = selectedPanel ? await (supabase.rpc as any)('create_patient_bill_order_mixed_catalogue', {
        p_patient_data: patientPayload,
        p_bill_data: billPayload,
        p_items_data: itemsPayload,
        p_payment_data: paymentPayload,
        p_idempotency_key: billingRequestKeyRef.current,
        p_packages: selectedPackages.map((pkg) => ({ package_id: pkg.package_id, component_ids: pkg.component_ids, agreed_price_paisa: selectedItems.filter((item) => pkg.component_ids.includes(item.test.id)).reduce((sum, item) => sum + item.unitPricePaisa, 0) })),
        p_panel_service_id: selectedPanel.service_id,
        p_expected_panel_version: selectedPanel.panel_version,
        p_agreed_panel_price_paisa: selectedItems.filter((item)=>selectedPanel.component_ids.includes(item.test.id)).reduce((sum, item) => sum + item.unitPricePaisa, 0),
      }) : await supabase.rpc('create_patient_bill_order_with_packages', {
        p_patient_data: patientPayload,
        p_bill_data: billPayload,
        p_items_data: itemsPayload,
        p_payment_data: paymentPayload,
        p_idempotency_key: billingRequestKeyRef.current,
        p_packages: selectedPackages.map((pkg) => ({
          package_id: pkg.package_id,
          component_ids: pkg.component_ids,
          agreed_price_paisa: selectedItems
            .filter((item) => pkg.component_ids.includes(item.test.id))
            .reduce((sum, item) => sum + item.unitPricePaisa, 0),
        })),
      });

      if (error) throw error;

      setSubmitResult(data);
      setToastOpen(true);
      setPostBillModalOpen(true);
      publishWorkflowInvalidation('order-created',['patients','bills','samples','worklist','dashboard'],data?.order_id);

      // Build or fetch full bill snapshot for immediate printing
      let loadedBill: BillSnapshot | null = null;
      if (data?.bill_id) {
        try {
          const { data: billRecord } = await supabase
            .from('bills')
            .select('*, patient:patients(*), bill_items(*), payment_transactions(*)')
            .eq('id', data.bill_id)
            .maybeSingle();
          if (billRecord) {
            loadedBill = billRecord as unknown as BillSnapshot;
          }
        } catch {
          // fallback below
        }
      }

      if (!loadedBill && data?.bill_id) {
        loadedBill = {
          id: data.bill_id,
          bill_number: data.bill_number,
          created_at: new Date().toISOString(),
          patient: {
            full_name: normalizedFullName,
            uhid: data.uhid || uhid,
            age_years: typeof ageYears === 'number' ? ageYears : null,
            age_months: typeof ageMonths === 'number' ? ageMonths : null,
            age_days: typeof ageDays === 'number' ? ageDays : null,
            gender: gender,
            mobile: cleanMobile,
            address: address.trim() || 'Bharatpur, Chitwan',
          },
          referring_doctor_name_snapshot: referringDoctorName,
          gross_amount_paisa: totals.grossPaisa,
          discount_amount_paisa: totals.totalDiscountPaisa,
          net_amount_paisa: totals.netPaisa,
          paid_amount_paisa: totals.paidPaisa,
          due_amount_paisa: totals.duePaisa,
          payment_status: totals.duePaisa === 0 ? 'Paid' : totals.paidPaisa > 0 ? 'Partial' : 'Unpaid',
          bill_items: itemsPayload.map((it) => ({
            test_name: it.test_name,
            test_code: it.test_code,
            item_description: it.item_description,
            reporting_type: it.reporting_type,
            unit_price_paisa: it.unit_price_paisa,
            discount_paisa: it.discount_paisa,
            net_price_paisa: it.net_price_paisa,
          })),
          payment_transactions: totals.paidPaisa > 0 ? [{
            id: 'initial',
            receipt_number: 'Initial Receipt',
            amount_paisa: totals.paidPaisa,
            payment_mode: paymentMode,
            transaction_reference: transactionRef.trim() || null,
            created_at: new Date().toISOString(),
          }] : [],
        };
      }

      if (loadedBill) {
        setViewerBill(loadedBill);
      }

      if (data?.order_id) {
        const nextAction = await getNextOrderAction(supabase, data.order_id);
        setSubmitResult({ ...data, auto_next_message: nextAction.message, next_route: nextAction.route });
      }

    } catch (err: unknown) {
      const diagnostic = safeDiagnostic(err);
      const reference = safeBillingDiagnosticCode(err);
      console.error('[Billing Error]', { reference, code: diagnostic.code, status: diagnostic.status });
      setErrorMsg(`${safeErrorMessage(err, 'Billing transaction failed. Please check the entered details or connectivity.')} (Reference: ${reference})`);
    } finally {
      setIsSubmitting(false);
    }
  };

  const resetFormForNextBill = () => {
    setMobileQuery('');
    setIsExistingPatient(false);
    setExistingPatientId(null);
    setUhid('10-DIGIT UHID GENERATED ON SAVE');
    setFullName('');
    setAgeYears(BLANK_PATIENT_AGE.years);
    setAgeMonths(BLANK_PATIENT_AGE.months);
    setAgeDays(BLANK_PATIENT_AGE.days);
    setAddress('Bharatpur, Chitwan');
    setSelectedItems([]);
    setSelectedPackages([]);
    setSelectedPanel(null);
    setZeroPriceAcknowledgedIds(new Set());
    setCustomDiscountRupees('');
    setDiscountReason('');
    setPaidRupees(0);
    setSubmitResult(null);
    billingRequestKeyRef.current = crypto.randomUUID();
  };

  return (
    <Box data-keyboard-form="true">
      <PageHeader
        title="New Bill & Lab Booking"
        subtitle={`Live Session: ${profile?.fullName || 'Reception'} | Registered: ${formatDualDate(new Date())}`}
      />

      <SmartMessageDialog open={Boolean(errorMsg)} message={errorMsg || ''} onPrimary={() => setErrorMsg(null)} />
      <SmartMessageDialog open={Boolean(zeroPriceTest)} variant="confirm" message="Confirm authorized NPR 0 billing?" guidance={`${zeroPriceTest?.code || ''} is explicitly configured as a genuine zero-price service. This acknowledgement is recorded with the billing request.`} primaryLabel="Acknowledge & Add" onPrimary={() => { if (!zeroPriceTest) return; const pending = zeroPriceTest; setZeroPriceAcknowledgedIds((current) => new Set(current).add(pending.id)); setZeroPriceTest(null); handleAddTest(pending, true); }} onSecondary={() => setZeroPriceTest(null)} />
      <SmartMessageDialog open={Boolean(pendingZeroRateTestId)} variant="confirm" message="Confirm authorized NPR 0 billing?" guidance="This catalogue item explicitly permits zero-price billing. The acknowledgement is recorded with the billing request; NPR 0 is never inferred from an unresolved price." primaryLabel="Acknowledge NPR 0" onPrimary={() => { if (!pendingZeroRateTestId) return; const testId = pendingZeroRateTestId; setZeroPriceAcknowledgedIds((current) => new Set(current).add(testId)); setSelectedItems((current) => current.map((item) => item.test.id === testId ? { ...item, unitPricePaisa: 0, rateResolved: true } : item)); setPendingZeroRateTestId(null); }} onSecondary={() => setPendingZeroRateTestId(null)} />

      {submitResult && (
        <Alert
          severity="success"
          icon={<CheckCircleOutlineIcon />}
          sx={{ mb: 3 }}
          action={
            <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', justifyContent: 'flex-end', alignItems: 'center' }}>
              <Button
                color="primary"
                size="small"
                variant="contained"
                onClick={resetFormForNextBill}
                sx={{ fontWeight: 700 }}
              >
                New Bill
              </Button>
              {submitResult.next_route && (
                <Button
                  color="success"
                  size="small"
                  variant="contained"
                  onClick={() => navigate(submitResult.next_route)}
                  sx={{ fontWeight: 700 }}
                >
                  {submitResult.auto_next_message || 'Continue to Sample Accession'}
                </Button>
              )}
              <Button
                color="inherit"
                size="small"
                variant="outlined"
                onClick={() => setBillViewerOpen(true)}
              >
                View Bill
              </Button>
              <Button
                color="inherit"
                size="small"
                variant="outlined"
                onClick={() => navigate('/billing')}
              >
                Bill List
              </Button>
              <Button
                color="inherit"
                size="small"
                variant="outlined"
                onClick={() => navigate('/patients')}
              >
                Open Patient
              </Button>
            </Box>
          }
        >
          <strong>Bill saved and order registered successfully.</strong> Bill <strong>{submitResult.bill_number}</strong> · Clinical Order <strong>{submitResult.order_number || 'N/A'}</strong> · UHID <strong>{submitResult.uhid}</strong>.{' '}
          {submitResult.auto_next_message || (selectedItems.some((item) => item.test.collectionRequired)
            ? 'Order queued for Sample Accession.'
            : 'Order queued directly to clinical worklist.')}
        </Alert>
      )}

      <Grid container spacing={3}>
        {/* Left Column: Demographics & Investigation Selection */}
        <Grid item xs={12} lg={8}>
          {/* Patient Card */}
          <Card sx={{ mb: 3 }}>
            <CardContent>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <Typography variant="h6" fontWeight={700} color="primary.main">
                    1. Patient Search & Demographics
                  </Typography>
                  <Chip label="F4" size="small" variant="outlined" sx={{ fontWeight: 700, height: 20, fontSize: '0.68rem' }} />
                </Box>
                <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
                  {isExistingPatient ? (
                    <Chip
                      label={`Existing Patient: ${uhid}`}
                      color="success"
                      size="small"
                      variant="outlined"
                    />
                  ) : (
                    <Chip label="New Patient Registration" color="secondary" size="small" />
                  )}
                  <Button
                    size="small"
                    variant="outlined"
                    color="primary"
                    startIcon={<PersonAddIcon />}
                    onClick={() => {
                      setQuickAddForm({
                        title: 'Mr.',
                        full_name: patientSearchTerm && isNaN(Number(patientSearchTerm)) ? patientSearchTerm : '',
                        gender: 'Male',
                        dob: null,
                        age_years: '',
                        age_months: '',
                        age_days: '',
                        mobile: patientSearchTerm && !isNaN(Number(patientSearchTerm)) ? patientSearchTerm : '',
                        address: 'Bharatpur, Chitwan',
                        referring_doctor_id: referringDoctorId || '',
                        email: '',
                        identification_no: '',
                      });
                      setQuickAddOpen(true);
                    }}
                    sx={{ fontWeight: 700, textTransform: 'none' }}
                  >
                    + Quick Add Patient
                  </Button>
                </Box>
              </Box>

              {/* Fast Simultaneous Patient Search (UHID, Mobile, Name) */}
              <Box sx={{ position: 'relative', p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0', mb: 2.5 }}>
                <Grid container spacing={2} alignItems="center">
                  <Grid item xs={12} sm={8}>
                    <TextField
                      inputRef={patientSearchInputRef}
                      data-patient-search="true"
                      fullWidth
                      label="Search Patient (UHID, Mobile, or Name) (F4) *"
                      placeholder="Type patient name, phone number, or UHID (e.g. 9845012345, Ram Thapa, BP-2026-0001)..."
                      value={patientSearchTerm}
                      onChange={(e) => setPatientSearchTerm(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'ArrowDown') {
                          e.preventDefault();
                          setHighlightedPatientIndex((prev) => Math.min(prev + 1, patientSearchResults.length - 1));
                        } else if (e.key === 'ArrowUp') {
                          e.preventDefault();
                          setHighlightedPatientIndex((prev) => Math.max(prev - 1, 0));
                        } else if (e.key === 'Escape') {
                          e.preventDefault();
                          setPatientSearchTerm('');
                          setPatientSearchResults([]);
                        } else if (e.key === 'Enter') {
                          e.preventDefault();
                          if (patientSearchResults[highlightedPatientIndex]) {
                            handleSelectPatient(patientSearchResults[highlightedPatientIndex]);
                          } else if (patientSearchTerm.trim().length >= 2) {
                            // If no matching patient found on Enter, prompt Quick Add
                            setQuickAddForm({
                              title: 'Mr.',
                              full_name: isNaN(Number(patientSearchTerm)) ? patientSearchTerm : '',
                              gender: 'Male',
                              dob: null,
                              age_years: '',
                              age_months: '',
                              age_days: '',
                              mobile: !isNaN(Number(patientSearchTerm)) ? patientSearchTerm : '',
                              address: 'Bharatpur, Chitwan',
                              referring_doctor_id: referringDoctorId || '',
                              email: '',
                              identification_no: '',
                            });
                            setQuickAddOpen(true);
                          }
                        }
                      }}
                      InputProps={{
                        startAdornment: (
                          <InputAdornment position="start">
                            <SearchIcon color="primary" />
                          </InputAdornment>
                        ),
                        endAdornment: isSearchingPatient ? (
                          <CircularProgress size={20} />
                        ) : null,
                        sx: { bgcolor: '#ffffff', fontWeight: 600 },
                      }}
                      helperText="Type UHID, mobile or name. Arrow Up/Down + Enter to select patient."
                    />
                  </Grid>
                  <Grid item xs={12} sm={4}>
                    <TextField
                      fullWidth
                      label="UHID (Lab Identifier)"
                      value={uhid}
                      disabled
                      InputProps={{ sx: { bgcolor: '#ffffff', fontWeight: 700 } }}
                    />
                  </Grid>
                </Grid>

                {/* Floating Patient Suggestions Dropdown */}
                {patientSearchTerm.trim().length >= 1 && (
                  <Paper
                    elevation={6}
                    sx={{
                      position: 'absolute',
                      zIndex: 40,
                      left: 16,
                      right: 16,
                      top: '100%',
                      mt: 0.5,
                      maxHeight: 280,
                      overflowY: 'auto',
                      borderRadius: 2,
                      border: '1px solid #cbd5e1',
                      bgcolor: '#ffffff',
                      boxShadow: '0 8px 24px rgba(15, 23, 42, 0.12)',
                    }}
                  >
                    {patientSearchResults.length === 0 && !isSearchingPatient ? (
                      <Box sx={{ p: 2, textAlign: 'center' }}>
                        <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                          No patient matching &quot;{patientSearchTerm}&quot; found.
                        </Typography>
                        <Button
                          size="small"
                          variant="contained"
                          color="primary"
                          startIcon={<PersonAddIcon />}
                          onClick={() => {
                            setQuickAddForm({
                              title: 'Mr.',
                              full_name: isNaN(Number(patientSearchTerm)) ? patientSearchTerm : '',
                              gender: 'Male',
                              dob: null,
                              age_years: '',
                              age_months: '',
                              age_days: '',
                              mobile: !isNaN(Number(patientSearchTerm)) ? patientSearchTerm : '',
                              address: 'Bharatpur, Chitwan',
                              referring_doctor_id: referringDoctorId || '',
                              email: '',
                              identification_no: '',
                            });
                            setQuickAddOpen(true);
                          }}
                        >
                          + Quick Add Patient
                        </Button>
                      </Box>
                    ) : (
                      patientSearchResults.map((pat, idx) => {
                        const isHighlighted = idx === highlightedPatientIndex;
                        return (
                          <Box
                            key={pat.id || idx}
                            onClick={() => handleSelectPatient(pat)}
                            onMouseEnter={() => setHighlightedPatientIndex(idx)}
                            sx={{
                              p: 1.5,
                              cursor: 'pointer',
                              borderBottom: '1px solid #f1f5f9',
                              bgcolor: isHighlighted ? '#eff6ff' : '#ffffff',
                              borderLeft: isHighlighted ? '4px solid #2563eb' : '4px solid transparent',
                              display: 'flex',
                              justifyContent: 'space-between',
                              alignItems: 'center',
                            }}
                          >
                            <Box>
                              <Typography variant="body2" fontWeight={700}>
                                {pat.title ? `${pat.title} ` : ''}{pat.full_name}
                              </Typography>
                              <Typography variant="caption" color="text.secondary">
                                UHID: <strong style={{ color: '#0369a1' }}>{pat.uhid}</strong> · Mobile: {pat.mobile} · {pat.age_years ? `${pat.age_years}Y` : ''} / {pat.gender} · {pat.address}
                              </Typography>
                            </Box>
                            <Button size="small" variant="text" sx={{ fontWeight: 700 }}>
                              Select (Enter)
                            </Button>
                          </Box>
                        );
                      })
                    )}
                  </Paper>
                )}
              </Box>

              {/* Demographics Fields */}
              <Grid container spacing={2}>
                <Grid item xs={12} sm={2.5}>
                  <TextField
                    select
                    fullWidth
                    label="Title"
                    value={title}
                    onChange={(e) => {
                      const nextTitle = e.target.value;
                      setTitle(nextTitle);
                      const mappedGender = getGenderForTitle(nextTitle);
                      if (mappedGender) {
                        setGender(mappedGender);
                      }
                    }}
                    onKeyDown={handleEnterKeyNavigation}
                  >
                    {['Mr.', 'Mrs.', 'Ms.', 'Miss', 'Master', 'Dr.', 'Baby'].map((t) => (
                      <MenuItem key={t} value={t}>
                        {t}
                      </MenuItem>
                    ))}
                  </TextField>
                </Grid>
                <Grid item xs={12} sm={6.5}>
                  <TextField
                    inputRef={fullNameInputRef}
                    fullWidth
                    label="Patient Full Name *"
                    value={fullName}
                    onChange={(e) => setFullName(e.target.value)}
                    onBlur={() => setFullName(normalizePatientName(fullName))}
                    onKeyDown={(e) => handleEnterKeyNavigation(e, () => ageYearsInputRef.current?.focus())}
                    required
                    placeholder="e.g. Ram Bahadur Thapa"
                  />
                </Grid>
                <Grid item xs={12} sm={3}>
                  <TextField
                    inputRef={genderInputRef}
                    select
                    fullWidth
                    label="Gender *"
                    value={gender}
                    onChange={(e) => {
                      const nextGender = e.target.value as 'Male' | 'Female' | 'Other';
                      setGender(nextGender);
                      if (nextGender === 'Female' && (title === 'Mr.' || title === 'Master')) {
                        setTitle('Mrs.');
                      } else if (nextGender === 'Male' && (title === 'Mrs.' || title === 'Ms.' || title === 'Miss')) {
                        setTitle('Mr.');
                      }
                    }}
                    onKeyDown={(e) => handleEnterKeyNavigation(e, () => addressInputRef.current?.focus())}
                  >
                    <MenuItem value="Male">Male</MenuItem>
                    <MenuItem value="Female">Female</MenuItem>
                    <MenuItem value="Other">Other</MenuItem>
                  </TextField>
                </Grid>

                <Grid item xs={12} sm={4}>
                  <TextField
                    inputRef={ageYearsInputRef}
                    fullWidth
                    type="number"
                    label="Age (Years) *"
                    placeholder="Enter age"
                    value={ageYears}
                    onChange={(e) => setAgeYears(e.target.value ? Number(e.target.value) : '')}
                    onKeyDown={(e) => handleEnterKeyNavigation(e, () => ageMonthsInputRef.current?.focus())}
                    inputProps={{ min: 0, max: 120, step: 1 }}
                  />
                </Grid>
                <Grid item xs={6} sm={4}>
                  <TextField
                    inputRef={ageMonthsInputRef}
                    fullWidth
                    type="number"
                    label="Months (Optional)"
                    value={ageMonths}
                    onChange={(e) => setAgeMonths(e.target.value ? Number(e.target.value) : '')}
                    onKeyDown={(e) => handleEnterKeyNavigation(e, () => ageDaysInputRef.current?.focus())}
                    inputProps={{ min: 0, max: 11, step: 1 }}
                  />
                </Grid>
                <Grid item xs={6} sm={4}>
                  <TextField
                    inputRef={ageDaysInputRef}
                    fullWidth
                    type="number"
                    label="Days (Optional)"
                    value={ageDays}
                    onChange={(e) => setAgeDays(e.target.value ? Number(e.target.value) : '')}
                    onKeyDown={(e) => handleEnterKeyNavigation(e, () => genderInputRef.current?.focus())}
                    inputProps={{ min: 0, max: 31, step: 1 }}
                  />
                </Grid>

                <Grid item xs={12} sm={6}>
                  <TextField
                    inputRef={addressInputRef}
                    fullWidth
                    label="Address / District *"
                    value={address}
                    onChange={(e) => setAddress(e.target.value)}
                    onBlur={() => setAddress(toTitleCase(address))}
                    onKeyDown={(e) => handleEnterKeyNavigation(e, () => referredByInputRef.current?.focus())}
                  />
                </Grid>
                <Grid item xs={12} sm={6}>
                  <TextField
                    inputRef={referredByInputRef}
                    select
                    fullWidth
                    label="Referred By Clinician *"
                    value={referringDoctorId}
                    onChange={(e) => {
                      const docId = e.target.value;
                      setReferringDoctorId(docId);
                      const found = doctors.find((d) => d.id === docId);
                      setReferringDoctorName(found ? found.fullName : 'Self / Walk-in');
                    }}
                    onKeyDown={(e) => handleEnterKeyNavigation(e, () => emailInputRef.current?.focus())}
                  >
                    <MenuItem value="">Self / Walk-in Patient</MenuItem>
                    {doctors.map((d) => (
                      <MenuItem key={d.id} value={d.id}>
                        {d.fullName} {d.institution ? `(${d.institution})` : ''}
                      </MenuItem>
                    ))}
                  </TextField>
                </Grid>
                <Grid item xs={12} sm={6}>
                  <TextField
                    inputRef={emailInputRef}
                    fullWidth
                    label="Email Address (Optional)"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    onKeyDown={(e) => handleEnterKeyNavigation(e, () => identificationInputRef.current?.focus())}
                    placeholder="patient@example.com"
                  />
                </Grid>
                <Grid item xs={12} sm={6}>
                  <TextField
                    inputRef={identificationInputRef}
                    fullWidth
                    label="Citizenship / ID No. (Optional)"
                    value={identificationNo}
                    onChange={(e) => setIdentificationNo(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        testSearchInputRef.current?.focus();
                      }
                    }}
                  />
                </Grid>
              </Grid>
            </CardContent>
          </Card>

          {/* Investigation Selection Card */}
          <Card>
            <CardContent>
              <Typography variant="h6" fontWeight={700} color="primary.main" sx={{ mb: 1.5 }}>2. Search Test / Profile / Package</Typography>

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

              {catalogueError && (
                <Alert
                  severity="error"
                  sx={{ mb: 2 }}
                  action={
                    <Button color="inherit" size="small" onClick={loadMasterData}>
                      Retry
                    </Button>
                  }
                >
                  {catalogueError}
                </Alert>
              )}

              <BillingCatalogueSearch
                inputRef={testSearchInputRef}
                searchTerm={testSearchTerm}
                onSearchChange={setTestSearchTerm}
                searchResults={searchResults}
                searchingCatalogue={searchingCatalogue}
                highlightedIndex={highlightedTestIndex}
                onHighlightChange={setHighlightedTestIndex}
                onSelectResult={selectCatalogueResult}
                selectedItems={selectedItems}
                selectedPanel={selectedPanel}
                selectedPackages={selectedPackages}
                onPanelConflictWarning={(msg) => setErrorMsg(msg)}
                onKeyDown={handleTestSearchKeyDown}
              />

              {/* Selected Tests Table */}
              <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>
                Selected Tests for Invoice ({selectedItems.length})
              </Typography>
              <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', overflow: 'auto' }}>
                <Table size="small">
                  <TableHead sx={{ bgcolor: '#f1f5f9' }}>
                    <TableRow>
                      <TableCell>Test</TableCell>
                      <TableCell align="right">Rate (NPR)</TableCell>
                      <TableCell align="center">Qty</TableCell>
                      <TableCell align="right">Amount</TableCell>
                      <TableCell align="center" width={50}>Remove</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {selectedItems.length === 0 ? (
                      <TableRow>
                        <TableCell colSpan={5} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                          No tests selected. Type 2–4 characters above, then press Enter.
                        </TableCell>
                      </TableRow>
                    ) : (
                      selectedItems.map((item) => (
                        <TableRow key={item.test.id} hover>
                          <TableCell sx={{ minWidth: 240 }}>
                            <Typography variant="body2" fontWeight={600}>
                              {item.test.name}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              Code: {item.test.code}
                            </Typography>
                            {item.test.allowManualPrice && (
                              <TextField
                                size="small"
                                placeholder="Optional Description (e.g. IHC - ER/PR/HER2)"
                                value={item.description || ''}
                                onChange={(e) => handleUpdateItemDescription(item.test.id, e.target.value)}
                                sx={{ mt: 0.75, display: 'block', maxWidth: 280 }}
                                inputProps={{ style: { fontSize: '0.78rem', padding: '4px 8px' } }}
                              />
                            )}
                          </TableCell>
                          <TableCell align="right" sx={{ minWidth: 160 }}>
                            {item.test.allowManualPrice ? (
                              <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
                                <MoneyInputField
                                  size="small"
                                  label="Rate (NPR) *"
                                  valuePaisa={item.rateResolved ? item.unitPricePaisa : null}
                                  required
                                  allowZero={item.test.allowZeroPriceBilling}
                                  fieldName="Rate"
                                  onCommitPaisa={(newPaisa) => handleCommitItemPrice(item.test.id, newPaisa)}
                                  inputProps={{ style: { textAlign: 'right', fontWeight: 700, fontSize: '0.85rem' } }}
                                  sx={{ width: 140 }}
                                />
                                <Typography
                                  variant="caption"
                                  sx={{
                                    mt: 0.25,
                                    fontWeight: 500,
                                    color:
                                      item.test.priceConfigured && item.test.pricePaisa > 0
                                        ? 'text.secondary'
                                        : item.isManuallyEdited
                                        ? 'info.main'
                                        : 'warning.main',
                                  }}
                                >
                                  {/* Price not configured — enter agreed rate */}
                                  {item.test.priceConfigured && item.test.pricePaisa > 0
                                    ? 'Catalogue rate'
                                    : item.isManuallyEdited
                                    ? 'Manual rate'
                                    : 'Default rate — verify'}
                                </Typography>
                              </Box>
                            ) : (
                              <MoneyDisplay paisa={item.unitPricePaisa} />
                            )}
                          </TableCell>
                          <TableCell align="center">1</TableCell>
                          <TableCell align="right">{item.rateResolved ? <MoneyDisplay paisa={item.unitPricePaisa} /> : <Chip size="small" color="warning" label="Rate required" />}</TableCell>
                          <TableCell align="center">
                            <IconButton
                              size="small"
                              color="error"
                              onClick={() => handleRemoveItem(item.test.id)}
                            >
                              <DeleteOutlineIcon fontSize="small" />
                            </IconButton>
                          </TableCell>
                        </TableRow>
                      ))
                    )}
                  </TableBody>
                </Table>
              </TableContainer>
            </CardContent>
          </Card>
        </Grid>

        {/* Right Column: Financial Settlement & Atomic Commit */}
        <Grid item xs={12} lg={4}>
          <Card sx={{ position: 'sticky', top: 80 }}>
            <CardContent>
              <Typography variant="h6" fontWeight={700} color="primary.main" gutterBottom>
                3. Financial Settlement
              </Typography>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 2 }}>
                All calculations computed server-side in integer Paisa
              </Typography>

              {/* Breakdown Box */}
              <Box sx={{ bgcolor: 'var(--color-surface-alt)', p: 2, borderRadius: 2, border: '1px solid var(--color-border)', borderTop: '4px solid var(--color-primary)', mb: 2.5 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}>
                  <Typography variant="body2" color="text.secondary">Gross Total:</Typography>
                  <MoneyDisplay paisa={totals.grossPaisa} />
                </Box>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}>
                  <Typography variant="body2" color="text.secondary">Discount Applied:</Typography>
                  <MoneyDisplay paisa={totals.totalDiscountPaisa} sx={{ color: 'success.main' }} />
                </Box>
                <Divider sx={{ my: 1 }} />
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1.5 }}>
                  <Typography variant="subtitle1" fontWeight={700}>Net Payable:</Typography>
                  <MoneyDisplay
                    paisa={totals.netPaisa}
                    sx={{ fontSize: '1.2rem', fontWeight: 800, color: 'primary.main' }}
                  />
                </Box>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}>
                  <Typography variant="body2" color="text.secondary">Paid Now:</Typography>
                  <MoneyDisplay paisa={totals.paidPaisa} sx={{ color: 'success.main' }} />
                </Box>
                <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                  <Typography
                    variant="subtitle2"
                    fontWeight={700}
                    color={totals.duePaisa > 0 ? 'error.main' : 'inherit'}
                  >
                    Outstanding Due:
                  </Typography>
                  <MoneyDisplay paisa={totals.duePaisa} highlightDue sx={{ fontWeight: 700 }} />
                </Box>
              </Box>

              {/* Discount Inputs */}
              <Grid container spacing={1.5} sx={{ mb: 2 }}>
                <Grid item xs={6}>
                  <MoneyInputField
                    fullWidth
                    size="small"
                    label="Discount (NPR)"
                    valuePaisa={customDiscountRupees !== '' ? rupeesToPaisa(customDiscountRupees) : null}
                    fieldName="Discount"
                    allowZero={true}
                    maxPaisa={totals.grossPaisa}
                    onCommitPaisa={(newPaisa) => {
                      if (newPaisa === null || newPaisa === 0) {
                        setCustomDiscountRupees('');
                        const newTotals = calculateBillTotals(selectedItems, 0, 0);
                        setPaidRupees(paisaToRupees(newTotals.netPaisa));
                      } else {
                        setCustomDiscountRupees(paisaToRupees(newPaisa));
                        const newTotals = calculateBillTotals(selectedItems, newPaisa, 0);
                        setPaidRupees(paisaToRupees(newTotals.netPaisa));
                      }
                    }}
                  />
                </Grid>
                <Grid item xs={6}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Discount Reason"
                    placeholder="e.g. Staff / Senior"
                    value={discountReason}
                    onChange={(e) => setDiscountReason(e.target.value)}
                  />
                </Grid>
              </Grid>

              {/* Payment Mode & Amount */}
              <Grid container spacing={1.5} sx={{ mb: 2 }}>
                <Grid item xs={6}>
                  <TextField
                    select
                    fullWidth
                    size="small"
                    label="Payment Mode *"
                    value={paymentMode}
                    onChange={(e) => setPaymentMode(e.target.value as PaymentMode)}
                  >
                    {Object.values(PAYMENT_MODES).map((mode) => (
                      <MenuItem key={mode} value={mode}>
                        {mode}
                      </MenuItem>
                    ))}
                  </TextField>
                </Grid>
                <Grid item xs={6}>
                  <MoneyInputField
                    inputRef={paidAmountInputRef}
                    fullWidth
                    size="small"
                    label="Paid Amount (NPR) *"
                    valuePaisa={paidRupees !== '' ? rupeesToPaisa(paidRupees) : null}
                    fieldName="Paid amount"
                    required
                    allowZero={true}
                    maxPaisa={totals.netPaisa}
                    onCommitPaisa={(newPaisa) => {
                      if (newPaisa === null) {
                        setPaidRupees('');
                      } else {
                        setPaidRupees(paisaToRupees(newPaisa));
                      }
                    }}
                    onKeyDown={handleEnterKeyNavigation}
                  />
                </Grid>
                {paymentMode !== PAYMENT_MODES.CASH && (
                  <Grid item xs={12}>
                    <TextField
                      fullWidth
                      size="small"
                      label="Transaction Ref / Slip No."
                      placeholder="e.g. Fonepay Trace ID / Bank Ref"
                      value={transactionRef}
                      onChange={(e) => setTransactionRef(e.target.value)}
                    />
                  </Grid>
                )}
              </Grid>

              {/* Remarks */}
              <TextField
                fullWidth
                size="small"
                multiline
                rows={2}
                label="Billing Remarks (Optional)"
                value={remarks}
                onChange={(e) => setRemarks(e.target.value)}
                sx={{ mb: 3 }}
              />

              {/* Submit Button */}
              <Button
                fullWidth
                variant="contained"
                color="primary"
                size="large"
                startIcon={isSubmitting ? <CircularProgress size={20} color="inherit" /> : <SaveIcon />}
                disabled={isSubmitting}
                onClick={handleSaveBill}
                sx={{ py: 1.3, fontSize: '0.95rem', fontWeight: 700 }}
              >
                {isSubmitting ? 'Processing Bill...' : 'Confirm Bill & Register Order'}
              </Button>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Compact Centered Success Toast */}
      <Snackbar
        open={toastOpen}
        autoHideDuration={4000}
        onClose={() => setToastOpen(false)}
        anchorOrigin={{ vertical: 'top', horizontal: 'center' }}
      >
        <Alert
          onClose={() => setToastOpen(false)}
          severity="success"
          variant="filled"
          sx={{ width: '100%', boxShadow: 4 }}
        >
          Bill {submitResult?.bill_number} posted successfully!
        </Alert>
      </Snackbar>

      {/* Post-Billing Success Modal */}
      <Dialog
        open={postBillModalOpen}
        onClose={() => setPostBillModalOpen(false)}
        maxWidth="xs"
        fullWidth
        PaperProps={{ sx: { borderRadius: 2 } }}
      >
        <DialogTitle sx={{ textAlign: 'center', pt: 3, pb: 1 }}>
          <CheckCircleOutlineIcon sx={{ fontSize: 44, color: 'success.main', mb: 0.5 }} />
          <Typography variant="h6" fontWeight={800}>Bill Created Successfully</Typography>
        </DialogTitle>
        <DialogContent sx={{ textAlign: 'center', pb: 2 }}>
          <Typography variant="h5" fontWeight={800} color="primary.main" sx={{ my: 1, fontFamily: 'monospace' }}>
            {submitResult?.bill_number}
          </Typography>
          <Typography variant="body2" color="text.secondary">
            UHID: <strong>{submitResult?.uhid || uhid}</strong> · {fullName}
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            Total: <strong>NPR {paisaToRupees(totals.netPaisa)}</strong> ({totals.duePaisa === 0 ? 'Paid in Full' : `Due: NPR ${paisaToRupees(totals.duePaisa)}`})
          </Typography>
        </DialogContent>
        <DialogActions sx={{ flexDirection: 'column', gap: 1, p: 2.5, pt: 0 }}>
          <Button
            fullWidth
            variant="contained"
            color="primary"
            size="large"
            sx={{ fontWeight: 700 }}
            onClick={() => {
              setPostBillModalOpen(false);
              navigate(submitResult?.next_route || '/samples');
            }}
          >
            Collect Sample →
          </Button>
          <Box sx={{ display: 'flex', gap: 1, width: '100%' }}>
            <Button
              fullWidth
              variant="outlined"
              onClick={() => {
                setPostBillModalOpen(false);
                resetFormForNextBill();
              }}
            >
              + New Bill
            </Button>
            <Button
              fullWidth
              variant="outlined"
              onClick={() => {
                setPostBillModalOpen(false);
                setBillViewerOpen(true);
              }}
            >
              View Bill
            </Button>
          </Box>
        </DialogActions>
      </Dialog>

      {/* Quick Add Patient Dialog */}
      <Dialog
        open={quickAddOpen}
        onClose={() => setQuickAddOpen(false)}
        maxWidth="sm"
        fullWidth
        PaperProps={{ sx: { borderRadius: 2 } }}
      >
        <DialogTitle sx={{ fontWeight: 800, pb: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
          <PersonAddIcon color="primary" /> Quick Add Patient
        </DialogTitle>
        <DialogContent dividers>
          <Grid container spacing={2} sx={{ mt: 0.2 }}>
            <Grid item xs={12} sm={8}>
              <TextField
                fullWidth
                size="small"
                required
                autoFocus
                label="Full Legal Name *"
                placeholder="e.g. Ram Bahadur Thapa"
                value={quickAddForm.full_name}
                onChange={(e) => setQuickAddForm({ ...quickAddForm, full_name: e.target.value })}
                onBlur={() => setQuickAddForm({ ...quickAddForm, full_name: normalizePatientName(quickAddForm.full_name) })}
              />
            </Grid>
            <Grid item xs={12} sm={4}>
              <TextField
                select
                fullWidth
                size="small"
                label="Gender *"
                value={quickAddForm.gender}
                onChange={(e) => {
                  const nextGender = e.target.value as any;
                  setQuickAddForm((prev) => {
                    let nextTitle = prev.title;
                    if (nextGender === 'Female' && (nextTitle === 'Mr.' || nextTitle === 'Master')) {
                      nextTitle = 'Mrs.';
                    } else if (nextGender === 'Male' && (nextTitle === 'Mrs.' || nextTitle === 'Ms.' || nextTitle === 'Miss')) {
                      nextTitle = 'Mr.';
                    }
                    return {
                      ...prev,
                      gender: nextGender,
                      title: nextTitle,
                    };
                  });
                }}
              >
                <MenuItem value="Male">Male</MenuItem>
                <MenuItem value="Female">Female</MenuItem>
                <MenuItem value="Other">Other</MenuItem>
              </TextField>
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                type="number"
                label="Age (Years) *"
                placeholder="Age in years"
                value={quickAddForm.age_years}
                onChange={(e) => setQuickAddForm({ ...quickAddForm, age_years: e.target.value ? Number(e.target.value) : '' })}
                inputProps={{ min: 0, max: 120 }}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                type="tel"
                required
                label="Mobile Number *"
                placeholder="9845012345"
                value={quickAddForm.mobile}
                onChange={(e) => setQuickAddForm({ ...quickAddForm, mobile: e.target.value })}
                onBlur={() => setQuickAddForm({ ...quickAddForm, mobile: normalizeNepalMobile(quickAddForm.mobile) })}
                InputProps={{
                  startAdornment: <InputAdornment position="start">+977</InputAdornment>,
                }}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Address / District *"
                value={quickAddForm.address}
                onChange={(e) => setQuickAddForm({ ...quickAddForm, address: e.target.value })}
                onBlur={() => setQuickAddForm({ ...quickAddForm, address: toTitleCase(quickAddForm.address) })}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                select
                fullWidth
                size="small"
                label="Referring Doctor"
                value={quickAddForm.referring_doctor_id}
                onChange={(e) => setQuickAddForm({ ...quickAddForm, referring_doctor_id: e.target.value })}
              >
                <MenuItem value="">Self / Walk-in Patient</MenuItem>
                {doctors.map((d) => (
                  <MenuItem key={d.id} value={d.id}>
                    {d.fullName} {d.institution ? `(${d.institution})` : ''}
                  </MenuItem>
                ))}
              </TextField>
            </Grid>

            {/* Collapsible Additional Details */}
            <Grid item xs={12}>
              <Accordion
                expanded={quickAddShowMore}
                onChange={() => setQuickAddShowMore(!quickAddShowMore)}
                elevation={0}
                sx={{ border: '1px solid #e2e8f0', borderRadius: 1.5, '&:before': { display: 'none' } }}
              >
                <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                  <Typography variant="caption" fontWeight={700} color="text.secondary">
                    {quickAddShowMore ? 'Hide Additional Details' : '+ Additional Details (DOB, Months, Email, ID)'}
                  </Typography>
                </AccordionSummary>
                <AccordionDetails sx={{ pt: 0 }}>
                  <Grid container spacing={2}>
                    <Grid item xs={12} sm={4}>
                      <TextField
                        select
                        fullWidth
                        size="small"
                        label="Title"
                        value={quickAddForm.title}
                        onChange={(e) => {
                          const nextTitle = e.target.value;
                          const mappedGender = getGenderForTitle(nextTitle);
                          setQuickAddForm((prev) => ({
                            ...prev,
                            title: nextTitle,
                            gender: mappedGender || prev.gender,
                          }));
                        }}
                      >
                        {['Mr.', 'Mrs.', 'Ms.', 'Miss', 'Master', 'Dr.', 'Baby'].map((t) => (
                          <MenuItem key={t} value={t}>{t}</MenuItem>
                        ))}
                      </TextField>
                    </Grid>
                    <Grid item xs={12} sm={4}>
                      <TextField
                        fullWidth
                        size="small"
                        type="date"
                        label="Date of Birth"
                        value={quickAddForm.dob || ''}
                        onChange={(e) => setQuickAddForm({ ...quickAddForm, dob: e.target.value || null })}
                        InputLabelProps={{ shrink: true }}
                      />
                    </Grid>
                    <Grid item xs={6} sm={2}>
                      <TextField
                        fullWidth
                        size="small"
                        type="number"
                        label="Months"
                        value={quickAddForm.age_months}
                        onChange={(e) => setQuickAddForm({ ...quickAddForm, age_months: e.target.value ? Number(e.target.value) : '' })}
                        inputProps={{ min: 0, max: 11 }}
                      />
                    </Grid>
                    <Grid item xs={6} sm={2}>
                      <TextField
                        fullWidth
                        size="small"
                        type="number"
                        label="Days"
                        value={quickAddForm.age_days}
                        onChange={(e) => setQuickAddForm({ ...quickAddForm, age_days: e.target.value ? Number(e.target.value) : '' })}
                        inputProps={{ min: 0, max: 31 }}
                      />
                    </Grid>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        fullWidth
                        size="small"
                        type="email"
                        label="Email Address"
                        placeholder="patient@example.com"
                        value={quickAddForm.email}
                        onChange={(e) => setQuickAddForm({ ...quickAddForm, email: e.target.value })}
                      />
                    </Grid>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        fullWidth
                        size="small"
                        label="Citizenship / ID No."
                        value={quickAddForm.identification_no}
                        onChange={(e) => setQuickAddForm({ ...quickAddForm, identification_no: e.target.value })}
                      />
                    </Grid>
                  </Grid>
                </AccordionDetails>
              </Accordion>
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setQuickAddOpen(false)} disabled={quickAddSaving}>
            Cancel
          </Button>
          <Button
            variant="contained"
            color="primary"
            onClick={handleQuickAddSave}
            disabled={quickAddSaving || !quickAddForm.full_name.trim() || !quickAddForm.mobile.trim()}
            startIcon={quickAddSaving ? <CircularProgress size={18} color="inherit" /> : <PersonAddIcon />}
            sx={{ fontWeight: 700 }}
          >
            {quickAddSaving ? 'Saving...' : 'Save & Select Patient'}
          </Button>
        </DialogActions>
      </Dialog>

      {/* Canonical Bill Viewer & Print Dialog */}
      <BillViewerDialog
        open={billViewerOpen}
        bill={viewerBill}
        onClose={() => setBillViewerOpen(false)}
        onNavigateNext={submitResult?.next_route ? () => navigate(submitResult.next_route) : undefined}
        nextActionLabel={submitResult?.auto_next_message ? 'Continue to Next Stage' : undefined}
      />

    </Box>
  );
};
