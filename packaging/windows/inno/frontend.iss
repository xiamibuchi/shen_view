#include ConfigPath

[Setup]
AppId=ShenView.Inno7.Frontend
AppName=ShenView
AppVersion={#ProductVersion}
AppPublisher=ShenView
#ifdef MaintenanceBuild
VersionInfoDescription=ShenView Uninstall
#else
VersionInfoDescription=ShenView Setup
#endif
VersionInfoProductName=ShenView
VersionInfoCompany=ShenView
DefaultDirName={autopf}\ShenView
CreateAppDir=no
CreateUninstallRegKey=no
Uninstallable=no
PrivilegesRequired=lowest
SetupArchitecture=x64
UseSetupLdr=x64
ArchitecturesAllowed=x64compatible
MinVersion=10.0.19041
#ifdef MaintenanceBuild
OutputDir={#WorkOutput}
OutputBaseFilename=maintenance
#else
OutputDir={#PackageOutput}
#ifdef ValidationBuild
OutputBaseFilename=ShenView-{#ProductVersion}-windows-x64-inno7-validation
#else
#ifdef ReleaseBuild
OutputBaseFilename=ShenView-{#ProductVersion}-windows-x64-setup
#else
OutputBaseFilename=ShenView-{#ProductVersion}-windows-x64-inno7-preview
#endif
#endif
#endif
Compression=none
SetupIconFile={#ProductIcon}
#ifdef ForceDark
WizardStyle=modern dark
#else
WizardStyle=modern dynamic
#endif
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableFinishedPage=no
ShowLanguageDialog=no
UsePreviousLanguage=no
AllowCancelDuringInstall=no
CloseApplications=no
RestartApplications=no

[Languages]
Name: en; MessagesFile: compiler:Default.isl
Name: zh; MessagesFile: compiler:Languages\ChineseSimplified.isl

[LangOptions]
DialogFontName=Segoe UI
DialogFontSize=9

[Files]
Source: {#BrandImage}; DestName: brand.png; Flags: dontcopy
Source: {#UninstallWorkerPath}; Flags: dontcopy
#ifndef MaintenanceBuild
Source: {#EnginePath}; Flags: dontcopy
#endif

#include "common.iss"
#include "preferences.iss"
#include "appearance.iss"
#include "running-apps.iss"

[Code]
function SetTimer(Window: HWND; ID: NativeUInt; Interval: Cardinal; Callback: NativeInt): NativeUInt;
  external 'SetTimer@user32.dll stdcall';
function KillTimer(Window: HWND; ID: NativeUInt): Boolean;
  external 'KillTimer@user32.dll stdcall';
function Subclass(Window: HWND; Callback: NativeInt; ID, Data: NativeUInt): Boolean;
  external 'SetWindowSubclass@comctl32.dll stdcall';
function RemoveSubclass(Window: HWND; Callback: NativeInt; ID: NativeUInt): Boolean;
  external 'RemoveWindowSubclass@comctl32.dll stdcall';
function DefaultSubclass(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM): LRESULT;
  external 'DefSubclassProc@comctl32.dll stdcall';
function PostAction(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM): Boolean;
  external 'PostMessageW@user32.dll stdcall';
function CopyMaintenance(const Source, Destination: String; FailIfExists: Boolean): Boolean;
  external 'CopyFileW@kernel32.dll stdcall';
function ReleaseDrag: Boolean;
  external 'ReleaseCapture@user32.dll stdcall';
function FrontendProcessID: Cardinal;
  external 'GetCurrentProcessId@kernel32.dll stdcall';
procedure RefreshShellAssociations(Event: Integer; Flags: Cardinal; Item1, Item2: NativeUInt);
  external 'SHChangeNotify@shell32.dll stdcall';
function ShowInstallerWindow(Window: HWND; Command: Integer): Boolean;
  external 'ShowWindow@user32.dll stdcall';
function ActivateInstallerWindow(Window: HWND): Boolean;
  external 'SetForegroundWindow@user32.dll stdcall';

const
  InstallFlowWidth = 640;
  InstallFlowHeight = 480;

var
  OptionsPage: TWizardPage;
  Body, Content, PathFrame, PathSurface, Header, AssociationPanel, FooterLine, OptionsLine: TPanel;
  Brand, BrandVersion, AssociationSummary, ResultMark: TNewStaticText;
  BrandIcon: TBitmapImage;
  Title, Intro, PathLabel, UninstallLocation, SpaceLabel, FormatLabel, ShortcutLabel, StateTitle, StateDetail: TNewStaticText;
  PathEdit: TNewPathEdit;
  Browse, ImageDetails, LogDetails, DeferredClose, RecoveryDetails: TNewButton;
  FailureReason: TNewStaticText;
  Images, Archives, DesktopShortcut, StartShortcut, LaunchApp, PurgeData: TNewCheckBox;
  ImageList, ArchiveList: TNewCheckListBox;
  Language: TNewComboBox;
  Gauge: TNewProgressBar;
  UILanguage, RootPath, InstalledRoot, PreviousExecutable, JobDirectory, Worker, Failure, PreferenceFile: String;
  Removing, Working, Completed, Relayouting, PathHasError: Boolean;
  Failed, CloseWhenFinished, Restoring: Boolean;
  RecoveryOutcome, RecoveryDirectory: String;
  PollTimer: NativeUInt;
  SyncingSelection: Boolean;
  PollCount: Integer;
  HeaderCallback: NativeInt;
  CloseCallback: NativeInt;
  ProgressText, WorkingHint: TNewStaticText;
  FlowHeight: Integer;
  ActionName: String;

function Tr(const Chinese, English: String): String; forward;

procedure SyncSelection(Sender: TObject);
var I, Count, ImageCount, ArchiveCount: Integer;
begin
  if SyncingSelection then exit;
  SyncingSelection := True;
  try
    Count := 0;
    for I := 0 to ImageList.Items.Count - 1 do if ImageList.Checked[I] then Count := Count + 1;
    Images.Caption := Tr('图片格式', 'Images');
    if (Count > 0) and (Count < ImageList.Items.Count) then
      Images.Caption := Images.Caption + '  ' + IntToStr(Count) + ' / ' + IntToStr(ImageList.Items.Count);
    if Count = 0 then Images.State := cbUnchecked
    else if Count = ImageList.Items.Count then Images.State := cbChecked else Images.State := cbGrayed;
    ImageCount := Count;
    Count := 0;
    for I := 0 to ArchiveList.Items.Count - 1 do if ArchiveList.Checked[I] then Count := Count + 1;
    Archives.Caption := Tr('压缩包与漫画', 'Archives and comics');
    if (Count > 0) and (Count < ArchiveList.Items.Count) then
      Archives.Caption := Archives.Caption + '  ' + IntToStr(Count) + ' / ' + IntToStr(ArchiveList.Items.Count);
    if Count = 0 then Archives.State := cbUnchecked
    else if Count = ArchiveList.Items.Count then Archives.State := cbChecked else Archives.State := cbGrayed;
    ArchiveCount := Count;
    AssociationSummary.Caption := Tr('打开方式：图片 ', 'Open With: Images ') + IntToStr(ImageCount) +
      Tr(' 种 · 压缩包 ', ' · Archives ') + IntToStr(ArchiveCount) + Tr(' 种','');
  finally SyncingSelection := False; end;
end;

function Tr(const Chinese, English: String): String;
begin
  if (UILanguage = 'zh') or ((UILanguage = 'system') and ((GetUILanguage and $3FF) = 4)) then
    Result := Chinese else Result := English;
end;

function TextLabel(const Parent: TWinControl; const X, Y, W, H: Integer): TNewStaticText;
begin
  Result := TNewStaticText.Create(Parent);
  Result.Parent := Parent;
  Result.SetBounds(ScaleX(X), ScaleY(Y), ScaleX(W), ScaleY(H));
  Result.AutoSize := False;
  Result.WordWrap := True;
end;

function NewButton(const Parent: TWinControl; const Caption: String; const Handler: TNotifyEvent): TNewButton;
begin
  Result := TNewButton.Create(Parent);
  Result.Parent := Parent;
  Result.Caption := Caption;
  Result.OnClick := Handler;
end;

function NewCheck(const Parent: TWinControl; const Selected: Boolean; const Handler: TNotifyEvent): TNewCheckBox;
begin
  Result := TNewCheckBox.Create(Parent);
  Result.Parent := Parent;
  Result.Checked := Selected;
  Result.OnClick := Handler;
end;

function OperationName: String;
var Existing: String;
begin
  if Removing then begin Result := Tr('卸载', 'Uninstall'); exit; end;
  if (InstalledRoot <> '') and IsRepairableRoot(InstalledRoot) then begin Result := Tr('修复安装','Repair'); exit; end;
  if InstalledRoot <> '' then begin
    Existing := InstalledVersion(InstalledRoot);
    if CompareVersion('{#ProductVersion}', Existing) = 0 then Result := Tr('重新安装', 'Reinstall')
    else Result := Tr('更新', 'Update');
  end else Result := Tr('安装', 'Install');
end;

function ShortcutTargetsInstallation(const Path: String): Boolean;
var Shell, Link: Variant;
begin
  Result := False;
  if not FileExists(Path) then exit;
  try
    Shell := CreateOleObject('WScript.Shell'); Link := Shell.CreateShortcut(Path);
    Result := PathSame(Link.TargetPath,PreviousExecutable);
  except Log('Unable to inspect shortcut: ' + Path); end;
end;

function ShortcutExists(const Desktop: Boolean): Boolean;
var Name: String;
begin
  Name := 'ShenView'; if IsValidation then Name := Name + ' Inno7 Validation';
  if Desktop then begin
    Result := ShortcutTargetsInstallation(ExpandConstant('{userdesktop}\') + Name + '.lnk');
    if not IsValidation then Result := Result or ShortcutTargetsInstallation(ExpandConstant('{commondesktop}\') + Name + '.lnk');
  end else begin
    Result := ShortcutTargetsInstallation(ExpandConstant('{userprograms}\') + Name + '.lnk');
    if not IsValidation then Result := Result or ShortcutTargetsInstallation(ExpandConstant('{commonprograms}\') + Name + '.lnk');
  end;
end;

function InitialShortcut(const Root: String; Desktop: Boolean): Boolean;
var Task: String;
begin
  Result := ShortcutExists(Desktop);
  if IsOwned(Root) then begin
    if FileExists(ApplicationExecutable(Root)) then exit;
    if Desktop then Task := 'desktopicon' else Task := 'startmenuicon';
    Result := Result or (Pos(',' + Task + ',',',' + InstalledValue(Root,'tasks','') + ',') > 0);
  end else if not Desktop then Result := True;
end;

function EffectiveRoot: String;
begin
  Result := RemoveBackslash(Trim(PathEdit.Text));
  if Length(Result) < 4 then exit;
  if not IsOwned(Result) and (CompareText(ExtractFileName(Result),'ShenView') <> 0) then
    Result := AddBackslash(Result) + 'ShenView';
end;

procedure UpdateCloseButton;
begin
  WorkingHint.Visible := Working;
  DeferredClose.Visible := Working;
  if CloseWhenFinished then WorkingHint.Caption := Tr('成功后自动关闭；失败时会重新显示。','Closes on success; reopens if the operation fails.')
  else WorkingHint.Caption := Tr('可最小化，操作会继续。','You can minimize while the operation continues.');
  Language.Visible := not Working and not Completed and not Failed;
  LogDetails.Visible := not Working and (Failure <> '') and (JobDirectory <> '');
  RecoveryDetails.Visible := Failed and (RecoveryDirectory <> '');
end;

procedure DeferClose(Sender: TObject);
begin
  CloseWhenFinished := True;
  UpdateCloseButton;
  ShowInstallerWindow(WizardForm.Handle,6);
end;

procedure OpenRecovery(Sender: TObject);
var ErrorCode: Integer;
begin
  if RecoveryDirectory <> '' then
    ShellExec('open',RecoveryDirectory,'','',SW_SHOWNORMAL,ewNoWait,ErrorCode);
end;

function CloseMessages(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM; ID, Data: NativeUInt): LRESULT;
begin
  if Working and ((MessageID = $10) or ((MessageID = $112) and ((W and $FFF0) = $F060))) then begin
    DeferClose(nil); Result := 0; exit;
  end;
  Result := DefaultSubclass(Window,MessageID,W,L);
end;

function HeaderMessages(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM; ID, Data: NativeUInt): LRESULT;
begin
  if MessageID = $201 then begin
    ReleaseDrag;
    PaintMessage(WizardForm.Handle,$A1,2,0);
    Result := 0;
  end else Result := DefaultSubclass(Window,MessageID,W,L);
end;

procedure ShowLog(Sender: TObject);
var ErrorCode: Integer;
begin
  if FileExists(JobDirectory + '\engine.log') then
    ShellExec('', 'notepad.exe', '"' + JobDirectory + '\engine.log"', '', SW_SHOWNORMAL, ewNoWait, ErrorCode)
  else ShellExec('open', JobDirectory, '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;

function FontLineHeight(Window: HWND): Integer;
var DC, OldFont: NativeUInt; Rect: TPaintRect;
begin
  DC := PaintDC(Window);
  OldFont := SelectPaintObject(DC,PaintMessage(Window,$31,0,0));
  Rect.Left := 0; Rect.Top := 0; Rect.Right := 0; Rect.Bottom := 0;
  PaintText(DC,'Mg',2,Rect,$420);
  Result := Rect.Bottom;
  SelectPaintObject(DC,OldFont); FreePaintDC(Window,DC);
end;

function WrapLocation(const Value: String; Width: Integer; var Lines: Integer): String;
var DC, OldFont: NativeUInt; Rect: TPaintRect; I: Integer; Line: String;
begin
  Result := ''; Line := ''; Lines := 1;
  DC := PaintDC(UninstallLocation.Handle);
  OldFont := SelectPaintObject(DC,PaintMessage(UninstallLocation.Handle,$31,0,0));
  for I := 1 to Length(Value) do begin
    Rect.Left := 0; Rect.Top := 0; Rect.Right := 0; Rect.Bottom := 0;
    PaintText(DC,Line + Value[I],Length(Line) + 1,Rect,$C20);
    if (Line <> '') and (Rect.Right > Width) then begin
      Result := Result + Line + #13#10; Line := ''; Lines := Lines + 1;
    end;
    Line := Line + Value[I];
  end;
  Result := Result + Line;
  SelectPaintObject(DC,OldFont); FreePaintDC(UninstallLocation.Handle,DC);
end;

function WrappedTextHeight(LabelControl: TNewStaticText; Width: Integer): Integer;
var DC, OldFont: NativeUInt; Rect: TPaintRect;
begin
  DC := PaintDC(LabelControl.Handle);
  OldFont := SelectPaintObject(DC,PaintMessage(LabelControl.Handle,$31,0,0));
  Rect.Left := 0; Rect.Top := 0; Rect.Right := Width; Rect.Bottom := 0;
  PaintText(DC,LabelControl.Caption,Length(LabelControl.Caption),Rect,$410);
  Result := Rect.Bottom + ScaleY(4);
  SelectPaintObject(DC,OldFont); FreePaintDC(LabelControl.Handle,DC);
end;

procedure Layout;
var Width, FooterTop, HeaderHeight, FooterHeight, LineHeight, SummaryTop, ShortcutTop, Y, LaunchWidth,
    Shrink, WindowHeight, SummaryHeight, SummaryBottom, ShortcutBlock, StartOffset, HintTop, HeaderShift,
    LocationLines, LocationHeight, GroupHeight, InfoHeight, IntroExtra, I, MeasuredHeight, DetailOffset, ReasonOffset, ReasonHeight: Integer;
    OriginalFace, OriginalIntro, WrappedLocation: String; DC, OldFont: NativeUInt; Rect, WorkArea: TPaintRect;
begin
  if Relayouting then exit;
  Relayouting := True;
  try
    InstallerWorkArea(WizardForm.Handle,WorkArea);
    if not Removing then begin
      Width := LimitLayout(WorkArea.Right-WorkArea.Left-ScaleX(16),ScaleX(520),ScaleX(InstallFlowWidth));
      WizardForm.Width := WizardForm.Width+Width-WizardForm.ClientWidth;
    end;
    Width := WizardForm.ClientWidth;
    LocationHeight := ScaleY(40);
    InfoHeight := ScaleY(24); IntroExtra := 0;
    if Removing then begin
      InfoHeight := WrappedTextHeight(Intro,Width-ScaleX(64));
      if InfoHeight < ScaleY(40) then InfoHeight := ScaleY(40);
      { Reserve both locales before the first paint: switching language must not resize the flow. }
      OriginalFace := UninstallLocation.Font.Name; OriginalIntro := Intro.Caption;
      for I := 0 to 1 do begin
        if I = 0 then begin
          UninstallLocation.Font.Name := 'Microsoft YaHei UI'; Intro.Font.Name := 'Microsoft YaHei UI';
          if Failure = '' then Intro.Caption := '移除应用、快捷方式和打开方式，默认保留设置与阅读记录。';
        end else begin
          UninstallLocation.Font.Name := 'Segoe UI'; Intro.Font.Name := 'Segoe UI';
          if Failure = '' then Intro.Caption := 'Remove the app, shortcuts and Open With entries. Keep settings and history by default.';
        end;
        MeasuredHeight := WrappedTextHeight(Intro,Width-ScaleX(64));
        if MeasuredHeight > InfoHeight then InfoHeight := MeasuredHeight;
        WrappedLocation := WrapLocation(RootPath,Width-ScaleX(64),LocationLines);
        MeasuredHeight := LocationLines * FontLineHeight(UninstallLocation.Handle) + ScaleY(4);
        if MeasuredHeight > LocationHeight then LocationHeight := MeasuredHeight;
      end;
      UninstallLocation.Font.Name := OriginalFace; Intro.Font.Name := OriginalFace; Intro.Caption := OriginalIntro;
      UninstallLocation.Caption := WrapLocation(RootPath,Width-ScaleX(64),LocationLines);
      IntroExtra := InfoHeight-ScaleY(40);
      Y := 380 + ((LocationHeight-ScaleY(40)+IntroExtra)*1000 + ScaleY(1000)-1) div ScaleY(1000);
      if Y > FlowHeight then FlowHeight := Y;
    end else begin
      if SpaceLabel.Caption <> '' then InfoHeight := WrappedTextHeight(SpaceLabel,Width-ScaleX(64))
      else if InstalledRoot <> '' then InfoHeight := WrappedTextHeight(Intro,Width-ScaleX(64));
      if InfoHeight < ScaleY(24) then InfoHeight := ScaleY(24);
      Y := InstallFlowHeight + ((InfoHeight-ScaleY(24))*1000 + ScaleY(1000)-1) div ScaleY(1000);
      if Y > FlowHeight then FlowHeight := Y;
    end;
    WindowHeight := ScaleY(FlowHeight); Shrink := 0;
    if not Removing then begin
      WindowHeight := LimitLayout(WindowHeight,WindowHeight-ScaleY(48),WorkArea.Bottom-WorkArea.Top-ScaleY(16));
      Shrink := ScaleY(FlowHeight)-WindowHeight;
    end;
    WizardForm.Height := WizardForm.Height + WindowHeight - WizardForm.ClientHeight;
    Width := WizardForm.ClientWidth;
    FooterHeight := ScaleY(72)-LimitLayout(Shrink-ScaleY(8),0,ScaleY(8));
    FooterTop := WizardForm.ClientHeight-FooterHeight;
    HeaderHeight := ScaleY(88)-LimitLayout(Shrink,0,ScaleY(8));
    if Removing then HeaderHeight := ScaleY(96);
    Header.SetBounds(0,0,Width,HeaderHeight);
    HeaderShift := 0; if not Removing then HeaderShift := ScaleY(4)+LimitLayout(Shrink,0,ScaleY(8)) div 2;
    BrandIcon.SetBounds(ScaleX(32),ScaleY(24)-HeaderShift,ScaleX(40),ScaleY(40));
    Brand.SetBounds(ScaleX(88),ScaleY(20)-HeaderShift,Width-ScaleX(288),ScaleY(32));
    Y := ScaleY(54); if not Removing then Y := ScaleY(48)-LimitLayout(Shrink,0,ScaleY(8)) div 2;
    BrandVersion.SetBounds(ScaleX(88),Y,Width-ScaleX(288),ScaleY(20));
    Language.SetBounds(Width-ScaleX(184),ScaleY(26)-HeaderShift,ScaleX(152),ScaleY(30));
    Body.SetBounds(0,HeaderHeight,Width,FooterTop-HeaderHeight);
    Content.SetBounds(0,0,Width,Body.ClientHeight);
    Title.Visible := Removing;
    Title.SetBounds(ScaleX(32),ScaleY(8),Width-ScaleX(64),ScaleY(32));
    Intro.Visible := Removing or ((InstalledRoot <> '') and (SpaceLabel.Caption = ''));
    if Removing then Intro.SetBounds(ScaleX(32),ScaleY(52),Width-ScaleX(64),InfoHeight)
    else Intro.SetBounds(ScaleX(32),ScaleY(92)-LimitLayout(Shrink-ScaleY(40),0,ScaleY(8)),Width-ScaleX(64),InfoHeight);
    PathFrame.Visible := not Removing; Browse.Visible := not Removing;
    UninstallLocation.Visible := Removing;
    SpaceLabel.Visible := not Removing and (SpaceLabel.Caption <> '');
    if Removing then begin
      PathLabel.SetBounds(ScaleX(32),ScaleY(100)+IntroExtra,Width-ScaleX(64),ScaleY(20));
      UninstallLocation.SetBounds(ScaleX(32),ScaleY(124)+IntroExtra,Width-ScaleX(64),LocationHeight);
      PurgeData.SetBounds(ScaleX(32),ScaleY(168)+IntroExtra+LocationHeight-ScaleY(40),Width-ScaleX(64),ScaleY(36));
    end else begin
      PathLabel.SetBounds(ScaleX(32),ScaleY(8),Width-ScaleX(64),ScaleY(24));
      PathFrame.SetBounds(ScaleX(32),ScaleY(40),Width-ScaleX(180),ScaleY(40));
      PathSurface.SetBounds(1,1,PathFrame.Width-2,PathFrame.Height-2);
      LineHeight := FontLineHeight(PathEdit.Handle);
      PathEdit.SetBounds(ScaleX(12),(PathSurface.Height-LineHeight) div 2-ScaleY(2),PathSurface.Width-ScaleX(24),LineHeight);
      Browse.SetBounds(Width-ScaleX(136),ScaleY(40),ScaleX(104),ScaleY(40));
      HintTop := ScaleY(92)-LimitLayout(Shrink-ScaleY(40),0,ScaleY(8));
      SpaceLabel.SetBounds(ScaleX(32),HintTop,Width-ScaleX(64),InfoHeight);
    end;
    SummaryHeight := ScaleY(56)-LimitLayout(Shrink-ScaleY(16),0,ScaleY(8));
    SummaryBottom := ScaleY(16)-LimitLayout(Shrink-ScaleY(24),0,ScaleY(4));
    ShortcutBlock := ScaleY(108)-LimitLayout(Shrink-ScaleY(28),0,ScaleY(12));
    StartOffset := ScaleY(60)-LimitLayout(Shrink-ScaleY(28),0,ScaleY(4));
    SummaryTop := Body.ClientHeight-SummaryBottom-SummaryHeight;
    ShortcutTop := SummaryTop-ShortcutBlock;
    OptionsLine.SetBounds(ScaleX(32),ShortcutTop-ScaleY(12),Width-ScaleX(64),1);
    ShortcutLabel.SetBounds(ScaleX(32),ShortcutTop,Width-ScaleX(64),ScaleY(20));
    DesktopShortcut.SetBounds(ScaleX(32),ShortcutTop+ScaleY(24),Width-ScaleX(64),ScaleY(32));
    StartShortcut.SetBounds(ScaleX(32),ShortcutTop+StartOffset,Width-ScaleX(64),ScaleY(32));
    DesktopShortcut.Visible := not Removing; StartShortcut.Visible := not Removing;
    ShortcutLabel.Visible := not Removing; OptionsLine.Visible := not Removing;
    AssociationPanel.Visible := not Removing;
    AssociationPanel.SetBounds(ScaleX(32),SummaryTop,Width-ScaleX(64),SummaryHeight);
    AssociationSummary.SetBounds(ScaleX(16),(SummaryHeight-ScaleY(24)) div 2+ScaleY(2),AssociationPanel.Width-ScaleX(160),ScaleY(24));
    ImageDetails.SetBounds(AssociationPanel.Width-ScaleX(136),(SummaryHeight-ScaleY(36)) div 2,ScaleX(120),ScaleY(36));
    Images.Visible := False; Archives.Visible := False; FormatLabel.Visible := False;
    ImageList.Visible := False; ArchiveList.Visible := False;
    PurgeData.Visible := Removing;
    FooterLine.SetBounds(ScaleX(32),FooterTop,Width-ScaleX(64),1);
    WizardForm.CancelButton.SetBounds(Width-ScaleX(248),FooterTop+ScaleY(16),ScaleX(104),ScaleY(40));
    WizardForm.NextButton.SetBounds(Width-ScaleX(136),FooterTop+ScaleY(16),ScaleX(104),ScaleY(40));
    LogDetails.SetBounds(ScaleX(32),FooterTop+ScaleY(16),ScaleX(104),ScaleY(40));
    WorkingHint.SetBounds(ScaleX(32),FooterTop+ScaleY(16),Width-ScaleX(224),ScaleY(40));
    DeferredClose.SetBounds(Width-ScaleX(184),FooterTop+ScaleY(16),ScaleX(152),ScaleY(40));
    RecoveryDetails.SetBounds(ScaleX(144),FooterTop+ScaleY(16),ScaleX(136),ScaleY(40));
    ResultMark.Visible := Completed or Failed;
    FailureReason.Visible := Failed;
    ResultError := Failed;
    WizardForm.NextButton.Tag := 0;
    if Removing and not Completed and not Failed then WizardForm.NextButton.Tag := 1;
    if Failed then begin
      GroupHeight := ScaleY(232);
      DetailOffset := ScaleY(112); ReasonOffset := ScaleY(168); ReasonHeight := ScaleY(64);
      if FooterTop-HeaderHeight < ScaleY(248) then begin
        GroupHeight := ScaleY(200);
        DetailOffset := ScaleY(100); ReasonOffset := ScaleY(152); ReasonHeight := ScaleY(48);
      end;
      Y := HeaderHeight+(FooterTop-HeaderHeight-GroupHeight) div 2;
      ResultMark.SetBounds((Width-ScaleX(56)) div 2,Y,ScaleX(56),ScaleY(56));
      StateTitle.SetBounds(ScaleX(32),Y+ScaleY(64),Width-ScaleX(64),ScaleY(36));
      StateDetail.SetBounds(ScaleX(40),Y+DetailOffset,Width-ScaleX(80),ScaleY(48));
      FailureReason.SetBounds(ScaleX(48),Y+ReasonOffset,Width-ScaleX(96),ReasonHeight);
      FailureReason.Caption := Failure;
      while (Length(FailureReason.Caption) > 4) and
        (WrappedTextHeight(FailureReason,FailureReason.Width) > FailureReason.Height) do
        FailureReason.Caption := Copy(FailureReason.Caption,1,Length(FailureReason.Caption)-4) + '…';
      FailureReason.Hint := Failure; FailureReason.ShowHint := True;
      WizardForm.NextButton.Caption := Tr('返回重试','Try again');
      WizardForm.CancelButton.Caption := Tr('关闭','Close');
      WizardForm.NextButton.Visible := RecoveryOutcome <> 'incomplete';
      if RecoveryOutcome = 'incomplete' then
        WizardForm.CancelButton.SetBounds(Width-ScaleX(136),FooterTop+ScaleY(16),ScaleX(104),ScaleY(40));
    end else if Completed then begin
      GroupHeight := ScaleY(160); if not Removing then GroupHeight := ScaleY(208);
      Y := HeaderHeight + (FooterTop-HeaderHeight-GroupHeight) div 2;
      ResultMark.SetBounds((Width-ScaleX(56)) div 2,Y,ScaleX(56),ScaleY(56));
      StateTitle.SetBounds(ScaleX(32),Y+ScaleY(64),Width-ScaleX(64),ScaleY(36));
      StateDetail.SetBounds(ScaleX(40),Y+ScaleY(108),Width-ScaleX(80),ScaleY(48));
    end else begin
      Y := HeaderHeight+(FooterTop-HeaderHeight-ScaleY(160)) div 2;
      StateTitle.SetBounds(ScaleX(32),Y,Width-ScaleX(64),ScaleY(40));
      StateDetail.SetBounds(ScaleX(40),Y+ScaleY(52),Width-ScaleX(80),ScaleY(48));
    end;
    Gauge.SetBounds(ScaleX(64),Y+ScaleY(112),Width-ScaleX(128),ScaleY(8));
    ProgressText.SetBounds(ScaleX(48),Y+ScaleY(136),Width-ScaleX(96),ScaleY(24));
    LaunchWidth := AlignedCheckWidth(LaunchApp);
    LaunchApp.SetBounds((Width-LaunchWidth) div 2,Y+ScaleY(172),LaunchWidth,ScaleY(32));
    UpdateCloseButton;
    KeepWindowInWorkArea(WizardForm.Handle);
  finally Relayouting := False; end;
end;

procedure ResizeWindow(Sender: TObject);
begin Layout; end;

function SelectedFormats: String;
var I: Integer;
begin
  Result := '';
  for I := 0 to ImageList.Items.Count - 1 do
    if ImageList.Checked[I] then begin
      if Result <> '' then Result := Result + ',';
      Result := Result + ImageList.ItemCaption[I];
    end;
  for I := 0 to ArchiveList.Items.Count - 1 do
    if ArchiveList.Checked[I] then begin
      if Result <> '' then Result := Result + ',';
      Result := Result + ArchiveList.ItemCaption[I];
    end;
end;

procedure UpdatePathAppearance;
begin
  if PathHasError then begin
    PathFrame.Color := ThemePaint($4242B5,$9CA8FF);
    SpaceLabel.Font.Color := ThemePaint($3434A8,$9CA8FF);
  end else begin
    SpaceLabel.Font.Color := ThemePaint($606060,$B8B8B8);
    if WizardForm.ActiveControl = PathEdit then PathFrame.Color := ThemePaint($6E6F18,$D3DA85)
    else PathFrame.Color := ThemePaint($B8B8B8,$666666);
  end;
end;

procedure ValidatePath(Sender: TObject);
var Error, Normalized, Existing: String; Free, Total: Int64;
begin
  if not Assigned(PathEdit) then exit;
  WizardForm.NextButton.Caption := OperationName;
  if not Removing and (LegacyRoot <> '') then begin
    WizardForm.NextButton.Enabled := False;
    SpaceLabel.Caption := Tr('检测到旧 NSIS 安装，此验证包暂不接管。', 'A legacy NSIS installation was found. This preview does not migrate it.');
    PathHasError := True; UpdatePathAppearance;
    exit;
  end;
  if Removing then begin
    WizardForm.NextButton.Caption := OperationName;
    WizardForm.NextButton.Enabled := IsOwned(PathEdit.Text);
    SpaceLabel.Caption := Tr('默认保留设置、阅读记录和个人文件。', 'Settings, reading history and personal files are kept by default.');
    if PurgeData.Checked then SpaceLabel.Caption := Tr('删除当前用户的设置、缓存，以及此安装目录内的所有文件。','Delete current-user settings, caches and every file in this installation folder.');
    exit;
  end;
  WizardForm.NextButton.Enabled := SafeRoot(EffectiveRoot, Normalized, Error);
  if (InstalledRoot <> '') and IsRepairableRoot(InstalledRoot) and not PathSame(InstalledRoot,EffectiveRoot) then begin
    Error := Tr('请先修复原位置的安装，再更换目录。','Repair the original installation before moving it.');
    WizardForm.NextButton.Enabled := False;
  end;
  Existing := InstalledVersion(EffectiveRoot);
  if (Existing <> '') and (CompareVersion('{#ProductVersion}', Existing) < 0) then begin
    Error := Tr('已安装更新版本，不能使用此安装包降级。', 'A newer version is installed. Downgrade is blocked.');
    WizardForm.NextButton.Enabled := False;
  end;
  SpaceLabel.Caption := Error;
  if (Error = '') and GetSpaceOnDisk64(ExtractFileDrive(EffectiveRoot), Free, Total) then
    if Free div 1048576 < {#RequiredSpaceMB} then begin
      Error := Tr('空间不足，请选择其他位置或释放磁盘空间。', 'Not enough space. Choose another location or free disk space.');
      SpaceLabel.Caption := Error;
      WizardForm.NextButton.Enabled := False;
    end;
  if (Error = '') and not PathSame(PathEdit.Text,EffectiveRoot) then
    SpaceLabel.Caption := Tr('实际安装位置：', 'Actual install location: ') + EffectiveRoot;
  if (Error = '') and (InstalledRoot <> '') and not PathSame(InstalledRoot,EffectiveRoot) then
    SpaceLabel.Caption := Tr('将迁移到新位置；完成后更新快捷方式并清理旧安装。','Moves to the new location, updates shortcuts and removes the old installation.');
  PathHasError := Error <> ''; UpdatePathAppearance;
  Title.Caption := OperationName;
  WizardForm.NextButton.Caption := OperationName;
  if Assigned(LaunchApp) then Layout;
end;

procedure Translate;
var Face: String;
begin
  MessageLanguage := Tr('zh','en');
  Face := Tr('Microsoft YaHei UI','Segoe UI');
  WizardForm.Font.Name := Face;
  WizardForm.Caption := Tr('神羊看图','ShenView');
  Brand.Caption := WizardForm.Caption; Brand.Font.Name := Face;
  BrandVersion.Font.Name := Face; BrandVersion.Caption := Tr('版本 ', 'Version ') + '{#ProductVersion}' + ' · ' + OperationName;
  AssociationSummary.Font.Name := Face;
  Content.Font.Name := Face;
  Title.Font.Name := Face; Intro.Font.Name := Face;
  if IsDarkInstallMode then begin BrandVersion.Font.Color := $00B8B8B8; Intro.Font.Color := $00B8B8B8; end
  else begin BrandVersion.Font.Color := $00606060; Intro.Font.Color := $00606060; end;
  PathLabel.Font.Name := Face; SpaceLabel.Font.Name := Face;
  UninstallLocation.Font.Name := Face;
  FormatLabel.Font.Name := Face;
  ShortcutLabel.Font.Name := Face; StateTitle.Font.Name := Face; StateDetail.Font.Name := Face;
  FailureReason.Font.Name := Face; WorkingHint.Font.Name := Face;
  DeferredClose.Font.Name := Face; RecoveryDetails.Font.Name := Face;
  WizardForm.NextButton.Font.Name := Face; WizardForm.CancelButton.Font.Name := Face;
  Title.Caption := Tr('确认卸载','Confirm uninstall');
  if Removing then Intro.Caption := Tr('移除应用、快捷方式和打开方式，默认保留设置与阅读记录。', 'Remove the app, shortcuts and Open With entries. Keep settings and history by default.')
  else if InstalledRoot <> '' then Intro.Caption := Tr('将覆盖现有应用文件，保留设置与阅读记录。', 'Replace application files and keep settings and reading history.')
  else Intro.Caption := '';
  PathLabel.Caption := Tr('安装位置', 'Install location');
  if Removing then PathLabel.Caption := Tr('当前位置','Current location');
  Browse.Caption := Tr('浏览…', 'Browse…');
  FormatLabel.Caption := Tr('关联格式', 'File associations');
  Images.Caption := Tr('图片格式', 'Images');
  Archives.Caption := Tr('压缩包与漫画', 'Archives and comics');
  ImageDetails.Caption := Tr('自定义…', 'Customize…');
  ShortcutLabel.Caption := Tr('快捷方式', 'Shortcuts');
  DesktopShortcut.Caption := Tr('桌面快捷方式', 'Desktop shortcut');
  StartShortcut.Caption := Tr('开始菜单快捷方式', 'Start menu shortcut');
  PurgeData.Caption := Tr('同时删除设置、阅读记录和缓存', 'Also delete settings, history and caches');
  LaunchApp.Caption := Tr('启动神羊看图', 'Launch ShenView');
  WorkingHint.Caption := Tr('操作完成后可关闭窗口。','You can close this window when the operation finishes.');
  WizardForm.CancelButton.Caption := Tr('取消', 'Cancel');
  LogDetails.Caption := Tr('查看日志','View log');
  DeferredClose.Caption := Tr('完成后关闭','Close when done');
  RecoveryDetails.Caption := Tr('查看恢复副本','Recovery copy');
  SyncSelection(nil);
  ValidatePath(nil);
end;

procedure ChangeLanguage(Sender: TObject);
begin
  case Language.ItemIndex of
    1: UILanguage := 'zh';
    2: UILanguage := 'en';
  else UILanguage := 'system'; end;
  Translate;
  Layout;
end;

procedure BrowseClick(Sender: TObject);
var Selected: String;
begin
  Selected := PathEdit.Text;
  if BrowseForFolder(Tr('选择安装位置', 'Choose install location'), Selected, False) then begin
    if CompareText(ExtractFileName(RemoveBackslash(Selected)), 'ShenView') <> 0 then Selected := AddBackslash(Selected) + 'ShenView';
    PathEdit.Text := Selected;
  end;
end;

procedure PathFocus(Sender: TObject);
begin
  UpdatePathAppearance;
end;

#include "format-dialog.iss"

procedure RefreshApplicationName;
var Cache, Executable, CachedName: String;
begin
  Cache := 'Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache';
  Executable := ApplicationExecutable(RootPath);
  if RegQueryStringValue(HKCU,Cache,Executable + '.FriendlyAppName',CachedName) then
    if Removing or (CachedName <> 'ShenView') then
      RegDeleteValue(HKCU,Cache,Executable + '.FriendlyAppName');
  if Removing and PurgeData.Checked then RegDeleteValue(HKCU,Cache,Executable + '.ApplicationCompany');
  if (PreviousExecutable <> '') and not PathSame(PreviousExecutable,Executable) then begin
    RegDeleteValue(HKCU,Cache,PreviousExecutable + '.FriendlyAppName');
    RegDeleteValue(HKCU,Cache,PreviousExecutable + '.ApplicationCompany');
  end;
  RefreshShellAssociations($8000000,0,0,0);
end;

procedure ToggleGroup(Sender: TObject);
var I: Integer; List: TNewCheckListBox; Checked: Boolean;
begin
  if SyncingSelection then exit;
  if Sender = Images then begin List := ImageList; Checked := Images.Checked; end
  else begin List := ArchiveList; Checked := Archives.Checked; end;
  for I := 0 to List.Items.Count - 1 do List.Checked[I] := Checked;
  SyncSelection(nil);
end;

procedure ShowFailure(const Recovery, Directory: String);
begin
  Working := False; Failed := True; CloseWhenFinished := False; Restoring := False;
  RecoveryOutcome := Recovery; RecoveryDirectory := Directory;
  Body.Visible := False; LaunchApp.Visible := False;
  StateTitle.Visible := True; StateDetail.Visible := True;
  Gauge.Visible := False; ProgressText.Visible := False;
  StateTitle.Caption := ActionName + Tr('未完成',' failed');
  if Recovery = 'restored' then StateDetail.Caption := Tr('已恢复操作前的状态，可调整选项后重试。','The previous state was restored. Review your options and try again.')
  else if Recovery = 'unchanged' then StateDetail.Caption := Tr('尚未更改安装文件，可调整选项后重试。','Installation files were not changed. Review your options and try again.')
  else if Recovery = 'incomplete' then begin
    StateTitle.Caption := Tr('恢复未完成','Recovery incomplete');
    StateDetail.Caption := Tr('恢复副本已保留。请保留副本并查看日志。','The recovery copy was kept. Keep it and check the log.');
  end else StateDetail.Caption := Tr('未能确认最终状态，请查看日志。','The final state could not be confirmed. Check the log.');
  WizardForm.NextButton.Enabled := True; WizardForm.CancelButton.Enabled := True;
  WizardForm.NextButton.Visible := True; WizardForm.CancelButton.Visible := True;
  Layout;
  if not WizardSilent then begin
    ShowInstallerWindow(WizardForm.Handle,9); ActivateInstallerWindow(WizardForm.Handle);
    WizardForm.ActiveControl := WizardForm.CancelButton;
  end;
end;

procedure PollState(Window: HWND; MessageID: Cardinal; TimerID: NativeUInt; Tick: Cardinal);
var F, State: String;
begin
  F := AddBackslash(JobDirectory) + 'status.ini';
  Gauge.Position := GetIniInt('result', 'progress', Gauge.Position, 0, 100, F);
  StateDetail.Caption := GetIniString('result', 'message', StateDetail.Caption, F);
  ProgressText.Caption := IntToStr(Gauge.Position) + '%';
  PollCount := PollCount + 1;
  UpdateCloseButton;
  State := GetIniString('result','state','',F);
  if State = 'restoring' then begin
    Restoring := True;
    StateTitle.Caption := Tr('正在恢复…','Restoring previous state…');
    ProgressText.Visible := False;
  end;
  { Elapsed time cannot prove that the elevated worker has stopped. Keep waiting rather than enable a second deployment. }
  if (PollCount >= 3000) and (State <> 'success') and (State <> 'failed') and (State <> 'recovery-failed') then
    StateDetail.Caption := Tr('操作耗时较长，仍在等待执行结果。请勿强制结束进程。','This is taking longer. Waiting for the result; do not force the process to stop.');
  if (State = 'success') or (State = 'failed') or (State = 'recovery-failed') then begin
    KillTimer(0,PollTimer); PollTimer := 0;
    Working := False;
    UpdateCloseButton;
    WizardForm.NextButton.Enabled := True;
    WizardForm.CancelButton.Enabled := True;
    if State = 'success' then begin
      Completed := True;
      RefreshApplicationName;
      if GetIniInt('result','skipped',0,0,1000000,F) > 0 then Failure := StateDetail.Caption;
      if not Removing and ((not WizardSilent) or (ExpandConstant('{param:UILANG|}') <> '')) and not MergePreferenceLanguage(PreferenceFile,UILanguage) then
        Failure := Tr('操作完成，但语言偏好保存失败，原设置已保留。', 'Completed, but the language preference could not be saved. Previous settings were kept.');
      if not WizardSilent then begin
        if CloseWhenFinished and (Failure <> '') then begin ShowInstallerWindow(WizardForm.Handle,9); ActivateInstallerWindow(WizardForm.Handle); end;
        { BM_CLICK may be ignored while minimized; deliver the same button notification to its parent. }
        PostAction(WizardForm.Handle,$111,0,WizardForm.NextButton.Handle);
      end;
    end else begin
      Failure := GetIniString('result','message',Tr('执行状态未知，请检查日志。', 'Execution status is unknown. Check the log.'),F);
      ShowFailure(GetIniString('result','recovery','unknown',F),GetIniString('result','recovery-path','',F));
    end;
  end;
end;

function RunWorker: Boolean;
var Params, Verb, EngineLanguage: String; ErrorCode: Integer;
begin
  Result := False;
  RootPath := EffectiveRoot;
  if IsValidation then PreferenceFile := RootPath + '\test-user\settings.json';
  SetCurrentDir(ExpandConstant('{%TEMP}'));
  JobDirectory := ExpandConstant('{localappdata}\ShenView\installer-logs\') + GetDateTimeString('yyyymmddhhnnsszzz','-',':');
  if IsValidation then JobDirectory := ExpandConstant('{localappdata}\ShenView-Inno7-Validation\installer-logs\') + GetDateTimeString('yyyymmddhhnnsszzz','-',':');
  if Removing and PurgeData.Checked then JobDirectory := ExpandConstant('{%TEMP}\ShenView-uninstall-') + GetDateTimeString('yyyymmddhhnnsszzz','-',':');
  if not ForceDirectories(JobDirectory) then begin
    Failure := Tr('无法创建安装日志目录，请检查磁盘空间与写入权限。','Cannot create the installer log folder. Check free space and write permissions.'); exit;
  end;
  if Removing then begin
    ExtractTemporaryFile('ShenView-Uninstall.exe');
    Worker := ExpandConstant('{tmp}\ShenView-Uninstall.exe');
  end
  else begin
#ifndef MaintenanceBuild
    ExtractTemporaryFile('ShenView-Setup.exe');
#endif
    Worker := ExpandConstant('{tmp}\ShenView-Setup.exe');
  end;
  EngineLanguage := 'en';
  if Tr('zh','en') = 'zh' then EngineLanguage := 'zh';
  Params := '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /SESSION="' + JobDirectory + '" /LANG=' + EngineLanguage;
#ifdef ValidationBuild
  Params := Params + ' /FAIL=' + ExpandConstant('{param:FAIL|0}') + ' /TESTDELAY=' + ExpandConstant('{param:TESTDELAY|0}');
#endif
  Params := Params + ' /LOG="' + JobDirectory + '\engine.log"';
  if Removing then Params := Params + ' /ROOT="' + RootPath + '"';
  if Removing and PurgeData.Checked then Params := Params + ' /PURGE=1 /OWNER="' + InstallerUser + '"';
#ifdef MaintenanceBuild
  if Removing and WizardSilent and (ExpandConstant('{param:DETACHED|0}') <> '1') then
    Params := Params + ' /CLEANUPPID=' + IntToStr(FrontendProcessID);
#endif
  if not Removing then begin
    Params := Params + ' /MIGRATE=1 /DIR="' + RootPath + '" /UILANG=' + UILanguage + ' /FORMATS=' + SelectedFormats;
    if IsRepairableRoot(RootPath) then Params := Params + ' /REPAIR=1';
    if DesktopShortcut.Checked then Params := Params + ' /DESKTOP=1' else Params := Params + ' /DESKTOP=0';
    if StartShortcut.Checked then Params := Params + ' /STARTMENU=1' else Params := Params + ' /STARTMENU=0';
  end;
  Verb := 'runas';
  if IsValidation then Verb := '';
    if not ShellExec(Verb, Worker, Params, ExpandConstant('{%TEMP}'), SW_HIDE, ewNoWait, ErrorCode) then begin
      if ErrorCode = 1223 then Failure := Tr('已取消授权，安装选项已保留。', 'Authorization cancelled. Your choices were kept.')
      else Failure := SysErrorMessage(ErrorCode);
      exit;
    end;
    PollCount := 0;
#ifdef ValidationBuild
    PollCount := StrToIntDef(ExpandConstant('{param:TESTPOLLSTART|0}'),0);
#endif
    PollTimer := SetTimer(0,0,100,CreateCallback(@PollState));
    Result := True;
end;

function CloseRunningApplication: Boolean;
var I, Attempt: Integer; ProcessID: Cardinal; Handles: array of NativeUInt; Exited: Boolean;
begin
  Result := False;
  FindApplicationWindows(EffectiveRoot,InstalledRoot);
  if GetArrayLength(ApplicationProcesses) = 0 then begin Result := True; exit; end;
  Failure := Tr('神羊看图仍在运行，请关闭该安装目录中的应用后重试。','ShenView is still running. Close the app from this installation, then retry.');
  if WizardSilent then exit;
  if MsgBox(Tr('神羊看图正在运行。继续将关闭当前安装和目标目录中的全部窗口，并等待解码进程退出。请先保存未完成的操作。','ShenView is running. Continue to close all windows in the current and target installations and wait for decoder processes to exit. Save any unfinished work first.'),mbConfirmation,MB_OKCANCEL or MB_DEFBUTTON2) <> IDOK then exit;
  SetArrayLength(Handles,GetArrayLength(ApplicationProcesses));
  try
    for I := 0 to GetArrayLength(ApplicationProcesses)-1 do begin
      ProcessID := ApplicationProcesses[I];
      Handles[I] := OpenApplicationProcess($101000,False,ProcessID);
      if Handles[I] = 0 then exit;
    end;
    for I := 0 to GetArrayLength(ApplicationWindows)-1 do
      RequestApplicationClose(ApplicationWindows[I],$10,0,0);
    for Attempt := 0 to 99 do begin
      Exited := True;
      for I := 0 to GetArrayLength(Handles)-1 do
        if WaitApplicationExit(Handles[I],0) <> 0 then Exited := False;
      if Exited then begin Result := True; Failure := ''; exit; end;
      Sleep(100);
    end;
  finally
    for I := 0 to GetArrayLength(Handles)-1 do
      if Handles[I] <> 0 then CloseApplicationHandle(Handles[I]);
  end;
  Failure := Tr('应用尚未退出，请完成应用中的提示并关闭窗口后重试。','The app has not exited. Finish any prompts and close its windows, then retry.');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID <> OptionsPage.ID then exit;
  if Completed then exit;
  Result := False;
  if Working then exit;
  if Failed then begin
    Failed := False; Failure := ''; RecoveryOutcome := ''; RecoveryDirectory := '';
    Body.Visible := True; StateTitle.Visible := False; StateDetail.Visible := False;
    FailureReason.Visible := False; ResultMark.Visible := False;
    WizardForm.NextButton.Visible := True;
    Translate; Layout; exit;
  end;
  if (IsValidation and CheckForMutexes('ShenView.Inno7.Validation.Deploy')) or
    (not IsValidation and CheckForMutexes('Global\ShenView.Inno7.Deploy')) then begin
    Failure := Tr('另一个安装或卸载正在进行，请等它完成后重试。','Another installation or uninstall is running. Wait for it to finish, then retry.');
    SpaceLabel.Caption := Failure; Layout; exit;
  end;
  Failure := '';
  if Removing and PurgeData.Checked and not WizardSilent then
    if MsgBox(Tr('完全卸载将删除当前用户的设置、阅读记录、缓存，以及以下安装目录中的所有文件：',
      'Complete uninstall will delete current-user settings, reading history, caches and every file in this installation folder:') + #13#10#13#10 + EffectiveRoot + #13#10#13#10 +
      Tr('请先移出需要保留的文件。是否继续？','Move out any files you want to keep. Continue?'),mbConfirmation,MB_OKCANCEL or MB_DEFBUTTON2) <> IDOK then exit;
  if IsRepairableRoot(EffectiveRoot) then begin
    if WizardSilent then begin
      if ExpandConstant('{param:REPAIR|0}') <> '1' then begin Failure := Tr('检测到损坏的旧安装，静默修复需要 /REPAIR=1。','A damaged installation was found. Silent repair requires /REPAIR=1.'); PostAction(WizardForm.Handle,$10,0,0); exit; end;
    end else if MsgBox(Tr('检测到旧安装未清理完整，将在当前位置修复应用文件并重建安装记录。设置和个人文件会保留。是否继续？',
      'A previous installation was not fully removed. Repair application files and rebuild the installation record here? Settings and personal files will be kept.'),mbConfirmation,MB_OKCANCEL or MB_DEFBUTTON2) <> IDOK then exit;
  end;
  if (InstalledRoot <> '') and not Removing and not PathSame(InstalledRoot,EffectiveRoot) then begin
    if not WizardSilent then
      if MsgBox(Tr('将更换安装位置：','The installation location will change:') + #13#10#13#10 +
        InstalledRoot + #13#10 + Tr('迁移到：','Move to: ') + EffectiveRoot + #13#10#13#10 +
        Tr('可读取的设置和数据会复制到新目录，无法复制的文件保留在原处。安装成功后更新已有快捷方式并清理旧安装。是否继续？',
        'Readable settings and data will be copied. Files that cannot be copied stay at the original location. After a successful install, existing shortcuts will be updated and the old installation removed. Continue?'),
        mbConfirmation,MB_OKCANCEL or MB_DEFBUTTON2) <> IDOK then exit;
  end;
  if not CloseRunningApplication then begin
    SpaceLabel.Caption := Failure;
    Layout;
    if WizardSilent then PostAction(WizardForm.Handle,$10,0,0);
    exit;
  end;
  ActionName := OperationName;
  Working := True;
  Restoring := False; CloseWhenFinished := False;
  UpdateCloseButton;
  Body.Visible := False;
  StateTitle.Caption := ActionName + Tr('中…', ' in progress…');
  StateDetail.Caption := Tr('正在准备文件，请稍候。','Preparing files. Please wait.');
  ProgressText.Caption := '0%'; ProgressText.Visible := True;
  WizardForm.NextButton.Visible := False; WizardForm.CancelButton.Visible := False;
  StateTitle.Visible := True; StateDetail.Visible := True; Gauge.Visible := True;
  StateTitle.BringToFront; StateDetail.BringToFront; Gauge.BringToFront; ProgressText.BringToFront;
  WizardForm.NextButton.Enabled := False;
  { Keep the close event enabled so Alt+F4 can request a deferred close. The cancel control stays hidden. }
  WizardForm.CancelButton.Enabled := True;
  WizardForm.Refresh;
    if not RunWorker then begin
      ShowFailure('unchanged','');
    end;
  if WizardSilent then begin
    while Working do begin Sleep(100); PollState(0,0,0,0); end;
    Result := Completed;
    if not Completed then PostAction(WizardForm.Handle,$10,0,0);
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin Result := (PageID <> OptionsPage.ID) and (PageID <> wpFinished); end;

procedure CurPageChanged(CurPageID: Integer);
begin
  WizardForm.BackButton.Visible := False;
  if CurPageID = wpFinished then begin
    Body.Visible := False;
    StateTitle.Visible := True; StateDetail.Visible := True; Gauge.Visible := True;
    StateTitle.Caption := Tr('安装完成', 'Installation complete');
    if Removing then StateTitle.Caption := Tr('卸载完成','Uninstall complete');
    StateDetail.Caption := Tr('神羊看图已准备就绪。', 'ShenView is ready to use.');
    if Failure <> '' then StateDetail.Caption := Failure;
    if Removing then StateDetail.Caption := Tr('已卸载神羊看图。设置、阅读记录和个人文件已保留。', 'ShenView was removed. Settings, reading history and personal files were kept.');
    if Removing and PurgeData.Checked then StateDetail.Caption := Tr('已完全卸载。安装文件、快捷方式、关联注册项及当前用户的数据已移除。','Complete uninstall finished. Installation files, shortcuts, association records and current-user data were removed.');
    Gauge.Position := 100; Gauge.Visible := False; ProgressText.Visible := False;
    LogDetails.Visible := Failure <> '';
    WizardForm.NextButton.Visible := True;
    LaunchApp.Visible := not Removing;
    WizardForm.NextButton.Caption := Tr('完成', 'Finish');
    WizardForm.CancelButton.Visible := False;
  end else if CurPageID = OptionsPage.ID then Translate;
  Layout;
  if (CurPageID = wpFinished) and CloseWhenFinished and (Failure = '') then
    PostAction(WizardForm.Handle,$111,0,WizardForm.NextButton.Handle);
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  Cancel := not Working;
  Confirm := False;
  if Working then DeferClose(nil);
end;

procedure DeinitializeSetup;
var ErrorCode: Integer;
begin
  if PollTimer <> 0 then KillTimer(0,PollTimer);
  if CloseCallback <> 0 then begin RemoveSubclass(WizardForm.Handle,CloseCallback,6); CloseCallback := 0; end;
  { Windows can destroy controls after the script VM has gone away. }
  if HeaderCallback <> 0 then begin
    RemoveSubclass(Header.Handle,HeaderCallback,2);
    RemoveSubclass(Brand.Handle,HeaderCallback,2);
    HeaderCallback := 0;
  end;
  ClearAppearance;
  ClearWindowFrame;
  if Completed and not Removing and LaunchApp.Checked then
    ShellExec('', ApplicationExecutable(RootPath), '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;

function InitializeSetup: Boolean;
var Root, Clone: String; ErrorCode: Integer;
begin
  Result := True;
#ifdef MaintenanceBuild
  if WizardSilent then exit;
  if ExpandConstant('{param:DETACHED|0}') = '1' then exit;
  Root := ExpandConstant('{param:ROOT|}');
  if Root = '' then Root := ExpandConstant('{src}');
  if not IsOwned(Root) then begin Result := False; exit; end;
  Clone := ExpandConstant('{%TEMP}\ShenView-uninstall-') + GetDateTimeString('yyyymmddhhnnsszzz','-',':');
  if not ForceDirectories(Clone) then begin Result := False; exit; end;
  Clone := AddBackslash(Clone) + 'uninstall.exe';
  if not CopyMaintenance(ExpandConstant('{srcexe}'),Clone,True) then begin Result := False; exit; end;
  if not ShellExec('',Clone,'/DETACHED=1 /MODE=uninstall /ROOT="' + Root + '" ' + GetCmdTail,'',SW_SHOWNORMAL,ewNoWait,ErrorCode) then
    MsgBox(SysErrorMessage(ErrorCode),mbError,MB_OK);
  Result := False;
#endif
end;

procedure InitializeWizard;
var Values: TArrayOfString; I: Integer; ExistingFormats, ProfileRoot: String;
begin
  Removing := ExpandConstant('{param:MODE|install}') = 'uninstall';
  SetCurrentDir(ExpandConstant('{%TEMP}'));
#ifdef MaintenanceBuild
  Removing := True;
#endif
  OptionsPage := CreateCustomPage(wpWelcome, '', '');
  WizardForm.OuterNotebook.Visible := False;
  WizardForm.MainPanel.Visible := False;
  WizardForm.Bevel.Visible := False;
  WizardForm.Bevel1.Visible := False;
  WizardForm.Caption := 'ShenView Setup';
  WizardForm.BorderStyle := bsNone;
  FlowHeight := InstallFlowHeight;
  if Removing then begin FlowHeight := 380; I := 520; end else I := InstallFlowWidth;
  WizardForm.Width := WizardForm.Width + ScaleX(I) - WizardForm.ClientWidth;
  WizardForm.Height := WizardForm.Height + ScaleY(FlowHeight) - WizardForm.ClientHeight;
  Header := TPanel.Create(WizardForm); Header.Parent := WizardForm; Header.BevelOuter := bvNone;
  BrandIcon := TBitmapImage.Create(WizardForm); BrandIcon.Parent := Header;
  BrandIcon.Stretch := True; BrandIcon.BackColor := clNone;
  ExtractTemporaryFile('brand.png'); BrandIcon.PngImage.LoadFromFile(ExpandConstant('{tmp}\brand.png'));
  Brand := TextLabel(Header,88,20,240,32); Brand.Font.Size := 18; Brand.Font.Style := [fsBold];
  BrandVersion := TextLabel(Header,88,54,240,20); BrandVersion.Font.Size := 10;
  BrandVersion.StyleElements := [seClient,seBorder];
  HeaderCallback := CreateCallback(@HeaderMessages);
  Subclass(Header.Handle,HeaderCallback,2,0); Subclass(Brand.Handle,HeaderCallback,2,0);
  Body := TPanel.Create(WizardForm);
  Body.Parent := WizardForm;
  Body.BevelOuter := bvNone;
  Content := TPanel.Create(WizardForm);
  Content.Parent := Body;
  Content.BevelOuter := bvNone;
  WizardForm.Font.Size := 11;
  Content.Font.Size := 11;
  WizardForm.NextButton.Font.Size := 11;
  WizardForm.CancelButton.Font.Size := 11;
  if IsDarkInstallMode then begin
    WizardForm.Color := $002B2B2B; Header.Color := $002B2B2B; Body.Color := $002B2B2B; Content.Color := $002B2B2B;
  end else begin
    WizardForm.Color := clWhite; Header.Color := clWhite; Body.Color := clWhite; Content.Color := clWhite;
  end;
  Body.Visible := True;
  Title := TextLabel(Content,28,54,564,36); Title.Font.Size := 18; Title.Font.Style := [fsBold];
  Intro := TextLabel(Content,28,96,564,44);
  Intro.StyleElements := [seClient,seBorder];
  PathLabel := TextLabel(Content,28,153,564,22); PathLabel.Font.Style := [fsBold];
  PathFrame := TPanel.Create(WizardForm); PathFrame.Parent := Content; PathFrame.BevelOuter := bvNone;
  PathFrame.ParentBackground := False;
  PathFrame.StyleElements := [];
  if IsDarkInstallMode then PathFrame.Color := $00666666 else PathFrame.Color := $00B8B8B8;
  PathSurface := TPanel.Create(WizardForm); PathSurface.Parent := PathFrame; PathSurface.BevelOuter := bvNone;
  PathSurface.ParentBackground := False;
  PathSurface.StyleElements := [];
  if IsDarkInstallMode then PathSurface.Color := $00202020 else PathSurface.Color := clWhite;
  PathEdit := TNewPathEdit.Create(WizardForm); PathEdit.Parent := PathSurface; PathEdit.BorderStyle := bsNone;
  PathEdit.AutoSize := False;
  PathEdit.StyleElements := [];
  PathEdit.Color := PathSurface.Color;
  if IsDarkInstallMode then PathEdit.Font.Color := $00F3F3F3 else PathEdit.Font.Color := $00202020;
  PathEdit.Font.Size := 11;
  PathEdit.OnEnter := @PathFocus; PathEdit.OnExit := @PathFocus;
  RootPath := ExpandConstant('{param:ROOT|}');
#ifdef MaintenanceBuild
  if RootPath = '' then RootPath := ExpandConstant('{src}');
#endif
  if RootPath = '' then RootPath := RegisteredRoot;
  if RootPath = '' then begin
    RootPath := ExpandConstant('{commonpf64}\ShenView');
    if IsValidation then RootPath := ExpandConstant('{localappdata}\ShenView-Inno7-Validation\ShenView');
  end;
  PathEdit.Text := RootPath;
  RootPath := EffectiveRoot;
  InstalledRoot := RegisteredRoot;
  if Removing then InstalledRoot := RootPath;
  if (InstalledRoot = '') and IsOwned(RootPath) then InstalledRoot := RootPath;
  if (InstalledRoot = '') and IsRepairableRoot(RootPath) then InstalledRoot := RootPath;
  ProfileRoot := InstalledRoot;
  if ProfileRoot = '' then ProfileRoot := RootPath;
  PreviousExecutable := ApplicationExecutable(ProfileRoot);
  PreferenceFile := ExpandConstant('{localappdata}\ShenView\settings.json');
  if IsValidation then PreferenceFile := ProfileRoot + '\test-user\settings.json';
  UILanguage := ReadPreferenceLanguage(PreferenceFile);
  if UILanguage = '' then UILanguage := InstalledValue(ProfileRoot,'language','system');
  UILanguage := ExpandConstant('{param:UILANG|' + UILanguage + '}');
  PathEdit.ReadOnly := Removing;
  Browse := NewButton(Content,'',@BrowseClick); Browse.Enabled := not PathEdit.ReadOnly;
  UninstallLocation := TextLabel(Content,0,0,400,44); UninstallLocation.Font.Size := 11;
  SpaceLabel := TextLabel(Content,28,225,564,42);
  SpaceLabel.Font.Size := 10;
  SpaceLabel.StyleElements := [seClient,seBorder];
  FormatLabel := TextLabel(Content,28,274,564,22); FormatLabel.Font.Size := 10;
  AssociationPanel := TPanel.Create(WizardForm); AssociationPanel.Parent := Content; AssociationPanel.BevelOuter := bvNone;
  AssociationPanel.ParentBackground := False;
  AssociationPanel.StyleElements := [];
  AssociationSummary := TextLabel(AssociationPanel,16,20,360,24); AssociationSummary.Font.Size := 11;
  FooterLine := TPanel.Create(WizardForm); FooterLine.Parent := WizardForm; FooterLine.BevelOuter := bvNone; FooterLine.ParentBackground := False;
  OptionsLine := TPanel.Create(WizardForm); OptionsLine.Parent := Content; OptionsLine.BevelOuter := bvNone; OptionsLine.ParentBackground := False;
  FooterLine.StyleElements := []; OptionsLine.StyleElements := [];
  if IsDarkInstallMode then begin
    AssociationPanel.Color := $00333333; FooterLine.Color := $00444444; OptionsLine.Color := $00444444;
  end else begin
    AssociationPanel.Color := $00F7F7F7; FooterLine.Color := $00E8E8E8; OptionsLine.Color := $00E8E8E8;
  end;
  ImageList := TNewCheckListBox.Create(WizardForm); ImageList.Parent := Content;
  ArchiveList := TNewCheckListBox.Create(WizardForm); ArchiveList.Parent := Content;
  ExistingFormats := InstalledFormats(ProfileRoot);
  Values := StringSplit('{#ImageFormats}', [','], stAll);
  for I := 0 to GetArrayLength(Values)-1 do
    ImageList.AddCheckBox(Values[I],'',0, (not IsOwned(ProfileRoot)) or (Pos(',' + Values[I] + ',', ',' + ExistingFormats + ',') > 0), True, False,False,nil);
  Values := StringSplit('{#ArchiveFormats}', [','], stAll);
  for I := 0 to GetArrayLength(Values)-1 do
    ArchiveList.AddCheckBox(Values[I],'',0, Pos(',' + Values[I] + ',', ',' + ExistingFormats + ',') > 0, True, False, False, nil);
  Images := NewCheck(Content,True,@ToggleGroup); Archives := NewCheck(Content,False,@ToggleGroup);
  ImageList.OnClickCheck := @SyncSelection;
  ArchiveList.OnClickCheck := @SyncSelection;
  ImageDetails := NewButton(AssociationPanel,'',@ExpandOptions);
  ShortcutLabel := TextLabel(Content,0,0,400,24); ShortcutLabel.Font.Size := 10;
  ShortcutLabel.StyleElements := [seClient,seBorder];
  if IsDarkInstallMode then begin FormatLabel.Font.Color := $00B8B8B8; ShortcutLabel.Font.Color := $00B8B8B8; end
  else begin FormatLabel.Font.Color := $00606060; ShortcutLabel.Font.Color := $00606060; end;
  DesktopShortcut := NewCheck(Content,InitialShortcut(ProfileRoot,True),nil);
  StartShortcut := NewCheck(Content,InitialShortcut(ProfileRoot,False),nil);
  PurgeData := NewCheck(Content,ExpandConstant('{param:PURGE|0}') = '1',@ValidatePath);
  Language := TNewComboBox.Create(WizardForm); Language.Parent := Header; Language.Style := csDropDownList;
  Language.Items.Add('跟随系统 / System'); Language.Items.Add('简体中文'); Language.Items.Add('English');
  Language.Font.Size := 10;
  Language.ItemIndex := 0;
  if UILanguage = 'zh' then Language.ItemIndex := 1;
  if UILanguage = 'en' then Language.ItemIndex := 2;
  Language.OnChange := @ChangeLanguage;
  ProgressText := TextLabel(WizardForm,0,0,400,28); ProgressText.Alignment := taCenter; ProgressText.Visible := False;
  WorkingHint := TextLabel(WizardForm,0,0,400,40); WorkingHint.Visible := False; WorkingHint.Font.Size := 10;
  WorkingHint.StyleElements := [seClient,seBorder]; WorkingHint.Font.Color := ThemePaint($606060,$B8B8B8);
  LogDetails := NewButton(WizardForm,'',@ShowLog); LogDetails.Visible := False;
  DeferredClose := NewButton(WizardForm,Tr('完成后关闭','Close when done'),@DeferClose); DeferredClose.Visible := False;
  RecoveryDetails := NewButton(WizardForm,Tr('查看恢复副本','Recovery copy'),@OpenRecovery); RecoveryDetails.Visible := False;
  FailureReason := TextLabel(WizardForm,0,0,400,64); FailureReason.Visible := False;
  FailureReason.Font.Size := 10; FailureReason.Alignment := taCenter;
  FailureReason.StyleElements := [seClient,seBorder];
  FailureReason.Font.Color := ThemePaint($3434A8,$9CA8FF);
  StateTitle := TextLabel(WizardForm,28,80,564,42); StateTitle.Font.Size := 18; StateTitle.Font.Style := [fsBold]; StateTitle.Visible := False;
  StateDetail := TextLabel(WizardForm,28,140,564,120); StateDetail.Visible := False;
  StateDetail.StyleElements := [seClient,seBorder];
  StateDetail.Font.Color := ThemePaint($606060,$B8B8B8);
  StateTitle.Alignment := taCenter; StateDetail.Alignment := taCenter;
  Gauge := TNewProgressBar.Create(WizardForm); Gauge.Parent := WizardForm; Gauge.Max := 100; Gauge.Visible := False;
  LaunchApp := NewCheck(WizardForm,False,nil); LaunchApp.Visible := False;
  ResultMark := TextLabel(WizardForm,0,0,56,56); ResultMark.Visible := False;
  PathEdit.OnChange := @ValidatePath;
  WizardForm.OnResize := @ResizeWindow;
  Translate;
  Layout;
  StyleButton(WizardForm.NextButton,ButtonPrimary);
  StyleButton(WizardForm.CancelButton,ButtonSecondary);
  StyleButton(Browse,ButtonSecondary);
  StyleButton(LogDetails,ButtonSecondary);
  StyleButton(DeferredClose,ButtonSecondary);
  StyleButton(RecoveryDetails,ButtonText);
  StyleButton(ImageDetails,ButtonText);
  StyleResultMark(ResultMark);
  StyleAlignedCheck(LaunchApp);
  StyleWindowFrame;
  CloseCallback := CreateCallback(@CloseMessages);
  Subclass(WizardForm.Handle,CloseCallback,6,0);
end;
