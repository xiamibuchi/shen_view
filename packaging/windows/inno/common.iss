[Code]
function ReadInstallerUser(Format: Cardinal; Buffer: String; var Size: Cardinal): Boolean;
  external 'GetUserNameExW@secur32.dll stdcall';

function InstallerUser: String;
var Size: Cardinal; Buffer: String;
begin
  Size := 512; Buffer := StringOfChar(#0,Size); Result := '';
  if ReadInstallerUser(2,Buffer,Size) then Result := Copy(Buffer,1,Size);
end;

function Attributes(const Path: String): Cardinal;
  external 'GetFileAttributesW@kernel32.dll stdcall';
function DriveType(const Path: String): Cardinal;
  external 'GetDriveTypeW@kernel32.dll stdcall';
function MoveInstallationPath(const Source, Destination: String; Flags: Cardinal): Boolean;
  external 'MoveFileExW@kernel32.dll stdcall';
function OpenStatusFile(const Name: String; Access, Sharing: Cardinal; Security: NativeUInt; Creation, Flags: Cardinal; TemplateFile: NativeUInt): NativeUInt;
  external 'CreateFileW@kernel32.dll stdcall';
function WriteStatusFile(Handle: NativeUInt; Buffer: String; Size: Cardinal; var Written: Cardinal; Overlapped: NativeUInt): Boolean;
  external 'WriteFile@kernel32.dll stdcall';
function CloseStatusFile(Handle: NativeUInt): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

var MessageLanguage: String;

function Choice(const Chinese, English: String): String;
begin
  if (MessageLanguage = 'zh') or ((MessageLanguage = '') and (ActiveLanguage = 'zh')) then Result := Chinese else Result := English;
end;

function IsValidation: Boolean;
begin
#ifdef ValidationBuild
  Result := True;
#else
  Result := False;
#endif
end;

function Identity: String;
begin
  if IsValidation then Result := 'ShenView.Inno7.Validation' else Result := 'ShenView.Inno7';
end;

function ProductIdentity(Param: String): String;
begin Result := Identity; end;

function InstallationHive: NativeUInt;
begin
  if IsValidation then Result := HKCU64 else Result := HKLM64;
end;

function UninstallKey: String;
begin Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + Identity + '_is1'; end;

function RecordedRoot: String;
begin
  Result := '';
  RegQueryStringValue(InstallationHive,UninstallKey,'InstallLocation',Result);
  Result := RemoveBackslash(Result);
end;

function IsLegacyOwned(const Root: String): Boolean;
begin
  Result := (Root <> '') and (GetIniString('install','identity','',AddBackslash(Root) + 'install.ini') = Identity);
end;

function IsOwned(const Root: String): Boolean;
var Recorded: String;
begin
  Recorded := RecordedRoot;
  Result := (Root <> '') and (((Recorded <> '') and PathSame(Root,Recorded)) or IsLegacyOwned(Root));
end;

function InstalledValue(const Root, Name, Default: String): String;
var ValueName: String;
begin
  Result := Default;
  ValueName := Name;
  if Name = 'version' then ValueName := 'DisplayVersion';
  if Name = 'language' then ValueName := 'Inno Setup: Language';
  if Name = 'tasks' then ValueName := 'Inno Setup: Selected Tasks';
  if (RecordedRoot <> '') and PathSame(Root,RecordedRoot) then
    if RegQueryStringValue(InstallationHive,UninstallKey,ValueName,Result) then exit;
  Result := Default;
  if IsLegacyOwned(Root) then Result := GetIniString('install',Name,Default,AddBackslash(Root) + 'install.ini');
end;

function PayloadDirectory(const Root: String): String;
begin
  Result := Root;
  if FileExists(AddBackslash(Root) + 'ShenView.exe') then exit;
  if FileExists(AddBackslash(Root) + 'app\ShenView.exe') then Result := AddBackslash(Root) + 'app';
end;

function ApplicationExecutable(const Root: String): String;
begin Result := AddBackslash(PayloadDirectory(Root)) + 'ShenView.exe'; end;

function AssociationPrefix: String;
begin
  Result := 'Software\';
  if IsValidation then Result := 'Software\ShenView\Inno7Validation\';
end;

function AssociationCapabilities: String;
begin Result := AssociationPrefix + 'ShenView\Associations\ShenView.Machine'; end;

function InstalledFormats(const Root: String): String;
var Formats: TArrayOfString; I: Integer; Executable, Command, Value, ProgID, Capabilities: String;
begin
  Result := '';
  Executable := ApplicationExecutable(Root);
  Capabilities := AssociationCapabilities;
  if IsValidation and IsLegacyOwned(Root) and not RegKeyExists(InstallationHive,Capabilities) then begin
    Result := InstalledValue(Root,'formats',''); exit;
  end;
  if not RegQueryStringValue(InstallationHive,Capabilities,'ApplicationPath',Value) or not PathSame(Value,Executable) then exit;
  Formats := StringSplit('{#ImageFormats},{#ArchiveFormats}',[','],stAll);
  for I := 0 to GetArrayLength(Formats)-1 do begin
    ProgID := 'ShenView.Machine.' + Formats[I];
    if not RegQueryStringValue(InstallationHive,Capabilities + '\FileAssociations','.' + Formats[I],Value) or (Value <> ProgID) then continue;
    if not RegValueExists(InstallationHive,AssociationPrefix + 'Classes\.' + Formats[I] + '\OpenWithProgids',ProgID) then continue;
    if not RegQueryStringValue(InstallationHive,AssociationPrefix + 'Classes\' + ProgID + '\shell\open\command','',Command) then continue;
    if CompareText(Command,'"' + Executable + '" -- "%1"') <> 0 then continue;
    if Result <> '' then Result := Result + ',';
    Result := Result + Formats[I];
  end;
end;

procedure SetValidationFormats(const Root, Selected: String);
var Formats: TArrayOfString; I: Integer; ExtensionKey, ProgID, Capabilities, Executable: String;
begin
  if not IsValidation then exit;
  { Mirror application registrations under an isolated HKCU subtree; never register validation files with Windows. }
  Formats := StringSplit('{#ImageFormats},{#ArchiveFormats}',[','],stAll);
  Capabilities := AssociationCapabilities; Executable := ApplicationExecutable(Root);
  RegDeleteKeyIncludingSubkeys(InstallationHive,Capabilities);
  if Selected <> '' then
    if not RegWriteStringValue(InstallationHive,Capabilities,'ApplicationPath',Executable) then RaiseException('Unable to write validation associations.');
  for I := 0 to GetArrayLength(Formats)-1 do begin
    ProgID := 'ShenView.Machine.' + Formats[I];
    ExtensionKey := AssociationPrefix + 'Classes\.' + Formats[I] + '\OpenWithProgids';
    RegDeleteKeyIncludingSubkeys(InstallationHive,AssociationPrefix + 'Classes\' + ProgID);
    RegDeleteValue(InstallationHive,ExtensionKey,ProgID);
    RegDeleteKeyIfEmpty(InstallationHive,ExtensionKey);
    RegDeleteKeyIfEmpty(InstallationHive,AssociationPrefix + 'Classes\.' + Formats[I]);
    if Pos(',' + Formats[I] + ',',',' + Selected + ',') > 0 then begin
      if not RegWriteStringValue(InstallationHive,Capabilities + '\FileAssociations','.' + Formats[I],ProgID) or
        not RegWriteStringValue(InstallationHive,AssociationPrefix + 'Classes\' + ProgID + '\shell\open\command','', '"' + Executable + '" -- "%1"') or
        not RegWriteStringValue(InstallationHive,ExtensionKey,ProgID,'') then RaiseException('Unable to write validation formats.');
    end;
  end;
end;

function IsPreservedDataRoot(const Root: String): Boolean;
var Marker: AnsiString;
begin Result := LoadStringFromFile(AddBackslash(Root) + '.shenview-user-data',Marker) and (String(Marker) = Identity); end;

function VersionBlockSize(const FileName: String; var Handle: Cardinal): Cardinal;
  external 'GetFileVersionInfoSizeW@version.dll stdcall';
function ReadVersionBlock(const FileName: String; Handle, Size: Cardinal; Buffer: NativeUInt): Boolean;
  external 'GetFileVersionInfoW@version.dll stdcall';
function QueryVersionBlock(Buffer: NativeUInt; const Name: String; var Value: NativeUInt; var Length: Cardinal): Boolean;
  external 'VerQueryValueW@version.dll stdcall';
function AllocateVersionBlock(Flags: Cardinal; Bytes: NativeUInt): NativeUInt;
  external 'GlobalAlloc@kernel32.dll stdcall';
function FreeVersionBlock(Buffer: NativeUInt): NativeUInt;
  external 'GlobalFree@kernel32.dll stdcall';
procedure CopyVersionText(Destination: String; Source, Bytes: NativeUInt);
  external 'RtlMoveMemory@kernel32.dll stdcall';

function ReadProductField(const FileName, Field: String; var Value: String): Boolean;
var Size, Ignored, Length: Cardinal; Buffer, Text: NativeUInt;
begin
  Result := False; Size := VersionBlockSize(FileName,Ignored);
  if (Size = 0) or (Size > 1048576) then exit;
  Buffer := AllocateVersionBlock(0,Size);
  if Buffer = 0 then exit;
  try
    if not ReadVersionBlock(FileName,0,Size,Buffer) then exit;
    if not QueryVersionBlock(Buffer,'\StringFileInfo\040904e4\' + Field,Text,Length) then exit;
    if (Length = 0) or (Length > 1024) then exit;
    Value := StringOfChar(#0,Length); CopyVersionText(Value,Text,Length*2); SetLength(Value,Length-1);
    Result := True;
  finally FreeVersionBlock(Buffer); end;
end;

function IsRepairableRoot(const Root: String): Boolean;
var Product, Company, Original: String;
begin
  Result := False;
  if IsOwned(Root) then exit;
  if IsValidation and not IsPreservedDataRoot(Root) then exit;
  if not ReadProductField(ApplicationExecutable(Root),'ProductName',Product) then exit;
  if not ReadProductField(ApplicationExecutable(Root),'CompanyName',Company) then exit;
  if not ReadProductField(ApplicationExecutable(Root),'OriginalFilename',Original) then exit;
  Result := (Product = 'ShenView') and (Company = 'ShenView') and (Original = 'ShenView.exe');
end;

function RegisteredRoot: String;
begin
  Result := RecordedRoot;
  if not DirExists(Result) then Result := '';
end;

function InstalledVersion(const Root: String): String;
begin
  Result := InstalledValue(Root,'version','');
  if (Result = '') and IsRepairableRoot(Root) then GetVersionNumbersString(ApplicationExecutable(Root),Result);
end;

function LegacyRoot: String;
begin
  Result := '';
  if IsValidation then exit;
  RegQueryStringValue(HKLM64,'Software\ShenView\Installer','Path',Result);
  if Result = '' then RegQueryStringValue(HKCU64,'Software\ShenView\Installer','Path',Result);
  Result := RemoveBackslash(Result);
  if not DirExists(Result) then Result := '';
end;

function SafeRoot(const Input: String; var Root, Error: String): Boolean;
var
  Parent, Leaf: String;
  Attr: Cardinal;
  Find: TFindRec;
begin
  Result := False;
  Error := Choice('请选择本地磁盘上的普通文件夹。', 'Choose an ordinary folder on a local disk.');
  Root := RemoveBackslash(Trim(Input));
  if Length(Root) < 4 then exit;
  if (Root[2] <> ':') or (Root[3] <> #92) then exit;
  if PathHasInvalidCharacters(Root,True) or (DriveType(Copy(Root,1,3)) <> 3) then exit;
  if (Pos('..', Root) > 0) or (Pos('*', Root) > 0) or (Pos('?', Root) > 0) then exit;
  Root := RemoveBackslash(ExpandFileName(Root));
  if (Length(Root) < 4) or (Length(Root) > 160) then exit;
  if (CompareText(Root, ExpandConstant('{win}')) = 0) or
    (Pos(Lowercase(AddBackslash(ExpandConstant('{win}'))), Lowercase(AddBackslash(Root))) = 1) or
    (CompareText(Root, ExpandConstant('{commonappdata}')) = 0) or
    (Pos('$recycle.bin', Lowercase(Root)) > 0) or
    (Pos('system volume information', Lowercase(Root)) > 0) or
    (Pos('windowsapps', Lowercase(Root)) > 0) or
    (Pos('common files', Lowercase(Root)) > 0) then exit;
  Parent := Root;
  while Length(Parent) > 3 do begin
    Attr := Attributes(Parent);
    if (Attr <> $FFFFFFFF) and ((Attr and $400) <> 0) then exit;
    Leaf := ExtractFileName(Parent);
    if (Leaf = '') or (Leaf[Length(Leaf)] = '.') or (Leaf[Length(Leaf)] = ' ') then exit;
    Leaf := Lowercase(Leaf);
    if Pos('.',Leaf) > 0 then Leaf := Copy(Leaf,1,Pos('.',Leaf)-1);
    if (Leaf = 'con') or (Leaf = 'prn') or (Leaf = 'aux') or (Leaf = 'nul') then exit;
    if (Length(Leaf) = 4) and ((Copy(Leaf,1,3) = 'com') or (Copy(Leaf,1,3) = 'lpt')) and (Leaf[4] >= '1') and (Leaf[4] <= '9') then exit;
    Parent := ExtractFileDir(Parent);
  end;
  if DirExists(Root) and not IsOwned(Root) and not IsPreservedDataRoot(Root) and not IsRepairableRoot(Root) then begin
    Error := Choice('该目录已有其他文件，请选择空目录。', 'This folder contains unrelated files. Choose an empty folder.');
    if FindFirst(AddBackslash(Root) + '*', Find) then begin
      try
        repeat
          if (Find.Name <> '.') and (Find.Name <> '..') then exit;
        until not FindNext(Find);
      finally
        FindClose(Find);
      end;
    end;
  end;
  Error := '';
  Result := True;
end;

function CompareVersion(const Left, Right: String): Integer;
var
  A, B: TArrayOfString;
  I, X, Y: Integer;
begin
  A := StringSplit(Left, ['.'], stAll);
  B := StringSplit(Right, ['.'], stAll);
  Result := 0;
  for I := 0 to 3 do begin
    X := 0; Y := 0;
    if I < GetArrayLength(A) then X := StrToIntDef(A[I], 0);
    if I < GetArrayLength(B) then Y := StrToIntDef(B[I], 0);
    if X < Y then begin Result := -1; exit; end;
    if X > Y then begin Result := 1; exit; end;
  end;
end;

function SessionFile: String;
begin
  Result := ExpandConstant('{param:SESSION|}');
  if Result <> '' then Result := AddBackslash(Result) + 'status.ini';
end;

procedure ReportStateRecord(const State, Message: String; const Progress, Skipped: Integer; const Recovery, RecoveryPath: String);
var F, Data: String; Handle: NativeUInt; Written: Cardinal; Saved: Boolean; Attempt: Integer;
begin
  F := SessionFile;
  if F = '' then exit;
  { Unicode INI and replacement keep localized messages intact across processes. }
  Data := #$FEFF + '[result]'#13#10 + 'message=' + Message + #13#10 + 'progress=' + IntToStr(Progress) + #13#10 + 'state=' + State + #13#10 + 'skipped=' + IntToStr(Skipped) + #13#10 +
    'recovery=' + Recovery + #13#10 + 'recovery-path=' + RecoveryPath + #13#10;
  Handle := OpenStatusFile(F + '.pending',$40000000,1,0,2,0,0);
  if Handle = NativeUInt(-1) then exit;
  Saved := WriteStatusFile(Handle,Data,Length(Data)*2,Written,0);
  CloseStatusFile(Handle);
  if Saved and (Written = Length(Data)*2) then begin
    { GetIniString in the polling frontend briefly opens the destination without delete sharing. }
    for Attempt := 0 to 79 do begin
      if MoveInstallationPath(F + '.pending',F,1) then exit;
      Sleep(25);
    end;
    Log('Unable to publish installer status; the complete pending record is retained: ' + F + '.pending');
  end;
end;

procedure ReportStateDetails(const State, Message: String; const Progress, Skipped: Integer);
begin ReportStateRecord(State,Message,Progress,Skipped,'',''); end;

procedure ReportState(const State, Message: String; const Progress: Integer);
begin ReportStateDetails(State,Message,Progress,0); end;
