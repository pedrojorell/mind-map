; Instalador do MapLong para Windows (Inno Setup 6).
;
; Gere com:  powershell -ExecutionPolicy Bypass -File scripts\criar_instalador.ps1
; ou abra este arquivo no Inno Setup e clique em "Compile".
; Antes, compile o app:  flutter build windows --release

#ifndef MyAppVersion
  #define MyAppVersion "2.0.0"
#endif
#define MyAppName "MapLong"
#define MyAppPublisher "MapLong"
#define MyAppURL "https://github.com/pedrojorell/mind-map"
#define MyAppExeName "maplong.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; Identificador fixo do app: não mude, senão o Windows trata cada versão
; como um programa diferente (e não atualiza o já instalado).
AppId={{6B7B1C1E-3F2A-4D6C-9A51-8E0D4C2B7A90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Instala só para o usuário atual (não pede senha de administrador),
; com opção de instalar para todos.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=Output
OutputBaseFilename=MapLong-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ChangesAssociations=yes
; Fecha o MapLong aberto antes de atualizar.
CloseApplications=yes

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "fileassoc"; Description: "Abrir arquivos .maplong com o MapLong"; GroupDescription: "Arquivos:"

[Files]
; Todo o conteúdo da pasta Release (exe, DLLs e a pasta data).
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; Associa .maplong (e o formato antigo .pmap) ao MapLong.
Root: HKA; Subkey: "Software\Classes\.maplong\OpenWithProgids"; ValueType: string; ValueName: "MapLong.Mapa"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKA; Subkey: "Software\Classes\.pmap\OpenWithProgids"; ValueType: string; ValueName: "MapLong.Mapa"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKA; Subkey: "Software\Classes\MapLong.Mapa"; ValueType: string; ValueName: ""; ValueData: "Mapa mental MapLong"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKA; Subkey: "Software\Classes\MapLong.Mapa\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Tasks: fileassoc
Root: HKA; Subkey: "Software\Classes\MapLong.Mapa\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: fileassoc

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
