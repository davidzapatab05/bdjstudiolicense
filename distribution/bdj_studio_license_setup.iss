; BDJ Studio License - Instalador Windows (Inno Setup 6)

; La version puede inyectarse desde fuera para que no se desincronice de
; pubspec.yaml / preflight:  ISCC /DMyAppVersion=1.0.3 bdj_studio_license_setup.iss
; El valor de abajo es solo el respaldo cuando se compila a mano.
#ifndef MyAppVersion
  #define MyAppVersion "1.0.3"
#endif

#define MyAppName "BDJ Studio License"
#define MyAppPublisher "BDJ Studio"
#define MyAppExeName "bdj_studio_license.exe"

[Setup]
AppId={{E49CE24C-AE87-49F8-8BB6-3122823DF6F3}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Iconos y logos de la aplicacion
SetupIconFile=..\frontend\windows\runner\resources\app_icon.ico
WizardImageFile=setup_assets\wizard_logo.bmp
WizardSmallImageFile=setup_assets\wizard_small.bmp
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern
PrivilegesRequired=admin
OutputDir=.
OutputBaseFilename=BDJ_Studio_License_Setup_{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "..\frontend\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

; Politica del producto (compartida con las demas apps BDJ Studio): los datos
; NO sobreviven a la desinstalacion. Se borra la carpeta de soporte de la app
; --%APPDATA%\CompanyName\ProductName (Runner.rc: CompanyName "com.bdjstudio",
; ProductName "BDJ Studio License")-- con sus preferencias y almacen heredado,
; ademas de los nombres que usaban versiones antiguas.
[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\com.bdjstudio\BDJ Studio License"
Type: filesandordirs; Name: "{userappdata}\com.bdjstudio\bdj_studio_license"
Type: filesandordirs; Name: "{userappdata}\bdj_studio_license"
