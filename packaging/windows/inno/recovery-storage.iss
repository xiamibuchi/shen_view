[Code]
type
  TRecoveryGuid = record
    A: Cardinal;
    B, C: Word;
    D: array[0..7] of Byte;
  end;
  { These installers are x64; SECURITY_ATTRIBUTES has pointer alignment. }
  TRecoverySecurity = record
    Size, Padding: Cardinal;
    Descriptor: NativeUInt;
    InheritHandle, PaddingEnd: Cardinal;
  end;

function CreateRecoveryGuid(var Value: TRecoveryGuid): Integer;
  external 'CoCreateGuid@ole32.dll stdcall';
function RecoveryGuidText(const Value: TRecoveryGuid; Buffer: String; Size: Integer): Integer;
  external 'StringFromGUID2@ole32.dll stdcall';
function ConvertRecoverySecurity(const Text: String; Revision: Cardinal; var Descriptor: NativeUInt; Size: NativeUInt): Boolean;
  external 'ConvertStringSecurityDescriptorToSecurityDescriptorW@advapi32.dll stdcall';
function ApplyRecoverySecurity(const Path: String; Information: Cardinal; Descriptor: NativeUInt): Boolean;
  external 'SetFileSecurityW@advapi32.dll stdcall';
function ReleaseRecoverySecurity(Descriptor: NativeUInt): NativeUInt;
  external 'LocalFree@kernel32.dll stdcall';
function CreateRecoveryFolder(const Path: String; var Security: TRecoverySecurity): Boolean;
  external 'CreateDirectoryW@kernel32.dll stdcall';

function RecoveryRoot: String;
begin
  Result := ExpandConstant('{commonappdata}\ShenView\Installer\Transactions');
  if IsValidation then Result := ExpandConstant('{localappdata}\ShenView-Inno7-Validation\Installer\Transactions');
end;

function RecoveryPathAllowed(const Path: String): Boolean;
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

function PrepareRecoveryStorage: Boolean;
var Root, Parent, ProductRoot, Name, SDDL: String; Information: Cardinal; GUID: TRecoveryGuid; Security: TRecoverySecurity;
begin
  Result := False; Root := RecoveryRoot;
  if not RecoveryPathAllowed(Root) then exit;
  Parent := ExtractFileDir(Root);
  ProductRoot := ExtractFileDir(Parent);
  SDDL := 'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'; Information := $80000005;
  if IsValidation then begin
    SDDL := 'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;OW)'; Information := $80000004;
  end;
  Security.Size := 24; Security.Padding := 0; Security.InheritHandle := 0; Security.PaddingEnd := 0;
  if not ConvertRecoverySecurity(SDDL,1,Security.Descriptor,0) then exit;
  try
    if not DirExists(ProductRoot) and not CreateRecoveryFolder(ProductRoot,Security) then exit;
    if not IsValidation and not ApplyRecoverySecurity(ProductRoot,Information,Security.Descriptor) then exit;
    if not DirExists(Parent) and not CreateRecoveryFolder(Parent,Security) then exit;
    if not RecoveryPathAllowed(Parent) or not ApplyRecoverySecurity(Parent,Information,Security.Descriptor) then exit;
    if not DirExists(Root) and not CreateRecoveryFolder(Root,Security) then exit;
    if not RecoveryPathAllowed(Root) or not ApplyRecoverySecurity(Root,Information,Security.Descriptor) then exit;
    if CreateRecoveryGuid(GUID) <> 0 then exit;
    Name := StringOfChar(#0,39);
    if RecoveryGuidText(GUID,Name,39) <> 39 then exit;
    TransactionDirectory := Root + '\' + Copy(Name,2,36);
    if not CreateRecoveryFolder(TransactionDirectory,Security) then exit;
    TransactionCreated := True;
    Result := RecoveryPathAllowed(TransactionDirectory);
  finally ReleaseRecoverySecurity(Security.Descriptor); end;
end;

procedure CleanupTransaction;
var Parent: String;
begin
  if not TransactionCreated then exit;
  if (ExtractFileDir(TransactionDirectory) <> RecoveryRoot) or not RecoveryPathAllowed(TransactionDirectory) then exit;
  if RegistryBackup <> '' then RegDeleteKeyIncludingSubkeys(HKA64,RegistryBackup);
  if DelTree(TransactionDirectory,True,True,True) then begin
    TransactionCreated := False;
    Parent := RecoveryRoot; RemoveDir(Parent);
    Parent := ExtractFileDir(Parent); RemoveDir(Parent);
    RemoveDir(ExtractFileDir(Parent));
  end else Log('Unable to remove completed recovery copy: ' + TransactionDirectory);
end;
