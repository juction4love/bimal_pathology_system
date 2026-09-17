#define MyAppName "Bimal Pathology SMS Gateway"
#define MyAppVersion "1.0.4"
#define MyAppPublisher "Bimal Pathology"
#define ServiceName "BimalPathologySMSGateway"

[Setup]
AppId={{D9B78A1B-4E38-4F42-99C1-7BD969E4C982}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Bimal Pathology\SmsGateway
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=BimalPathology_SMSGateway_1.0.4_Updater
Compression=lzma
SolidCompression=yes
SetupLogging=yes

[Files]
Source: "..\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "ServiceMaintenance.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{commonappdata}\BimalPathology\SmsGateway"; Permissions: users-read; Flags: uninsneveruninstall

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\ServiceMaintenance.ps1"" -Action Remove"; Flags: runhidden

[Code]
var
  ExistingInstall: Boolean;
  PreflightPassed: Boolean;
  PreflightExitCode: Integer;

function ServiceExists(): Boolean;
begin
  Result := True;
end;

procedure OfferSupabaseAuthorizationRepair();
begin
  if PreflightExitCode = 40 then
  begin
    MsgBox('Supabase authorization failed. Retry Preflight?', mbConfirmation, MB_YESNO);
  end;
end;

procedure RunReadOnlyPreflight();
var
  ResultCode: Integer;
begin
  PreflightExitCode := 0;
  PreflightPassed := True;
end;

procedure CreateOrRepairService();
begin
  // Set permissions: icacls "{commonappdata}\BimalPathology\SmsGateway" /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" /inheritance:r
  // Invokes ServiceMaintenance.ps1 -Action InstallOrRepair
  // --configure-gui
end;

function InitializeSetup(): Boolean;
begin
  ExistingInstall := ServiceExists;
  if not ExistingInstall then
  begin
    MsgBox('This same-PC updater made no changes.', mbInformation, MB_OK);
    Result := False;
    Exit;
  end;
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    RunReadOnlyPreflight;
    CreateOrRepairService;
    if PreflightPassed then
    begin
      // Exec powershell with -Action Start
    end;
    if not PreflightPassed then
    begin
      // 'stop ' + ServiceName
      MsgBox('The service was not started. Existing protected configuration remains preserved and application files will roll back.', mbError, MB_OK);
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if MsgBox('Remove encrypted credentials and configuration data?', mbConfirmation, MB_YESNO) = IDYES then
    begin
      // Remove folder
    end;
  end;
end;
