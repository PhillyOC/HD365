; HD365 Inno Setup script
; Build with: ISCC.exe /DMyAppVersion=X.Y.Z build\HD365.iss

#define MyAppName "HD365"
#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif
#define MyAppPublisher "HelpDesk 365 AI"
#define MyAppURL "https://github.com/PhillyOC/HD365"

[Setup]
AppId={{A7C3E9F1-2B4D-4E8A-9C1F-6D5E8A0B3C72}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\HD365
DefaultGroupName=HD365
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=HD365-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\HD365.psd1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\HD365.psm1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Start-HD365.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Install-HD365.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\VERSIONING.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SYNC.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Public\*"; DestDir: "{app}\Public"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\Private\*"; DestDir: "{app}\Private"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\Config\*"; DestDir: "{app}\Config"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\HD365"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\Start-HD365.ps1"""; WorkingDir: "{app}"
Name: "{autodesktop}\HD365"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\Start-HD365.ps1"""; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Install-HD365.ps1"""; WorkingDir: "{app}"; StatusMsg: "Installing prerequisites..."; Flags: waituntilterminated
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\Start-HD365.ps1"""; WorkingDir: "{app}"; Description: "Launch HD365"; Flags: nowait postinstall skipifsilent
