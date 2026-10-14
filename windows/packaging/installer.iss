; Values are passed by tool/package.py, which validates version and file names.
[Setup]
AppId=app.fivea.five_a_ui
AppName=5a-ui
AppVersion={#AppVersion}
AppPublisher=5a-ui
AppPublisherURL=https://github.com/freephilx/5a-ui
DefaultDirName={localappdata}\Programs\5a-ui
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile={#AppIcon}
UninstallDisplayIcon={app}\5a-ui.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\5a-ui"; Filename: "{app}\5a-ui.exe"

[Run]
Filename: "{app}\5a-ui.exe"; Description: "Launch 5a-ui"; Flags: nowait postinstall skipifsilent
