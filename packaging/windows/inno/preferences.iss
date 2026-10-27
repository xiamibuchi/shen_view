[Code]
function OpenLock(const Name: String; Access, Share: Cardinal; Security: NativeUInt; Creation, Flags: Cardinal; Template: NativeUInt): NativeInt;
  external 'CreateFileW@kernel32.dll stdcall';
function LockBytes(Handle: NativeInt; OffsetLow, OffsetHigh, BytesLow, BytesHigh: Cardinal): Boolean;
  external 'LockFile@kernel32.dll stdcall';
function CloseLock(Handle: NativeInt): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function ReplacePreference(const Existing, Replacement: String; Flags: Cardinal): Boolean;
  external 'MoveFileExW@kernel32.dll stdcall';

var Json: String; JsonPos, JsonDepth: Integer;

function JsonDigit(C: Char): Boolean;
begin Result := (C >= '0') and (C <= '9'); end;

procedure JsonSpace;
begin
  while JsonPos <= Length(Json) do begin
    if not (Json[JsonPos] in [#9,#10,#13,' ']) then exit;
    JsonPos := JsonPos + 1;
  end;
end;

function JsonString: String;
var C: Char; Hex: String;
begin
  Result := '';
  if (JsonPos > Length(Json)) or (Json[JsonPos] <> '"') then RaiseException('Invalid JSON string');
  JsonPos := JsonPos + 1;
  while JsonPos <= Length(Json) do begin
    C := Json[JsonPos]; JsonPos := JsonPos + 1;
    if C = '"' then exit;
    if Ord(C) < 32 then RaiseException('Invalid JSON control character');
    if C = #92 then begin
      if JsonPos > Length(Json) then RaiseException('Invalid JSON escape');
      C := Json[JsonPos]; JsonPos := JsonPos + 1;
      case C of
        '"', '/', #92: Result := Result + C;
        'b': Result := Result + #8;
        'f': Result := Result + #12;
        'n': Result := Result + #10;
        'r': Result := Result + #13;
        't': Result := Result + #9;
        'u': begin
          Hex := Copy(Json, JsonPos, 4);
          if Length(Hex) <> 4 then RaiseException('Invalid Unicode escape');
          Result := Result + Chr(StrToInt('$' + Hex)); JsonPos := JsonPos + 4;
        end;
      else RaiseException('Invalid JSON escape'); end;
    end else Result := Result + C;
  end;
  RaiseException('Unterminated JSON string');
end;

procedure JsonValue;
var Closing: Char; Start: Integer; Token: String;
begin
  JsonSpace;
  if JsonPos > Length(Json) then RaiseException('Missing JSON value');
  if Json[JsonPos] = '"' then begin JsonString; exit; end;
  if Json[JsonPos] in ['{','['] then begin
    JsonDepth := JsonDepth + 1;
    if JsonDepth > 64 then RaiseException('Settings nesting exceeds limit');
    Closing := '}'; if Json[JsonPos] = '[' then Closing := ']';
    JsonPos := JsonPos + 1; JsonSpace;
    if (JsonPos <= Length(Json)) and (Json[JsonPos] = Closing) then begin JsonPos := JsonPos + 1; JsonDepth := JsonDepth - 1; exit; end;
    while True do begin
      if Closing = '}' then begin
        JsonSpace; JsonString; JsonSpace;
        if (JsonPos > Length(Json)) or (Json[JsonPos] <> ':') then RaiseException('Invalid JSON member');
        JsonPos := JsonPos + 1;
      end;
      JsonValue; JsonSpace;
      if JsonPos > Length(Json) then RaiseException('Unterminated JSON container');
      if Json[JsonPos] = Closing then begin JsonPos := JsonPos + 1; break; end;
      if Json[JsonPos] <> ',' then RaiseException('Invalid JSON separator');
      JsonPos := JsonPos + 1;
    end;
    JsonDepth := JsonDepth - 1;
    exit;
  end;
  Start := JsonPos;
  while JsonPos <= Length(Json) do begin
    if Json[JsonPos] in [#9,#10,#13,' ', ',',']','}'] then break;
    JsonPos := JsonPos + 1;
  end;
  Token := Copy(Json,Start,JsonPos-Start);
  if (Token = 'true') or (Token = 'false') or (Token = 'null') then exit;
  { Validate number grammar without depending on the user's decimal separator. }
  if Token = '' then RaiseException('Empty JSON value');
  Start := 1;
  if Token[Start] = '-' then Start := Start + 1;
  if Start > Length(Token) then RaiseException('Invalid JSON number');
  if Token[Start] = '0' then Start := Start + 1
  else begin
    if (Token[Start] < '1') or (Token[Start] > '9') then RaiseException('Invalid JSON value');
    while (Start <= Length(Token)) and JsonDigit(Token[Start]) do Start := Start + 1;
  end;
  if (Start <= Length(Token)) and (Token[Start] = '.') then begin
    Start := Start + 1;
    if (Start > Length(Token)) or not JsonDigit(Token[Start]) then RaiseException('Invalid JSON fraction');
    while (Start <= Length(Token)) and JsonDigit(Token[Start]) do Start := Start + 1;
  end;
  if (Start <= Length(Token)) and (Token[Start] in ['e','E']) then begin
    Start := Start + 1;
    if (Start <= Length(Token)) and (Token[Start] in ['+','-']) then Start := Start + 1;
    if (Start > Length(Token)) or not JsonDigit(Token[Start]) then RaiseException('Invalid JSON exponent');
    while (Start <= Length(Token)) and JsonDigit(Token[Start]) do Start := Start + 1;
  end;
  if Start <= Length(Token) then RaiseException('Invalid JSON number');
end;

function Member(const ObjectAt: Integer; const Name: String; var ValueAt, EndAt, InsertAt: Integer): Boolean;
var Key: String;
begin
  Result := False; JsonPos := ObjectAt; JsonSpace;
  if Json[JsonPos] <> '{' then RaiseException('Expected JSON object');
  JsonPos := JsonPos + 1; JsonSpace; InsertAt := JsonPos;
  if Json[JsonPos] = '}' then exit;
  while True do begin
    Key := JsonString; JsonSpace;
    if Json[JsonPos] <> ':' then RaiseException('Invalid JSON member');
    JsonPos := JsonPos + 1; JsonSpace; ValueAt := JsonPos;
    JsonValue; EndAt := JsonPos;
    if Key = Name then begin Result := True; exit; end;
    JsonSpace;
    if Json[JsonPos] = '}' then exit;
    JsonPos := JsonPos + 1; JsonSpace;
  end;
end;

function LoadPreferences(const FileName: String): Boolean;
var Bytes: AnsiString;
begin
  Result := False;
  if not FileExists(FileName) then begin Json := '{}'; Result := True; exit; end;
  if not LoadStringFromFile(FileName,Bytes) or (Length(Bytes) > 16777216) then exit;
  Json := Utf8Decode(Bytes); JsonPos := 1; JsonDepth := 0;
  try
    JsonSpace; if Json[JsonPos] <> '{' then exit;
    JsonValue; JsonSpace;
    Result := JsonPos > Length(Json);
  except Result := False; end;
end;

function ReadPreferenceLanguage(const FileName: String): String;
var A,B,C,D,E,F: Integer;
begin
  Result := '';
  if not LoadPreferences(FileName) then exit;
  try
    if Member(1,'settings',A,B,C) and Member(A,'localeCode',D,E,F) then begin
      JsonPos := D; Result := JsonString;
      if (Result <> 'system') and (Result <> 'zh') and (Result <> 'en') then Result := '';
    end;
  except Result := ''; end;
end;

function MergePreferenceLanguage(const FileName, LanguageCode: String): Boolean;
var Lock: NativeInt; A,B,C,D,E,F,Attempt: Integer; Value, Separator, Temporary: String;
begin
  Result := False;
  if not ForceDirectories(ExtractFileDir(FileName)) then exit;
  Lock := OpenLock(FileName + '.lock',$C0000000,7,0,4,$80,0);
  if Lock = -1 then exit;
  try
    for Attempt := 1 to 100 do begin
      if LockBytes(Lock,0,0,$FFFFFFFF,$7FFFFFFF) then break;
      if Attempt = 100 then exit;
      Sleep(20);
    end;
    if not LoadPreferences(FileName) then exit;
    try
      Value := '"' + LanguageCode + '"';
      if Member(1,'settings',A,B,C) then begin
        if Member(A,'localeCode',D,E,F) then Json := Copy(Json,1,D-1) + Value + Copy(Json,E,Length(Json))
        else begin
          Separator := ','; if Json[F] = '}' then Separator := '';
          Json := Copy(Json,1,F-1) + '"localeCode":' + Value + Separator + Copy(Json,F,Length(Json));
        end;
      end else begin
        Separator := ','; if Json[C] = '}' then Separator := '';
        Json := Copy(Json,1,C-1) + '"settings":{"localeCode":' + Value + '}' + Separator + Copy(Json,C,Length(Json));
      end;
      Temporary := FileName + '.inno-tmp';
      if not SaveStringToFile(Temporary,Utf8Encode(Json),False) then exit;
      Result := ReplacePreference(Temporary,FileName,9);
      if not Result then DeleteFile(Temporary);
    except Result := False; end;
  finally CloseLock(Lock); end;
end;
