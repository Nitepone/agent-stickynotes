; Inno Setup script for the Windows installer. Built by scripts/package-windows.sh,
; which passes: AppVersion, NumericVersion, SourceDir (the windeployqt folder),
; OutputDir and OutputName.
#ifndef AppVersion
  #error AppVersion is not defined; build through scripts/package-windows.sh
#endif

[Setup]
; Never change AppId: it is how Windows (and later installers) recognise this app.
AppId={{6D1B0E52-3C4A-4F0B-9A57-2B7E8C41D5A3}
AppName=Agent Stickynotes
AppVersion={#AppVersion}
VersionInfoVersion={#NumericVersion}
AppPublisher=agent-stickynotes
AppPublisherURL=https://github.com/Nitepone/agent-stickynotes
; 64-bit only. {autopf} is C:\Program Files for an all-users install and
; %LOCALAPPDATA%\Programs for a per-user one.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
DefaultDirName={autopf}\Agent Stickynotes
DefaultGroupName=Agent Stickynotes
; Show the "Select Destination Location" page even when upgrading.
DisableDirPage=no
DisableProgramGroupPage=yes
; Ask admin vs current user at start; no admin rights needed for a per-user install.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Registers the uninstaller under Settings > Apps.
UninstallDisplayName=Agent Stickynotes
UninstallDisplayIcon={app}\stickynotes.exe
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Agent Stickynotes"; Filename: "{app}\stickynotes.exe"; WorkingDir: "{app}"

[Run]
Filename: "{app}\stickynotes.exe"; Description: "Launch Agent Stickynotes"; Flags: nowait postinstall skipifsilent
