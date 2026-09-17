const sensitiveKey = /authorization|password|token|secret|message_body|recipient|mobile|phone|report_url/i;
const jwt = /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g;
const mobile = /(?<!\d)(?:\+?977[- ]?)?9[678]\d{8}(?!\d)/g;
const reportRoute = /https?:\/\/[^\s]+\/r\/[A-Za-z0-9_-]+/gi;

export function redact(value: unknown, key = ''): unknown {
  if (sensitiveKey.test(key)) return '[REDACTED]';
  if (typeof value === 'string') return value.replace(jwt, '[REDACTED_JWT]').replace(mobile, '[REDACTED_MOBILE]').replace(reportRoute, '[REDACTED_REPORT_URL]');
  if (Array.isArray(value)) return value.map(item => redact(item));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, redact(v, k)]));
  return value;
}
