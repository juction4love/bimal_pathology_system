#define MyAppName "Bimal Pathology Public IP Assistant"
#define MyAppVersion "1.0.0"
#define MyAppExeName "BimalPathology.PublicIpAssistant.exe"

[Setup]
AppId={{B94DA7DD-8EB1-48F4-A1B2-B9128D202A10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Bimal Pathology
DefaultDirName={localappdata}\Programs\Bimal Pathology\Public IP Assistant
DefaultGroupName={#MyAppName}
OutputDir=output
OutputBaseFilename=BimalPathologyPublicIpAssistantSetup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
WizardStyle=modern

[Files]
Source: "..\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Public IP Assistant"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\Public IP Assistant"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "BimalPathologyPublicIpAssistant"; ValueData: """{app}\{#MyAppExeName}"" --startup"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Run Public IP Assistant now"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--remove-startup"; Flags: runhidden waituntilterminated; RunOnceId: "RemovePublicIpAssistantStartup"
