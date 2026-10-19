#define AppName "Locus Planner"
#define AppVersion GetEnv("LOCUS_VERSION")
#ifndef AppVersion
  #define AppVersion "1.3.0"
#endif

[Setup]
AppId={{A67F4A21-2F9B-4F29-9B14-2D0A1B7E5D21}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Locus Planner
DefaultDirName={autopf}\Locus Planner
DefaultGroupName=Locus Planner
OutputDir=..\dist
OutputBaseFilename=LocusPlanner-Setup-{#AppVersion}
ArchitecturesInstallIn64BitMode=x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\locus_planner.exe

[Files]
Source: "..\dist\LocusPlanner\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Locus Planner"; Filename: "{app}\locus_planner.exe"
Name: "{autodesktop}\Locus Planner"; Filename: "{app}\locus_planner.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Run]
Filename: "{app}\locus_planner.exe"; Description: "Launch Locus Planner"; Flags: postinstall nowait skipifsilent
