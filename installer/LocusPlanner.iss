#define AppName "Locus Planner"
#define AppVersion GetEnv("LOCUS_VERSION")
#if AppVersion == ""
  #error "LOCUS_VERSION is not set. The release workflow derives it from pubspec.yaml; local installer builds must set it too."
#endif

[Setup]
AppId={{A67F4A21-2F9B-4F29-9B14-2D0A1B7E5D21}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Locus Planner
DefaultDirName={autopf}\Locus Planner
PrivilegesRequiredOverridesAllowed=dialog
DefaultGroupName=Locus Planner
OutputDir=..\dist
OutputBaseFilename=LocusPlanner-Setup-{#AppVersion}
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
WizardStyle=modern
UninstallDisplayIcon={app}\locus_planner.exe

[Files]
Source: "..\dist\LocusPlanner\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Locus Planner"; Filename: "{app}\locus_planner.exe"; AppUserModelID: "LocusPlanner.Desktop"
Name: "{autodesktop}\Locus Planner"; Filename: "{app}\locus_planner.exe"; Tasks: desktopicon; AppUserModelID: "LocusPlanner.Desktop"

[Registry]
Root: HKA; Subkey: "Software\Classes\locus"; ValueType: string; ValueName: ""; ValueData: "URL:Locus"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\locus"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\locus\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\locus_planner.exe,0"
Root: HKA; Subkey: "Software\Classes\locus\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\locus_planner.exe"" ""%1"""

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Run]
Filename: "{app}\locus_planner.exe"; Description: "Launch Locus Planner"; Flags: postinstall nowait skipifsilent
