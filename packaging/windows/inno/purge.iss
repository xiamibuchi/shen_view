[Code]
var
  Purging, PurgeReady: Boolean;
  UserDataRoot: String;
  FullFiles, FullDirectories, UserFiles, UserDirectories: TArrayOfString;

function SafePurgePath(const Path: String): Boolean;
var Parent: String; Attr: Cardinal;
begin
  Result := False; Parent := Path;
  while Length(Parent) > 3 do begin
    Attr := Attributes(Parent);
    if (Attr <> $FFFFFFFF) and ((Attr and $400) <> 0) then exit;
    Parent := ExtractFileDir(Parent);
  end;
  Result := True;
end;

function SnapshotPurgeTree(const Root, Backup, Relative: String; KeepMSIX: Boolean;
  var Files, Directories: TArrayOfString): Boolean;
var Find: TFindRec; Name, Path: String;
begin
  Result := False; Path := AddBackslash(Root) + Relative;
  if not SafePurgePath(Path) then begin Log('Cannot purge a reparse point: ' + Path); exit; end;
  if not DirExists(Path) then begin Result := not FileExists(Path); exit; end;
  if not ForceDirectories(AddBackslash(Backup) + Relative) then exit;
  AddName(Directories,Relative);
  if not FindFirst(Path + '*',Find) then begin Result := DLLGetLastError = 2; exit; end;
  try
    repeat
      if (Find.Name = '.') or (Find.Name = '..') then continue;
      if KeepMSIX and (Relative = '') and (CompareText(Find.Name,'MSIX') = 0) then continue;
      Name := Relative + Find.Name;
      if (Find.Attributes and $400) <> 0 then begin Log('Cannot purge a reparse point: ' + Root + '\' + Name); exit; end;
      if (Find.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then begin
        if not SnapshotPurgeTree(Root,Backup,Name + '\',KeepMSIX,Files,Directories) then exit;
      end else begin
        if not CopyRequired(Root + '\' + Name,Backup + '\' + Name) then exit;
        AddName(Files,Name);
      end;
    until not FindNext(Find);
    Result := True;
  finally FindClose(Find); end;
end;

function PreparePurge: Boolean;
begin
  Purging := ExpandConstant('{param:PURGE|0}') = '1'; Result := True;
  if not Purging then exit;
  Result := False;
  if not IsValidation then begin
    { Never resolve another administrator's profile after over-the-shoulder UAC. }
    if (InstallerUser = '') or (CompareText(InstallerUser,ExpandConstant('{param:OWNER|}')) <> 0) then begin
      Log('Full uninstall requires the original user identity.'); exit;
    end;
    UserDataRoot := ExpandConstant('{localappdata}\ShenView');
    if (Pos(Lowercase(AddBackslash(SourceRoot)),Lowercase(AddBackslash(UserDataRoot))) = 1) or
      (Pos(Lowercase(AddBackslash(UserDataRoot)),Lowercase(AddBackslash(SourceRoot))) = 1) then exit;
  end else UserDataRoot := SourceRoot + '.user-data';
  if not SnapshotPurgeTree(UserDataRoot,TransactionDirectory + '\purge-user','',True,UserFiles,UserDirectories) then exit;
  if not SnapshotPurgeTree(SourceRoot,TransactionDirectory + '\purge-root','',False,FullFiles,FullDirectories) then exit;
  if not SaveStringsToFile(TransactionDirectory + '\purge-root-files.txt',FullFiles,False) or
    not SaveStringsToFile(TransactionDirectory + '\purge-root-dirs.txt',FullDirectories,False) or
    not SaveStringsToFile(TransactionDirectory + '\purge-user-files.txt',UserFiles,False) or
    not SaveStringsToFile(TransactionDirectory + '\purge-user-dirs.txt',UserDirectories,False) or
    not SetIniString('purge','user-root',UserDataRoot,TransactionDirectory + '\journal.ini') then exit;
  PurgeReady := True; Result := True;
end;

function RemovePurgeTree(const Root: String; const Files, Directories: TArrayOfString;
  Deferred, KeepRoot: Boolean): Boolean;
var I: Integer; Path: String;
begin
  Result := False;
  for I := 0 to GetArrayLength(Files)-1 do begin
    if Deferred and PathSame(Files[I],'uninstall.exe') then continue;
    if not RelativeFile(Files[I]) then exit;
    Path := Root + '\' + Files[I];
    if not SafePurgePath(Path) then exit;
    if (Attributes(Path) <> $FFFFFFFF) and not DeleteFile(Path) then begin Log('Unable to remove: ' + Path); exit; end;
  end;
  for I := GetArrayLength(Directories)-1 downto 0 do begin
    if (Directories[I] = '') and (Deferred or KeepRoot) then continue;
    Path := RemoveBackslash(AddBackslash(Root) + Directories[I]);
    if not SafePurgePath(Path) then exit;
    if DirExists(Path) and not RemoveDir(Path) then begin Log('Unable to remove directory: ' + Path); exit; end;
  end;
  Result := True;
end;

function RestorePurgeTree(const Root, Backup: String; const Files, Directories: TArrayOfString): Boolean;
var I: Integer; OK: Boolean;
begin
  Result := True;
  for I := 0 to GetArrayLength(Directories)-1 do begin
    OK := SafePurgePath(AddBackslash(Root) + Directories[I]) and ForceDirectories(AddBackslash(Root) + Directories[I]); Result := OK and Result;
  end;
  for I := 0 to GetArrayLength(Files)-1 do begin
    OK := RestoreFile(Backup + '\' + Files[I],Root + '\' + Files[I]); Result := OK and Result;
  end;
end;

function RestorePurge: Boolean;
var OK: Boolean;
begin
  Result := True;
  if not PurgeReady then exit;
  Result := RestorePurgeTree(SourceRoot,TransactionDirectory + '\purge-root',FullFiles,FullDirectories);
  if UserDataRoot <> '' then begin
    OK := RestorePurgeTree(UserDataRoot,TransactionDirectory + '\purge-user',UserFiles,UserDirectories); Result := OK and Result;
  end;
end;
