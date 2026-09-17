const EXPECTED_ENVIRONMENT = 'isolated-staging';
export const EXPECTED_PROJECT_REF = 'ilcnctiaumrjbnlmnise';
export const RETIRED_PROJECT_REF = 'qvuidmgddjoircheapzk';
export const PRODUCTION_PROJECT_REF = 'rncjxstujioagcezvfkb';
const EXPECTED_SUPABASE_ORIGIN = `https://${EXPECTED_PROJECT_REF}.supabase.co`;
const CONFIRMATION = `RUN_ISOLATED_STAGING_${EXPECTED_PROJECT_REF}`;

function requireEnvironment(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`[staging-acceptance] ${name} is required; no staging target or credential has a default.`);
  }
  return value;
}

function parseUrl(name, value) {
  try {
    return new URL(value);
  } catch {
    throw new Error(`[staging-acceptance] ${name} must be an absolute URL.`);
  }
}

function isSafeFrontendHost(hostname) {
  const normalized = hostname.toLowerCase();
  return normalized === '127.0.0.1'
    || normalized === 'localhost'
    || normalized === '::1'
    || normalized.includes('staging')
    || normalized.includes(EXPECTED_PROJECT_REF);
}

export function loadStagingAcceptanceEnvironment() {
  const environment = requireEnvironment('STAGING_ACCEPTANCE_ENVIRONMENT');
  const projectRef = requireEnvironment('STAGING_ACCEPTANCE_PROJECT_REF');
  const confirmation = requireEnvironment('STAGING_ACCEPTANCE_CONFIRM');
  const baseUrl = parseUrl('STAGING_ACCEPTANCE_BASE_URL', requireEnvironment('STAGING_ACCEPTANCE_BASE_URL'));
  const supabaseUrl = parseUrl('STAGING_ACCEPTANCE_SUPABASE_URL', requireEnvironment('STAGING_ACCEPTANCE_SUPABASE_URL'));

  const foundation = environment === 'isolated-acceptance';
  const expectedOrigin = foundation ? `https://${projectRef}.supabase.co` : EXPECTED_SUPABASE_ORIGIN;
  const expectedConfirmation = foundation ? `RUN_FOUNDATION_ACCEPTANCE_${projectRef}` : CONFIRMATION;
  if (!foundation && environment !== EXPECTED_ENVIRONMENT) throw new Error(`[staging-acceptance] unsupported environment ${environment}.`);
  if (projectRef === RETIRED_PROJECT_REF) throw new Error('[staging-acceptance] retired staging project is permanently refused.');
  if (foundation && projectRef !== EXPECTED_PROJECT_REF) throw new Error(`[staging-acceptance] foundation target must be exactly ${EXPECTED_PROJECT_REF}.`);
  if (!foundation && projectRef !== EXPECTED_PROJECT_REF) throw new Error(`[staging-acceptance] project ref must be exactly ${EXPECTED_PROJECT_REF}; received ${projectRef}.`);
  if (confirmation !== expectedConfirmation) throw new Error(`[staging-acceptance] explicit confirmation must be exactly ${expectedConfirmation}.`);
  if (supabaseUrl.origin !== expectedOrigin || supabaseUrl.pathname !== '/') throw new Error(`[staging-acceptance] backend must be exactly ${expectedOrigin}/.`);
  if (baseUrl.username || baseUrl.password) {
    throw new Error('[staging-acceptance] frontend base URL must not contain credentials.');
  }
  if (!['http:', 'https:'].includes(baseUrl.protocol)) {
    throw new Error('[staging-acceptance] frontend base URL must use HTTP or HTTPS.');
  }
  if (!isSafeFrontendHost(baseUrl.hostname)) {
    throw new Error('[staging-acceptance] frontend host must be loopback or explicitly named as isolated staging.');
  }
  if (baseUrl.href.includes(PRODUCTION_PROJECT_REF) || baseUrl.hostname === 'lis.bimalpathology.com.np') {
    throw new Error('[staging-acceptance] production frontend/backend targeting is forbidden.');
  }

  const resultItemId = requireEnvironment('STAGING_ACCEPTANCE_RESULT_ITEM_ID');
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(resultItemId)) {
    throw new Error('[staging-acceptance] STAGING_ACCEPTANCE_RESULT_ITEM_ID must be a synthetic staging UUID.');
  }

  const searches = [
    requireEnvironment('STAGING_ACCEPTANCE_SEARCH_2'),
    requireEnvironment('STAGING_ACCEPTANCE_SEARCH_3'),
    requireEnvironment('STAGING_ACCEPTANCE_SEARCH_4'),
  ];
  searches.forEach((query, index) => {
    const expectedLength = index + 2;
    if (query.length !== expectedLength) {
      throw new Error(`[staging-acceptance] STAGING_ACCEPTANCE_SEARCH_${expectedLength} must contain exactly ${expectedLength} characters.`);
    }
  });

  return Object.freeze({
    environment,
    projectRef,
    baseURL: baseUrl.origin,
    supabaseOrigin: supabaseUrl.origin,
    adminEmail: requireEnvironment('STAGING_ACCEPTANCE_ADMIN_EMAIL'),
    adminPassword: requireEnvironment('STAGING_ACCEPTANCE_ADMIN_PASSWORD'),
    technicianEmail: requireEnvironment('STAGING_ACCEPTANCE_TECHNICIAN_EMAIL'),
    technicianPassword: requireEnvironment('STAGING_ACCEPTANCE_TECHNICIAN_PASSWORD'),
    technicianBEmail: process.env.STAGING_ACCEPTANCE_TECHNICIAN_B_EMAIL?.trim() || null,
    technicianBPassword: process.env.STAGING_ACCEPTANCE_TECHNICIAN_B_PASSWORD?.trim() || null,
    verifierEmail: process.env.STAGING_ACCEPTANCE_VERIFIER_EMAIL?.trim() || null,
    verifierPassword: process.env.STAGING_ACCEPTANCE_VERIFIER_PASSWORD?.trim() || null,
    signatoryEmail: process.env.STAGING_ACCEPTANCE_SIGNATORY_EMAIL?.trim() || null,
    signatoryPassword: process.env.STAGING_ACCEPTANCE_SIGNATORY_PASSWORD?.trim() || null,
    resultItemId,
    searches,
  });
}

export function projectRefFromSupabaseUrl(rawUrl) {
  try {
    const url = new URL(rawUrl);
    const match = /^([a-z0-9]+)\.supabase\.co$/i.exec(url.hostname);
    return match?.[1] ?? null;
  } catch {
    return null;
  }
}
