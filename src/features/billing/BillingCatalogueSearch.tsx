/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Billing Fast Catalogue Search Component with Category Chips, Rich Result Cards & Panel Inspection
 */

import React, { useState, useRef, useCallback } from 'react';
import {
  Box,
  Typography,
  TextField,
  Paper,
  Button,
  Chip,
  InputAdornment,
  CircularProgress,
  Collapse,
  Divider,
  Alert,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import AddCircleOutlineIcon from '@mui/icons-material/AddCircleOutline';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ListAltIcon from '@mui/icons-material/ListAlt';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import ExpandLessIcon from '@mui/icons-material/ExpandLess';
import ScienceIcon from '@mui/icons-material/Science';
import AccessTimeIcon from '@mui/icons-material/AccessTime';
import InfoOutlinedIcon from '@mui/icons-material/InfoOutlined';

import { MoneyDisplay } from '@/components/common/MoneyDisplay';
import { supabase } from '@/lib/supabase';
import {
  BILLING_CATEGORY_FILTERS,
  BillingCategoryFilter,
  getSafeClinicalMeta,
  matchesCategoryFilter,
} from './billingCatalogueMeta';
import type { SelectedBillTest } from './mixedTierSelection';

export type CatalogueSearchResult = {
  entity_type: 'Test' | 'Package' | 'Panel';
  entity_id: string;
  code: string;
  name: string;
  short_name?: string | null;
  category?: string | null;
  specimen?: string | null;
  container?: string | null;
  price_paisa: number;
  price_configured: boolean;
  pricing_policy: 'Fixed' | 'Negotiable' | 'PricePending' | 'Manual';
  allow_zero_price_billing: boolean;
  reporting_type: string;
  rank_score: number;
  clinical_reporting_enabled?: boolean;
  collection_required?: boolean;
  workflow_type?: string;
  workflow_supported?: boolean;
  approval_state?: string;
  readiness_classification?: string;
  department?: string | null;
  validation_status?: string | null;
  test_kind?: string | null;
  reporting_model?: string | null;
  parameter_count?: number;
  panel_component_count?: number;
};

export interface PanelComponentItem {
  component_test_id: string;
  component_code: string;
  component_name: string;
  component_unit: string;
  component_specimen: string;
  component_role: string;
  display_order: number;
  is_required: boolean;
}

interface BillingCatalogueSearchProps {
  inputRef: React.RefObject<HTMLInputElement | null>;
  searchTerm: string;
  onSearchChange: (term: string) => void;
  searchResults: CatalogueSearchResult[];
  searchingCatalogue: boolean;
  highlightedIndex: number;
  onHighlightChange: (index: number) => void;
  onSelectResult: (result: CatalogueSearchResult) => void;
  selectedItems: SelectedBillTest[];
  selectedPanel: { service_id: string; panel_version: number; name: string; component_ids: string[] } | null;
  selectedPackages: { package_id: string; code: string; name: string; component_ids: string[] }[];
  onPanelConflictWarning?: (message: string) => void;
  onKeyDown?: (e: React.KeyboardEvent<HTMLInputElement>) => void;
}

export const BillingCatalogueSearch: React.FC<BillingCatalogueSearchProps> = ({
  inputRef,
  searchTerm,
  onSearchChange,
  searchResults,
  searchingCatalogue,
  highlightedIndex,
  onHighlightChange,
  onSelectResult,
  selectedItems,
  selectedPanel,
  selectedPackages,
  onPanelConflictWarning,
  onKeyDown,
}) => {
  const [selectedCategory, setSelectedCategory] = useState<BillingCategoryFilter>(BILLING_CATEGORY_FILTERS[0]);
  const [expandedPanelId, setExpandedPanelId] = useState<string | null>(null);
  const [panelComponentsMap, setPanelComponentsMap] = useState<Record<string, PanelComponentItem[]>>({});
  const [loadingPanelDetails, setLoadingPanelDetails] = useState<string | null>(null);
  const [componentWarning, setComponentWarning] = useState<string | null>(null);
  const searchContainerRef = useRef<HTMLDivElement>(null);

  // Filter search results with selected category
  const filteredResults = React.useMemo(() => {
    if (selectedCategory.id === 'ALL') {
      return searchResults;
    }
    return searchResults.filter((item) => matchesCategoryFilter(selectedCategory, item));
  }, [searchResults, selectedCategory]);

  // Load panel components on expand
  const togglePanelDetails = useCallback(async (panelTestId: string) => {
    if (expandedPanelId === panelTestId) {
      setExpandedPanelId(null);
      return;
    }

    setExpandedPanelId(panelTestId);

    if (!panelComponentsMap[panelTestId]) {
      setLoadingPanelDetails(panelTestId);
      try {
        const { data, error } = await supabase.rpc('get_catalogue_panel_components', {
          p_panel_test_id: panelTestId,
        });

        if (!error && data) {
          setPanelComponentsMap((prev) => ({ ...prev, [panelTestId]: data as PanelComponentItem[] }));
        } else {
          // Fallback direct query on catalogue_panel_components
          const { data: directData } = await supabase
            .from('catalogue_panel_components')
            .select('display_order, is_required, component_role, component:tests!component_test_id(id, code, name, unit, sample_type)')
            .eq('panel_test_id', panelTestId)
            .order('display_order', { ascending: true });

          if (directData) {
            const mapped: PanelComponentItem[] = (directData as any[]).map((d) => ({
              component_test_id: d.component?.id || '',
              component_code: d.component?.code || '',
              component_name: d.component?.name || '',
              component_unit: d.component?.unit || '',
              component_specimen: d.component?.sample_type || 'Blood',
              component_role: d.component_role || 'Measured',
              display_order: d.display_order || 0,
              is_required: d.is_required ?? true,
            }));
            setPanelComponentsMap((prev) => ({ ...prev, [panelTestId]: mapped }));
          }
        }
      } catch (err) {
        console.warn('[Billing Search] Panel component fetch error:', err);
      } finally {
        setLoadingPanelDetails(null);
      }
    }
  }, [expandedPanelId, panelComponentsMap]);

  // Keyboard Navigation inside search box
  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (onKeyDown) {
      onKeyDown(e);
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      onHighlightChange(Math.min(highlightedIndex + 1, filteredResults.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      onHighlightChange(Math.max(highlightedIndex - 1, 0));
    } else if (e.key === 'Escape') {
      e.preventDefault();
      onSearchChange('');
      onHighlightChange(0);
      setExpandedPanelId(null);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      const match = filteredResults[highlightedIndex];
      if (match) {
        handleAddItem(match);
      }
    }
  };

  // Add Item with Duplicate Component Safety Check
  const handleAddItem = (result: CatalogueSearchResult) => {
    // Check if item is already added
    const isAlreadySelected = result.entity_type === 'Test'
      ? selectedItems.some((item) => item.test.id === result.entity_id)
      : result.entity_type === 'Panel'
      ? selectedPanel?.service_id === result.entity_id
      : selectedPackages.some((pkg) => pkg.package_id === result.entity_id);

    if (isAlreadySelected) return;

    // Check if adding a panel that has components already in bill
    const isPanel = result.name.toLowerCase().includes('profile') || result.name.toLowerCase().includes('panel') || result.code.startsWith('PRO-');
    if (isPanel) {
      const components = panelComponentsMap[result.entity_id];
      if (components && components.length > 0) {
        const conflictingTests = selectedItems.filter((item) =>
          components.some((c) => c.component_test_id === item.test.id || c.component_code === item.test.code)
        );

        if (conflictingTests.length > 0) {
          const names = conflictingTests.map((t) => t.test.name).join(', ');
          const msg = `Component test "${names}" is already in the bill. Adding this panel bundles the full investigation at the panel rate.`;
          setComponentWarning(msg);
          onPanelConflictWarning?.(msg);
        }
      }
    }

    // Check if adding an individual test that is already covered under a selected panel
    if (selectedPanel && selectedPanel.component_ids.includes(result.entity_id)) {
      const msg = `"${result.name}" is already included in the selected panel "${selectedPanel.name}". It will not be charged separately.`;
      setComponentWarning(msg);
      onPanelConflictWarning?.(msg);
    }

    // Check if reportable single test has zero parameters configured (and is not a valid profile container)
    const isProfile = isPanel || result.test_kind === 'Profile' || result.reporting_model === 'Profile' || (result.panel_component_count != null && result.panel_component_count > 0);
    const isIncomplete = result.entity_type === 'Test' && result.reporting_type !== 'NoReporting' && !isProfile && result.parameter_count === 0;
    if (isIncomplete) {
      const msg = `"${result.name}" (${result.code}) has 0 reporting parameters configured. Lab parameter setup is required before it can be clinically ordered.`;
      setComponentWarning(msg);
      onPanelConflictWarning?.(msg);
      return;
    }

    onSelectResult(result);
  };

  return (
    <Box sx={{ position: 'relative', mb: 3 }} ref={searchContainerRef}>
      {/* 1. Horizontal Category Chips */}
      <Box
        sx={{
          display: 'flex',
          gap: 0.75,
          overflowX: 'auto',
          pb: 1.25,
          mb: 1.5,
          scrollbarWidth: 'thin',
          '&::-webkit-scrollbar': { height: 4 },
          '&::-webkit-scrollbar-thumb': { bgcolor: '#cbd5e1', borderRadius: 2 },
        }}
      >
        {BILLING_CATEGORY_FILTERS.map((cat) => {
          const isSelected = selectedCategory.id === cat.id;
          return (
            <Chip
              key={cat.id}
              label={cat.fullLabel}
              clickable
              onClick={() => {
                setSelectedCategory(cat);
                inputRef.current?.focus();
              }}
              color={isSelected ? 'primary' : 'default'}
              variant={isSelected ? 'filled' : 'outlined'}
              size="small"
              sx={{
                fontWeight: isSelected ? 700 : 500,
                fontSize: '0.8rem',
                borderRadius: '16px',
                px: 0.5,
                bgcolor: isSelected ? 'primary.main' : '#f8fafc',
                borderColor: isSelected ? 'primary.main' : '#cbd5e1',
                color: isSelected ? '#ffffff' : 'text.primary',
                '&:hover': {
                  bgcolor: isSelected ? 'primary.dark' : '#e2e8f0',
                },
              }}
            />
          );
        })}
      </Box>

      {/* 2. Fast Search Box */}
      <TextField
        inputRef={inputRef}
        fullWidth
        size="medium"
        label="Search Test / Profile / Package (परीक्षण वा प्रोफाइल खोज्नुहोस्)"
        placeholder="Type name, abbreviation, alias or code (e.g. cbc, lft, kft, lipid, tsh, vit d, troponin, sugar, पिसाब…)"
        value={searchTerm}
        onChange={(e) => onSearchChange(e.target.value)}
        onKeyDown={handleKeyDown}
        helperText="नाम, संक्षिप्त नाम (Abbreviation) वा समूह अनुसार प्रयोगशालामा उपलब्ध परीक्षणहरू तुरुन्त खोज्नुहोस्।"
        InputProps={{
          startAdornment: (
            <InputAdornment position="start">
              <SearchIcon color="primary" />
            </InputAdornment>
          ),
          endAdornment: searchingCatalogue ? (
            <InputAdornment position="end">
              <CircularProgress size={20} color="primary" />
            </InputAdornment>
          ) : null,
          sx: {
            bgcolor: '#ffffff',
            borderRadius: 2,
            fontWeight: 500,
            '&.Mui-focused': {
              boxShadow: '0 0 0 3px rgba(37, 99, 235, 0.15)',
            },
          },
        }}
      />

      {/* Conflict / Duplicate Warning Dialog / Banner */}
      {componentWarning && (
        <Alert
          severity="info"
          icon={<InfoOutlinedIcon />}
          onClose={() => setComponentWarning(null)}
          sx={{ mt: 1, mb: 1, fontSize: '0.825rem' }}
        >
          {componentWarning}
        </Alert>
      )}

      {/* 3. Search Results Overlay / Cards */}
      {searchTerm.trim().length >= 1 && (
        <Paper
          elevation={8}
          sx={{
            position: 'absolute',
            zIndex: 30,
            left: 0,
            right: 0,
            mt: 0.5,
            maxHeight: 480,
            overflowY: 'auto',
            borderRadius: 2,
            border: '1px solid #cbd5e1',
            bgcolor: '#f8fafc',
            boxShadow: '0 12px 28px rgba(15, 23, 42, 0.12)',
          }}
        >
          {filteredResults.length === 0 && !searchingCatalogue ? (
            <Box sx={{ p: 3, textAlign: 'center' }}>
              <Typography variant="body2" color="text.secondary" fontWeight={600}>
                No matching billable investigation found for &quot;{searchTerm}&quot; in {selectedCategory.labelEn}.
              </Typography>
              <Typography variant="caption" color="text.secondary" display="block" sx={{ mt: 0.5 }}>
                Try searching with short abbreviation (e.g. CBC, LFT, KFT, TSH, Vit D) or Nepali name.
              </Typography>
            </Box>
          ) : (
            filteredResults.map((result, index) => {
              const isHighlighted = index === highlightedIndex;
              const isTest = result.entity_type === 'Test';
              const isPanel = result.entity_type === 'Panel' || result.name.toLowerCase().includes('profile') || result.code.startsWith('PRO-');
              const isPackage = result.entity_type === 'Package';

              const isDuplicate = isTest
                ? selectedItems.some((item) => item.test.id === result.entity_id)
                : isPanel
                ? selectedPanel?.service_id === result.entity_id || selectedItems.some((item) => item.test.id === result.entity_id)
                : selectedPackages.some((pkg) => pkg.package_id === result.entity_id);

              const clinicalMeta = getSafeClinicalMeta(
                result.code,
                result.name,
                result.department || result.category,
                result.specimen,
                result.container
              );

              const isExpanded = expandedPanelId === result.entity_id;
              const panelComponents = panelComponentsMap[result.entity_id];
              const isLoadingComponents = loadingPanelDetails === result.entity_id;

              const isProfile = isPanel || result.test_kind === 'Profile' || result.reporting_model === 'Profile' || (result.panel_component_count != null && result.panel_component_count > 0);
              const isIncomplete = result.entity_type === 'Test' && result.reporting_type !== 'NoReporting' && !isProfile && result.parameter_count === 0;

              return (
                <Box
                  key={`${result.entity_type}-${result.entity_id}`}
                  onMouseEnter={() => onHighlightChange(index)}
                  sx={{
                    p: 2,
                    borderBottom: '1px solid #e2e8f0',
                    bgcolor: isHighlighted ? '#ffffff' : '#f8fafc',
                    borderLeft: isHighlighted ? '4px solid #2563eb' : '4px solid transparent',
                    transition: 'all 0.15s ease-in-out',
                    opacity: isDuplicate || isIncomplete ? 0.65 : 1,
                  }}
                >
                  {/* Result Card Header */}
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 0.75 }}>
                    <Box sx={{ flex: 1, pr: 2 }}>
                      {/* Bilingual Title */}
                      {clinicalMeta.titleNp && (
                        <Typography variant="caption" sx={{ color: 'primary.dark', fontWeight: 700, display: 'block', fontSize: '0.8rem' }}>
                          {clinicalMeta.titleNp}
                        </Typography>
                      )}
                      <Typography variant="subtitle1" sx={{ fontWeight: 800, color: '#0f172a', lineHeight: 1.3 }}>
                        {result.name}
                        {clinicalMeta.abbreviation && clinicalMeta.abbreviation !== result.code && (
                          <Chip
                            size="small"
                            label={clinicalMeta.abbreviation}
                            sx={{ ml: 1, height: 20, fontSize: '0.72rem', fontWeight: 700, bgcolor: '#e0f2fe', color: '#0369a1' }}
                          />
                        )}
                        {isIncomplete && (
                          <Chip
                            size="small"
                            label="Needs Parameter Setup"
                            color="warning"
                            variant="outlined"
                            sx={{ ml: 1, height: 20, fontSize: '0.72rem', fontWeight: 700 }}
                          />
                        )}
                      </Typography>
                    </Box>

                    {/* Price & Action */}
                    <Box sx={{ textAlign: 'right', flexShrink: 0 }}>
                      <Box sx={{ mb: 0.75 }}>
                        {result.pricing_policy === 'Fixed' || (result.price_configured && result.price_paisa > 0) ? (
                          <Typography variant="subtitle1" fontWeight={800} color="primary.main">
                            <MoneyDisplay paisa={result.price_paisa} />
                          </Typography>
                        ) : result.allow_zero_price_billing ? (
                          <Chip size="small" label="Free / Zero-Price" color="success" variant="outlined" sx={{ fontWeight: 700 }} />
                        ) : (
                          <Chip size="small" label="Rate on Entry" color="warning" variant="outlined" sx={{ fontWeight: 700 }} />
                        )}
                      </Box>

                      <Box sx={{ display: 'flex', gap: 1, justifyContent: 'flex-end' }}>
                        {isPanel && (
                          <Button
                            size="small"
                            variant="outlined"
                            color="inherit"
                            onClick={(e) => {
                              e.stopPropagation();
                              void togglePanelDetails(result.entity_id);
                            }}
                            endIcon={isExpanded ? <ExpandLessIcon fontSize="small" /> : <ExpandMoreIcon fontSize="small" />}
                            sx={{ fontSize: '0.75rem', textTransform: 'none', py: 0.25, px: 1 }}
                          >
                            {isExpanded ? 'Hide Details' : 'View Details'}
                          </Button>
                        )}

                        <Button
                          size="small"
                          variant="contained"
                          color={isDuplicate ? 'inherit' : isIncomplete ? 'warning' : 'primary'}
                          disabled={isDuplicate || isIncomplete}
                          onClick={(e) => {
                            e.stopPropagation();
                            handleAddItem(result);
                          }}
                          startIcon={isDuplicate ? <CheckCircleIcon fontSize="small" /> : <AddCircleOutlineIcon fontSize="small" />}
                          sx={{
                            fontSize: '0.75rem',
                            fontWeight: 700,
                            textTransform: 'none',
                            py: 0.35,
                            px: 1.5,
                            borderRadius: 1.5,
                          }}
                        >
                          {isIncomplete ? 'Incomplete Setup' : isDuplicate ? 'Added' : '+ Add'}
                        </Button>
                      </Box>
                    </Box>
                  </Box>

                  {/* Badges: Code, Entity Type, Department, Status */}
                  <Box sx={{ display: 'flex', gap: 0.75, flexWrap: 'wrap', alignItems: 'center', mb: 1 }}>
                    <Chip
                      size="small"
                      label={result.code}
                      sx={{ height: 20, fontSize: '0.72rem', fontWeight: 700, bgcolor: '#f1f5f9', color: '#475569' }}
                    />
                    <Chip
                      size="small"
                      label={result.entity_type}
                      color={isPanel ? 'secondary' : isPackage ? 'info' : 'default'}
                      sx={{ height: 20, fontSize: '0.72rem', fontWeight: 700 }}
                    />
                    <Chip
                      size="small"
                      label={result.department || result.category || 'Clinical Pathology'}
                      sx={{ height: 20, fontSize: '0.72rem', fontWeight: 600, bgcolor: '#f8fafc', border: '1px solid #e2e8f0' }}
                    />
                  </Box>

                  {/* Safe Clinical Description */}
                  <Typography variant="body2" sx={{ color: '#475569', fontSize: '0.825rem', mb: 1, lineHeight: 1.4 }}>
                    {clinicalMeta.safeDescription}
                  </Typography>

                  {/* Specimen, Preparation & TAT Footnote */}
                  <Box
                    sx={{
                      display: 'grid',
                      gridTemplateColumns: { xs: '1fr', sm: '1fr 1fr auto' },
                      gap: 1.5,
                      p: 1.25,
                      borderRadius: 1.5,
                      bgcolor: '#ffffff',
                      border: '1px solid #e2e8f0',
                      fontSize: '0.775rem',
                    }}
                  >
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75 }}>
                      <ScienceIcon fontSize="inherit" color="primary" />
                      <Typography variant="caption" sx={{ color: '#334155' }}>
                        <strong>Sample:</strong> {clinicalMeta.specimenGuide}
                      </Typography>
                    </Box>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75 }}>
                      <InfoOutlinedIcon fontSize="inherit" color="action" />
                      <Typography variant="caption" sx={{ color: '#334155' }}>
                        <strong>Prep:</strong> {clinicalMeta.prepInstructions}
                      </Typography>
                    </Box>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75 }}>
                      <AccessTimeIcon fontSize="inherit" color="action" />
                      <Typography variant="caption" sx={{ color: '#64748b' }}>
                        <strong>TAT:</strong> {clinicalMeta.tatEstimate}
                      </Typography>
                    </Box>
                  </Box>

                  {/* Expandable Panel Breakdown Tree */}
                  {isPanel && (
                    <Collapse in={isExpanded} timeout="auto" unmountOnExit>
                      <Box sx={{ mt: 1.5, p: 1.5, bgcolor: '#ffffff', borderRadius: 1.5, border: '1px solid #cbd5e1' }}>
                        <Typography variant="caption" fontWeight={700} color="primary.main" sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 1 }}>
                          <ListAltIcon fontSize="small" /> Bundled Panel Components ({panelComponents?.length || 'Loading...'}):
                        </Typography>

                        {isLoadingComponents ? (
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, py: 1 }}>
                            <CircularProgress size={16} />
                            <Typography variant="caption">Loading panel component breakdown…</Typography>
                          </Box>
                        ) : panelComponents && panelComponents.length > 0 ? (
                          <Box sx={{ pl: 1, fontFamily: 'monospace', fontSize: '0.8rem', color: '#1e293b' }}>
                            <Typography variant="caption" fontWeight={700} display="block" sx={{ mb: 0.5 }}>
                              {result.name}
                            </Typography>
                            {panelComponents.map((comp, cIdx) => {
                              const isLast = cIdx === panelComponents.length - 1;
                              const branchChar = isLast ? '└── ' : '├── ';
                              return (
                                <Box
                                  key={comp.component_test_id || cIdx}
                                  sx={{
                                    display: 'flex',
                                    justifyContent: 'space-between',
                                    py: 0.25,
                                    borderBottom: isLast ? 'none' : '1px dashed #f1f5f9',
                                  }}
                                >
                                  <Typography variant="caption" sx={{ fontFamily: 'inherit' }}>
                                    {branchChar}<strong>{comp.component_name}</strong>
                                    {comp.component_unit && ` (${comp.component_unit})`}
                                  </Typography>
                                  <Chip
                                    size="small"
                                    label={comp.component_role || 'Measured'}
                                    sx={{ height: 16, fontSize: '0.65rem' }}
                                  />
                                </Box>
                              );
                            })}
                            <Divider sx={{ my: 1 }} />
                            <Typography variant="caption" color="text.secondary" sx={{ fontStyle: 'italic', display: 'block' }}>
                              * Adding this panel bills the unified bundled rate. Individual components will not be billed separately.
                            </Typography>
                          </Box>
                        ) : (
                          <Typography variant="caption" color="text.secondary">
                            Panel components configured in laboratory master catalogue.
                          </Typography>
                        )}
                      </Box>
                    </Collapse>
                  )}
                </Box>
              );
            })
          )}
        </Paper>
      )}
    </Box>
  );
};
