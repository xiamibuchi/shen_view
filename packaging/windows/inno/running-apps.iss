[Code]
function VisitWindows(Callback: NativeInt; Context: LPARAM): Boolean;
  external 'EnumWindows@user32.dll stdcall';
function WindowProcess(Window: HWND; var ProcessID: Cardinal): Cardinal;
  external 'GetWindowThreadProcessId@user32.dll stdcall';
function OpenApplicationProcess(Access: Cardinal; Inherit: Boolean; ProcessID: Cardinal): NativeUInt;
  external 'OpenProcess@kernel32.dll stdcall';
function ApplicationImage(ProcessHandle: NativeUInt; Flags: Cardinal; ImageName: String; var Size: Cardinal): Boolean;
  external 'QueryFullProcessImageNameW@kernel32.dll stdcall';
function CloseApplicationHandle(Handle: NativeUInt): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function RequestApplicationClose(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM): Boolean;
  external 'PostMessageW@user32.dll stdcall';
function WaitApplicationExit(ProcessHandle: NativeUInt; Milliseconds: Cardinal): Cardinal;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function ListApplicationProcesses(Buffer: String; Bytes: Cardinal; var Needed: Cardinal): Boolean;
  external 'K32EnumProcesses@kernel32.dll stdcall';

var
  ApplicationRoot, PreviousApplicationRoot: String;
  ApplicationWindows: array of HWND;
  ApplicationProcesses: array of Cardinal;
  ApplicationCallback: NativeInt;

function IsInstallationProcess(const Image, Root: String): Boolean;
begin
  Result := (Root <> '') and (Pos(Lowercase(AddBackslash(Root)),Lowercase(Image)) = 1) and
    not PathSame(Image,AddBackslash(Root) + 'uninstall.exe') and
    not PathSame(Image,AddBackslash(Root) + 'maintain.exe') and
    not PathSame(Image,AddBackslash(Root) + 'unins000.exe');
end;

procedure FindApplicationProcesses(const Root, PreviousRoot: String);
var Buffer, Image: String; Needed, ProcessID, Size: Cardinal; I, Count: Integer; Handle: NativeUInt;
begin
  ApplicationRoot := Root; PreviousApplicationRoot := PreviousRoot;
  SetArrayLength(ApplicationProcesses,0);
  Buffer := StringOfChar(#0,32768);
  if not ListApplicationProcesses(Buffer,65536,Needed) or (Needed >= 65536) then RaiseException('Unable to enumerate running application processes.');
  for I := 0 to (Needed div 4)-1 do begin
    ProcessID := Ord(Buffer[I*2+1]) or (Cardinal(Ord(Buffer[I*2+2])) shl 16);
    Handle := OpenApplicationProcess($1000,False,ProcessID);
    if Handle = 0 then continue;
    try
      Size := 32768; Image := StringOfChar(#0,Size);
      if not ApplicationImage(Handle,0,Image,Size) then continue;
      SetLength(Image,Size);
      if not IsInstallationProcess(Image,Root) and not IsInstallationProcess(Image,PreviousRoot) then continue;
      Count := GetArrayLength(ApplicationProcesses); SetArrayLength(ApplicationProcesses,Count+1);
      ApplicationProcesses[Count] := ProcessID;
    finally CloseApplicationHandle(Handle); end;
  end;
end;

function CollectApplicationWindow(Window: HWND; Context: LPARAM): Boolean;
var ProcessID, Size: Cardinal; ProcessHandle: NativeUInt; Image: String; Count: Integer;
begin
  Result := True;
  WindowProcess(Window,ProcessID);
  ProcessHandle := OpenApplicationProcess($1000,False,ProcessID);
  if ProcessHandle = 0 then exit;
  try
    Size := 32768; Image := StringOfChar(#0,Size);
    if not ApplicationImage(ProcessHandle,0,Image,Size) then exit;
    SetLength(Image,Size);
    if not IsInstallationProcess(Image,ApplicationRoot) and not IsInstallationProcess(Image,PreviousApplicationRoot) then exit;
    Count := GetArrayLength(ApplicationWindows);
    SetArrayLength(ApplicationWindows,Count+1);
    ApplicationWindows[Count] := Window;
  finally CloseApplicationHandle(ProcessHandle); end;
end;

procedure FindApplicationWindows(const Root, PreviousRoot: String);
begin
  FindApplicationProcesses(Root,PreviousRoot);
  SetArrayLength(ApplicationWindows,0);
  if ApplicationCallback = 0 then ApplicationCallback := CreateCallback(@CollectApplicationWindow);
  VisitWindows(ApplicationCallback,0);
end;
