; AFRP OIDC Client - Inno Setup script
; Build with: build.bat (stages files first, then calls ISCC on this script)

#define MyAppname "AFRP OIDC Client"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "afrp.net"
#define MyAppURL "https://www.afrp.net"
#define MyAppExename "afrp_oidc.exe"
#define StageDir "..\build\installer\staging"
#define OutputDir "..\build\installer\output"

[Setup]
AppId={{A6C5E7B2-3F41-4D8E-9B07-5C2A8F16D9E3}
Appname={#MyAppname}
AppVersion={#MyAppVersion}
AppVername={#MyAppname} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirname={autopf}\{#MyAppname}
DefaultGroupname={#MyAppname}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline
OutputDir={#OutputDir}
OutputBaseFilename=afrp-oidc-client_{#MyAppVersion}_windows_amd64_setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExename}
UninstallDisplayname={#MyAppname}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
SetupLogging=yes
InfoBeforeFile=install-notes.txt
VersionInfoVersion=1.1.0.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductname={#MyAppname}
VersionInfoDescription=AFRP OIDC Client Setup

[Languages]
name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"
name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
name: "defexcl"; Description: "添加 Windows 安全中心排除项（推荐，避免内置 frpc 被误拦）"; GroupDescription: "安全设置："; Flags: checkedonce
name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "附加图标："; Flags: checkedonce

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
name: "{autoprograms}\{#MyAppname}"; Filename: "{app}\{#MyAppExename}"
name: "{autodesktop}\{#MyAppname}"; Filename: "{app}\{#MyAppExename}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExename}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppname, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
const
  ExclRegKey = 'Software\AFRP OIDC Client';

var
  ExclTried: Boolean;
  ExclOk: Boolean;

function PsExclusionCmd(const AddMode: Boolean): String;
var
  AppDir: String;
  FrpcDir: String;
begin
  AppDir := ExpandConstant('{app}');
  FrpcDir := ExpandConstant('{userappdata}\net.afrp\AFRP OIDC Client\frpc');
  if AddMode then
    Result := '-noProfile -ExecutionPolicy Bypass -Command "try { Add-MpPreference -ExclusionPath ''' + AppDir + ''', ''' + FrpcDir + ''' -ErrorAction Stop; exit 0 } catch { exit 1 }"'
  else
    Result := '-noProfile -ExecutionPolicy Bypass -Command "Remove-MpPreference -ExclusionPath ''' + AppDir + ''', ''' + FrpcDir + ''' -ErrorAction SilentlyContinue; exit 0"';
end;

function RunPs(const Params: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec('powershell.exe', Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    { ssInstall runs before file copy: add Defender exclusions for the app dir }
    { (contains frpc.exe) and the runtime frpc cache before files land on disk. }
    ExclTried := WizardIsTaskSelected('defexcl');
    ExclOk := False;
    if ExclTried then
    begin
      ExclOk := RunPs(PsExclusionCmd(True));
      if ExclOk then
        RegWriteDWordValue(HKA, ExclRegKey, 'DefenderExclAdded', 1)
      else
        Log('Failed to add Defender exclusions (not elevated, tamper protection on, or Defender absent).');
    end;
  end
  else if CurStep = ssPostInstall then
  begin
    if ExclTried and (not ExclOk) then
    begin
      if not WizardSilent then
        MsgBox('未能自动添加 Windows 安全中心排除项（常见原因：当前账户没有管理员权限、"篡改防护"开启、或系统未使用 Windows Defender）。' + #13#10#13#10 +
               '这不影响安装本身。若之后连接服务器时内置 frpc 被安全中心拦截，请手动添加排除项：' + #13#10 +
               'Windows 安全中心 → 病毒和威胁防护 → 管理设置 → 排除项 → 添加或删除排除项 → 添加排除项 → 文件夹，' + #13#10 +
               '选择安装目录和  %APPDATA%\net.afrp\AFRP OIDC Client\frpc  两个文件夹。',
               mbInformation, MB_OK);
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  { Remove Defender exclusions only if this installer added them. }
  if CurUninstallStep = usUninstall then
    if RegValueExists(HKA, ExclRegKey, 'DefenderExclAdded') then
    begin
      RunPs(PsExclusionCmd(False));
      RegDeleteValue(HKA, ExclRegKey, 'DefenderExclAdded');
      RegDeleteKeyIfEmpty(HKA, ExclRegKey);
    end;
end;
