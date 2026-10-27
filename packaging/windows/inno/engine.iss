#include ConfigPath

[Setup]
AppId={code:ProductIdentity}
AppName=ShenView
AppVersion={#ProductVersion}
AppPublisher=ShenView
VersionInfoDescription=ShenView Setup
VersionInfoProductName=ShenView
VersionInfoCompany=ShenView
AppVerName=ShenView {#ProductVersion}
DefaultDirName={autopf}\ShenView
SetupArchitecture=x64
UseSetupLdr=x64
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
#ifdef ValidationBuild
PrivilegesRequired=lowest
#else
PrivilegesRequired=admin
#endif
OutputDir={#WorkOutput}
OutputBaseFilename=ShenView-Setup
Compression=lzma2/fast
SolidCompression=yes
SetupIconFile={#ProductIcon}
WizardStyle=modern dynamic
UsePreviousLanguage=no
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
AllowCancelDuringInstall=no
CloseApplications=no
RestartApplications=no
SetupLogging=yes
Uninstallable=no
CreateUninstallRegKey=no
UsePreviousAppDir=no
#ifdef ValidationBuild
SetupMutex=ShenView.Inno7.Validation.Deploy
#else
SetupMutex=Global\ShenView.Inno7.Deploy
#endif
ChangesAssociations=yes

[Languages]
Name: en; MessagesFile: compiler:Default.isl
Name: zh; MessagesFile: compiler:Languages\ChineseSimplified.isl

[Files]
Source: {#PayloadPath}\*; DestDir: {app}; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: *.pdb,unins*.exe,unins*.dat
Source: {#MaintenancePath}; DestDir: {app}; DestName: uninstall.exe; Flags: ignoreversion
Source: {#PayloadList}; DestDir: {app}; DestName: payload-files.txt; Flags: ignoreversion

Source: {#PayloadList}; DestName: transaction-payload.txt; Flags: dontcopy

[Icons]
Name: {autoprograms}\{code:ShortcutName}; Filename: {app}\ShenView.exe; Check: WantStartMenu
Name: {autodesktop}\{code:ShortcutName}; Filename: {app}\ShenView.exe; Check: WantDesktop

#include "common.iss"
#include "running-apps.iss"

[Code]
var
  Committed: Boolean;
  EngineFailure: String;

function ShortcutName(Param: String): String;
begin
  Result := 'ShenView';
  if IsValidation then Result := Result + ' Inno7 Validation';
end;

function WantDesktop: Boolean;
begin Result := ExpandConstant('{param:DESKTOP|0}') = '1'; end;

function WantStartMenu: Boolean;
begin Result := ExpandConstant('{param:STARTMENU|1}') = '1'; end;

#include "transaction.iss"

procedure InstallationError(const Message: String);
begin EngineFailure := Message; RaiseException(Message); end;

procedure InjectFailure(const Stage: String);
begin
#ifdef ValidationBuild
  if Stage = 'files' then Sleep(StrToIntDef(ExpandConstant('{param:TESTDELAY|0}'),0));
  if ExpandConstant('{param:FAIL|0}') = Stage then
    InstallationError('Injected validation failure: ' + Stage);
#endif
end;

function PrepareDeployment: String;
var Root, Error, Existing: String; Attempt, ErrorCode: Integer; FileHandle: NativeUInt;
begin
  Result := ''; SetCurrentDir(ExpandConstant('{%TEMP}'));
#ifdef ValidationBuild
  if ExpandConstant('{param:FAIL|0}') = 'prepare' then begin
    Result := Choice('无法保存恢复副本，请检查磁盘空间和文件夹权限。','Unable to save the recovery copy. Check disk space and folder permissions.'); exit;
  end;
#endif
  if LegacyRoot <> '' then begin Result := 'A legacy NSIS installation requires migration before using this preview.'; exit; end;
  if not SafeRoot(ExpandConstant('{app}'),Root,Error) then begin Result := Error; exit; end;
  TargetRoot := Root; SourceRoot := RegisteredRoot;
  if (SourceRoot = '') and (IsOwned(Root) or IsRepairableRoot(Root)) then SourceRoot := Root;
  SourceDirectory := PayloadDirectory(SourceRoot);
  if IsRepairableRoot(Root) and (ExpandConstant('{param:REPAIR|0}') <> '1') then begin
    Result := Choice('检测到损坏的旧安装，请确认修复后重试。','A damaged installation was found. Confirm repair before retrying.'); exit;
  end;
  if SourceRoot <> '' then begin
    if not SafeRoot(SourceRoot,Existing,Error) then begin Result := Error; exit; end;
    if not PathSame(SourceRoot,Root) then begin
      if IsOwned(Root) or IsPreservedDataRoot(Root) or
        (Pos(Lowercase(AddBackslash(SourceRoot)),Lowercase(AddBackslash(Root))) = 1) or
        (Pos(Lowercase(AddBackslash(Root)),Lowercase(AddBackslash(SourceRoot))) = 1) then begin
        Result := Choice('请选择与原目录互不包含的空目录。','Choose an empty folder outside the existing installation.'); exit;
      end;
      if ExpandConstant('{param:MIGRATE|0}') <> '1' then begin
        Result := Choice('更换安装目录需要先确认迁移。','Confirm migration before changing the installation folder.'); exit;
      end;
    end;
    Existing := InstalledVersion(SourceRoot);
    if CompareVersion('{#ProductVersion}',Existing) < 0 then begin
      Result := Choice('已安装更新版本，不能降级。','A newer version is installed. Downgrade is blocked.'); exit;
    end;
    if FileExists(SourceDirectory + '\ShenView.exe') then begin
      { Check replacement access without renaming files or blocking on unrelated personal data. }
      for Attempt := 0 to 19 do begin
        FileHandle := OpenStatusFile(SourceDirectory + '\ShenView.exe',$10002,7,0,3,0,0);
        if FileHandle <> NativeUInt(-1) then begin CloseStatusFile(FileHandle); break; end;
        ErrorCode := DLLGetLastError; Sleep(100);
      end;
      if FileHandle = NativeUInt(-1) then begin
        Result := Choice('程序文件仍被占用或不可写。请关闭神羊看图及解码进程，检查权限后重试。','Application files are in use or not writable. Close ShenView and decoder processes, check permissions, then retry.') + ' (' + IntToStr(ErrorCode) + ')'; exit;
      end;
    end;
  end;
  FindApplicationProcesses(SourceRoot,Root);
  if GetArrayLength(ApplicationProcesses) > 0 then begin Result := Choice('神羊看图或解码进程仍在运行，请关闭后重试。','ShenView or a decoder process is still running. Close it and retry.'); exit; end;
  ExtractTemporaryFile('transaction-payload.txt');
  if not LoadStringsFromFile(ExpandConstant('{tmp}\transaction-payload.txt'),NewFiles) then begin Result := 'Unable to read deployment manifest.'; exit; end;
  ReportState('running',Choice('正在保存恢复副本…','Saving recovery copy…'),1);
  if not SnapshotTransaction then begin
    Result := Choice('无法完整保存恢复副本，未更改现有安装。请检查磁盘空间和权限。','Unable to save a complete recovery copy. The existing installation was not changed. Check disk space and permissions.'); exit;
  end;
  TransactionChanged := True;
  SetIniString('transaction','state','deploying',TransactionDirectory + '\journal.ini');
#ifdef ValidationBuild
  if ExpandConstant('{param:FAIL|0}') = '1' then begin Result := 'Injected validation failure before file deployment.'; exit; end;
#endif
  ReportState('running',Choice('正在部署应用文件…','Deploying application files…'),3);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin Result := PrepareDeployment; EngineFailure := Result; end;

procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
begin
  if MaxProgress > 0 then ReportState('running',Choice('正在安装…','Installing…'),Round((CurProgress * 85.0) / MaxProgress));
end;

procedure CurStepChanged(CurStep: TSetupStep);
var ExitCode, I: Integer; Formats, Key, Link, Tasks: String;
begin
  if EngineFailure <> '' then exit;
  if CurStep = ssPostInstall then begin
    InjectFailure('files');
    InjectFailure('restore');
    Formats := 'installed-system'; if IsValidation then Formats := 'portable';
    if not SaveStringToFile(ExpandConstant('{app}\installation-mode'),Formats,False) then InstallationError('Unable to write installation mode.');
    if (SourceRoot <> '') and (not PathSame(SourceRoot,TargetRoot) or (SourcePrefix <> '')) then begin
      ReportState('running',Choice('正在继承用户数据…','Copying user data…'),87); CopyPersonalData('');
    end;
    InjectFailure('data');
    Formats := ExpandConstant('{param:FORMATS|}');
    if not IsValidation then begin
      { Remove old commands before registering new ones; their executable path changes during migration. }
      if (SourceRoot <> '') and not PathSame(SourceDirectory,TargetRoot) then
        if not Exec(SourceDirectory + '\ShenView.exe','--remove-file-types','',SW_HIDE,ewWaitUntilTerminated,ExitCode) or (ExitCode <> 0) then InstallationError('Unable to remove old file associations.');
      if not Exec(ExpandConstant('{app}\ShenView.exe'),'--set-file-types=' + Formats,'',SW_HIDE,ewWaitUntilTerminated,ExitCode) or (ExitCode <> 0) then InstallationError(Choice('文件关联注册失败。','File association registration failed.'));
    end;
    if IsValidation then SetValidationFormats(TargetRoot,Formats);
    InjectFailure('associations');
    for I := 0 to GetArrayLength(ShortcutPaths)-1 do begin
      Link := ShortcutPaths[I];
      if (SourceRoot <> '') and not PathSame(SourceDirectory,TargetRoot) and FileExists(TransactionDirectory + '\shortcut' + IntToStr(I) + '.lnk') then
        CreateShellLink(Link,'ShenView',TargetRoot + '\ShenView.exe','',TargetRoot,TargetRoot + '\ShenView.exe',0,SW_SHOWNORMAL);
    end;
    if not WantDesktop and FileExists(ShortcutPaths[0]) then DeleteFile(ShortcutPaths[0]);
    if not WantStartMenu and FileExists(ShortcutPaths[1]) then DeleteFile(ShortcutPaths[1]);
    InjectFailure('shortcuts');
  end;
  if CurStep = ssDone then begin
    Key := UninstallKey;
    if not RegWriteStringValue(HKA64,Key,'DisplayName',ShortcutName('')) or
      not RegWriteStringValue(HKA64,Key,'DisplayVersion','{#ProductVersion}') or
      not RegWriteStringValue(HKA64,Key,'Publisher','ShenView') or
      not RegWriteStringValue(HKA64,Key,'InstallLocation',TargetRoot) or
      not RegWriteStringValue(HKA64,Key,'DisplayIcon',TargetRoot + '\ShenView.exe,0') or
      not RegWriteDWordValue(HKA64,Key,'NoModify',1) or
      not RegWriteDWordValue(HKA64,Key,'NoRepair',1) or
      not RegWriteDWordValue(HKA64,Key,'EstimatedSize',{#RequiredSpaceMB} * 1024) then InstallationError('Unable to write uninstall record.');
    if not RegWriteStringValue(HKA64,Key,'UninstallString','"' + TargetRoot + '\uninstall.exe" /MODE=uninstall /ROOT="' + TargetRoot + '"') then InstallationError('Unable to update uninstall record.');
    if not RegWriteStringValue(HKA64,Key,'QuietUninstallString','"' + TargetRoot + '\uninstall.exe" /MODE=uninstall /ROOT="' + TargetRoot + '" /VERYSILENT /SUPPRESSMSGBOXES') then InstallationError('Unable to update silent uninstall record.');
    Tasks := '';
    if WantDesktop then Tasks := 'desktopicon';
    if WantStartMenu then begin if Tasks <> '' then Tasks := Tasks + ','; Tasks := Tasks + 'startmenuicon'; end;
    if not RegWriteStringValue(HKA64,Key,'Inno Setup: Language',ExpandConstant('{param:UILANG|system}')) or
      not RegWriteStringValue(HKA64,Key,'Inno Setup: Selected Tasks',Tasks) then InstallationError('Unable to save installation choices.');
    { Older previews generated an unused native uninstaller and a duplicate ownership marker. }
    for I := 0 to 5 do begin
      case I of
        0: Link := 'unins000.exe'; 1: Link := 'unins000.dat';
        2: Link := 'unins000.msg'; 3: Link := 'shenview-install-root'; 4: Link := 'maintain.exe';
        5: Link := 'install.ini';
      end;
      Link := TargetRoot + '\' + Link;
      if FileExists(Link) and not DeleteFile(Link) then InstallationError('Unable to remove obsolete maintenance file: ' + Link);
    end;
    if (SourceRoot <> '') and not PathSame(SourceRoot,TargetRoot) then begin
      ReportState('running',Choice('正在清理旧安装…','Removing old installation…'),94);
      if not RemoveManagedFiles(SourceRoot,SourceDirectory,SourceFiles) then InstallationError(Choice('旧安装清理失败，正在恢复。','Unable to remove the old installation. Restoring previous state.'));
    end else if (SourceRoot <> '') and (SourcePrefix <> '') then begin
      if not RemovePayloadFiles(SourceRoot,SourceDirectory,SourceFiles) then InstallationError(Choice('旧应用目录清理失败，正在恢复。','Unable to remove the old app folder. Restoring previous state.'));
    end else if SourceRoot <> '' then begin
      if not RemoveObsoletePayload then InstallationError(Choice('旧组件清理失败，正在恢复。','Unable to remove obsolete components. Restoring previous state.'));
    end;
    InjectFailure('cleanup');
    Committed := True; CommitTransaction;
    Formats := Choice('安装完成。','Installation completed.');
    if DataSkipped > 0 then Formats := Formats + Choice(' 部分数据未复制，已保留在原目录。详见日志。',' Some data was not copied and remains at the original location. See the log.');
    ReportStateDetails('success',Formats,100,DataSkipped);
  end;
end;

procedure ReportFailure;
begin
  if EngineFailure = '' then EngineFailure := Choice('操作未完成，请查看日志后重试。','The operation did not complete. Check the log, then retry.');
  if not TransactionReady or not TransactionChanged then begin CleanupTransaction; ReportStateRecord('failed',EngineFailure,0,0,'unchanged',''); exit; end;
  ReportState('restoring',Choice('操作未完成，正在恢复原来的安装。请稍候。','The operation failed. Restoring the previous installation. Please wait.'),0);
#ifdef ValidationBuild
  Sleep(StrToIntDef(ExpandConstant('{param:TESTDELAY|0}'),0));
#endif
  if RestoreTransaction then begin
    CleanupTransaction;
    ReportStateRecord('failed',EngineFailure,0,0,'restored','');
  end
  else ReportStateRecord('recovery-failed',EngineFailure,0,0,'incomplete',TransactionDirectory);
end;

procedure DeinitializeSetup;
begin if not Committed then ReportFailure; end;

function GetCustomSetupExitCode: Integer;
begin if Committed then Result := 0 else Result := 1; end;
