/**
 * testSourceResolver.ts
 *
 * Authoritative central resolver for:
 *   1. Configured Source: What instrument/method the parameter/test/profile is configured to use.
 *   2. Actual Result Provenance: How the stored test result was actually captured.
 *
 * Configured Source kinds:
 *   - ANALYZER          : Single physical analyzer instrument (e.g. "CounCell 23 Excel", "CORALAB ACE", "FIAcheck")
 *   - MANUAL            : Explicitly manual / microscopy / visual method
 *   - CALCULATED        : Formula-derived analyte (no physical instrument directly measuring it)
 *   - OUTSOURCE         : External reference laboratory
 *   - MIXED             : Mixed physical sources (e.g. Analyzer + Manual)
 *   - MULTIPLE_ANALYZERS: >1 active physical analyzers mapped to the same parameter/test
 *   - MULTIPLE_SOURCES  : Profile/panel consisting of child components on different physical analyzers
 *   - UNKNOWN           : Missing/unconfigured source (MUST NOT default to Manual)
 *
 * Actual Result Provenance kinds:
 *   - ANALYZER   : Sourced from analyzer data stream
 *   - MANUAL     : Typed manually by laboratory technician
 *   - CALCULATED : Calculated by server math engine
 *   - IMPORT     : Sourced from external batch/file import
 *   - UNKNOWN    : Unspecified / historical record without provenance
 */

export type ConfiguredSourceKind =
  | 'ANALYZER'
  | 'MANUAL'
  | 'CALCULATED'
  | 'OUTSOURCE'
  | 'MIXED'
  | 'MULTIPLE_ANALYZERS'
  | 'MULTIPLE_SOURCES'
  | 'UNKNOWN';

export interface ConfiguredSourceResult {
  kind: ConfiguredSourceKind;
  /** Human-readable label shown in UI chips */
  label: string;
  /** List of analyzer display names associated with this source (if any) */
  analyzerNames?: string[];
  /** MUI sx-compatible background color */
  bgcolor: string;
  /** MUI sx-compatible text color */
  color: string;
}

export type ActualResultProvenanceKind =
  | 'ANALYZER'
  | 'MANUAL'
  | 'CALCULATED'
  | 'IMPORT'
  | 'UNKNOWN';

export interface ActualResultProvenanceResult {
  kind: ActualResultProvenanceKind;
  label: string;
  bgcolor: string;
  color: string;
}

/** Mapping row as returned by Supabase when joining analyzer_parameter_mappings → analyzers */
export interface AnalyzerMappingRow {
  parameter_id: string;
  analyzer_id?: string;
  is_active?: boolean | null;
  analyzers?: {
    name: string;
    code?: string;
    lifecycle_status?: string | null;
  } | null;
}

/** Theme color tokens for configured sources */
const SOURCE_COLORS: Record<ConfiguredSourceKind, { bgcolor: string; color: string }> = {
  ANALYZER: { bgcolor: '#e0f2fe', color: '#0369a1' },
  MANUAL: { bgcolor: '#f1f5f9', color: '#334155' },
  CALCULATED: { bgcolor: '#f3e8ff', color: '#7e22ce' },
  OUTSOURCE: { bgcolor: '#ffedd5', color: '#c2410c' },
  MIXED: { bgcolor: '#fef3c7', color: '#92400e' },
  MULTIPLE_ANALYZERS: { bgcolor: '#e0e7ff', color: '#4338ca' },
  MULTIPLE_SOURCES: { bgcolor: '#e0e7ff', color: '#4338ca' },
  UNKNOWN: { bgcolor: '#f8fafc', color: '#64748b' },
};

/** Theme color tokens for actual result provenance */
const PROVENANCE_COLORS: Record<ActualResultProvenanceKind, { bgcolor: string; color: string }> = {
  ANALYZER: { bgcolor: '#e0f2fe', color: '#0369a1' },
  MANUAL: { bgcolor: '#f1f5f9', color: '#334155' },
  CALCULATED: { bgcolor: '#f3e8ff', color: '#7e22ce' },
  IMPORT: { bgcolor: '#ecfdf5', color: '#047857' },
  UNKNOWN: { bgcolor: '#f8fafc', color: '#64748b' },
};

/** Known manual methods/analyzers */
const MANUAL_PATTERNS = [
  'MANUAL',
  'MICROSCOPY',
  'WESTERGREN',
  'PERIPHERAL SMEAR',
  'RAPID',
  'VISUAL',
  'SLIDE',
  'STRIP',
];

function isExplicitManual(methodOrAnalyzer?: string | null): boolean {
  if (!methodOrAnalyzer) return false;
  const upper = methodOrAnalyzer.toUpperCase();
  return MANUAL_PATTERNS.some((pattern) => upper.includes(pattern));
}

/**
 * Build a lookup map of parameter_id → Array of active analyzer display names.
 * Avoids silent overwrite of multi-analyzer configurations.
 *
 * @param mappings - Rows from `analyzer_parameter_mappings` with joined `analyzers(name, code, lifecycle_status)`
 */
export function buildAnalyzerLookup(
  mappings: AnalyzerMappingRow[]
): Map<string, string[]> {
  const lookup = new Map<string, string[]>();

  for (const m of mappings) {
    // 1. Check mapping active state
    if (m.is_active === false) continue;

    // 2. Check analyzer lifecycle status
    const analyzerStatus = m.analyzers?.lifecycle_status?.toUpperCase();
    if (analyzerStatus === 'INACTIVE' || analyzerStatus === 'RETIRED') continue;

    const analyzerName = m.analyzers?.name?.trim();
    if (!analyzerName) continue;

    const existing = lookup.get(m.parameter_id) || [];
    if (!existing.includes(analyzerName)) {
      existing.push(analyzerName);
      // Sort deterministically
      existing.sort((a, b) => a.localeCompare(b));
      lookup.set(m.parameter_id, existing);
    }
  }

  return lookup;
}

export interface ResolveParameterSourceOptions {
  valueType?: string | null;
  parameterId?: string | null;
  analyzerLookup?: Map<string, string[] | string> | null;
  isOutsource?: boolean | null;
  department?: string | null;
  method?: string | null;
  isManual?: boolean | null;
}

/**
 * Resolve configured source for a single parameter.
 */
export function resolveConfiguredParameterSource(
  optionsOrValueType: ResolveParameterSourceOptions | string,
  parameterId?: string,
  analyzerLookup?: Map<string, string[] | string> | null,
  isOutsource?: boolean | null,
  method?: string | null
): ConfiguredSourceResult {
  let valueType: string | null = null;
  let paramId: string | null = null;
  let lookup: Map<string, string[] | string> | null = null;
  let outsource = false;
  let explicitMethod: string | null = null;
  let isManualFlag = false;

  if (typeof optionsOrValueType === 'object' && optionsOrValueType !== null) {
    valueType = optionsOrValueType.valueType ?? null;
    paramId = optionsOrValueType.parameterId ?? null;
    lookup = optionsOrValueType.analyzerLookup ?? null;
    outsource = Boolean(
      optionsOrValueType.isOutsource ||
      optionsOrValueType.department?.toLowerCase().includes('outsource')
    );
    explicitMethod = optionsOrValueType.method ?? null;
    isManualFlag = Boolean(optionsOrValueType.isManual);
  } else {
    valueType = optionsOrValueType;
    paramId = parameterId ?? null;
    lookup = analyzerLookup ?? null;
    outsource = Boolean(isOutsource);
    explicitMethod = method ?? null;
  }

  // 1. Outsource check
  if (outsource) {
    return {
      kind: 'OUTSOURCE',
      label: 'Outsource',
      ...SOURCE_COLORS.OUTSOURCE,
    };
  }

  // 2. Calculated formula parameters are always CALCULATED
  if (valueType === 'Calculated') {
    return {
      kind: 'CALCULATED',
      label: 'Calculated',
      ...SOURCE_COLORS.CALCULATED,
    };
  }

  // 3. Analyzer mappings check
  if (paramId && lookup) {
    const rawVal = lookup.get(paramId);
    const analyzerNames = Array.isArray(rawVal) ? rawVal : (rawVal ? [rawVal] : []);

    if (analyzerNames.length === 1) {
      const name = analyzerNames[0];
      if (isExplicitManual(name)) {
        return {
          kind: 'MANUAL',
          label: 'Manual',
          ...SOURCE_COLORS.MANUAL,
        };
      }
      return {
        kind: 'ANALYZER',
        label: name,
        analyzerNames: [name],
        ...SOURCE_COLORS.ANALYZER,
      };
    } else if (analyzerNames.length > 1) {
      return {
        kind: 'MULTIPLE_ANALYZERS',
        label: 'Multiple Analyzers',
        analyzerNames: [...analyzerNames].sort((a, b) => a.localeCompare(b)),
        ...SOURCE_COLORS.MULTIPLE_ANALYZERS,
      };
    }
  }

  // 4. Explicit manual configuration
  if (isManualFlag || isExplicitManual(explicitMethod)) {
    return {
      kind: 'MANUAL',
      label: 'Manual',
      ...SOURCE_COLORS.MANUAL,
    };
  }

  // 5. UNKNOWN - Missing source configuration (must NOT default to Manual)
  return {
    kind: 'UNKNOWN',
    label: 'Unknown',
    ...SOURCE_COLORS.UNKNOWN,
  };
}

export interface ResolveTestSourceOptions {
  isOutsource?: boolean | null;
  department?: string | null;
  method?: string | null;
  parameters?: Array<{
    id?: string;
    value_type?: string | null;
    method?: string | null;
    is_outsource?: boolean | null;
  }>;
  analyzerLookup?: Map<string, string[] | string> | null;
}

/**
 * Resolve configured source for a whole single test (aggregating its parameters).
 * Calculated parameters do NOT distort physical source aggregation.
 */
export function resolveConfiguredTestSource(
  options: ResolveTestSourceOptions
): ConfiguredSourceResult {
  const { isOutsource, department, method, parameters, analyzerLookup } = options;

  if (isOutsource || department?.toLowerCase().includes('outsource')) {
    return {
      kind: 'OUTSOURCE',
      label: 'Outsource',
      ...SOURCE_COLORS.OUTSOURCE,
    };
  }

  if (!parameters || parameters.length === 0) {
    if (isExplicitManual(method)) {
      return {
        kind: 'MANUAL',
        label: 'Manual',
        ...SOURCE_COLORS.MANUAL,
      };
    }
    return {
      kind: 'UNKNOWN',
      label: 'Unknown',
      ...SOURCE_COLORS.UNKNOWN,
    };
  }

  // Resolve all parameters
  const resolvedParams = parameters.map((p) =>
    resolveConfiguredParameterSource({
      valueType: p.value_type,
      parameterId: p.id,
      analyzerLookup,
      isOutsource: p.is_outsource,
      method: p.method || method,
    })
  );

  // Filter out pure calculated parameters when evaluating physical source
  const physicalParams = resolvedParams.filter((r) => r.kind !== 'CALCULATED');

  // If test only has calculated parameters
  if (physicalParams.length === 0) {
    return {
      kind: 'CALCULATED',
      label: 'Calculated',
      ...SOURCE_COLORS.CALCULATED,
    };
  }

  const allAnalyzerNames = Array.from(
    new Set(physicalParams.flatMap((p) => p.analyzerNames || []))
  ).sort((a, b) => a.localeCompare(b));

  const hasManual = physicalParams.some((p) => p.kind === 'MANUAL');
  const hasOutsource = physicalParams.some((p) => p.kind === 'OUTSOURCE');
  const hasAnalyzer = allAnalyzerNames.length > 0;
  const hasUnknown = physicalParams.some((p) => p.kind === 'UNKNOWN');

  // Multi-analyzer
  if (allAnalyzerNames.length > 1) {
    if (hasManual || hasOutsource) {
      return {
        kind: 'MIXED',
        label: 'Mixed',
        analyzerNames: allAnalyzerNames,
        ...SOURCE_COLORS.MIXED,
      };
    }
    return {
      kind: 'MULTIPLE_ANALYZERS',
      label: 'Multiple Analyzers',
      analyzerNames: allAnalyzerNames,
      ...SOURCE_COLORS.MULTIPLE_ANALYZERS,
    };
  }

  // Single analyzer + manual -> Mixed
  if (hasAnalyzer && hasManual) {
    return {
      kind: 'MIXED',
      label: 'Mixed',
      analyzerNames: allAnalyzerNames,
      ...SOURCE_COLORS.MIXED,
    };
  }

  // Single analyzer
  if (hasAnalyzer && !hasManual && !hasOutsource && !hasUnknown) {
    return {
      kind: 'ANALYZER',
      label: allAnalyzerNames[0],
      analyzerNames: allAnalyzerNames,
      ...SOURCE_COLORS.ANALYZER,
    };
  }

  // Single analyzer with some unconfigured params -> Mixed
  if (hasAnalyzer && hasUnknown) {
    return {
      kind: 'MIXED',
      label: 'Mixed',
      analyzerNames: allAnalyzerNames,
      ...SOURCE_COLORS.MIXED,
    };
  }

  // All manual
  if (hasManual && !hasAnalyzer && !hasOutsource && !hasUnknown) {
    return {
      kind: 'MANUAL',
      label: 'Manual',
      ...SOURCE_COLORS.MANUAL,
    };
  }

  // All outsource
  if (hasOutsource && !hasAnalyzer && !hasManual && !hasUnknown) {
    return {
      kind: 'OUTSOURCE',
      label: 'Outsource',
      ...SOURCE_COLORS.OUTSOURCE,
    };
  }

  // All unknown
  if (hasUnknown && !hasAnalyzer && !hasManual && !hasOutsource) {
    return {
      kind: 'UNKNOWN',
      label: 'Unknown',
      ...SOURCE_COLORS.UNKNOWN,
    };
  }

  return {
    kind: 'MIXED',
    label: 'Mixed',
    analyzerNames: allAnalyzerNames,
    ...SOURCE_COLORS.MIXED,
  };
}

export interface ProfileComponentSourceItem {
  isOutsource?: boolean | null;
  department?: string | null;
  method?: string | null;
  parameters?: Array<{
    id?: string;
    value_type?: string | null;
    method?: string | null;
    is_outsource?: boolean | null;
  }>;
  resolvedSource?: ConfiguredSourceResult;
}

export interface ResolveProfileSourceOptions {
  isOutsource?: boolean | null;
  department?: string | null;
  components?: ProfileComponentSourceItem[];
  analyzerLookup?: Map<string, string[] | string> | null;
}

/**
 * Resolve configured source for a Profile / Panel by aggregating child components.
 * Calculated child components do NOT create false Mixed status.
 */
export function resolveConfiguredProfileSource(
  options: ResolveProfileSourceOptions
): ConfiguredSourceResult {
  const { isOutsource, department, components, analyzerLookup } = options;

  if (isOutsource || department?.toLowerCase().includes('outsource')) {
    return {
      kind: 'OUTSOURCE',
      label: 'Outsource',
      ...SOURCE_COLORS.OUTSOURCE,
    };
  }

  if (!components || components.length === 0) {
    return {
      kind: 'UNKNOWN',
      label: 'Unknown',
      ...SOURCE_COLORS.UNKNOWN,
    };
  }

  // Resolve each component
  const resolvedComponents = components.map((c) => {
    if (c.resolvedSource) return c.resolvedSource;
    return resolveConfiguredTestSource({
      isOutsource: c.isOutsource,
      department: c.department,
      method: c.method,
      parameters: c.parameters,
      analyzerLookup,
    });
  });

  // Filter out pure calculated components
  const physicalComponents = resolvedComponents.filter((r) => r.kind !== 'CALCULATED');

  if (physicalComponents.length === 0) {
    return {
      kind: 'CALCULATED',
      label: 'Calculated',
      ...SOURCE_COLORS.CALCULATED,
    };
  }

  const allAnalyzerNames = Array.from(
    new Set(physicalComponents.flatMap((c) => c.analyzerNames || []))
  ).sort((a, b) => a.localeCompare(b));

  const hasManual = physicalComponents.some(
    (c) => c.kind === 'MANUAL' || c.kind === 'MIXED'
  );
  const hasOutsource = physicalComponents.some((c) => c.kind === 'OUTSOURCE');
  const hasUnknown = physicalComponents.some((c) => c.kind === 'UNKNOWN');
  const hasAnalyzer = allAnalyzerNames.length > 0;

  // Multiple distinct physical analyzers across profile components -> MULTIPLE_SOURCES
  if (allAnalyzerNames.length > 1) {
    return {
      kind: 'MULTIPLE_SOURCES',
      label: 'Multiple Sources',
      analyzerNames: allAnalyzerNames,
      ...SOURCE_COLORS.MULTIPLE_SOURCES,
    };
  }

  // Single analyzer + manual in profile -> MIXED
  if (hasAnalyzer && hasManual) {
    return {
      kind: 'MIXED',
      label: 'Mixed',
      analyzerNames: allAnalyzerNames,
      ...SOURCE_COLORS.MIXED,
    };
  }

  // All children single analyzer
  if (hasAnalyzer && !hasManual && !hasOutsource && !hasUnknown) {
    return {
      kind: 'ANALYZER',
      label: allAnalyzerNames[0],
      analyzerNames: allAnalyzerNames,
      ...SOURCE_COLORS.ANALYZER,
    };
  }

  // All manual
  if (hasManual && !hasAnalyzer && !hasOutsource && !hasUnknown) {
    return {
      kind: 'MANUAL',
      label: 'Manual',
      ...SOURCE_COLORS.MANUAL,
    };
  }

  // All outsource
  if (hasOutsource && !hasAnalyzer && !hasManual && !hasUnknown) {
    return {
      kind: 'OUTSOURCE',
      label: 'Outsource',
      ...SOURCE_COLORS.OUTSOURCE,
    };
  }

  // All unknown
  if (hasUnknown && !hasAnalyzer && !hasManual && !hasOutsource) {
    return {
      kind: 'UNKNOWN',
      label: 'Unknown',
      ...SOURCE_COLORS.UNKNOWN,
    };
  }

  return {
    kind: 'MIXED',
    label: 'Mixed',
    analyzerNames: allAnalyzerNames,
    ...SOURCE_COLORS.MIXED,
  };
}

/**
 * Resolve Actual Result Provenance directly from saved result row data.
 * Does NOT infer actual provenance from analyzer mapping.
 */
export function resolveActualResultSource(
  savedResultSource?: string | null
): ActualResultProvenanceResult {
  const norm = (savedResultSource || '').toUpperCase().trim();

  switch (norm) {
    case 'ANALYZER':
      return {
        kind: 'ANALYZER',
        label: 'Analyzer',
        ...PROVENANCE_COLORS.ANALYZER,
      };
    case 'MANUAL':
      return {
        kind: 'MANUAL',
        label: 'Manual',
        ...PROVENANCE_COLORS.MANUAL,
      };
    case 'CALCULATED':
      return {
        kind: 'CALCULATED',
        label: 'Calculated',
        ...PROVENANCE_COLORS.CALCULATED,
      };
    case 'IMPORT':
      return {
        kind: 'IMPORT',
        label: 'Import',
        ...PROVENANCE_COLORS.IMPORT,
      };
    default:
      return {
        kind: 'UNKNOWN',
        label: 'Unknown',
        ...PROVENANCE_COLORS.UNKNOWN,
      };
  }
}

/**
 * Backward compatibility alias for resolveConfiguredParameterSource.
 */
export function resolveParameterSource(
  valueType: string,
  parameterId: string,
  analyzerLookup: Map<string, string[] | string>,
  _savedResultSource?: string | null
): ConfiguredSourceResult {
  return resolveConfiguredParameterSource({
    valueType,
    parameterId,
    analyzerLookup,
  });
}
