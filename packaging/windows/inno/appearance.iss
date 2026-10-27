[Code]
type
  TPaintRect = record Left, Top, Right, Bottom: Integer; end;

function PaintSubclass(Window: HWND; Callback: NativeInt; ID, Data: NativeUInt): Boolean;
  external 'SetWindowSubclass@comctl32.dll stdcall';
function RemovePaintSubclass(Window: HWND; Callback: NativeInt; ID: NativeUInt): Boolean;
  external 'RemoveWindowSubclass@comctl32.dll stdcall';
function PaintDefault(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM): LRESULT;
  external 'DefSubclassProc@comctl32.dll stdcall';
function PaintDC(Window: HWND): NativeUInt;
  external 'GetDC@user32.dll stdcall';
function FreePaintDC(Window: HWND; DC: NativeUInt): Integer;
  external 'ReleaseDC@user32.dll stdcall';
function PaintBounds(Window: HWND; var Rect: TPaintRect): Boolean;
  external 'GetClientRect@user32.dll stdcall';
function PaintBrush(Color: Cardinal): NativeUInt;
  external 'CreateSolidBrush@gdi32.dll stdcall';
function SelectPaintObject(DC, ObjectHandle: NativeUInt): NativeUInt;
  external 'SelectObject@gdi32.dll stdcall';
function StockPaintObject(Index: Integer): NativeUInt;
  external 'GetStockObject@gdi32.dll stdcall';
function DeletePaintObject(ObjectHandle: NativeUInt): Boolean;
  external 'DeleteObject@gdi32.dll stdcall';
function RoundPaint(DC: NativeUInt; Left, Top, Right, Bottom, RX, RY: Integer): Boolean;
  external 'RoundRect@gdi32.dll stdcall';
function PaintTextMode(DC: NativeUInt; Mode: Integer): Integer;
  external 'SetBkMode@gdi32.dll stdcall';
function PaintTextColor(DC: NativeUInt; Color: Cardinal): Cardinal;
  external 'SetTextColor@gdi32.dll stdcall';
function PaintText(DC: NativeUInt; Text: String; Count: Integer; var Rect: TPaintRect; Flags: Cardinal): Integer;
  external 'DrawTextW@user32.dll stdcall';
function PaintMessage(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM): LRESULT;
  external 'SendMessageW@user32.dll stdcall';
function PaintEnabled(Window: HWND): Boolean;
  external 'IsWindowEnabled@user32.dll stdcall';
function PaintFocus: HWND;
  external 'GetFocus@user32.dll stdcall';
function PaintFocusRect(DC: NativeUInt; var Rect: TPaintRect): Boolean;
  external 'DrawFocusRect@user32.dll stdcall';
function FillPaintRect(DC: NativeUInt; const Rect: TPaintRect; Brush: NativeUInt): Integer;
  external 'FillRect@user32.dll stdcall';
function PaintPen(Style, Width: Integer; Color: Cardinal): NativeUInt;
  external 'CreatePen@gdi32.dll stdcall';
function PaintMove(DC: NativeUInt; X, Y: Integer; Previous: NativeUInt): Boolean;
  external 'MoveToEx@gdi32.dll stdcall';
function PaintLine(DC: NativeUInt; X, Y: Integer): Boolean;
  external 'LineTo@gdi32.dll stdcall';
function PaintEllipse(DC: NativeUInt; Left, Top, Right, Bottom: Integer): Boolean;
  external 'Ellipse@gdi32.dll stdcall';
function InvalidatePaint(Window: HWND; Rect: NativeUInt; Erase: Boolean): Boolean;
  external 'InvalidateRect@user32.dll stdcall';

type
  { TRACKMOUSEEVENT is 24 bytes on x64, including its trailing alignment padding. }
  TPaintTracking = record Size, Flags: Cardinal; Window: HWND; HoverTime, Reserved: Cardinal; end;
  TStyledButton = record Button: TNewButton; Role: Integer; end;

function TrackPaintMouse(var Tracking: TPaintTracking): Boolean;
  external 'TrackMouseEvent@user32.dll stdcall';

const
  ButtonPrimary = 0;
  ButtonSecondary = 1;
  ButtonText = 2;
  ButtonTab = 3;

type
  TFrameMargins = record Left, Right, Top, Bottom: Integer; end;
  TWindowMonitorInfo = record Size: Cardinal; Bounds, Work: TPaintRect; Flags: Cardinal; end;

function WindowMonitor(Window: HWND; Flags: Cardinal): NativeUInt;
  external 'MonitorFromWindow@user32.dll stdcall';
function ReadWindowMonitor(Monitor: NativeUInt; var Info: TWindowMonitorInfo): Boolean;
  external 'GetMonitorInfoW@user32.dll stdcall';
function ReadWindowBounds(Window: HWND; var Bounds: TPaintRect): Boolean;
  external 'GetWindowRect@user32.dll stdcall';

function FrameStyle(Window: HWND; Index: Integer): NativeInt;
  external 'GetWindowLongPtrW@user32.dll stdcall';
function SetFrameStyle(Window: HWND; Index: Integer; Value: NativeInt): NativeInt;
  external 'SetWindowLongPtrW@user32.dll stdcall';
function RefreshFrame(Window, After: HWND; X, Y, W, H: Integer; Flags: Cardinal): Boolean;
  external 'SetWindowPos@user32.dll stdcall';
function ExtendFrame(Window: HWND; var Margins: TFrameMargins): Integer;
  external 'DwmExtendFrameIntoClientArea@dwmapi.dll stdcall';
function FrameAttribute(Window: HWND; Attribute: Cardinal; var Value: Cardinal; Size: Cardinal): Integer;
  external 'DwmSetWindowAttribute@dwmapi.dll stdcall';

function LimitLayout(Value, Minimum, Maximum: Integer): Integer;
begin
  Result := Value;
  if Result > Maximum then Result := Maximum;
  if Result < Minimum then Result := Minimum;
end;

procedure InstallerWorkArea(Window: HWND; var Area: TPaintRect);
var Info: TWindowMonitorInfo; Height: Integer;
begin
  Info.Size := SizeOf(Info);
  if ReadWindowMonitor(WindowMonitor(Window,2),Info) then Area := Info.Work
  else begin Area.Left := 0; Area.Top := 0; Area.Right := ScaleX(1024); Area.Bottom := ScaleY(768); end;
#ifdef ValidationBuild
  Height := StrToIntDef(ExpandConstant('{param:WORKAREAHEIGHT|0}'),0);
  if (Height > 0) and (ScaleY(Height) < Area.Bottom-Area.Top) then Area.Bottom := Area.Top+ScaleY(Height);
#endif
end;

procedure KeepWindowInWorkArea(Window: HWND);
var Bounds, Area: TPaintRect; X, Y: Integer;
begin
  InstallerWorkArea(Window,Area); ReadWindowBounds(Window,Bounds);
  X := LimitLayout(Bounds.Left,Area.Left+ScaleX(8),Area.Right-ScaleX(8)-(Bounds.Right-Bounds.Left));
  Y := LimitLayout(Bounds.Top,Area.Top+ScaleY(8),Area.Bottom-ScaleY(8)-(Bounds.Bottom-Bounds.Top));
  if (X <> Bounds.Left) or (Y <> Bounds.Top) then RefreshFrame(Window,0,X,Y,0,0,$15);
end;

var FrameCallback, ButtonCallback, ResultCallback: NativeInt;
  StyledButtons: array of TStyledButton;
  HotButton: HWND;
  ResultWindow: HWND;
  ResultError: Boolean;
  AlignedCheck: TNewCheckBox;
  CheckCallback: NativeInt;
  CheckHovered: Boolean;

function ThemePaint(Light, Dark: Cardinal): Cardinal; forward;

type
  TCheckFontMetrics = record
    Height, Ascent, Descent, InternalLeading, ExternalLeading, AverageWidth, MaximumWidth,
    Weight, Overhang, AspectX, AspectY: Integer;
    FirstChar, LastChar, DefaultChar, BreakChar: Word;
    Italic, Underlined, StruckOut, Pitch, Charset, Padding1, Padding2, Padding3: Byte;
  end;
  TCheckGlyphMetrics = record Width, Height: Cardinal; OriginX, OriginY: Integer; AdvanceX, AdvanceY: SmallInt; end;
  TCheckMatrix = record AFrac: Word; A: SmallInt; BFrac: Word; B: SmallInt;
    CFrac: Word; C: SmallInt; DFrac: Word; D: SmallInt; end;
  TCheckSize = record Width, Height: Integer; end;

function CheckFontMetrics(DC: NativeUInt; var Metrics: TCheckFontMetrics): Boolean;
  external 'GetTextMetricsW@gdi32.dll stdcall';
function CheckGlyphMetrics(DC: NativeUInt; Character, Format: Cardinal; var Metrics: TCheckGlyphMetrics;
  BufferSize: Cardinal; Buffer: NativeUInt; var Matrix: TCheckMatrix): Cardinal;
  external 'GetGlyphOutlineW@gdi32.dll stdcall';
function OpenCheckTheme(Window: HWND; Name: String): NativeUInt;
  external 'OpenThemeData@uxtheme.dll stdcall';
function CloseCheckTheme(Theme: NativeUInt): Integer;
  external 'CloseThemeData@uxtheme.dll stdcall';
function CheckThemeSize(Theme, DC: NativeUInt; Part, State: Integer; Bounds: NativeUInt; SizeType: Integer; var Size: TCheckSize): Integer;
  external 'GetThemePartSize@uxtheme.dll stdcall';
function PaintCheckTheme(Theme, DC: NativeUInt; Part, State: Integer; var Bounds: TPaintRect; Clip: NativeUInt): Integer;
  external 'DrawThemeBackground@uxtheme.dll stdcall';
function PaintClassicCheck(DC: NativeUInt; var Bounds: TPaintRect; Kind, State: Cardinal): Boolean;
  external 'DrawFrameControl@user32.dll stdcall';

procedure MeasureCheck(Control: TNewCheckBox; DC: NativeUInt; var TextWidth, InkAbove, InkBelow, Ascent: Integer; var GlyphSize: TCheckSize);
var I: Integer; Rect: TPaintRect; Metrics: TCheckFontMetrics; Glyph: TCheckGlyphMetrics; Matrix: TCheckMatrix; Theme: NativeUInt;
begin
  Rect.Left := 0; Rect.Top := 0; Rect.Right := 0; Rect.Bottom := 0;
  PaintText(DC,Control.Caption,Length(Control.Caption),Rect,$C20);
  TextWidth := Rect.Right; InkAbove := 0; InkBelow := 0;
  CheckFontMetrics(DC,Metrics); Ascent := Metrics.Ascent;
  Matrix.AFrac := 0; Matrix.A := 1; Matrix.BFrac := 0; Matrix.B := 0;
  Matrix.CFrac := 0; Matrix.C := 0; Matrix.DFrac := 0; Matrix.D := 1;
  for I := 1 to Length(Control.Caption) do
    if CheckGlyphMetrics(DC,Ord(Control.Caption[I]),0,Glyph,0,0,Matrix) <> $FFFFFFFF then
      if Glyph.Height > 0 then begin
        if Glyph.OriginY > InkAbove then InkAbove := Glyph.OriginY;
        if Glyph.OriginY-Integer(Glyph.Height) < InkBelow then InkBelow := Glyph.OriginY-Integer(Glyph.Height);
      end;
  if InkAbove = 0 then begin InkAbove := Metrics.Ascent; InkBelow := -Metrics.Descent; end;
  GlyphSize.Width := ScaleX(13); GlyphSize.Height := ScaleY(13);
  Theme := OpenCheckTheme(Control.Handle,'Button');
  if Theme <> 0 then begin CheckThemeSize(Theme,DC,3,1,0,1,GlyphSize); CloseCheckTheme(Theme); end;
end;

function AlignedCheckWidth(Control: TNewCheckBox): Integer;
var DC, OldFont: NativeUInt; TextWidth, Above, Below, Ascent: Integer; Size: TCheckSize;
begin
  DC := PaintDC(Control.Handle); OldFont := SelectPaintObject(DC,PaintMessage(Control.Handle,$31,0,0));
  MeasureCheck(Control,DC,TextWidth,Above,Below,Ascent,Size);
  Result := Size.Width+ScaleX(8)+TextWidth;
  SelectPaintObject(DC,OldFont); FreePaintDC(Control.Handle,DC);
end;

function CheckMessages(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM; ID, Data: NativeUInt): LRESULT;
var DC, OldFont, Brush, Theme: NativeUInt; Rect, GlyphRect, TextRect: TPaintRect;
  TextWidth, Above, Below, Ascent, State: Integer; Size: TCheckSize; Ink: Cardinal; Tracking: TPaintTracking;
begin
  Result := PaintDefault(Window,MessageID,W,L);
  if (MessageID = $200) and not CheckHovered then begin
    CheckHovered := True; InvalidatePaint(Window,0,False);
    Tracking.Size := SizeOf(Tracking); Tracking.Flags := 2; Tracking.Window := Window;
    Tracking.HoverTime := 0; Tracking.Reserved := 0; TrackPaintMouse(Tracking);
  end;
  if MessageID = $2A3 then begin CheckHovered := False; InvalidatePaint(Window,0,False); end;
  if (MessageID = 7) or (MessageID = 8) or (MessageID = 10) then InvalidatePaint(Window,0,False);
  if (MessageID <> $F) and (MessageID <> $318) then exit;
  if MessageID = $318 then DC := W else DC := PaintDC(Window);
  if DC = 0 then exit;
  OldFont := SelectPaintObject(DC,PaintMessage(Window,$31,0,0));
  try
    PaintBounds(Window,Rect); Brush := PaintBrush(ThemePaint($FFFFFF,$2B2B2B));
    FillPaintRect(DC,Rect,Brush); DeletePaintObject(Brush);
    MeasureCheck(AlignedCheck,DC,TextWidth,Above,Below,Ascent,Size);
    GlyphRect.Left := 0; GlyphRect.Top := (Rect.Bottom-Size.Height) div 2;
    GlyphRect.Right := Size.Width; GlyphRect.Bottom := GlyphRect.Top+Size.Height;
    State := 1; if AlignedCheck.Checked then State := 5;
    if (PaintMessage(Window,$F2,0,0) and 4) <> 0 then State := State+2
    else if CheckHovered then State := State+1;
    if not PaintEnabled(Window) then begin if AlignedCheck.Checked then State := 8 else State := 4; end;
    Theme := OpenCheckTheme(Window,'Button');
    if Theme <> 0 then begin PaintCheckTheme(Theme,DC,3,State,GlyphRect,0); CloseCheckTheme(Theme); end
    else begin
      State := 0; if AlignedCheck.Checked then State := $400;
      if not PaintEnabled(Window) then State := State or $100;
      PaintClassicCheck(DC,GlyphRect,4,State);
    end;
    TextRect := Rect; TextRect.Left := Size.Width+ScaleX(8);
    { Align the visible glyphs, including descenders, rather than the font's extra line leading. }
    TextRect.Top := (Rect.Bottom-(Above-Below)) div 2+Above-Ascent;
    TextRect.Bottom := Rect.Bottom;
    Ink := ThemePaint($202020,$F3F3F3); if not PaintEnabled(Window) then Ink := ThemePaint($777777,$A0A0A0);
    PaintTextMode(DC,1); PaintTextColor(DC,Ink);
    PaintText(DC,AlignedCheck.Caption,Length(AlignedCheck.Caption),TextRect,$820);
    if PaintFocus = Window then begin
      Rect.Left := 1; Rect.Top := 1; Rect.Right := Rect.Right-1; Rect.Bottom := Rect.Bottom-1;
      PaintFocusRect(DC,Rect);
    end;
  finally SelectPaintObject(DC,OldFont); if MessageID = $F then FreePaintDC(Window,DC); end;
end;

procedure StyleAlignedCheck(Control: TNewCheckBox);
begin
  AlignedCheck := Control; CheckCallback := CreateCallback(@CheckMessages);
  PaintSubclass(Control.Handle,CheckCallback,7,0);
end;

function ThemePaint(Light, Dark: Cardinal): Cardinal;
begin if IsDarkInstallMode then Result := Dark else Result := Light; end;

function BlendPaint(Base, Overlay: Cardinal; Percent: Integer): Cardinal;
var R, G, B: Cardinal;
begin
  R := ((Base and $FF)*(100-Percent)+(Overlay and $FF)*Percent) div 100;
  G := (((Base shr 8) and $FF)*(100-Percent)+((Overlay shr 8) and $FF)*Percent) div 100;
  B := (((Base shr 16) and $FF)*(100-Percent)+((Overlay shr 16) and $FF)*Percent) div 100;
  Result := R or (G shl 8) or (B shl 16);
end;

procedure PaintStroke(DC: NativeUInt; Color: Cardinal; Width, X1, Y1, X2, Y2: Integer);
var Pen, OldPen: NativeUInt;
begin
  Pen := PaintPen(0,Width,Color); OldPen := SelectPaintObject(DC,Pen);
  PaintMove(DC,X1,Y1,0); PaintLine(DC,X2,Y2);
  SelectPaintObject(DC,OldPen); DeletePaintObject(Pen);
end;

function ButtonMessages(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM; ID, Data: NativeUInt): LRESULT;
var DC, Brush, Pen, OldBrush, OldPen, OldFont: NativeUInt;
  Rect, TextRect: TPaintRect; Background, Fill, Ink, Border, Accent: Cardinal;
  Tracking: TPaintTracking; Button: TNewButton; Role, Strength: Integer; Active, Focused: Boolean;
begin
  Result := PaintDefault(Window,MessageID,W,L);
  if MessageID = $200 then begin
    if HotButton <> Window then begin
      if HotButton <> 0 then InvalidatePaint(HotButton,0,False);
      HotButton := Window; InvalidatePaint(Window,0,False);
      Tracking.Size := SizeOf(Tracking); Tracking.Flags := 2; Tracking.Window := Window; Tracking.HoverTime := 0; Tracking.Reserved := 0;
      TrackPaintMouse(Tracking);
    end;
  end;
  if MessageID = $2A3 then begin HotButton := 0; InvalidatePaint(Window,0,False); end;
  if (MessageID = 7) or (MessageID = 8) or (MessageID = 10) then InvalidatePaint(Window,0,False);
  if (MessageID <> $F) and (MessageID <> $318) then exit;
  if Data >= NativeUInt(GetArrayLength(StyledButtons)) then exit;
  Button := StyledButtons[Data].Button; if not Assigned(Button) then exit;
  Role := StyledButtons[Data].Role;
  if MessageID = $318 then DC := W else DC := PaintDC(Window);
  if DC = 0 then exit;
  try
    PaintBounds(Window,Rect); Background := ThemePaint($FFFFFF,$2B2B2B);
    if Role = ButtonText then Background := ThemePaint($F7F7F7,$333333);
    Brush := PaintBrush(Background); FillPaintRect(DC,Rect,Brush); DeletePaintObject(Brush);
    Accent := ThemePaint($6E6F18,$D3DA85);
    Ink := ThemePaint($202020,$F3F3F3); Border := ThemePaint($C8C8C8,$666666); Fill := Background;
    Focused := PaintFocus = Window; Active := (Role = ButtonTab) and (Button.Tag = 1);
    Strength := 0;
    if HotButton = Window then Strength := 6;
    if Focused then Strength := 12;
    if (PaintMessage(Window,$F2,0,0) and 4) <> 0 then Strength := 20;
    if not PaintEnabled(Window) then Strength := 0;
    if Role = ButtonPrimary then begin
      Fill := $6E6F18; if Button.Tag = 1 then Fill := $4242C4;
      Fill := BlendPaint(Fill,0,Strength); Ink := $FFFFFF; Border := Fill;
      if not PaintEnabled(Window) then begin Fill := ThemePaint($E8E8E8,$444444); Ink := ThemePaint($777777,$A0A0A0); Border := Fill; end;
    end else begin
      Fill := BlendPaint(Background,ThemePaint(0,$FFFFFF),Strength);
      if (Role = ButtonText) or Active then Ink := Accent;
      if not PaintEnabled(Window) then Ink := ThemePaint($777777,$A0A0A0);
    end;
    if (Role = ButtonPrimary) or (Role = ButtonSecondary) then begin
      Brush := PaintBrush(Fill); Pen := PaintPen(0,1,Border);
      OldBrush := SelectPaintObject(DC,Brush); OldPen := SelectPaintObject(DC,Pen);
      RoundPaint(DC,0,0,Rect.Right,Rect.Bottom,ScaleX(8),ScaleY(8));
      SelectPaintObject(DC,OldPen); SelectPaintObject(DC,OldBrush); DeletePaintObject(Pen); DeletePaintObject(Brush);
    end else if Role = ButtonTab then begin
      Brush := PaintBrush(Fill); FillPaintRect(DC,Rect,Brush); DeletePaintObject(Brush);
      if Active then PaintStroke(DC,Accent,ScaleY(2),ScaleX(12),Rect.Bottom-ScaleY(2),Rect.Right-ScaleX(12),Rect.Bottom-ScaleY(2));
    end;
    OldFont := SelectPaintObject(DC,PaintMessage(Window,$31,0,0));
    PaintTextMode(DC,1); PaintTextColor(DC,Ink); TextRect := Rect;
    if Role = ButtonText then begin
      TextRect.Left := ScaleX(4); PaintText(DC,Button.Caption,Length(Button.Caption),TextRect,$24);
      if (HotButton = Window) or Focused then begin
        TextRect.Right := 0; TextRect.Bottom := 0; PaintText(DC,Button.Caption,Length(Button.Caption),TextRect,$420);
        PaintStroke(DC,Ink,1,ScaleX(4),(Rect.Bottom+TextRect.Bottom) div 2,TextRect.Right,(Rect.Bottom+TextRect.Bottom) div 2);
      end;
    end else PaintText(DC,Button.Caption,Length(Button.Caption),TextRect,$25);
    SelectPaintObject(DC,OldFont);
  finally if MessageID = $F then FreePaintDC(Window,DC); end;
end;

procedure StyleButton(Button: TNewButton; Role: Integer);
var I, Slot: Integer;
begin
  if ButtonCallback = 0 then ButtonCallback := CreateCallback(@ButtonMessages);
  Slot := -1;
  for I := 0 to GetArrayLength(StyledButtons)-1 do
    if not Assigned(StyledButtons[I].Button) then Slot := I;
  if Slot = -1 then begin Slot := GetArrayLength(StyledButtons); SetArrayLength(StyledButtons,Slot+1); end;
  StyledButtons[Slot].Button := Button; StyledButtons[Slot].Role := Role;
  if Role = ButtonText then Button.Cursor := crHandPoint;
  PaintSubclass(Button.Handle,ButtonCallback,4,Slot);
end;

procedure ClearOwnedButtons(Parent: TWinControl);
var I: Integer;
begin
  for I := 0 to GetArrayLength(StyledButtons)-1 do
    if Assigned(StyledButtons[I].Button) then
      if StyledButtons[I].Button.Parent = Parent then begin
        if HotButton = StyledButtons[I].Button.Handle then HotButton := 0;
        RemovePaintSubclass(StyledButtons[I].Button.Handle,ButtonCallback,4); StyledButtons[I].Button := nil;
      end;
end;

function ResultMessages(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM; ID, Data: NativeUInt): LRESULT;
var DC, Brush, OldBrush, OldPen: NativeUInt; Rect: TPaintRect; Green: Cardinal;
begin
  Result := PaintDefault(Window,MessageID,W,L);
  if (MessageID <> $F) and (MessageID <> $318) then exit;
  if MessageID = $318 then DC := W else DC := PaintDC(Window);
  if DC = 0 then exit;
  try
    PaintBounds(Window,Rect); Brush := PaintBrush(ThemePaint($FFFFFF,$2B2B2B));
    FillPaintRect(DC,Rect,Brush); DeletePaintObject(Brush);
    if ResultError then Brush := PaintBrush(ThemePaint($EDEDFB,$363651))
    else Brush := PaintBrush(ThemePaint($EDF5EC,$3A4937));
    OldBrush := SelectPaintObject(DC,Brush);
    OldPen := SelectPaintObject(DC,StockPaintObject(8));
    PaintEllipse(DC,1,1,Rect.Right-1,Rect.Bottom-1);
    SelectPaintObject(DC,OldPen); SelectPaintObject(DC,OldBrush); DeletePaintObject(Brush);
    if ResultError then begin
      Green := ThemePaint($3434A8,$9CA8FF);
      PaintStroke(DC,Green,ScaleX(3),ScaleX(20),ScaleY(20),ScaleX(36),ScaleY(36));
      PaintStroke(DC,Green,ScaleX(3),ScaleX(36),ScaleY(20),ScaleX(20),ScaleY(36));
    end else begin
      Green := ThemePaint($387525,$97D39D);
      PaintStroke(DC,Green,ScaleX(3),ScaleX(16),ScaleY(28),ScaleX(24),ScaleY(36));
      PaintStroke(DC,Green,ScaleX(3),ScaleX(23),ScaleY(36),ScaleX(40),ScaleY(20));
    end;
  finally if MessageID = $F then FreePaintDC(Window,DC); end;
end;

procedure StyleResultMark(Control: TNewStaticText);
begin
  ResultCallback := CreateCallback(@ResultMessages); ResultWindow := Control.Handle;
  PaintSubclass(ResultWindow,ResultCallback,5,0);
end;

procedure ClearAppearance;
var I: Integer;
begin
  for I := 0 to GetArrayLength(StyledButtons)-1 do
    if Assigned(StyledButtons[I].Button) then RemovePaintSubclass(StyledButtons[I].Button.Handle,ButtonCallback,4);
  if ResultCallback <> 0 then RemovePaintSubclass(ResultWindow,ResultCallback,5);
  if CheckCallback <> 0 then begin RemovePaintSubclass(AlignedCheck.Handle,CheckCallback,7); CheckCallback := 0; end;
  ButtonCallback := 0; ResultCallback := 0; HotButton := 0; SetArrayLength(StyledButtons,0);
end;

function FrameMessages(Window: HWND; MessageID: Cardinal; W: WPARAM; L: LPARAM; ID, Data: NativeUInt): LRESULT;
begin
  { Keep DWM's frame and shadow while using the full window as the client area. }
  if MessageID = $83 then begin Result := 0; exit; end;
  if MessageID = $84 then begin Result := 1; exit; end;
  Result := PaintDefault(Window,MessageID,W,L);
end;

procedure StyleFrameWindow(Window: HWND);
var Margins: TFrameMargins; Value: Cardinal;
begin
  if FrameCallback = 0 then FrameCallback := CreateCallback(@FrameMessages);
  PaintSubclass(Window,FrameCallback,3,0);
  SetFrameStyle(Window,-16,FrameStyle(Window,-16) or $C40000);
  Value := 2; FrameAttribute(Window,2,Value,4);
  FrameAttribute(Window,33,Value,4);
  if IsDarkInstallMode then Value := $00666666 else Value := $00B8B8B8;
  FrameAttribute(Window,34,Value,4);
  Margins.Left := 1; Margins.Right := 1; Margins.Top := 1; Margins.Bottom := 1;
  ExtendFrame(Window,Margins);
  RefreshFrame(Window,0,0,0,0,0,$37);
end;

procedure StyleWindowFrame;
begin StyleFrameWindow(WizardForm.Handle); end;

procedure ClearWindowFrame;
begin
  if FrameCallback <> 0 then RemovePaintSubclass(WizardForm.Handle,FrameCallback,3);
  FrameCallback := 0;
end;

