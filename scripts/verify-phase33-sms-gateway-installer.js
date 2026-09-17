import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const iss = read('tools/sms-gateway/installer/BimalPathologySmsGateway.iss');
const program = read('tools/sms-gateway/Program.cs');
const settings = read('tools/sms-gateway/ProtectedSettings.cs');
const preflight = read('tools/sms-gateway/GatewayPreflight.cs');
const build = read('tools/sms-gateway/build-installer.ps1');
const service = read('tools/sms-gateway/installer/ServiceMaintenance.ps1');
const configurator = read('tools/sms-gateway/InstallerConfigurator.cs');

let passed = 0;
const check = (condition, label) => {
  if (!condition) throw new Error(`FAIL: ${label}`);
  passed++;
  console.log(`PASS: ${label}`);
};

check(iss.includes('OutputBaseFilename=BimalPathology_SMSGateway_1.0.4_Updater'), '1.0.4 updater installer output is exact');
check(iss.includes('#define MyAppVersion "1.0.4"'), 'installer patch version is 1.0.4');
check(iss.includes('ArchitecturesAllowed=x64compatible') && iss.includes('ArchitecturesInstallIn64BitMode=x64compatible'), 'installer is x64');
check(iss.includes('Source: "..\\publish\\*"') && build.includes('--self-contained true'), 'self-contained publish is packaged');
check(iss.includes('#define ServiceName "BimalPathologySMSGateway"') && service.includes("'BimalPathologySMSGateway'"), 'service identity is exact');
check(service.includes('-StartupType Automatic') && service.includes("'obj=', 'LocalSystem'") && service.includes("StartMode -ne 'Auto'"), 'service is verified Automatic LocalSystem');
check(iss.includes('DefaultDirName={autopf}\\Bimal Pathology\\SmsGateway'), 'Program Files destination is exact');
check(iss.includes('{commonappdata}\\BimalPathology\\SmsGateway'), 'ProgramData destination is exact');
check(configurator.includes('UseSystemPasswordChar = secret') && configurator.includes('Supabase service-role key') && configurator.includes('Sparrow production token'), 'target-PC credential fields are masked');
check(iss.includes('SetupLogging=yes') && iss.includes('--configure-gui') && !iss.includes('gateway.secrets.json'), 'diagnostic logging is enabled and no secret is passed in arguments or plaintext files');
check(program.includes('--configure-gui') && settings.includes('DataProtectionScope.LocalMachine'), 'target PC saves credentials with machine-scope DPAPI');
check(!iss.includes('machine-bound\\gateway.secrets.bin') && !build.includes('--provision-machine-package'), 'portable installer embeds no machine-bound credential package');
check(settings.includes('GatewayConstants.SupabaseUrl') && settings.includes('GatewayConstants.SparrowSender'), 'only URL and sender are reconstructed as non-secret constants');
check(!program.includes('--configure-installer-env') && !settings.includes('BPSG_INSTALL_SERVICE_KEY'), 'installer environment secret handoff is removed');
check(iss.includes('if not ExistingInstall then') && iss.includes('This same-PC updater made no changes.') && !iss.includes('RunCredentialConfiguration'), 'same-PC updater refuses fresh install and never requests initial credentials');
check(iss.includes('OfferSupabaseAuthorizationRepair') && iss.includes('PreflightExitCode = 40') && iss.includes('Retry Preflight?'), 'rejected Supabase authorization offers scoped repair while transient failures offer retry');
check(!iss.includes('DeleteFile(SecretPath)') && iss.indexOf('RunCredentialConfiguration') < iss.indexOf('CreateOrRepairService'), 'upgrade preserves configuration unless the operator replaces it before service repair');
check(iss.includes('*S-1-5-18') && iss.includes('*S-1-5-32-544') && iss.includes('/inheritance:r'), 'ACL is restricted to SYSTEM and Administrators');
check(preflight.includes('HttpMethod.Get') && preflight.includes('select=id&limit=0') && preflight.includes('HttpStatusCode.OK'), 'preflight is read-only and requires HTTP 200');
check(iss.includes('The service was not started. Existing protected configuration remains preserved and application files will roll back.'), 'preflight failure leaves service stopped, preserves configuration, and rolls back application files');
check(iss.includes('ExistingInstall := ServiceExists') && service.includes("'InstallOrRepair'") && service.includes("Invoke-Sc @('config'") && service.includes('Stop-ServiceSafely'), 'existing installation stops safely and repairs without duplicate creation');
check(iss.includes('[UninstallRun]') && iss.includes('-Action Remove') && service.includes("Invoke-Sc @('delete'") && service.includes('Stop-ServiceSafely'), 'uninstall stops and removes the service');
check(iss.includes("MsgBox('Remove encrypted credentials") && !iss.includes('[UninstallDelete]'), 'ProgramData deletion requires explicit confirmation');
check(!iss.includes('sparrowsms.com') && !iss.includes('/v2/sms') && !preflight.includes('sms/'), 'installer never calls Sparrow or sends SMS');
check(!iss.includes('rpc/') && !iss.includes('claim_sms') && !iss.includes('db push') && !preflight.includes('PostAsync'), 'installer performs no queue claim or database mutation');
check(iss.includes('PreflightPassed') && iss.includes('-Action Start') && !iss.includes('StartPage'), 'successful preflight always starts service without operator action');
check(iss.indexOf('RunReadOnlyPreflight;') < iss.indexOf('CreateOrRepairService;') && iss.indexOf('CreateOrRepairService;') < iss.lastIndexOf('-Action Start'), 'preflight and registration precede automatic start');
check(iss.includes('if not PreflightPassed then') && iss.includes("'stop ' + ServiceName"), 'failed preflight explicitly leaves service stopped');
check(service.includes("Wait-ServiceState -DesiredState 'Running' -Starting") && service.includes('Start-Sleep -Milliseconds 750') && service.includes('AddSeconds($TimeoutSeconds)'), 'start polls pending states for up to the configured timeout');
check(service.includes("$current.State -notin @('Start Pending', 'Continue Pending')") && service.includes("$lastState -eq $DesiredState"), 'temporary START_PENDING is not treated as failure');
check(service.includes("Invoke-Sc @('failure'") && service.includes('restart/60000/restart/60000/restart/300000'), 'service recovery is configured for unexpected crashes');
check(service.includes('Normalize-ServiceBinaryPath') && service.includes('OrdinalIgnoreCase') && !service.includes('PathName -ne $quotedBinaryPath'), 'SCM-normalized service path is compared semantically');
check(service.includes("$logDirectory = Join-Path $dataDirectory 'Logs'") && service.includes('service-maintenance.log') && service.includes('Diagnostic log:'), 'service failures produce a persistent diagnostic log');
check(service.includes('ServiceSpecificExitCode') && service.includes('ExitCode -ne 0'), 'Running state and healthy service exit codes are verified');
check(build.includes('dotnet test') && build.includes('dotnet publish') && build.includes('scriptblock]::Create') && build.includes('ISCC') && build.includes('BimalPathology_SMSGateway_1.0.4_Updater.exe'), 'build pipeline is fail-fast test publish parser verification and compile');

console.log(`\nPhase 33 SMS Gateway installer verification: ${passed} passed, 0 failed`);
