/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Laboratory Clinical Calculation & Safe Formula Evaluation Engine
 * Evaluates safe arithmetic expressions, handles dependency graphs, topological evaluation,
 * clinical safety constraints, and parameter-specific precision formatting.
 */

export type CalculationStatus =
  | 'SUCCESS'
  | 'MISSING_DEPENDENCY'
  | 'DIVIDE_BY_ZERO'
  | 'CIRCULAR_DEPENDENCY'
  | 'NOT_APPLICABLE'
  | 'SYNTAX_ERROR';

export interface CalculationResult {
  status: CalculationStatus;
  rawValue: number | null;
  displayValue: string;
  formattedValue: string;
  isCalculated: boolean;
  isError: boolean;
  errorMessage?: string;
  dependenciesUsed?: Record<string, number>;
  formulaUsed?: string;
}

export interface ClinicalEligibilityRule {
  condition: (values: Record<string, number>) => boolean;
  failureReason: string;
}

/**
 * Pre-configured clinical calculation safety constraints
 */
export const CLINICAL_RULES: Record<string, ClinicalEligibilityRule> = {
  LDL_FRIEDEWALD: {
    condition: (values) => {
      const trig = values['TRIG'] ?? values['TRIGLYCERIDES'];
      return trig === undefined || trig <= 400;
    },
    failureReason: 'Triglycerides > 400 mg/dL: Friedewald calculation not applicable',
  },
};

/**
 * Resolves precision (number of decimal places) for display/report
 */
export function getParameterPrecision(paramCode: string, _unit?: string | null): number {
  const code = (paramCode || '').toUpperCase().trim();

  // Bilirubin fractions -> 2 decimal places
  if (['TBIL', 'DBIL', 'IBIL', 'TOTAL_BILIRUBIN', 'DIRECT_BILIRUBIN', 'INDIRECT_BILIRUBIN'].includes(code)) {
    return 2;
  }
  // Serum Proteins & Albumin/Globulin -> 2 decimal places
  if (['TP', 'TOTAL_PROTEIN', 'ALB', 'ALBUMIN', 'GLOB', 'GLOBULIN'].includes(code)) {
    return 2;
  }
  // Ratios -> 2 decimal places
  if (['AG_RATIO', 'A_G_RATIO', 'INR', 'RATIO'].includes(code) || code.includes('RATIO')) {
    return 2;
  }
  // Lipids -> 2 decimal places (or 1 for VLDL)
  if (['VLDL', 'CHOL', 'TRIG', 'HDL', 'LDL'].includes(code)) {
    return 2;
  }
  // Routine Clinical Enzymes -> 0 decimals (Whole Integers)
  if (['SGOT', 'SGPT', 'AST', 'ALT', 'ALP', 'GGT', 'AMYLASE', 'LIPASE', 'CK', 'CKMB'].includes(code)) {
    return 0;
  }
  // Hematology Counts -> 0 decimals; Hb -> 1 or 2; RBC -> 2
  if (['TLC', 'PLT', 'NEUT', 'LYMPH', 'EOSIN', 'MONO', 'BASO', 'ESR'].includes(code)) {
    return 0;
  }
  if (['HB', 'PCV'].includes(code)) {
    return 1;
  }
  if (['RBC', 'MCV', 'MCH', 'MCHC', 'RDW'].includes(code)) {
    return 2;
  }
  // Suppression Percentage / Ratios -> 1 or 2 decimals
  if (code === 'END-0061-03' || code.includes('SUPPRESSION') || code.includes('PERCENT')) {
    return 1;
  }
  // Default fallback for biochemistry formulas
  return 2;
}

/**
 * Formats a numeric value with the appropriate precision
 */
export function formatPrecisionValue(value: number | null | undefined, precision: number): string {
  if (value === null || value === undefined || isNaN(value)) {
    return '';
  }
  return value.toFixed(precision);
}

/**
 * Extracts dependency variable codes from a formula string (e.g. "TBIL - DBIL" -> ["TBIL", "DBIL"])
 */
export function extractFormulaVariables(formula: string): string[] {
  if (!formula || typeof formula !== 'string') return [];
  const matches = formula.toUpperCase().match(/\b[A-Z_][A-Z0-9_]*\b/g);
  if (!matches) return [];

  // Filter out any potential reserved words or function names
  const reserved = new Set(['AND', 'OR', 'NOT', 'IF', 'THEN', 'ELSE', 'MIN', 'MAX', 'AVG', 'ROUND', 'POW', 'SQRT']);
  return Array.from(new Set(matches.filter((m) => !reserved.has(m))));
}

/**
 * Safely evaluates mathematical expressions supporting +, -, *, /, ^, and parentheses
 */
export function evaluateSafeFormula(
  formula: string,
  parametersMap: Record<string, number | null | undefined>
): number | null {
  const res = evaluateClinicalFormula(formula, parametersMap);
  return res.rawValue;
}

/**
 * Comprehensive clinical formula evaluation with full diagnostic status and precision formatting
 */
export function evaluateClinicalFormula(
  formula: string,
  parametersMap: Record<string, number | null | undefined>,
  paramCode?: string,
  unit?: string | null,
  ruleKey?: string
): CalculationResult {
  if (!formula || typeof formula !== 'string' || formula.trim() === '') {
    return {
      status: 'MISSING_DEPENDENCY',
      rawValue: null,
      displayValue: '',
      formattedValue: '',
      isCalculated: false,
      isError: false,
    };
  }

  const cleanFormula = formula.trim();
  const variables = extractFormulaVariables(cleanFormula);

  // 1. Check if all required dependency parameters are present and have valid numeric values
  const missingVars: string[] = [];
  const usedVars: Record<string, number> = {};

  for (const v of variables) {
    const val = parametersMap[v] ?? parametersMap[v.toUpperCase()] ?? parametersMap[v.toLowerCase()];
    if (val === null || val === undefined || isNaN(val)) {
      missingVars.push(v);
    } else {
      usedVars[v] = val;
    }
  }

  if (missingVars.length > 0) {
    return {
      status: 'MISSING_DEPENDENCY',
      rawValue: null,
      displayValue: '—',
      formattedValue: '—',
      isCalculated: true,
      isError: false,
      formulaUsed: cleanFormula,
    };
  }

  // 2. Check Clinical Safety / Eligibility Constraints (e.g. Friedewald LDL)
  if (ruleKey && CLINICAL_RULES[ruleKey]) {
    const rule = CLINICAL_RULES[ruleKey];
    if (!rule.condition(usedVars)) {
      return {
        status: 'NOT_APPLICABLE',
        rawValue: null,
        displayValue: 'Calculation not applicable',
        formattedValue: 'Calculation not applicable',
        isCalculated: true,
        isError: false,
        errorMessage: rule.failureReason,
        formulaUsed: cleanFormula,
        dependenciesUsed: usedVars,
      };
    }
  }

  // 3. Substitute variables with actual numeric values
  let expr = cleanFormula.toUpperCase();
  const sortedVars = Object.keys(usedVars).sort((a, b) => b.length - a.length);

  for (const key of sortedVars) {
    const val = usedVars[key];
    const regex = new RegExp(`\\b${key}\\b`, 'g');
    expr = expr.replace(regex, `(${val})`);
  }

  // 4. Validate expression contains ONLY safe arithmetic characters
  if (!/^[0-9\s.+\-*/^()]+$/.test(expr)) {
    return {
      status: 'SYNTAX_ERROR',
      rawValue: null,
      displayValue: 'Calculation Error',
      formattedValue: 'Calculation Error',
      isCalculated: true,
      isError: true,
      errorMessage: 'Formula contains unsupported characters',
      formulaUsed: cleanFormula,
    };
  }

  // 5. Tokenize expression
  const tokens = tokenize(expr);
  if (!tokens || tokens.length === 0) {
    return {
      status: 'SYNTAX_ERROR',
      rawValue: null,
      displayValue: 'Calculation Error',
      formattedValue: 'Calculation Error',
      isCalculated: true,
      isError: true,
      errorMessage: 'Invalid expression syntax',
      formulaUsed: cleanFormula,
    };
  }

  // 6. Convert to Reverse Polish Notation (RPN)
  const rpn = toRpn(tokens);
  if (!rpn) {
    return {
      status: 'SYNTAX_ERROR',
      rawValue: null,
      displayValue: 'Calculation Error',
      formattedValue: 'Calculation Error',
      isCalculated: true,
      isError: true,
      errorMessage: 'Parentheses mismatch or operator syntax error',
      formulaUsed: cleanFormula,
    };
  }

  // 7. Evaluate RPN
  const evalResult = evalRpnDetailed(rpn);
  if (evalResult.status === 'DIVIDE_BY_ZERO') {
    return {
      status: 'DIVIDE_BY_ZERO',
      rawValue: null,
      displayValue: 'Calculation Error',
      formattedValue: 'Calculation Error',
      isCalculated: true,
      isError: true,
      errorMessage: 'Divide by zero encountered',
      formulaUsed: cleanFormula,
      dependenciesUsed: usedVars,
    };
  }

  if (evalResult.status !== 'SUCCESS' || evalResult.value === null || isNaN(evalResult.value)) {
    return {
      status: 'SYNTAX_ERROR',
      rawValue: null,
      displayValue: 'Calculation Error',
      formattedValue: 'Calculation Error',
      isCalculated: true,
      isError: true,
      errorMessage: 'Calculation execution error',
      formulaUsed: cleanFormula,
    };
  }

  const precision = getParameterPrecision(paramCode || '', unit);
  const formatted = formatPrecisionValue(evalResult.value, precision);

  return {
    status: 'SUCCESS',
    rawValue: evalResult.value,
    displayValue: formatted,
    formattedValue: formatted,
    isCalculated: true,
    isError: false,
    formulaUsed: cleanFormula,
    dependenciesUsed: usedVars,
  };
}

function tokenize(expr: string): string[] | null {
  const tokens: string[] = [];
  let i = 0;

  while (i < expr.length) {
    const char = expr[i];

    if (/\s/.test(char)) {
      i++;
      continue;
    }

    if (/[0-9.]/.test(char)) {
      let numStr = '';
      while (i < expr.length && /[0-9.]/.test(expr[i])) {
        numStr += expr[i];
        i++;
      }
      tokens.push(numStr);
      continue;
    }

    if (['+', '-', '*', '/', '^', '(', ')'].includes(char)) {
      if (char === '-') {
        const prev = tokens[tokens.length - 1];
        if (!prev || ['+', '-', '*', '/', '^', '('].includes(prev)) {
          tokens.push('0');
        }
      }
      tokens.push(char);
      i++;
      continue;
    }

    return null;
  }

  return tokens;
}

const PRECEDENCE: Record<string, number> = {
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '^': 3,
};

function toRpn(tokens: string[]): string[] | null {
  const output: string[] = [];
  const opStack: string[] = [];

  for (const token of tokens) {
    if (/^[0-9.]+$/.test(token)) {
      output.push(token);
    } else if (['+', '-', '*', '/', '^'].includes(token)) {
      while (
        opStack.length > 0 &&
        opStack[opStack.length - 1] !== '(' &&
        PRECEDENCE[opStack[opStack.length - 1]] >= PRECEDENCE[token]
      ) {
        output.push(opStack.pop()!);
      }
      opStack.push(token);
    } else if (token === '(') {
      opStack.push(token);
    } else if (token === ')') {
      while (opStack.length > 0 && opStack[opStack.length - 1] !== '(') {
        output.push(opStack.pop()!);
      }
      if (opStack.length === 0) return null;
      opStack.pop();
    }
  }

  while (opStack.length > 0) {
    const op = opStack.pop()!;
    if (op === '(' || op === ')') return null;
    output.push(op);
  }

  return output;
}

function evalRpnDetailed(rpn: string[]): { status: CalculationStatus; value: number | null } {
  const stack: number[] = [];

  for (const token of rpn) {
    if (/^[0-9.]+$/.test(token)) {
      stack.push(parseFloat(token));
    } else if (['+', '-', '*', '/', '^'].includes(token)) {
      if (stack.length < 2) return { status: 'SYNTAX_ERROR', value: null };
      const b = stack.pop()!;
      const a = stack.pop()!;

      switch (token) {
        case '+':
          stack.push(a + b);
          break;
        case '-':
          stack.push(a - b);
          break;
        case '*':
          stack.push(a * b);
          break;
        case '/':
          if (b === 0) {
            return { status: 'DIVIDE_BY_ZERO', value: null };
          }
          stack.push(a / b);
          break;
        case '^':
          stack.push(Math.pow(a, b));
          break;
      }
    }
  }

  if (stack.length !== 1 || isNaN(stack[0])) {
    return { status: 'SYNTAX_ERROR', value: null };
  }

  // Preserve raw numeric precision up to 6 decimals internally
  const rounded = Math.round(stack[0] * 1000000) / 1000000;
  return { status: 'SUCCESS', value: rounded };
}

/**
 * Resolves dependency graph & sorts parameters in topological execution order
 */
export function getTopologicalCalculationOrder(
  parameters: Array<{ code: string; value_type: string; formula?: string | null; formula_dependencies?: string[] | null }>
): { orderedCodes: string[]; hasCircular: boolean } {
  const adj = new Map<string, string[]>();
  const inDegree = new Map<string, number>();
  const allCodes = new Set(parameters.map((p) => p.code.toUpperCase()));

  parameters.forEach((p) => {
    const code = p.code.toUpperCase();
    adj.set(code, []);
    inDegree.set(code, 0);
  });

  parameters.forEach((p) => {
    if (p.value_type === 'Calculated' && p.formula) {
      const targetCode = p.code.toUpperCase();
      const deps = (p.formula_dependencies && p.formula_dependencies.length > 0)
        ? p.formula_dependencies.map((d) => d.toUpperCase())
        : extractFormulaVariables(p.formula);

      for (const dep of deps) {
        if (allCodes.has(dep)) {
          adj.get(dep)?.push(targetCode);
          inDegree.set(targetCode, (inDegree.get(targetCode) || 0) + 1);
        }
      }
    }
  });

  const queue: string[] = [];
  inDegree.forEach((deg, code) => {
    if (deg === 0) queue.push(code);
  });

  const orderedCodes: string[] = [];
  while (queue.length > 0) {
    const u = queue.shift()!;
    orderedCodes.push(u);

    const neighbors = adj.get(u) || [];
    for (const v of neighbors) {
      const newDeg = (inDegree.get(v) || 1) - 1;
      inDegree.set(v, newDeg);
      if (newDeg === 0) {
        queue.push(v);
      }
    }
  }

  const hasCircular = orderedCodes.length < parameters.length;
  return { orderedCodes, hasCircular };
}

/**
 * Deterministic INR Calculation Engine
 * Formula: INR = (patientPt / mnpt) ^ isi
 * Validation: patientPt > 0, mnpt > 0, isi > 0
 * If MNPT or ISI is missing or invalid: returns inr: null with informative warning without inventing defaults.
 */
export function calculateINR(
  patientPt: number | null | undefined,
  mnpt: number | null | undefined,
  isi: number | null | undefined
): {
  inr: number | null;
  displayValue: string;
  warning?: string;
  isValid: boolean;
} {
  if (patientPt === null || patientPt === undefined || isNaN(patientPt) || patientPt <= 0) {
    return { inr: null, displayValue: '—', isValid: false };
  }
  if (mnpt === null || mnpt === undefined || isNaN(mnpt) || mnpt <= 0) {
    return {
      inr: null,
      displayValue: '—',
      warning: 'Mean Normal Prothrombin Time (MNPT) is unconfigured or non-positive. INR calculation disabled.',
      isValid: false,
    };
  }
  if (isi === null || isi === undefined || isNaN(isi) || isi <= 0) {
    return {
      inr: null,
      displayValue: '—',
      warning: 'International Sensitivity Index (ISI) is unconfigured or non-positive. INR calculation disabled.',
      isValid: false,
    };
  }

  const rawInr = Math.pow(patientPt / mnpt, isi);
  const precision = getParameterPrecision('INR');
  const displayValue = formatPrecisionValue(rawInr, precision);

  return {
    inr: rawInr,
    displayValue,
    isValid: true,
  };
}

/**
 * Recalculates all calculated parameters in an investigation or test profile
 */
export function recalculateInvestigationParameters<
  T extends {
    code: string;
    name?: string;
    value_type: string;
    formula?: string | null;
    formula_dependencies?: string[] | null;
    display_value: string;
    numeric_value?: number | null;
    text_value?: string | null;
    unit?: string | null;
    flag?: any;
    is_critical?: boolean;
    resolved_range?: any;
    calculation_status?: CalculationStatus;
    calculation_error?: string | null;
  }
>(
  params: T[],
  evaluateFlagFn?: (val: string, type: string, range: any) => { flag: any; isCritical: boolean },
  contextVariables?: Record<string, number | null | undefined>
): T[] {
  const paramMap = new Map<string, T>();
  params.forEach((p) => paramMap.set(p.code.toUpperCase(), { ...p }));

  const { orderedCodes, hasCircular } = getTopologicalCalculationOrder(params);
  if (hasCircular) {
    // Flag circular dependency on calculated parameters
    return params.map((p) => {
      if (p.value_type === 'Calculated') {
        return {
          ...p,
          numeric_value: null,
          display_value: 'Calculation Error',
          calculation_status: 'CIRCULAR_DEPENDENCY' as CalculationStatus,
          calculation_error: 'Circular dependency detected in formula',
          flag: 'Normal',
          is_critical: false,
        };
      }
      return p;
    });
  }

  const numericValueMap: Record<string, number> = {};

  // Populate context variables (e.g. MNPT, ISI)
  if (contextVariables) {
    for (const [k, v] of Object.entries(contextVariables)) {
      if (typeof v === 'number' && !isNaN(v) && v > 0) {
        numericValueMap[k.toUpperCase()] = v;
      }
    }
  }

  // Populate direct numeric inputs
  params.forEach((p) => {
    if (p.value_type !== 'Calculated') {
      const num = typeof p.numeric_value === 'number' && !isNaN(p.numeric_value)
        ? p.numeric_value
        : parseFloat(p.display_value);
      if (!isNaN(num) && p.display_value.trim() !== '') {
        const upperCode = p.code.toUpperCase();
        numericValueMap[upperCode] = num;
        // Also map PT parameter code COA-0001 -> PT, PATIENT_PT
        if (upperCode === 'COA-0001' || (p.name && p.name.toUpperCase().includes('PROTHROMBIN'))) {
          numericValueMap['PT'] = num;
          numericValueMap['PATIENT_PT'] = num;
        }
        // Map High Dose DST parameters -> BASELINE, POST
        if (upperCode === 'END-0061-01' || (upperCode.startsWith('END-0061') && p.name && p.name.toUpperCase().includes('BASELINE'))) {
          numericValueMap['BASELINE'] = num;
        }
        if (upperCode === 'END-0061-02' || (upperCode.startsWith('END-0061') && p.name && p.name.toUpperCase().includes('POST'))) {
          numericValueMap['POST'] = num;
        }
      }
    }
  });

  // Evaluate in topological order
  for (const code of orderedCodes) {
    const item = paramMap.get(code);
    if (!item) continue;

    if (item.value_type === 'Calculated' && item.formula) {
      const calcResult = evaluateClinicalFormula(
        item.formula,
        numericValueMap,
        item.code,
        item.unit
      );

      item.calculation_status = calcResult.status;
      item.calculation_error = calcResult.errorMessage || null;

      if (calcResult.status === 'SUCCESS' && calcResult.rawValue !== null) {
        item.numeric_value = calcResult.rawValue;
        item.display_value = calcResult.displayValue;
        numericValueMap[code] = calcResult.rawValue;
      } else if (calcResult.status === 'MISSING_DEPENDENCY') {
        item.numeric_value = null;
        item.display_value = '—';
      } else {
        item.numeric_value = null;
        item.display_value = calcResult.displayValue; // e.g. "Calculation Error" or "Calculation not applicable"
      }

      if (evaluateFlagFn) {
        const { flag, isCritical } = evaluateFlagFn(item.display_value, item.value_type, item.resolved_range);
        item.flag = flag;
        item.is_critical = isCritical;
      }
    }
  }

  return params.map((p) => paramMap.get(p.code.toUpperCase()) || p);
}
