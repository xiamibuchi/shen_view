#include ConfigPath

[Setup]
AppId=ShenView.Inno7.UninstallWorker
AppName=ShenView
AppVersion={#ProductVersion}
AppPublisher=ShenView
VersionInfoDescription=ShenView Uninstall
VersionInfoProductName=ShenView
VersionInfoCompany=ShenView
DefaultDirName={autopf}\ShenView
CreateAppDir=no
CreateUninstallRegKey=no
Uninstallable=no
SetupArchitecture=x64
UseSetupLdr=x64
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#ifdef ValidationBuild
PrivilegesRequired=lowest
#else
PrivilegesRequired=admin
#endif
OutputDir={#WorkOutput}
OutputBaseFilename=ShenView-Uninstall
SetupIconFile={#ProductIcon}
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
AllowCancelDuringInstall=no
CloseApplications=no
RestartApplications=no
SetupLogging=yes
#ifdef ValidationBuild
SetupMutex=ShenView.Inno7.Validation.Deploy
#else
SetupMutex=Global\ShenView.Inno7.Deploy
#endif

[Languages]
Name: en; MessagesFile: compiler:Default.isl
Name: zh; MessagesFile: compiler:Languages\ChineseSimplified.isl

#include "common.iss"
#include "running-apps.iss"

[Code]
var Committed: Boolean; Failure: String;

function ShortcutName(Param: String): String;
begin Result := 'ShenView'; if IsValidation then Result := Result + ' Inno7 Validation'; end;

#include "transaction.iss"
#include "purge.iss"

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Normalized, Error: String;
begin
  SourceRoot := RemoveBackslash(ExpandConstant('{param:ROOT|}'));
  DeferredMaintenance := ExpandConstant('{param:CLEANUPPID|0}') <> '0';
  Result := Choice('安装归属不匹配，未移除任何文件。','Installation ownership does not match. No files were removed.');
  if not IsOwned(SourceRoot) or not SafeRoot(SourceRoot,Normalized,Error) then begin Failure := Result; exit; end;
  if (ExpandConstant('{param:PURGE|0}') = '1') and (not IsValidation or (ExpandConstant('{param:OWNER|}') <> '')) and
    ((InstallerUser = '') or (CompareText(InstallerUser,ExpandConstant('{param:OWNER|}')) <> 0)) then begin
    Result := Choice('完全卸载需要使用当前登录用户授权，不能切换到另一管理员账号。未删除任何文件。',
      'Complete uninstall requires authorization as the current user, without switching administrator accounts. No files were removed.'); Failure := Result; exit;
  end;
  FindApplicationProcesses(SourceRoot,'');
  if GetArrayLength(ApplicationProcesses) > 0 then begin
    Result := Choice('神羊看图或解码进程仍在运行，请关闭后重试。','ShenView or a decoder process is still running. Close it and retry.'); Failure := Result; exit;
  end;
  TargetRoot := '';
  ReportState('running',Choice('正在保存卸载恢复副本…','Saving uninstall recovery copy…'),2);
  Result := '';
  if not SnapshotTransaction then begin
    Result := Choice('无法完整保存恢复副本，未更改现有安装。','Unable to save a complete recovery copy. The existing installation was not changed.'); Failure := Result;
  end;
  if (Result = '') and not PreparePurge then begin
    Result := Choice('无法备份完全卸载涉及的全部文件。请检查权限、可用空间和目录链接后重试。未更改现有安装。',
      'Unable to back up every file for complete uninstall. Check permissions, free space and directory links, then retry. The installation was not changed.'); Failure := Result;
  end;
end;

procedure Fail(const Message: String);
begin Failure := Message; RaiseException(Message); end;

procedure InjectFailure(const Stage: String);
begin
#ifdef ValidationBuild
  if Stage = 'uninstall-start' then Sleep(StrToIntDef(ExpandConstant('{param:TESTDELAY|0}'),0));
  if ExpandConstant('{param:FAIL|0}') = Stage then Fail('Injected validation failure: ' + Stage);
#endif
end;

procedure CurStepChanged(Step: TSetupStep);
var I, ExitCode: Integer; Parent: NativeUInt;
begin
  if Failure <> '' then exit;
  if Step = ssInstall then begin
    TransactionChanged := True;
    SetIniString('transaction','state','uninstalling',TransactionDirectory + '\journal.ini');
    if not IsValidation then
      if not Exec(SourceDirectory + '\ShenView.exe','--remove-file-types','',SW_HIDE,ewWaitUntilTerminated,ExitCode) or (ExitCode <> 0) then Fail('Unable to remove file associations.');
    if IsValidation then SetValidationFormats(SourceRoot,'');
    InjectFailure('uninstall-start');
    ReportState('running',Choice('正在卸载…','Uninstalling…'),35);
    for I := 0 to GetArrayLength(ShortcutPaths)-1 do
      if FileExists(ShortcutPaths[I]) and not DeleteFile(ShortcutPaths[I]) then Fail('Unable to remove shortcut: ' + ShortcutPaths[I]);
    if not RemoveManagedFiles(SourceRoot,SourceDirectory,SourceFiles) then Fail(Choice('部分应用文件无法移除，正在恢复。','Some application files could not be removed. Restoring previous state.'));
    InjectFailure('uninstall-files');
    if RegKeyExists(HKA64,UninstallKey) and not RegDeleteKeyIncludingSubkeys(HKA64,UninstallKey) then Fail('Unable to remove uninstall record.');
    InjectFailure('uninstall-record');
    if Purging then begin
      if not RemovePurgeTree(SourceRoot,FullFiles,FullDirectories,DeferredMaintenance,False) then Fail(Choice('安装目录无法完全移除，正在恢复。','The installation folder could not be fully removed. Restoring previous state.'));
      InjectFailure('purge-root');
      if (UserDataRoot <> '') and not RemovePurgeTree(UserDataRoot,UserFiles,UserDirectories,False,True) then Fail(Choice('用户数据无法完全移除，正在恢复。','User data could not be fully removed. Restoring previous state.'));
      if UserDataRoot <> '' then RemoveDir(UserDataRoot);
      InjectFailure('purge-data');
    end;
  end;
  if Step = ssDone then begin
    if not Purging and DirExists(SourceRoot) and not SaveStringToFile(SourceRoot + '\.shenview-user-data',Identity,False) then Fail('Unable to mark preserved user data. Restoring the installation.');
    Committed := True; CommitTransaction;
    RegDeleteKeyIfEmpty(HKA64,'Software\ShenView\InstallerTransactions');
    RegDeleteKeyIfEmpty(HKA64,'Software\ShenView\Associations');
    RegDeleteKeyIfEmpty(HKA64,'Software\ShenView');
    if Purging then ReportState('success',Choice('完全卸载完成。','Complete uninstall finished.'),100)
    else ReportState('success',Choice('卸载完成，用户数据已保留。','Uninstalled. User data was kept.'),100);
    if DeferredMaintenance then begin
      { A silent maintenance caller must return the real result before its own image can be deleted. }
      Parent := OpenApplicationProcess($100000,False,StrToIntDef(ExpandConstant('{param:CLEANUPPID|0}'),0));
      if Parent <> 0 then begin
        for I := 0 to 599 do begin if WaitApplicationExit(Parent,100) = 0 then break; end;
        CloseApplicationHandle(Parent);
      end;
      for I := 0 to 99 do begin if DeleteFile(SourceRoot + '\uninstall.exe') then break; Sleep(50); end;
      if FileExists(SourceRoot + '\uninstall.exe') then Log('Uninstaller executable could not be removed after its caller exited.');
      RemoveDir(SourceRoot);
    end;
  end;
end;

procedure DeinitializeSetup;
var RestoredFiles, RestoredData: Boolean;
begin
  if Committed then exit;
  if Failure = '' then Failure := Choice('卸载未完成，请查看日志后重试。','Uninstall did not complete. Check the log, then retry.');
  if not TransactionReady or not TransactionChanged then begin
    CleanupTransaction;
    RegDeleteKeyIfEmpty(HKA64,'Software\ShenView\InstallerTransactions');
    RegDeleteKeyIfEmpty(HKA64,'Software\ShenView');
    ReportStateRecord('failed',Failure,0,0,'unchanged',''); exit;
  end;
  ReportState('restoring',Choice('卸载未完成，正在恢复原来的安装和数据。请稍候。','Uninstall failed. Restoring the previous installation and data. Please wait.'),0);
#ifdef ValidationBuild
  Sleep(StrToIntDef(ExpandConstant('{param:TESTDELAY|0}'),0));
#endif
  RestoredFiles := RestoreTransaction; RestoredData := RestorePurge;
  if RestoredFiles and RestoredData then begin
    CleanupTransaction;
    ReportStateRecord('failed',Failure,0,0,'restored','');
  end
  else ReportStateRecord('recovery-failed',Failure,0,0,'incomplete',TransactionDirectory);
end;

function GetCustomSetupExitCode: Integer;
begin if Committed then Result := 0 else Result := 1; end;
