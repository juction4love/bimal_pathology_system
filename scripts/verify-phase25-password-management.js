/** Production password-management regression suite. No live password mutation. */
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const login = read('src/features/auth/LoginPage.tsx');
const forgot = read('src/features/auth/ForgotPasswordPage.tsx');
const reset = read('src/features/auth/ResetPasswordPage.tsx');
const change = read('src/features/auth/ChangePasswordPage.tsx');
const passwordField = read('src/features/auth/PasswordField.tsx');
const security = read('src/features/auth/passwordSecurity.ts');
const routes = read('src/app/routes.tsx');
const layout = read('src/app/AppLayout.tsx');
const auth = read('src/context/AuthContext.tsx');
const keyboard = read('src/lib/keyboardNav.ts');

let passed = 0;
let failed = 0;
const check = (condition, name, detail) => {
  if (condition) { passed += 1; console.log(`  PASS ${name}: ${detail}`); }
  else { failed += 1; console.error(`  FAIL ${name}: ${detail}`); }
};

console.log('\nBIMAL PATHOLOGY - PRODUCTION PASSWORD MANAGEMENT REGRESSION SUITE\n');

check(login.includes('Forgot Password?') && login.includes('to="/forgot-password"'), 'ForgotPasswordVisible', 'login exposes a clear recovery action');
check(forgot.includes('GENERIC_RECOVERY_MESSAGE') && security.includes('If an account exists for this email'), 'AntiEnumerationResponse', 'recovery response does not disclose account existence');
check(security.includes("https://lis.bimalpathology.com.np/reset-password") && forgot.includes('redirectTo: PRODUCTION_RESET_URL'), 'ProductionRedirect', 'recovery uses the exact production reset route');
check(routes.includes("path: '/reset-password'") && routes.includes('<ResetPasswordPage />'), 'ResetRouteExists', 'public recovery route is explicitly registered');
check(reset.includes('isPasswordRecovery') && reset.includes('Boolean(session?.user)') && reset.includes('!recoveryValid'), 'InvalidRecoveryRejected', 'a normal or absent session cannot update a password');
check(reset.includes('invalid, expired, or has already been used') && reset.includes("has('error')"), 'ExpiredRecoveryHandled', 'expired/reused recovery URLs fail safely');
check(security.includes('password !== confirmation') && security.includes('do not match'), 'ConfirmationMismatchRejected', 'new password confirmation must match');
check(security.includes('PASSWORD_MIN_LENGTH = 8') && security.includes('password.length < PASSWORD_MIN_LENGTH'), 'WeakPasswordRejected', 'minimum eight-character policy is enforced');
check(passwordField.includes("type={visible ? 'text' : 'password'}") && passwordField.includes('VisibilityOffIcon'), 'PasswordFieldsMasked', 'passwords are masked by default with show/hide controls');
check(![login, forgot, reset, change, passwordField].some((text) => /localStorage|sessionStorage|\.from\([^)]*password/i.test(text)), 'NoPasswordPersistence', 'password flows do not persist credentials in browser storage or database tables');
check(change.includes("label=\"Current Password\"") && change.includes('if (!currentPassword)'), 'CurrentPasswordRequired', 'authenticated change requires current password');
check(change.includes('signInWithPassword') && change.includes('current_password: currentPassword') && change.includes('Current password is incorrect.'), 'IncorrectCurrentPasswordRejected', 'current password is reauthenticated and supplied again to the secure update');
check(change.includes("signOut({ scope: 'global' })") && change.includes("navigate('/login'"), 'ChangeSignsOut', 'successful change globally signs out and returns to login');
check(reset.includes("signOut({ scope: 'global' })") && reset.includes('Password reset successfully.'), 'ResetSignsOut', 'successful reset clears recovery state and globally signs out');
check(auth.includes('activeProfile && !activeProfile.isActive') && auth.includes('initialSession?.user && recoveryUrlAtLoad') && !reset.includes('is_active: true'), 'InactiveProfileRemainsInactive', 'recovery bypasses profile loading but never modifies LIS profile activation');
check(layout.includes('if (!user || !profile?.isActive)') && layout.includes('<Navigate to="/login"') && !routes.includes("path: 'reset-password'"), 'ProtectedRoutesRemainProtected', 'only the top-level recovery route bypasses the staff layout guard');
check([login, forgot, reset, change].every((text) => text.includes('data-keyboard-form="true"') && text.includes('handleEnterKeyNavigation')) && keyboard.includes('e.preventDefault()'), 'KeyboardNavigationPreserved', 'Enter advances within scoped forms without early submission');

const distDirectory = path.join(root, 'dist');
const distText = fs.existsSync(distDirectory)
  ? fs.readdirSync(path.join(distDirectory, 'assets')).filter((name) => /\.js$/i.test(name)).map((name) => fs.readFileSync(path.join(distDirectory, 'assets', name), 'utf8')).join('\n')
  : '';
const forbiddenBuildMarkers = [
  'SUPABASE_' + 'SERVICE_ROLE_KEY',
  'LIS_TEST_' + 'ADMIN_PASSWORD',
  'LIS_TEST_' + 'TECH_PASSWORD',
  'Admin' + 'Password123',
  'Tech' + 'Password123',
];
check(!forbiddenBuildMarkers.some((marker) => distText.includes(marker)), 'NoSecretsInBuild', 'production bundle contains no service-role or test-password material');

console.log(`\nSUMMARY: ${passed} PASSED, ${failed} FAILED\n`);
if (failed) process.exit(1);
