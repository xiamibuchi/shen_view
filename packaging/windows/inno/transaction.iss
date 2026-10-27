[Code]
function OpenTransactionKey(Root: NativeUInt; const Key: String; Options, Access: Cardinal; var Handle: NativeUInt): Integer;
  external 'RegOpenKeyExW@advapi32.dll stdcall';
function CopyTransactionKey(Source: NativeUInt; const Key: String; Destination: NativeUInt): Integer;
  external 'RegCopyTreeW@advapi32.dll stdcall';
function CloseTransactionKey(Handle: NativeUInt): Integer;
  external 'RegCloseKey@advapi32.dll stdcall';
procedure NotifyRestoredAssociations(EventID, Flags: Cardinal; Item1, Item2: NativeUInt);
  external 'SHChangeNotify@shell32.dll stdcall';

var
  TransactionDirectory, SourceRoot, SourceDirectory, SourcePrefix, TargetRoot, RegistryBackup: String;
  TransactionCreated, TransactionReady, TransactionChanged, TransactionFinished, Restored: Boolean;
  DeferredMaintenance: Boolean;
  SourceFiles, NewFiles, Metadata, RegistryKeys, ShortcutPaths, CopiedData: TArrayOfString;
  DataCopied, DataSkipped: Integer;

#include "recovery-storage.iss"

function RegistryHive: NativeUInt;
begin
  if IsValidation then Result := $80000001 else Result := $80000002;
end;

function CopyRegistryTree(const Source, Destination: String): Boolean;
var FromKey, ToKey: NativeUInt;
begin
  Result := False;
  if not RegWriteStringValue(HKA64,Destination,'', '') then exit;
  if OpenTransactionKey(RegistryHive,Source,0,$20119,FromKey) <> 0 then exit;
  try
    if OpenTransactionKey(RegistryHive,Destination,0,$F013F,ToKey) <> 0 then exit;
    try Result := CopyTransactionKey(FromKey,'',ToKey) = 0;
    finally CloseTransactionKey(ToKey); end;
  finally CloseTransactionKey(FromKey); end;
end;

function RelativeFile(const Name: String): Boolean;
begin
  Result := (Name <> '') and (Pos('..',Name) = 0) and (Pos(':',Name) = 0);
  if Result then Result := (Name[1] <> #92) and (Name[1] <> '/');
end;

procedure AddName(var Names: TArrayOfString; const Name: String);
var N: Integer;
begin N := GetArrayLength(Names); SetArrayLength(Names,N+1); Names[N] := Name; end;

function CopyRequired(const FromFile, ToFile: String): Boolean;
var Parent: String; Attr: Cardinal;
begin
  Result := False;
  Parent := FromFile;
  while Length(Parent) > 3 do begin
    Attr := Attributes(Parent);
    if (Attr <> $FFFFFFFF) and ((Attr and $400) <> 0) then begin Log('Refusing reparse point: ' + Parent); exit; end;
    Parent := ExtractFileDir(Parent);
  end;
  Parent := ToFile;
  while Length(Parent) > 3 do begin
    Attr := Attributes(Parent);
    if (Attr <> $FFFFFFFF) and ((Attr and $400) <> 0) then begin Log('Refusing reparse point: ' + Parent); exit; end;
    Parent := ExtractFileDir(Parent);
  end;
  Result := ForceDirectories(ExtractFileDir(ToFile)) and FileCopy(FromFile,ToFile,False);
  if not Result then Log('Unable to copy transaction file: ' + FromFile + ' -> ' + ToFile);
end;

function RestoreFile(const FromFile, ToFile: String): Boolean;
begin
  Result := False;
  if FileExists(ToFile) then begin
    try
      if GetSHA256OfFile(FromFile) = GetSHA256OfFile(ToFile) then begin Result := True; exit; end;
    except Log('Unable to compare recovery destination: ' + ToFile); end;
  end;
  Result := CopyRequired(FromFile,ToFile);
end;

procedure FindOwnedShortcuts(const Directory: String);
var Find: TFindRec; Path, Target: String; Shell, Link: Variant; I: Integer; Known: Boolean;
begin
  if (SourceRoot = '') or not DirExists(Directory) or ((Attributes(Directory) and $400) <> 0) then exit;
  if not FindFirst(AddBackslash(Directory) + '*',Find) then exit;
  try
    repeat
      if (Find.Name = '.') or (Find.Name = '..') or ((Find.Attributes and $400) <> 0) then continue;
      Path := AddBackslash(Directory) + Find.Name;
      if (Find.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then begin FindOwnedShortcuts(Path); continue; end;
      if CompareText(ExtractFileExt(Path),'.lnk') <> 0 then continue;
      try
        Shell := CreateOleObject('WScript.Shell'); Link := Shell.CreateShortcut(Path); Target := Link.TargetPath;
        if not PathSame(Target,SourceDirectory + '\ShenView.exe') then continue;
        Known := False;
        for I := 0 to GetArrayLength(ShortcutPaths)-1 do if PathSame(ShortcutPaths[I],Path) then Known := True;
        if not Known then AddName(ShortcutPaths,Path);
      except Log('Unable to inspect shortcut: ' + Path); end;
    until not FindNext(Find);
  finally FindClose(Find); end;
end;

procedure TransactionNames;
var Formats: TArrayOfString; I: Integer;
begin
  Metadata := ['install.ini','payload-files.txt','uninstall.exe','shenview-install-root','maintain.exe','unins000.exe','unins000.dat','unins000.msg'];
  RegistryKeys := [UninstallKey,AssociationCapabilities];
  Formats := StringSplit('{#ImageFormats},{#ArchiveFormats}',[','],stAll);
  for I := 0 to GetArrayLength(Formats)-1 do
    AddName(RegistryKeys,AssociationPrefix + 'Classes\ShenView.Machine.' + Formats[I]);
  ShortcutPaths := [ExpandConstant('{autodesktop}\') + ShortcutName('') + '.lnk',
    ExpandConstant('{autoprograms}\') + ShortcutName('') + '.lnk'];
  if not IsValidation then begin
    AddName(ShortcutPaths,ExpandConstant('{userdesktop}\ShenView.lnk'));
    AddName(ShortcutPaths,ExpandConstant('{userprograms}\ShenView.lnk'));
  end;
  FindOwnedShortcuts(ExpandConstant('{autodesktop}'));
  FindOwnedShortcuts(ExpandConstant('{autoprograms}'));
  if not IsValidation then begin
    FindOwnedShortcuts(ExpandConstant('{userdesktop}'));
    FindOwnedShortcuts(ExpandConstant('{userprograms}'));
  end;
end;

function SnapshotTransaction: Boolean;
var I: Integer; Name, Key, Value: String; Formats: TArrayOfString;
begin
  SourceDirectory := PayloadDirectory(SourceRoot); SourcePrefix := '';
  if (SourceRoot <> '') and not PathSame(SourceDirectory,SourceRoot) then SourcePrefix := 'app\';
  Result := False; TransactionNames;
  if not PrepareRecoveryStorage then exit;
  RegistryBackup := 'Software\ShenView\InstallerTransactions\' + ExtractFileName(TransactionDirectory);
  if RegKeyExists(HKA64,RegistryBackup) then exit;
  if SourceRoot <> '' then begin
    LoadStringsFromFile(SourceRoot + '\payload-files.txt',SourceFiles);
    if (GetArrayLength(SourceFiles) = 0) and IsRepairableRoot(SourceRoot) then SourceFiles := NewFiles;
    if GetArrayLength(SourceFiles) = 0 then exit;
    for I := 0 to GetArrayLength(SourceFiles)-1 do begin
      Name := SourceFiles[I];
      if not RelativeFile(Name) then exit;
      if FileExists(SourceDirectory + '\' + Name) and
        not CopyRequired(SourceDirectory + '\' + Name,TransactionDirectory + '\files\' + SourcePrefix + Name) then exit;
    end;
    if FileExists(SourceDirectory + '\installation-mode') and
      not CopyRequired(SourceDirectory + '\installation-mode',TransactionDirectory + '\files\' + SourcePrefix + 'installation-mode') then exit;
    for I := 0 to GetArrayLength(Metadata)-1 do begin
      Name := Metadata[I];
      if FileExists(SourceRoot + '\' + Name) and not CopyRequired(SourceRoot + '\' + Name,TransactionDirectory + '\files\' + Name) then exit;
    end;
  end;
  for I := 0 to GetArrayLength(RegistryKeys)-1 do begin
    Key := RegistryKeys[I];
    if RegKeyExists(HKA64,Key) then begin
      if not CopyRegistryTree(Key,RegistryBackup + '\key' + IntToStr(I)) then exit;
      SetIniBool('registry',IntToStr(I),True,TransactionDirectory + '\journal.ini');
    end;
  end;
  if not IsValidation then begin
    Key := 'Software\RegisteredApplications';
    if RegQueryStringValue(HKLM64,Key,'ShenView.Machine',Value) then begin
      SetIniBool('values','registered-present',True,TransactionDirectory + '\journal.ini');
      SetIniString('values','registered',Value,TransactionDirectory + '\journal.ini');
    end;
  end;
  Formats := StringSplit('{#ImageFormats},{#ArchiveFormats}',[','],stAll);
  for I := 0 to GetArrayLength(Formats)-1 do begin
    Key := AssociationPrefix + 'Classes\.' + Formats[I] + '\OpenWithProgids';
    if RegValueExists(InstallationHive,Key,'ShenView.Machine.' + Formats[I]) then
      SetIniBool('openwith',Formats[I],True,TransactionDirectory + '\journal.ini');
  end;
  for I := 0 to GetArrayLength(ShortcutPaths)-1 do
    if FileExists(ShortcutPaths[I]) then
      if not CopyRequired(ShortcutPaths[I],TransactionDirectory + '\shortcut' + IntToStr(I) + '.lnk') then exit;
  SaveStringsToFile(TransactionDirectory + '\source-files.txt',SourceFiles,False);
  SetIniString('transaction','source',SourceRoot,TransactionDirectory + '\journal.ini');
  SetIniString('transaction','target',TargetRoot,TransactionDirectory + '\journal.ini');
  SetIniString('transaction','state','prepared',TransactionDirectory + '\journal.ini');
  TransactionReady := True; Result := True;
end;

function RemovePayloadFiles(const Root, Directory: String; const Files: TArrayOfString): Boolean;
var I: Integer; Path, Parent: String;
begin
  Result := True;
  for I := 0 to GetArrayLength(Files)-1 do begin
    if not RelativeFile(Files[I]) then begin Result := False; continue; end;
    Path := Directory + '\' + Files[I];
    if FileExists(Path) and not DeleteFile(Path) then Result := False;
    Parent := ExtractFileDir(Path);
    while Length(Parent) > Length(Root) do begin RemoveDir(Parent); Parent := ExtractFileDir(Parent); end;
  end;
  if FileExists(Directory + '\installation-mode') and not DeleteFile(Directory + '\installation-mode') then Result := False;
  if not PathSame(Directory,Root) then RemoveDir(Directory);
end;

function RemoveManagedFiles(const Root, Directory: String; const Files: TArrayOfString): Boolean;
var I: Integer; Path: String;
begin
  Result := RemovePayloadFiles(Root,Directory,Files);
  for I := 0 to GetArrayLength(Metadata)-1 do begin
    if DeferredMaintenance and (Metadata[I] = 'uninstall.exe') then continue;
    Path := Root + '\' + Metadata[I];
    if FileExists(Path) and not DeleteFile(Path) then Result := False;
  end;
  RemoveDir(Root);
end;

function RemoveObsoletePayload: Boolean;
var I, J: Integer; Current: Boolean; Path, Parent: String;
begin
  Result := True;
  for I := 0 to GetArrayLength(SourceFiles)-1 do begin
    Current := False;
    for J := 0 to GetArrayLength(NewFiles)-1 do
      if PathSame(SourceFiles[I],NewFiles[J]) then begin Current := True; break; end;
    if Current then continue;
    if not RelativeFile(SourceFiles[I]) then begin Result := False; continue; end;
    Path := SourceDirectory + '\' + SourceFiles[I];
    if not RecoveryPathAllowed(Path) then begin Result := False; continue; end;
    if FileExists(Path) and not DeleteFile(Path) then Result := False;
    Parent := ExtractFileDir(Path);
    while Length(Parent) > Length(SourceRoot) do begin RemoveDir(Parent); Parent := ExtractFileDir(Parent); end;
  end;
end;

procedure CopyPersonalData(const Relative: String);
var Find: TFindRec; Name, TargetName, FromFile, ToFile: String; I: Integer; Managed: Boolean;
begin
  if not FindFirst(AddBackslash(SourceRoot) + Relative + '*',Find) then begin
    DataSkipped := DataSkipped + 1; Log('Unable to read personal data directory: ' + SourceRoot + '\' + Relative); exit;
  end;
  try
    repeat
      if (Find.Name = '.') or (Find.Name = '..') then continue;
      Name := Relative + Find.Name; FromFile := SourceRoot + '\' + Name;
      TargetName := Name;
      if (SourcePrefix <> '') and (Pos(Lowercase(SourcePrefix),Lowercase(Name)) = 1) then TargetName := Copy(Name,Length(SourcePrefix)+1,Length(Name));
      ToFile := TargetRoot + '\' + TargetName;
      if (Find.Attributes and $400) <> 0 then begin DataSkipped := DataSkipped + 1; Log('Skipping reparse point: ' + FromFile); continue; end;
      if (Find.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then begin CopyPersonalData(Name + '\'); continue; end;
      Managed := False;
      for I := 0 to GetArrayLength(Metadata)-1 do if PathSame(Name,Metadata[I]) then Managed := True;
      for I := 0 to GetArrayLength(SourceFiles)-1 do if PathSame(Name,SourcePrefix + SourceFiles[I]) then Managed := True;
      if PathSame(Name,SourcePrefix + 'installation-mode') then Managed := True;
      if Managed or PathSame(FromFile,ToFile) then continue;
      if FileExists(ToFile) or not CopyRequired(FromFile,ToFile) then begin
        DataSkipped := DataSkipped + 1; Log('Personal data kept at original location: ' + FromFile);
      end else begin DataCopied := DataCopied + 1; AddName(CopiedData,TargetName); end;
    until not FindNext(Find);
  finally FindClose(Find); end;
end;

function RestoreTransaction: Boolean;
var I: Integer; Name, Key, Value, Parent: String; Formats: TArrayOfString; OK: Boolean;
begin
  Result := True;
  if not TransactionReady or not TransactionChanged or TransactionFinished or Restored then exit;
  Log('Restoring transaction: ' + TransactionDirectory);
#ifdef ValidationBuild
  if ExpandConstant('{param:FAIL|0}') = 'restore' then begin
    SetIniString('transaction','state','recovery-failed',TransactionDirectory + '\journal.ini');
    Result := False; exit;
  end;
#endif
  { Inno also rolls back its own file operations; this snapshot restores the previous installation and external state. }
  if TargetRoot <> '' then Result := RemoveManagedFiles(TargetRoot,TargetRoot,NewFiles);
  for I := 0 to GetArrayLength(CopiedData)-1 do begin
    Name := TargetRoot + '\' + CopiedData[I];
    if FileExists(Name) then begin OK := DeleteFile(Name); Result := OK and Result; end;
    Parent := ExtractFileDir(Name);
    while Length(Parent) > Length(TargetRoot) do begin RemoveDir(Parent); Parent := ExtractFileDir(Parent); end;
  end;
  if TargetRoot <> '' then RemoveDir(TargetRoot);
  if SourceRoot <> '' then begin
    for I := 0 to GetArrayLength(SourceFiles)-1 do begin
      Name := SourcePrefix + SourceFiles[I];
      if FileExists(TransactionDirectory + '\files\' + Name) then begin
        OK := RestoreFile(TransactionDirectory + '\files\' + Name,SourceRoot + '\' + Name); Result := OK and Result;
      end;
    end;
    Name := SourcePrefix + 'installation-mode';
    if FileExists(TransactionDirectory + '\files\' + Name) then begin
      OK := RestoreFile(TransactionDirectory + '\files\' + Name,SourceRoot + '\' + Name); Result := OK and Result;
    end;
    for I := 0 to GetArrayLength(Metadata)-1 do begin
      Name := Metadata[I];
      if FileExists(TransactionDirectory + '\files\' + Name) then begin
        OK := RestoreFile(TransactionDirectory + '\files\' + Name,SourceRoot + '\' + Name); Result := OK and Result;
      end;
    end;
  end;
  for I := 0 to GetArrayLength(RegistryKeys)-1 do begin
    Key := RegistryKeys[I];
    if RegKeyExists(HKA64,Key) then begin OK := RegDeleteKeyIncludingSubkeys(HKA64,Key); Result := OK and Result; end;
    if GetIniBool('registry',IntToStr(I),False,TransactionDirectory + '\journal.ini') then begin
      OK := CopyRegistryTree(RegistryBackup + '\key' + IntToStr(I),Key); Result := OK and Result;
    end;
  end;
  if not IsValidation then begin
    Key := 'Software\RegisteredApplications';
    if GetIniBool('values','registered-present',False,TransactionDirectory + '\journal.ini') then begin
      Value := GetIniString('values','registered','',TransactionDirectory + '\journal.ini');
      OK := RegWriteStringValue(HKLM64,Key,'ShenView.Machine',Value); Result := OK and Result;
    end else RegDeleteValue(HKLM64,Key,'ShenView.Machine');
  end;
  Formats := StringSplit('{#ImageFormats},{#ArchiveFormats}',[','],stAll);
  for I := 0 to GetArrayLength(Formats)-1 do begin
    Key := AssociationPrefix + 'Classes\.' + Formats[I] + '\OpenWithProgids';
    if GetIniBool('openwith',Formats[I],False,TransactionDirectory + '\journal.ini') then begin
      OK := RegWriteStringValue(InstallationHive,Key,'ShenView.Machine.' + Formats[I],''); Result := OK and Result;
    end else begin
      RegDeleteValue(InstallationHive,Key,'ShenView.Machine.' + Formats[I]);
      RegDeleteKeyIfEmpty(InstallationHive,Key);
      RegDeleteKeyIfEmpty(InstallationHive,AssociationPrefix + 'Classes\.' + Formats[I]);
    end;
  end;
  for I := 0 to GetArrayLength(ShortcutPaths)-1 do begin
    Name := TransactionDirectory + '\shortcut' + IntToStr(I) + '.lnk';
    if FileExists(Name) then begin OK := RestoreFile(Name,ShortcutPaths[I]); Result := OK and Result; end
    else if FileExists(ShortcutPaths[I]) then begin OK := DeleteFile(ShortcutPaths[I]); Result := OK and Result; end;
  end;
  Restored := Result;
  if Result then begin
    SetIniString('transaction','state','restored',TransactionDirectory + '\journal.ini');
    RegDeleteKeyIncludingSubkeys(HKA64,RegistryBackup);
  end else SetIniString('transaction','state','recovery-failed',TransactionDirectory + '\journal.ini');
  if not IsValidation then NotifyRestoredAssociations($8000000,0,0,0);
end;

procedure CommitTransaction;
begin
  TransactionFinished := True;
  SetIniString('transaction','state','committed',TransactionDirectory + '\journal.ini');
  CleanupTransaction;
end;
