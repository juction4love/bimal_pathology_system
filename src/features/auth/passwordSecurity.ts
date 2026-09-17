export const PASSWORD_MIN_LENGTH = 8;
export const PRODUCTION_RESET_URL = 'https://lis.bimalpathology.com.np/reset-password';
export const GENERIC_RECOVERY_MESSAGE =
  'If an account exists for this email, a password reset link has been sent.';

export function validateNewPassword(password: string, confirmation: string): string | null {
  if (password.length < PASSWORD_MIN_LENGTH) {
    return `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`;
  }
  if (password !== confirmation) {
    return 'New password and confirmation do not match.';
  }
  return null;
}

export function safeAuthError(error: unknown, fallback: string): string {
  const message = error instanceof Error ? error.message.toLowerCase() : '';
  if (message.includes('password') && (message.includes('weak') || message.includes('length'))) {
    return `Password must meet the security policy (minimum ${PASSWORD_MIN_LENGTH} characters).`;
  }
  if (message.includes('expired') || message.includes('invalid') || message.includes('otp')) {
    return 'This password recovery link is invalid, expired, or has already been used.';
  }
  if (message.includes('fetch') || message.includes('network')) {
    return 'Unable to reach the authentication service. Check your connection and try again.';
  }
  return fallback;
}
