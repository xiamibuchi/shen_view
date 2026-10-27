[CmdletBinding()]
param([Parameter(Mandatory)][string]$Installer,[switch]$Execute,[string]$PreviewRoot = '',[switch]$VerifyCodecs,[int]$WorkAreaHeight = 0,[switch]$CompletionOnly)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class InnoUi {
  public static DateTime MinimumStart;
  public delegate bool Visit(IntPtr window,IntPtr context);
  [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
  [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point point);
  [DllImport("user32.dll")] static extern bool EnumWindows(Visit visitor,IntPtr context);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr window,Visit visitor,IntPtr context);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window,StringBuilder text,int size);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder text,int size);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window,out Rect rect);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window,out Rect rect);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr window);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window,IntPtr dc,uint flags);
  [DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr window,IntPtr rect,IntPtr region,uint flags);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window,uint message,IntPtr w,IntPtr l);
  [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="SendMessageW")] public static extern IntPtr SetText(IntPtr window,uint message,IntPtr w,string text);
  [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr window);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint processId);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr window,uint attribute,out uint value,uint size);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr GetSystemMenu(IntPtr window,bool revert);
  [DllImport("user32.dll")] public static extern uint GetMenuState(IntPtr menu,uint item,uint flags);
  [DllImport("user32.dll",EntryPoint="GetWindowLongW")] public static extern int WindowStyle(IntPtr window,int index);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr window,int id);
  public static IntPtr DialogButton(IntPtr window,int id){var native=GetDlgItem(window,id);if(native!=IntPtr.Zero)return native;foreach(var child in Children(window)){if(!IsWindowVisible(child)||!Class(child).Contains("Button"))continue;var t=Text(child).Replace("&","");if(id==1&&(t=="OK"||t.StartsWith("确定")))return child;if(id==2&&(t.StartsWith("Cancel")||t.StartsWith("取消")))return child;}return IntPtr.Zero;}
  public static string Text(IntPtr window){var b=new StringBuilder(2048);GetWindowText(window,b,b.Capacity);return b.ToString();}
  public static string Class(IntPtr window){var b=new StringBuilder(256);GetClassName(window,b,b.Capacity);return b.ToString();}
  public static IntPtr Find(){IntPtr result=IntPtr.Zero;EnumWindows((w,c)=>{if((Text(w)=="ShenView" || Text(w)=="神羊看图") && Class(w)=="TWizardForm" && IsWindowVisible(w)){uint id;GetWindowThreadProcessId(w,out id);try{if(System.Diagnostics.Process.GetProcessById((int)id).StartTime<MinimumStart)return true;}catch{return true;}result=w;return false;}return true;},IntPtr.Zero);return result;}
  public static IntPtr FormatDialog(){IntPtr result=IntPtr.Zero;EnumWindows((w,c)=>{if(IsWindowVisible(w)&&(Text(w)=="自定义打开方式"||Text(w)=="Customize Open With")){result=w;return false;}return true;},IntPtr.Zero);return result;}
  public static IntPtr[] Children(IntPtr parent){var result=new List<IntPtr>();EnumChildWindows(parent,(w,c)=>{result.Add(w);return true;},IntPtr.Zero);return result.ToArray();}
  public static IntPtr Prompt(string prefix){IntPtr result=IntPtr.Zero;EnumWindows((w,c)=>{if((Class(w)=="#32770"||Class(w)=="TTaskDialogForm") && IsWindowVisible(w)){foreach(var child in Children(w)){if(Text(child).StartsWith(prefix)){result=w;return false;}}}return true;},IntPtr.Zero);return result;}
  public static IntPtr ClosePrompt(){return Prompt("神羊看图正在运行。");}
  public static IntPtr MigrationPrompt(){return Prompt("将更换安装位置：");}
  public static IntPtr PurgePrompt(){return Prompt("完全卸载将删除");}
  public static void Select(IntPtr combo,int index){SendMessage(combo,0x0100,(IntPtr)0x24,IntPtr.Zero);for(int i=0;i<index;i++)SendMessage(combo,0x0100,(IntPtr)0x28,IntPtr.Zero);}
}
'@
$work = Join-Path $RepositoryRoot ('build/packaging/inno7-ui/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$target = Join-Path $work 'ShenView'
if ($PreviewRoot) {
  if ($Execute) {throw '-PreviewRoot 仅用于查看界面，不能执行安装。'}
  if (-not [IO.Path]::IsPathFullyQualified($PreviewRoot)) {throw '-PreviewRoot 必须是完整的绝对路径。'}
  $target = [IO.Path]::GetFullPath($PreviewRoot)
}
[InnoUi]::MinimumStart = [DateTime]::Now
$launchArguments=@('/UILANG=zh',('/ROOT="' + $target + '"'))
if($WorkAreaHeight){
  if($Installer-notlike '*validation*' -or $Execute){throw '工作区高度模拟仅用于 validation 界面检查。'}
  $launchArguments+=('/WORKAREAHEIGHT='+$WorkAreaHeight)
}
$process = Start-Process -FilePath $Installer -ArgumentList $launchArguments -WindowStyle Normal -PassThru
function Save-Window([IntPtr]$Window,[string]$Name,[switch]$FromScreen) {
  Start-Sleep -Milliseconds 150
  [void][InnoUi]::RedrawWindow($Window,[IntPtr]::Zero,[IntPtr]::Zero,0x0185)
  $rect = [InnoUi+Rect]::new()
  [void][InnoUi]::GetWindowRect($Window,[ref]$rect)
  @{name=$Name;width=$rect.Right-$rect.Left;height=$rect.Bottom-$rect.Top} | ConvertTo-Json -Compress | Add-Content (Join-Path $work 'window-sizes.jsonl') -Encoding utf8
  $image = [Drawing.Bitmap]::new(($rect.Right-$rect.Left),($rect.Bottom-$rect.Top))
  $graphics = [Drawing.Graphics]::FromImage($image)
  if($FromScreen){
    # Flutter's GPU surface can be blank in PrintWindow even after it is painted.
    [void][InnoUi]::SetForegroundWindow($Window)
    Start-Sleep -Milliseconds 400
    $graphics.CopyFromScreen($rect.Left,$rect.Top,0,0,$image.Size)
  }else{
    $dc = $graphics.GetHdc()
    try { [void][InnoUi]::PrintWindow($Window,$dc,2) } finally { $graphics.ReleaseHdc($dc) }
  }
  $image.Save((Join-Path $work ($Name + '.png')),[Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose(); $image.Dispose()
}
function Visible-Text([IntPtr]$Window) {
  return @([InnoUi]::Children($Window) | Where-Object { [InnoUi]::IsWindowVisible($_) } | ForEach-Object { [InnoUi]::Text($_) })
}
function Click-FormatLink([IntPtr]$Control) {
  if($Control -eq [IntPtr]::Zero) {throw '找不到格式文字链接。'}
  $rect=[InnoUi+Rect]::new();$cursor=[InnoUi+Point]::new()
  [void][InnoUi]::GetWindowRect($Control,[ref]$rect)
  [void][InnoUi]::GetCursorPos([ref]$cursor)
  try {
    [void][InnoUi]::SetCursorPos($rect.Left+8,$rect.Top+8)
    [void][InnoUi]::SendMessage($Control,0x0200,[IntPtr]::Zero,[IntPtr]0x00080008)
    [void][InnoUi]::SendMessage($Control,0x0201,[IntPtr]1,[IntPtr]0x00080008)
    [void][InnoUi]::PostMessage($Control,0x0202,[IntPtr]::Zero,[IntPtr]0x00080008)
    for($i=0;$i-lt60;$i++){
      if([InnoUi]::FormatDialog()-ne[IntPtr]::Zero){break}
      Start-Sleep -Milliseconds 50
    }
  } finally {[void][InnoUi]::SetCursorPos($cursor.X,$cursor.Y)}
}
function Open-Formats([IntPtr]$Window,[switch]$Keyboard) {
  $link=[InnoUi]::Children($Window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_) -in @('自定义…','Customize…')} | Select-Object -First 1
  if($Keyboard){
    [void][InnoUi]::SendMessage($Window,0x0028,$link,[IntPtr]1)
    [void][InnoUi]::PostMessage($link,0x0100,[IntPtr]32,[IntPtr]::Zero)
    [void][InnoUi]::PostMessage($link,0x0101,[IntPtr]32,[IntPtr]::Zero)
  }else{Click-FormatLink $link}
  for($i=0;$i -lt 60;$i++) {$dialog=[InnoUi]::FormatDialog();if($dialog-ne[IntPtr]::Zero){return $dialog};Start-Sleep -Milliseconds 50}
  throw '格式选择弹窗没有出现。'
}
function Click-Label([IntPtr]$Window,[string]$Caption) {
  $control=[InnoUi]::Children($Window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Class($_)-like '*Button*' -and [InnoUi]::Text($_)-eq $Caption} | Select-Object -First 1
  if(-not $control){throw ('找不到按钮: '+$Caption)}
  [void][InnoUi]::SendMessage($control,0xF5,[IntPtr]::Zero,[IntPtr]::Zero)
}
function Format-Checks([IntPtr]$Dialog) {
  return @([InnoUi]::Children($Dialog) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-match '^\.[a-z0-9]+$'})
}
function Button-Fill([IntPtr]$Control) {
  $rect=[InnoUi+Rect]::new(); [void][InnoUi]::GetClientRect($Control,[ref]$rect)
  $bitmap=[Drawing.Bitmap]::new($rect.Right,$rect.Bottom)
  $graphics=[Drawing.Graphics]::FromImage($bitmap); $dc=$graphics.GetHdc()
  try {
    [void][InnoUi]::PrintWindow($Control,$dc,0)
    $graphics.ReleaseHdc($dc); $dc=[IntPtr]::Zero
    return $bitmap.GetPixel(12,8).ToArgb()
  } finally {if($dc-ne[IntPtr]::Zero){$graphics.ReleaseHdc($dc)};$graphics.Dispose();$bitmap.Dispose()}
}
function Assert-ButtonStates([IntPtr]$Window,[IntPtr]$Control) {
  $cursor=[InnoUi+Point]::new(); $rect=[InnoUi+Rect]::new(); $outer=[InnoUi+Rect]::new()
  [void][InnoUi]::GetCursorPos([ref]$cursor); [void][InnoUi]::GetWindowRect($Control,[ref]$rect)
  [void][InnoUi]::GetWindowRect($Window,[ref]$outer)
  $cancel=[InnoUi]::Children($Window) | Where-Object {[InnoUi]::Text($_)-eq 'Cancel'} | Select-Object -First 1
  $wasTopmost=([InnoUi]::WindowStyle($Window,-20)-band 8)-ne0
  try {
    [void][InnoUi]::SetWindowPos($Window,[IntPtr](-1),0,0,0,0,0x13)
    [void][InnoUi]::SendMessage($Window,0x28,$cancel,[IntPtr]1)
    [void][InnoUi]::SetForegroundWindow($Window)
    Start-Sleep -Milliseconds 100
    [void][InnoUi]::GetWindowRect($Control,[ref]$rect);[void][InnoUi]::GetWindowRect($Window,[ref]$outer)
    [void][InnoUi]::SetCursorPos($outer.Left-12,$outer.Top-12); Start-Sleep -Milliseconds 150
    $normal=Button-Fill $Control
    $hoverPoint=[InnoUi+Point]::new();$hover=$normal
    for($attempt=0;$attempt-lt10;$attempt++){
      [void][InnoUi]::SetCursorPos($rect.Left+12,$rect.Top+12); Start-Sleep -Milliseconds 50
      [void][InnoUi]::GetCursorPos([ref]$hoverPoint);$hit=[InnoUi]::WindowFromPoint($hoverPoint)
      if($hit-ne$Control){continue}
      [void][InnoUi]::SendMessage($Control,0x200,[IntPtr]::Zero,[IntPtr]0x000C000C)
      $hover=Button-Fill $Control
      if($hover-ne$normal){break}
    }
    if($hit-ne$Control){throw '其他鼠标输入打断了悬停验证，未取得按钮上的有效指针位置。'}
    Save-Window $Window 'button-hover'
    [void][InnoUi]::SendMessage($Control,0xF3,[IntPtr]1,[IntPtr]::Zero)
    $pressed=Button-Fill $Control; Save-Window $Window 'button-pressed'
    [void][InnoUi]::SendMessage($Control,0xF3,[IntPtr]::Zero,[IntPtr]::Zero)
    [void][InnoUi]::SetCursorPos($outer.Left-12,$outer.Top-12); Start-Sleep -Milliseconds 150
    $restored=Button-Fill $Control
    [void][InnoUi]::SendMessage($Window,0x28,$Control,[IntPtr]1)
    $focused=Button-Fill $Control; Save-Window $Window 'button-focus'
    @{normal=$normal;hover=$hover;pressed=$pressed;focused=$focused;restored=$restored;hoverTarget=$hit.ToInt64();expectedTarget=$Control.ToInt64();cursorX=$hoverPoint.X;cursorY=$hoverPoint.Y;buttonLeft=$rect.Left;buttonTop=$rect.Top} |
      ConvertTo-Json | Set-Content (Join-Path $work 'button-states.json') -Encoding utf8
    if($normal-eq$hover -or $hover-eq$pressed -or $normal-eq$focused -or $normal-ne$restored){throw '按钮悬停、按下、焦点或离开后的视觉反馈不正确。'}
  } finally {
    [void][InnoUi]::SendMessage($Control,0xF3,[IntPtr]::Zero,[IntPtr]::Zero)
    [void][InnoUi]::SendMessage($Window,0x28,$cancel,[IntPtr]1)
    [void][InnoUi]::SetCursorPos($cursor.X,$cursor.Y)
    if(-not$wasTopmost){[void][InnoUi]::SetWindowPos($Window,[IntPtr](-2),0,0,0,0,0x13)}
  }
}
function Close-Formats([IntPtr]$Dialog,[string]$Caption) {
  Click-Label $Dialog $Caption
  for($i=0;$i -lt 60 -and [InnoUi]::IsWindow($Dialog);$i++){Start-Sleep -Milliseconds 50}
  if([InnoUi]::IsWindow($Dialog)){throw '格式选择弹窗没有关闭。'}
}
function Assert-FixedOptions([IntPtr]$Window,[string[]]$ShortcutNames) {
  $visible=@([InnoUi]::Children($Window) | Where-Object {[InnoUi]::IsWindowVisible($_)})
  foreach($control in $visible) {
    $text=[InnoUi]::Text($control)
    if($text -match '^[123]\s{2}' -or $text -in @('Hide shortcuts','收起快捷方式')) {throw '主界面仍显示步骤指示或快捷方式折叠按钮。'}
    if(([InnoUi]::Class($control) -eq 'TPanel' -and ([InnoUi]::WindowStyle($control,-16)-band 0x300000)-ne 0) -or [InnoUi]::Class($control) -eq 'ScrollBar') {throw ('主界面仍有滚动条: '+[InnoUi]::Class($control))}
  }
  $shortcuts=@($visible | Where-Object {[InnoUi]::Text($_) -in $ShortcutNames})
  if($shortcuts.Count -ne 2) {throw '快捷方式没有直接展示两个选项。'}
  foreach($shortcut in $shortcuts) {
    $r=[InnoUi+Rect]::new();$body=[InnoUi+Rect]::new()
    [void][InnoUi]::GetWindowRect($shortcut,[ref]$r)
    [void][InnoUi]::GetWindowRect([InnoUi]::GetParent([InnoUi]::GetParent($shortcut)),[ref]$body)
    if($r.Top-lt $body.Top -or $r.Bottom-gt $body.Bottom) {throw '快捷方式被正文边界或底栏遮挡。'}
  }
  $content=[InnoUi]::GetParent($shortcuts[0])
  $items=@($visible | Where-Object {[InnoUi]::GetParent($_)-eq$content} | ForEach-Object {
    $r=[InnoUi+Rect]::new();[void][InnoUi]::GetWindowRect($_,[ref]$r)
    if($r.Right-gt$r.Left -and $r.Bottom-gt$r.Top){@{rect=$r;text=[InnoUi]::Text($_);class=[InnoUi]::Class($_)}}
  })
  for($i=0;$i-lt$items.Count;$i++){for($j=$i+1;$j-lt$items.Count;$j++){
    $a=$items[$i].rect;$b=$items[$j].rect
    if($a.Left-lt$b.Right -and $a.Right-gt$b.Left -and $a.Top-lt$b.Bottom -and $a.Bottom-gt$b.Top){
      throw ('安装选项互相遮挡: '+$items[$i].text+' / '+$items[$j].text)
    }
  }}
}
function Save-WindowContext([IntPtr]$Window) {
  $rect=[InnoUi+Rect]::new(); [void][InnoUi]::GetWindowRect($Window,[ref]$rect)
  $backdrop=[Windows.Forms.Form]::new()
  $backdrop.FormBorderStyle='None'; $backdrop.StartPosition='Manual'; $backdrop.BackColor=[Drawing.Color]::White
  $backdrop.SetBounds($rect.Left-48,$rect.Top-48,$rect.Right-$rect.Left+96,$rect.Bottom-$rect.Top+96)
  try {
    $backdrop.TopMost=$true
    $backdrop.Show(); [Windows.Forms.Application]::DoEvents()
    [void][InnoUi]::SetWindowPos($Window,[IntPtr](-1),0,0,0,0,0x13)
    [void][InnoUi]::SetForegroundWindow($Window)
    Start-Sleep -Milliseconds 400
    $bitmap=[Drawing.Bitmap]::new($backdrop.Width,$backdrop.Height)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.CopyFromScreen($backdrop.Left,$backdrop.Top,0,0,$bitmap.Size)
      $bitmap.Save((Join-Path $work 'window-shadow-context.png'),[Drawing.Imaging.ImageFormat]::Png)
    } finally {$graphics.Dispose();$bitmap.Dispose()}
    $border=[uint32]0; $corner=[uint32]0
    [void][InnoUi]::DwmGetWindowAttribute($Window,34,[ref]$border,4)
    [void][InnoUi]::DwmGetWindowAttribute($Window,33,[ref]$corner,4)
    @{border=$border;corner=$corner;thickFrame=(([InnoUi]::WindowStyle($Window,-16)-band 0x40000)-ne 0)} |
      ConvertTo-Json | Set-Content (Join-Path $work 'window-frame.json') -Encoding utf8
  } finally {[void][InnoUi]::SetWindowPos($Window,[IntPtr](-2),0,0,0,0,0x13);$backdrop.Close();$backdrop.Dispose()}
}
function Assert-PathInk([IntPtr]$Window,[string]$Name) {
  $edit = [InnoUi]::Children($Window) | Where-Object { [InnoUi]::Class($_) -like '*PathEdit*' -and [InnoUi]::IsWindowVisible($_) } | Select-Object -First 1
  $frame = [InnoUi]::GetParent([InnoUi]::GetParent($edit))
  $windowRect=[InnoUi+Rect]::new(); $frameRect=[InnoUi+Rect]::new()
  [void][InnoUi]::GetWindowRect($Window,[ref]$windowRect); [void][InnoUi]::GetWindowRect($frame,[ref]$frameRect)
  $bitmap=[Drawing.Bitmap]::new((Join-Path $work ($Name+'.png')))
  try {
    $cropRect=[Drawing.Rectangle]::new(($frameRect.Left-$windowRect.Left),($frameRect.Top-$windowRect.Top),($frameRect.Right-$frameRect.Left),($frameRect.Bottom-$frameRect.Top))
    $crop=$bitmap.Clone($cropRect,$bitmap.PixelFormat)
    try {
      $crop.Save((Join-Path $work ($Name+'-path.png')),[Drawing.Imaging.ImageFormat]::Png)
      $dark=$crop.GetPixel(3,3).GetBrightness() -lt 0.5
      $rows=@(for($y=3;$y -lt $crop.Height-3;$y++){
        $count=0
        for($x=12;$x -lt $crop.Width-12;$x++){
          $brightness=$crop.GetPixel($x,$y).GetBrightness()
          if (($dark -and $brightness -gt 0.7) -or (-not $dark -and $brightness -lt 0.35)) {$count++}
        }
        if ($count -ge 3) {$y}
      })
      if ($rows.Count -eq 0) {throw '路径截图没有可测量的文字。'}
      $top=$rows[0]; $bottom=$crop.Height-1-$rows[-1]
      @{name=$Name;top=$top;bottom=$bottom;difference=[Math]::Abs($top-$bottom)} | ConvertTo-Json -Compress | Add-Content (Join-Path $work 'path-ink-metrics.jsonl') -Encoding utf8
      if ([Math]::Abs($top-$bottom) -gt 2) {throw ('路径文字上下留白不均: '+$top+' / '+$bottom)}
    } finally {$crop.Dispose()}
  } finally {$bitmap.Dispose()}
}
function Assert-LaunchAlignment([IntPtr]$Window,[string]$Name) {
  $check=[InnoUi]::Children($Window)|Where-Object{[InnoUi]::IsWindowVisible($_)-and[InnoUi]::Text($_)-in @('启动神羊看图','Launch ShenView')}|Select-Object -First 1
  if(-not$check){throw '完成页没有启动复选框。'}
  $outer=[InnoUi+Rect]::new();$r=[InnoUi+Rect]::new()
  [void][InnoUi]::GetWindowRect($Window,[ref]$outer);[void][InnoUi]::GetWindowRect($check,[ref]$r)
  $scale=[InnoUi]::GetDpiForWindow($Window)/96.0
  $image=[Drawing.Bitmap]::new((Join-Path $work ($Name+'.png')))
  $crop=$image.Clone([Drawing.Rectangle]::new($r.Left-$outer.Left,$r.Top-$outer.Top,$r.Right-$r.Left,$r.Bottom-$r.Top),$image.PixelFormat)
  try {
    $crop.Save((Join-Path $work ($Name+'-launch.png')))
    $background=$crop.GetPixel($crop.Width-1,0).GetBrightness()
    $glyphY=[Collections.Generic.List[int]]::new();$textY=[Collections.Generic.List[int]]::new();$inkX=[Collections.Generic.List[int]]::new()
    for($y=0;$y-lt$crop.Height;$y++){for($x=0;$x-lt$crop.Width;$x++){
      if([Math]::Abs($crop.GetPixel($x,$y).GetBrightness()-$background)-lt0.28){continue}
      if($x-lt16*$scale){$glyphY.Add($y);$inkX.Add($x)}
      elseif($x-ge20*$scale){$textY.Add($y);$inkX.Add($x)}
    }}
    if(-not$glyphY.Count-or-not$textY.Count){throw '启动复选框截图缺少可测量的方框或文字。'}
    $glyphCenter=(($glyphY|Measure-Object -Minimum).Minimum+($glyphY|Measure-Object -Maximum).Maximum)/2
    $textCenter=(($textY|Measure-Object -Minimum).Minimum+($textY|Measure-Object -Maximum).Maximum)/2
    $contentCenter=$r.Left-$outer.Left+(($inkX|Measure-Object -Minimum).Minimum+($inkX|Measure-Object -Maximum).Maximum)/2
    $horizontal=[Math]::Abs($contentCenter-($outer.Right-$outer.Left)/2)
    $vertical=[Math]::Abs($glyphCenter-$textCenter)
    @{name=$Name;glyphCenter=$glyphCenter;textCenter=$textCenter;verticalDifference=$vertical;horizontalDifference=$horizontal}|ConvertTo-Json -Compress|Add-Content (Join-Path $work 'launch-alignment.jsonl') -Encoding utf8
    if($vertical-gt1*$scale){throw ('启动复选框和文字未垂直对齐: '+$vertical)}
    if($horizontal-gt1.5*$scale){throw ('启动选项未在窗口中居中: '+$horizontal)}
  } finally {$crop.Dispose();$image.Dispose()}
  [void][InnoUi]::SendMessage($Window,0x28,$check,[IntPtr]1)
  [void][InnoUi]::PostMessage($check,0x100,[IntPtr]32,[IntPtr]::Zero)
  [void][InnoUi]::PostMessage($check,0x101,[IntPtr]32,[IntPtr]::Zero)
  Start-Sleep -Milliseconds 100
  if([InnoUi]::SendMessage($check,0xF0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne1){throw '启动复选框不能使用空格勾选。'}
  [void][InnoUi]::PostMessage($check,0x201,[IntPtr]1,[IntPtr]0x00100020)
  [void][InnoUi]::PostMessage($check,0x202,[IntPtr]::Zero,[IntPtr]0x00100020)
  Start-Sleep -Milliseconds 100
  if([InnoUi]::SendMessage($check,0xF0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne0){throw '点击启动文字没有切换勾选状态。'}
}
try {
  $window=[IntPtr]::Zero
  for ($i=0;$i -lt 100;$i++) { $window=[InnoUi]::Find(); if ($window -ne [IntPtr]::Zero) { break }; Start-Sleep -Milliseconds 100 }
  if ($window -eq [IntPtr]::Zero) { throw 'Inno 自定义窗口未出现。' }
  Start-Sleep -Milliseconds 500
  if($CompletionOnly){
    if(-not$Execute-or$Installer-notlike '*validation*'){throw '完成页验证只允许执行 validation 安装包。'}
    foreach($locale in @('zh','en')){
      if($locale-eq'en'){
        $process=Start-Process -FilePath $Installer -ArgumentList @('/UILANG=en',('/ROOT="'+$target+'"')) -WindowStyle Normal -PassThru
        for($i=0;$i-lt100;$i++){$window=[InnoUi]::Find();if($window-ne[IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}
        Start-Sleep -Milliseconds 300
      }
      $action='安装';if($locale-eq'en'){$action='Reinstall'}
      Click-Label $window $action
      for($i=0;$i-lt240;$i++){if((Visible-Text $window)-contains '安装完成'-or(Visible-Text $window)-contains 'Installation complete'){break};Start-Sleep -Milliseconds 250}
      if($i-eq240){throw '完成页验证没有到达完成状态。'}
      Save-Window $window ('completed-'+$locale)
      Assert-LaunchAlignment $window ('completed-'+$locale)
      $finish='完成';if($locale-eq'en'){$finish='Finish'}
      Click-Label $window $finish
      if(-not$process.WaitForExit(10000)-or$process.ExitCode-ne0){throw '完成页没有正常退出。'}
    }
    $worker=Join-Path $RepositoryRoot 'build/packaging/inno7/validation/ShenView-Uninstall.exe'
    $cleanup=Start-Process -FilePath $worker -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES',('/ROOT="'+$target+'"')) -WindowStyle Hidden -PassThru
    if(-not$cleanup.WaitForExit(120000)-or$cleanup.ExitCode-ne0){throw '完成页验证安装清理失败。'}
    @{passed=$true;executed=$true;completionOnly=$true;work=$work;installer=[IO.Path]::GetFullPath($Installer)}|ConvertTo-Json|Set-Content (Join-Path $work 'ui-results.json') -Encoding utf8
    Write-Output $work
    return
  }
  Save-WindowContext $window
  Save-Window $window 'install-zh'
  Assert-FixedOptions $window @('桌面快捷方式','开始菜单快捷方式')
  if ([InnoUi]::Text($window) -ne '神羊看图') {throw '中文窗口标题不正确。'}
  Assert-PathInk $window 'install-zh'
  $texts = Visible-Text $window
  if(-not($texts -contains '打开方式：图片 29 种 · 压缩包 0 种')) {throw '首装没有显示格式摘要。'}
  $outer=[InnoUi+Rect]::new();$client=[InnoUi+Rect]::new()
  [void][InnoUi]::GetWindowRect($window,[ref]$outer);[void][InnoUi]::GetClientRect($window,[ref]$client)
  $dpiScale=[InnoUi]::GetDpiForWindow($window)/96.0
  $expectedHeight=480;if($WorkAreaHeight){$expectedHeight=[Math]::Max(432,[Math]::Min(480,$WorkAreaHeight-16))}
  if($client.Right-ne[Math]::Round(640*$dpiScale) -or $client.Bottom-ne[Math]::Round($expectedHeight*$dpiScale)){throw ('安装窗口尺寸不符合目标: '+$client.Right+'x'+$client.Bottom)}
  if($WorkAreaHeight){
    $area=[Windows.Forms.Screen]::FromHandle($window).WorkingArea
    if($outer.Top-lt$area.Top -or $outer.Bottom-gt($area.Top+$WorkAreaHeight*$dpiScale)){throw '安装窗口超出模拟工作区。'}
  }
  if (($outer.Bottom-$outer.Top) -ne ($client.Bottom-$client.Top) -or ($outer.Right-$outer.Left) -ne ($client.Right-$client.Left)) {throw '安装窗口仍留有系统标题栏或非客户区。'}
  if (@($texts | Where-Object {$_ -eq '神羊看图'}).Count -ne 1) {throw '品牌名称重复或缺失。'}
  if (-not ($texts | Where-Object {$_ -match '^(安装|更新|重新安装|修复安装)$'})) { throw ('缺少中文标题: ' + ($texts -join '|')) }
  $combo = [InnoUi]::Children($window) | Where-Object { [InnoUi]::Class($_) -like '*ComboBox*' -and [InnoUi]::IsWindowVisible($_) } | Select-Object -First 1
  if (-not $combo) { throw '找不到语言选择控件。' }
  [InnoUi]::Select($combo,2)
  Start-Sleep -Milliseconds 200
  if (-not ((Visible-Text $window) | Where-Object {$_ -match '^(Install|Update|Reinstall|Repair)$'})) { Save-Window $window 'failed-language'; throw ('即时英文切换失败: ' + ((Visible-Text $window) -join '|')) }
  Save-Window $window 'install-en'
  $surface=[Drawing.Bitmap]::new((Join-Path $work 'install-en.png'))
  try{
    $background=$surface.GetPixel(10,10).GetBrightness()
    foreach($point in @(@(320,60),@(320,238))){
      $pixel=$surface.GetPixel([int]($surface.Width*$point[0]/640),[int]($surface.Height*$point[1]/480))
      if([Math]::Abs($pixel.GetBrightness()-$background)-gt0.08){throw '辅助文字标签背景与窗口不一致。'}
    }
  }finally{$surface.Dispose()}
  Assert-FixedOptions $window @('Desktop shortcut','Start menu shortcut')
  if ([InnoUi]::Text($window) -ne 'ShenView') {throw '英文窗口标题不正确。'}
  Assert-PathInk $window 'install-en'
  $pathControl = [InnoUi]::Children($window) | Where-Object { [InnoUi]::Class($_) -like '*PathEdit*' -and [InnoUi]::IsWindowVisible($_) } | Select-Object -First 1
  if ([InnoUi]::Text($pathControl) -ne $target) {throw '窗口显示的路径与指定的验证路径不同。'}
  $browseControl = [InnoUi]::Children($window) | Where-Object { [InnoUi]::Text($_) -eq 'Browse…' -and [InnoUi]::IsWindowVisible($_) } | Select-Object -First 1
  $pathRect=[InnoUi+Rect]::new(); $browseRect=[InnoUi+Rect]::new()
  [void][InnoUi]::GetWindowRect([InnoUi]::GetParent([InnoUi]::GetParent($pathControl)),[ref]$pathRect); [void][InnoUi]::GetWindowRect($browseControl,[ref]$browseRect)
  if ($pathRect.Top -ne $browseRect.Top -or $pathRect.Bottom -ne $browseRect.Bottom) { throw '路径外框与浏览按钮没有对齐。' }
  Assert-ButtonStates $window $browseControl
  $unrelated=Join-Path $work 'unrelated/ShenView'
  New-Item -ItemType Directory -Path $unrelated -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $unrelated 'personal.txt') -Value 'Keep this file.'
  [void][InnoUi]::SetText($pathControl,0x000C,[IntPtr]::Zero,$unrelated)
  Save-Window $window 'invalid-folder'
  Assert-FixedOptions $window @('Desktop shortcut','Start menu shortcut')
  if(-not ((Visible-Text $window) -contains 'This folder contains unrelated files. Choose an empty folder.')) {throw '无关非空目录没有显示阻止说明。'}
  [void][InnoUi]::SetText($pathControl,0x000C,[IntPtr]::Zero,$target)
  [InnoUi]::Select($combo,1)
  $dialog=Open-Formats $window
  Save-Window $dialog 'formats-expanded'
  $formatControls=Format-Checks $dialog
  if($formatControls.Count-ne29){throw '图片格式网格数量不正确。'}
  $dialogRect=[InnoUi+Rect]::new();[void][InnoUi]::GetWindowRect($dialog,[ref]$dialogRect)
  if($WorkAreaHeight -and ($dialogRect.Top-lt$area.Top -or $dialogRect.Bottom-gt($area.Top+$WorkAreaHeight*$dpiScale))){throw '格式弹窗超出模拟工作区。'}
  $dialogCancel=[InnoUi]::Children($dialog) | Where-Object {[InnoUi]::Text($_)-eq '取消' -and [InnoUi]::IsWindowVisible($_)} | Select-Object -First 1
  $cancelRect=[InnoUi+Rect]::new();[void][InnoUi]::GetWindowRect($dialogCancel,[ref]$cancelRect)
  foreach($format in $formatControls){
    $r=[InnoUi+Rect]::new();[void][InnoUi]::GetWindowRect($format,[ref]$r)
    if($r.Bottom-gt($cancelRect.Top-16*$dpiScale)){throw '格式选项被底部操作区遮挡。'}
  }
  Click-Label $dialog '清空'
  foreach($format in $formatControls){if([InnoUi]::SendMessage($format,0xF0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne0){throw '清空没有取消所有格式。'}}
  Close-Formats $dialog '取消'
  if(-not((Visible-Text $window)-contains '打开方式：图片 29 种 · 压缩包 0 种')){throw '取消格式选择仍更改了摘要。'}
  $dialog=Open-Formats $window -Keyboard
  Click-Label $dialog '清空'; Click-Label $dialog '全选'
  $formatControls=Format-Checks $dialog
  foreach($format in $formatControls){if([InnoUi]::SendMessage($format,0xF0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne1){throw '全选没有选中所有格式。'}}
  [void][InnoUi]::SendMessage($formatControls[0],0xF5,[IntPtr]::Zero,[IntPtr]::Zero)
  Click-Label $dialog '压缩包格式'
  if((Format-Checks $dialog).Count-ne8){throw '压缩包格式网格数量不正确。'}
  Save-Window $dialog 'archive-formats'
  Click-Label $dialog '全选'
  Click-Label $dialog '图片格式'
  if([InnoUi]::SendMessage((Format-Checks $dialog)[0],0xF0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne0){throw '切换标签丢失了暂存选择。'}
  Close-Formats $dialog '确定'
  if(-not((Visible-Text $window)-contains '打开方式：图片 28 种 · 压缩包 8 种')){throw '确定没有提交两个格式分组。'}
  $dialog=Open-Formats $window
  Click-Label $dialog '全选'; Click-Label $dialog '压缩包格式'; Click-Label $dialog '清空'
  Close-Formats $dialog '确定'
  Assert-FixedOptions $window @('桌面快捷方式','开始菜单快捷方式')
  Save-Window $window 'shortcuts'
  [InnoUi]::Select($combo,2)
  $dialog=Open-Formats $window
  Save-Window $dialog 'formats-en'
  if((Format-Checks $dialog).Count-ne29){throw '英文格式选择弹窗没有正确显示。'}
  Close-Formats $dialog 'Cancel'
  [InnoUi]::Select($combo,1)
  [InnoUi]::Children($window) | Where-Object { [InnoUi]::IsWindowVisible($_) } | ForEach-Object {
    $r=[InnoUi+Rect]::new(); [void][InnoUi]::GetWindowRect($_,[ref]$r)
    @{text=[InnoUi]::Text($_);class=[InnoUi]::Class($_);left=$r.Left;top=$r.Top;right=$r.Right;bottom=$r.Bottom;enabled=[InnoUi]::IsWindowEnabled($_)}
  } | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $work 'controls.json') -Encoding utf8
  if ($Execute) {
    if ($Installer -notlike '*validation*') { throw '界面自动执行只允许 validation 安装包。' }
    $cacheKey='HKCU:/Software/Classes/Local Settings/Software/Microsoft/Windows/Shell/MuiCache'
    $cacheName=Join-Path $target 'ShenView.exe.FriendlyAppName'
    $cacheSentinel=Join-Path $work 'unrelated.exe.FriendlyAppName'
    New-ItemProperty -LiteralPath $cacheKey -Name $cacheName -Value '神羊看图 / ShenView' -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $cacheKey -Name $cacheSentinel -Value 'Do not change' -PropertyType String -Force | Out-Null
    $install = [InnoUi]::Children($window) | Where-Object { [InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_) -eq '安装' -and [InnoUi]::Class($_) -like '*Button*' } | Select-Object -First 1
    [void][InnoUi]::PostMessage($install,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    Start-Sleep -Milliseconds 300
    if (-not ((Visible-Text $window) -contains '安装中…') -and -not ((Visible-Text $window) -match '^(安装完成|卸载完成)$')) { throw '安装中没有状态标题。' }
    Save-Window $window 'progress'
    if ((Visible-Text $window) -contains '安装中…') {
      if (-not ((Visible-Text $window) -contains '完成后关闭')) {throw '安装期间缺少延后关闭操作。'}
      if (-not ((Visible-Text $window) -contains '可最小化，操作会继续。')) {throw '安装期间缺少关闭提示。'}
    }
    for ($i=0;$i -lt 240;$i++) {
      Start-Sleep -Milliseconds 250
      if ((Visible-Text $window) -match '^(安装完成|卸载完成)$') { break }
    }
    if (-not ((Visible-Text $window) -match '^(安装完成|卸载完成)$')) { throw ('安装前端没有到达完成页: ' + ((Visible-Text $window) -join '|')) }
    Save-Window $window 'completed'
    if($VerifyCodecs){& (Join-Path $PSScriptRoot 'windows_codec_layout.ps1') -InstallRoot $target -OutputDirectory (Join-Path $work 'codecs')}
    $cacheValues=Get-ItemProperty -LiteralPath $cacheKey
    if($cacheValues.PSObject.Properties[$cacheName] -and $cacheValues.PSObject.Properties[$cacheName].Value -ne 'ShenView') {throw '安装完成后旧显示名称缓存没有刷新。'}
    if($cacheValues.PSObject.Properties[$cacheSentinel].Value -ne 'Do not change') {throw '刷新名称修改了其他应用的缓存。'}
    Remove-ItemProperty -LiteralPath $cacheKey -Name $cacheSentinel
    $config = Get-Content -LiteralPath (Join-Path $target 'test-user/settings.json') -Raw | ConvertFrom-Json
    if ($config.settings.localeCode -ne 'zh') { throw '安装后的语言偏好没有保存。' }
    $finish = [InnoUi]::Children($window) | Where-Object { [InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_) -eq '完成' } | Select-Object -First 1
    [void][InnoUi]::PostMessage($finish,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    Start-Sleep -Milliseconds 500
    $stateKey='HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/ShenView.Inno7.Validation_is1'
    if(Test-Path (Join-Path $target 'install.ini')) {throw '新安装仍生成 install.ini。'}
    if((Get-ItemProperty $stateKey).'Inno Setup: Language' -ne 'zh') {throw '界面语言未写入卸载记录。'}
    $startShortcut=Join-Path ([Environment]::GetFolderPath('Programs')) 'ShenView Inno7 Validation.lnk'
    $startBytes=[IO.File]::ReadAllBytes($startShortcut)
    $pngKey='HKCU:/Software/ShenView/Inno7Validation/Classes/.png/OpenWithProgids'
    Remove-Item -LiteralPath $startShortcut
    Remove-ItemProperty -LiteralPath $pngKey -Name 'ShenView.Machine.png'
    try {
      $process=Start-Process -FilePath $Installer -ArgumentList @('/UILANG=zh',('/ROOT="'+$target+'"')) -WindowStyle Normal -PassThru
      for($i=0;$i -lt 100;$i++) {$window=[InnoUi]::Find();if($window-ne[IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}
      $startOption=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '开始菜单快捷方式'} | Select-Object -First 1
      if(-not $startOption -or [InnoUi]::SendMessage($startOption,0x00F0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne 0) {throw '已删除的快捷方式被旧安装选择重新勾选。'}
      Save-Window $window 'external-registry-state'
      $dialog=Open-Formats $window
      $pngOption=[InnoUi]::Children($dialog) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '.png'} | Select-Object -First 1
      $jpgOption=[InnoUi]::Children($dialog) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '.jpg'} | Select-Object -First 1
      if(-not $pngOption -or [InnoUi]::SendMessage($pngOption,0x00F0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne 0) {throw '外部取消的 PNG 关联没有从实际注册项读取。'}
      if(-not $jpgOption -or [InnoUi]::SendMessage($jpgOption,0x00F0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne 1) {throw '未变更的 JPG 关联没有保留。'}
      Save-Window $dialog 'external-format-state'
      Close-Formats $dialog '取消'
      $cancelOption=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '取消'} | Select-Object -First 1
      [void][InnoUi]::PostMessage($cancelOption,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
      if(-not $process.WaitForExit(10000)) {throw '状态读取验证窗口没有退出。'}
    } finally {
      [IO.File]::WriteAllBytes($startShortcut,$startBytes)
      New-ItemProperty -LiteralPath $pngKey -Name 'ShenView.Machine.png' -Value '' -PropertyType String -Force | Out-Null
    }
    $appArguments=@{}
    if($VerifyCodecs){$appArguments.ArgumentList=@('--',('"'+(Join-Path $ViewerRoot 'testdata/formats/format_static.psd')+'"'))}
    $runningApp = Start-Process -FilePath (Join-Path $target 'ShenView.exe') @appArguments -WorkingDirectory $target -WindowStyle Normal -PassThru
    try {
      for ($i=0;$i -lt 100;$i++) {Start-Sleep -Milliseconds 100; $runningApp.Refresh(); if ($runningApp.MainWindowHandle -ne [IntPtr]::Zero) {break}}
      if ($runningApp.HasExited -or $runningApp.MainWindowHandle -eq [IntPtr]::Zero) {throw '验证应用未成功启动。'}
      if($VerifyCodecs){
        Start-Sleep -Milliseconds 1800
        Save-Window $runningApp.MainWindowHandle 'installed-app-psd' -FromScreen
        $runningApp.Modules | Select-Object ModuleName,FileName | ConvertTo-Json | Set-Content (Join-Path $work 'installed-app-modules.json') -Encoding utf8
      }
      $silentBlocked = Start-Process -FilePath $Installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/ROOT="'+$target+'"')) -WindowStyle Hidden -PassThru
      if (-not $silentBlocked.WaitForExit(10000)) {throw '应用运行时的静默重装未退出。'}
      if ($silentBlocked.ExitCode -eq 0 -or $runningApp.HasExited) {throw '静默重装错误地关闭应用或报告成功。'}
      $process = Start-Process -FilePath $Installer -ArgumentList @('/UILANG=zh',('/ROOT="'+$target+'"')) -WindowStyle Normal -PassThru
      for ($i=0;$i -lt 100;$i++) {$window=[InnoUi]::Find(); if ($window -ne [IntPtr]::Zero) {break}; Start-Sleep -Milliseconds 100}
      Start-Sleep -Milliseconds 300
      Save-Window $window 'reinstall'
      Assert-FixedOptions $window @('桌面快捷方式','开始菜单快捷方式')
      $reinstall = [InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_) -eq '重新安装' -and [InnoUi]::Class($_) -like '*Button*'} | Select-Object -First 1
      if (-not $reinstall) {throw '没有识别出已安装副本。'}
      [void][InnoUi]::PostMessage($reinstall,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
      for ($i=0;$i -lt 100;$i++) {$prompt=[InnoUi]::ClosePrompt(); if ($prompt -ne [IntPtr]::Zero) {break}; Start-Sleep -Milliseconds 100}
      if ($prompt -eq [IntPtr]::Zero) {throw '重装未提示关闭运行中的应用。'}
      Save-Window $prompt 'close-app-confirmation'
      [void][InnoUi]::PostMessage([InnoUi]::DialogButton($prompt,2),0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
      Start-Sleep -Milliseconds 200
      if ($runningApp.HasExited) {throw '取消重装关闭确认后仍退出了应用。'}
      [void][InnoUi]::PostMessage($reinstall,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
      for ($i=0;$i -lt 100;$i++) {$prompt=[InnoUi]::ClosePrompt(); if ($prompt -ne [IntPtr]::Zero) {break}; Start-Sleep -Milliseconds 100}
      if ($prompt -eq [IntPtr]::Zero) {throw '第二次重装缺少关闭确认。'}
      [void][InnoUi]::PostMessage([InnoUi]::DialogButton($prompt,1),0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
      if (-not $runningApp.WaitForExit(10000)) {throw '重装没有正常关闭验证应用。'}
      $runningApp.Dispose(); $runningApp = $null
      for ($i=0;$i -lt 240;$i++) {Start-Sleep -Milliseconds 250; if ((Visible-Text $window) -match '^(安装完成|卸载完成)$') {break}}
      if (-not ((Visible-Text $window) -match '^(安装完成|卸载完成)$')) {Save-Window $window 'failed-reinstall'; throw ('关闭应用后的重装失败: '+((Visible-Text $window) -join '|'))}
      Save-Window $window 'reinstalled'
      $finish = [InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_) -eq '完成'} | Select-Object -First 1
      [void][InnoUi]::PostMessage($finish,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
      Start-Sleep -Milliseconds 500
    } finally {
      if ($null -ne $runningApp) {
        if (-not $runningApp.HasExited) {[void]$runningApp.CloseMainWindow(); [void]$runningApp.WaitForExit(5000)}
        $runningApp.Dispose()
      }
    }
    $shortcutShell=New-Object -ComObject WScript.Shell
    $existingDesktop=Join-Path ([Environment]::GetFolderPath('Desktop')) 'ShenView Inno7 Validation.lnk'
    $link=$shortcutShell.CreateShortcut($existingDesktop);$link.TargetPath=Join-Path $target 'ShenView.exe';$link.Save()
    $process=Start-Process -FilePath $Installer -ArgumentList @('/UILANG=zh',('/ROOT="'+$target+'"')) -WindowStyle Normal -PassThru
    for($i=0;$i -lt 100;$i++) {$window=[InnoUi]::Find();if($window-ne[IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}
    $pathControl=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Class($_)-like '*PathEdit*'} | Select-Object -First 1
    $browseControl=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '浏览…'} | Select-Object -First 1
    if(-not [InnoUi]::IsWindowEnabled($browseControl) -or ([InnoUi]::WindowStyle($pathControl,-16)-band 0x800)-ne 0) {throw '重新安装仍不能更换安装位置。'}
    Assert-FixedOptions $window @('桌面快捷方式','开始菜单快捷方式')
    $desktopOption=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '桌面快捷方式'} | Select-Object -First 1
    if(-not $desktopOption){throw '未找到直接展示的桌面快捷方式选项。'}
    if([InnoUi]::SendMessage($desktopOption,0x00F0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne 1){throw '已有桌面快捷方式没有自动保留。'}
    $movedTarget=Join-Path $work 'moved/ShenView'
    [void][InnoUi]::SetText($pathControl,0x000C,[IntPtr]::Zero,$movedTarget)
    Save-Window $window 'migration-options'
    Assert-FixedOptions $window @('桌面快捷方式','开始菜单快捷方式')
    $reinstall=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '重新安装' -and [InnoUi]::Class($_)-like '*Button*'} | Select-Object -First 1
    [void][InnoUi]::PostMessage($reinstall,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    for($i=0;$i -lt 100;$i++) {$prompt=[InnoUi]::MigrationPrompt();if($prompt-ne[IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}
    if($prompt-eq[IntPtr]::Zero){throw '更换目录没有迁移确认。'}
    Save-Window $prompt 'migration-confirmation'
    [void][InnoUi]::PostMessage([InnoUi]::DialogButton($prompt,2),0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    Start-Sleep -Milliseconds 200
    if(-not(Test-Path (Join-Path $target 'ShenView.exe')) -or (Test-Path $movedTarget)){throw '取消迁移后仍更改了安装。'}
    [void][InnoUi]::PostMessage($reinstall,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    for($i=0;$i -lt 100;$i++) {$prompt=[InnoUi]::MigrationPrompt();if($prompt-ne[IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}
    [void][InnoUi]::PostMessage([InnoUi]::DialogButton($prompt,1),0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    for($i=0;$i -lt 240;$i++) {Start-Sleep -Milliseconds 250;if((Visible-Text $window)-match '^(安装完成|卸载完成)$'){break}}
    if(-not((Visible-Text $window)-match '^(安装完成|卸载完成)$')){Save-Window $window 'failed-migration';throw '界面迁移没有完成。'}
    if(Test-Path (Join-Path $target 'ShenView.exe')){throw '界面迁移后旧目录未清理。'}
    if(-not(Test-Path (Join-Path $movedTarget 'test-user/settings.json'))){throw '界面迁移没有继承设置。'}
    Save-Window $window 'migration-completed'
    if($shortcutShell.CreateShortcut($existingDesktop).TargetPath-ne(Join-Path $movedTarget 'ShenView.exe')){throw '原记录未勾选的已有桌面快捷方式没有更新目标。'}
    $target=$movedTarget
    $finish=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '完成'} | Select-Object -First 1
    [void][InnoUi]::PostMessage($finish,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    if(-not $process.WaitForExit(10000)){throw '迁移完成后窗口未退出。'}
    $runningApp=Start-Process -FilePath (Join-Path $target 'ShenView.exe') -WorkingDirectory $target -WindowStyle Normal -PassThru
    for($i=0;$i -lt 100;$i++) {$runningApp.Refresh();if($runningApp.MainWindowHandle-ne[IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}
    # The native HWND appears before Dart finishes registering window listeners.
    Start-Sleep -Milliseconds 1500
    if($runningApp.HasExited -or $runningApp.MainWindowHandle-eq[IntPtr]::Zero){throw '卸载验证的应用未成功启动。'}
    $process = Start-Process -FilePath (Join-Path $target 'uninstall.exe') -ArgumentList @('/MODE=uninstall',('/ROOT="' + $target + '"')) -WindowStyle Normal -PassThru
    for ($i=0;$i -lt 100;$i++) { $window=[InnoUi]::Find(); if ($window -ne [IntPtr]::Zero) { break }; Start-Sleep -Milliseconds 100 }
    if ($window -eq [IntPtr]::Zero) { throw '维护前端未出现。' }
    Start-Sleep -Milliseconds 300
    Save-Window $window 'uninstall'
    if(@([InnoUi]::Children($window)|Where-Object {[InnoUi]::IsWindowVisible($_) -and ([InnoUi]::Class($_)-like '*PathEdit*' -or [InnoUi]::Text($_)-in @('浏览…','Browse…'))}).Count-ne0){throw '卸载界面仍显示路径输入框或浏览按钮。'}
    $uninstall = [InnoUi]::Children($window) | Where-Object { [InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_) -eq '卸载' -and [InnoUi]::Class($_) -like '*Button*' } | Select-Object -First 1
    if (-not $uninstall) { throw ('卸载按钮不存在: ' + ((Visible-Text $window) -join '|')) }
    [void][InnoUi]::PostMessage($uninstall,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    for($i=0;$i -lt 100;$i++) {$prompt=[InnoUi]::ClosePrompt();if($prompt-ne[IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}
    if($prompt-eq[IntPtr]::Zero){throw '卸载前没有关闭应用确认。'}
    Save-Window $prompt 'uninstall-close-confirmation'
    [void][InnoUi]::PostMessage([InnoUi]::DialogButton($prompt,1),0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    if(-not $runningApp.WaitForExit(10000)){throw '卸载未等待应用正常退出。'}
    $runningApp.Dispose();$runningApp=$null
    for ($i=0;$i -lt 240;$i++) { Start-Sleep -Milliseconds 250; if ((Visible-Text $window) -match '^(安装完成|卸载完成)$') { break } }
    if (-not ((Visible-Text $window) -match '^(安装完成|卸载完成)$')) { Save-Window $window 'failed-uninstall'; throw ('卸载前端没有到达完成页: ' + ((Visible-Text $window) -join '|')) }
    Save-Window $window 'uninstalled'
    if (Test-Path -LiteralPath (Join-Path $target 'ShenView.exe')) { throw '卸载后仍有主程序。' }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'test-user/settings.json'))) { throw '卸载删除了用户设置。' }
    $finish=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '完成'} | Select-Object -First 1
    [void][InnoUi]::PostMessage($finish,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    for($i=0;$i -lt 100 -and [InnoUi]::IsWindow($window);$i++){Start-Sleep -Milliseconds 100}
    $target=Join-Path $work 'Complete/ShenView'
    $installFixture=Start-Process -FilePath $Installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES',('/ROOT="'+$target+'"'),'/UILANG=zh') -WindowStyle Hidden -PassThru
    if(-not $installFixture.WaitForExit(120000) -or $installFixture.ExitCode-ne0){throw '完全卸载界面验证的初始安装失败。'}
    [IO.File]::WriteAllText((Join-Path $target 'personal.txt'),'full-uninstall-fixture')
    New-Item -ItemType Directory -Path ($target+'.user-data/cache') -Force | Out-Null
    [IO.File]::WriteAllText(($target+'.user-data/cache/test.txt'),'cache-fixture')
    $process=Start-Process -FilePath (Join-Path $target 'uninstall.exe') -WindowStyle Normal -PassThru
    $purge=$null
    for($i=0;$i -lt 100;$i++){
      $window=[InnoUi]::Find()
      if($window-ne[IntPtr]::Zero){
        $purge=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '同时删除设置、阅读记录和缓存'} | Select-Object -First 1
        if($purge){break}
      }
      Start-Sleep -Milliseconds 100
    }
    if(-not $purge){
      if($window-ne[IntPtr]::Zero){Save-Window $window 'failed-uninstall-options'}
      throw ('完全卸载界面未准备好: '+((Visible-Text $window)-join '|'))
    }
    if([InnoUi]::SendMessage($purge,0xF0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne0){throw '完全卸载不应默认勾选。'}
    [void][InnoUi]::SendMessage($purge,0xF5,[IntPtr]::Zero,[IntPtr]::Zero)
    Start-Sleep -Milliseconds 150
    if([InnoUi]::SendMessage($purge,0xF0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-ne1){throw '完全卸载选项未勾选。'}
    Save-Window $window 'complete-uninstall-options'
    $combo=[InnoUi]::Children($window) | Where-Object {[InnoUi]::Class($_)-like '*ComboBox*' -and [InnoUi]::IsWindowVisible($_)} | Select-Object -First 1
    [InnoUi]::Select($combo,2); Start-Sleep -Milliseconds 200
    Save-Window $window 'complete-uninstall-options-en'
    if(-not((Visible-Text $window)-contains 'Also delete settings, history and caches')){throw '完全卸载选项未翻译。'}
    [InnoUi]::Select($combo,1); Start-Sleep -Milliseconds 200
    $uninstall=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_)-eq '卸载' -and [InnoUi]::Class($_)-like '*Button*'} | Select-Object -First 1
    [void][InnoUi]::PostMessage($uninstall,0xF5,[IntPtr]::Zero,[IntPtr]::Zero)
    for($i=0;$i-lt100;$i++){$prompt=[InnoUi]::PurgePrompt();if($prompt-ne[IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}
    if($prompt-eq[IntPtr]::Zero){throw '完全卸载未提供删除确认。'}
    Save-Window $prompt 'complete-uninstall-confirmation'
    [void][InnoUi]::PostMessage([InnoUi]::DialogButton($prompt,2),0xF5,[IntPtr]::Zero,[IntPtr]::Zero)
    Start-Sleep -Milliseconds 200
    if(-not(Test-Path (Join-Path $target 'ShenView.exe')) -or -not(Test-Path (Join-Path $target 'personal.txt'))){throw '取消完全卸载确认后文件被更改。'}
    [void][InnoUi]::PostMessage($uninstall,0xF5,[IntPtr]::Zero,[IntPtr]::Zero)
    for($i=0;$i-lt100;$i++){$prompt=[InnoUi]::PurgePrompt();if($prompt-ne[IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}
    [void][InnoUi]::PostMessage([InnoUi]::DialogButton($prompt,1),0xF5,[IntPtr]::Zero,[IntPtr]::Zero)
    for($i=0;$i-lt360;$i++){Start-Sleep -Milliseconds 250;if((Visible-Text $window)-match '^(安装完成|卸载完成)$'){break}}
    if(-not((Visible-Text $window)-match '^(安装完成|卸载完成)$')){Save-Window $window 'failed-complete-uninstall';throw ('完全卸载未完成: '+((Visible-Text $window)-join '|'))}
    Save-Window $window 'complete-uninstalled'
    if((Test-Path $target) -or (Test-Path ($target+'.user-data'))){throw '完全卸载后仍残留安装或用户数据目录。'}
  }
  $sizes=@(Get-Content (Join-Path $work 'window-sizes.jsonl') | ForEach-Object {$_ | ConvertFrom-Json})
  foreach($group in @(
    @('install-zh','install-en','shortcuts','progress','completed','reinstall','reinstalled','migration-options','migration-completed'),
    @('formats-expanded','archive-formats','formats-en'),
    @('uninstall','uninstalled'),
    @('complete-uninstall-options','complete-uninstall-options-en','complete-uninstalled')
  )){
    $dimensions=@($sizes | Where-Object {$_.name -in $group} | ForEach-Object {"$($_.width)x$($_.height)"} | Select-Object -Unique)
    if($dimensions.Count-gt1){throw ('同一流程窗口尺寸发生变化: '+($group-join ',')+' '+($dimensions-join ','))}
  }
  @{passed=$true;executed=[bool]$Execute;work=$work;installer=[IO.Path]::GetFullPath($Installer)} | ConvertTo-Json | Set-Content (Join-Path $work 'ui-results.json') -Encoding utf8
  Write-Output $work
} finally {
  $dialog=[InnoUi]::FormatDialog()
  if($dialog-ne[IntPtr]::Zero){
    $cancelLabel='取消';if([InnoUi]::Text($dialog)-eq 'Customize Open With'){$cancelLabel='Cancel'}
    Close-Formats $dialog $cancelLabel
  }
  if($Execute -and $cacheKey) {
    foreach($name in @($cacheName,$cacheSentinel)) {
      if($name) {Remove-ItemProperty -LiteralPath $cacheKey -Name $name -ErrorAction SilentlyContinue}
    }
  }
  if ($window -ne [IntPtr]::Zero) {
    $back = [InnoUi]::Children($window) | Where-Object { [InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_) -in @('返回','Back') } | Select-Object -First 1
    if ($back) { [void][InnoUi]::SendMessage($back,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero) }
    $finish = [InnoUi]::Children($window) | Where-Object { [InnoUi]::IsWindowVisible($_) -and [InnoUi]::Text($_) -in @('完成','Finish') } | Select-Object -First 1
    if ($finish) { [void][InnoUi]::PostMessage($finish,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero) }
    else {
      $cancel=[InnoUi]::Children($window) | Where-Object {[InnoUi]::IsWindowVisible($_) -and [InnoUi]::Class($_)-like '*Button*' -and [InnoUi]::Text($_)-in @('取消','Cancel')} | Select-Object -First 1
      if($cancel){[void][InnoUi]::PostMessage($cancel,0xF5,[IntPtr]::Zero,[IntPtr]::Zero)}
      else {[void][InnoUi]::PostMessage($window,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)}
    }
    for ($i=0;$i -lt 50 -and [InnoUi]::IsWindow($window);$i++) { Start-Sleep -Milliseconds 50 }
  }
  if (-not $process.WaitForExit(10000)) { throw '验证窗口关闭后进程没有退出。' }
  if ($process.ExitCode -lt 0) { throw ('验证窗口退出异常: ' + $process.ExitCode) }
}
