[CmdletBinding()]
param([Parameter(Mandatory)][string]$Installer,[int]$WorkAreaHeight=0,[switch]$English)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference='Stop'
if($Installer-notlike '*validation*'){throw '失败界面验证只允许 validation 安装包。'}
$Installer=(Resolve-Path -LiteralPath $Installer).Path
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class FailureUi {
  public delegate bool Visit(IntPtr w,IntPtr c);
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
  [DllImport("user32.dll")] static extern bool EnumWindows(Visit v,IntPtr c);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p,Visit v,IntPtr c);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr w,StringBuilder b,int n);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr w,StringBuilder b,int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr w);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr w);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr w);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr w);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w,out Rect r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr w,IntPtr dc,uint f);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr w,uint m,IntPtr a,IntPtr b);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr w,uint m,IntPtr a,IntPtr b);
  public static string Text(IntPtr w){var b=new StringBuilder(4096);GetWindowText(w,b,b.Capacity);return b.ToString();}
  public static string Class(IntPtr w){var b=new StringBuilder(256);GetClassName(w,b,b.Capacity);return b.ToString();}
  public static IntPtr[] Children(IntPtr p){var r=new List<IntPtr>();EnumChildWindows(p,(w,c)=>{if(IsWindowVisible(w))r.Add(w);return true;},IntPtr.Zero);return r.ToArray();}
  public static IntPtr Find(){IntPtr r=IntPtr.Zero;EnumWindows((w,c)=>{if(Class(w)=="TWizardForm" && IsWindowVisible(w) && (Text(w)=="神羊看图" || Text(w)=="ShenView")){r=w;return false;}return true;},IntPtr.Zero);return r;}
}
'@
$work=Join-Path $RepositoryRoot ('build/packaging/inno7-failure-ui/'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$key='HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/ShenView.Inno7.Validation_is1'
if(Test-Path $key){throw '已有 validation 安装，请先卸载后再验证。'}
$engine=Join-Path $RepositoryRoot 'build/packaging/inno7/validation/ShenView-Setup.exe'
$worker=Join-Path $RepositoryRoot 'build/packaging/inno7/validation/ShenView-Uninstall.exe'
$results=[Collections.Generic.List[object]]::new()
$recoveryRoot=Join-Path $env:LOCALAPPDATA 'ShenView-Inno7-Validation/Installer/Transactions'
$existingCopies=@(Get-ChildItem -LiteralPath $recoveryRoot -Directory -ErrorAction SilentlyContinue|Select-Object -ExpandProperty FullName)
$window=[IntPtr]::Zero
$captions=@{'安装位置'='Install location';'当前位置'='Current location';'桌面快捷方式'='Desktop shortcut';'安装'='Install';'重新安装'='Reinstall';'正在恢复…'='Restoring previous state…';'完成后关闭'='Close when done';'安装未完成'='Install failed';'重新安装未完成'='Reinstall failed';'恢复未完成'='Recovery incomplete';'查看日志'='View log';'返回重试'='Try again';'查看恢复副本'='Recovery copy';'卸载'='Uninstall';'卸载未完成'='Uninstall failed';'关闭'='Close'}
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Texts {return @([FailureUi]::Children($script:window)|ForEach-Object{$t=[FailureUi]::Text($_);if($English){foreach($k in $captions.Keys){if($captions[$k]-eq$t){$t=$k;break}}};$t})}
function Button([string]$Caption){if($English-and$captions.ContainsKey($Caption)){$Caption=$captions[$Caption]};return [FailureUi]::Children($script:window)|Where-Object{([FailureUi]::Class($_)-like '*Button*'-or[FailureUi]::Class($_)-like '*CheckBox*')-and [FailureUi]::Text($_)-eq $Caption}|Select-Object -First 1}
function Click([string]$Caption){$b=Button $Caption;Assert ([bool]$b) ('找不到按钮：'+$Caption);[void][FailureUi]::PostMessage($b,0xF5,[IntPtr]::Zero,[IntPtr]::Zero)}
function Wait-For([scriptblock]$Condition,[string]$Message){for($i=0;$i-lt900;$i++){if(& $Condition){return};Start-Sleep -Milliseconds 100};throw $Message}
function Capture([string]$Name){
  Start-Sleep -Milliseconds 250
  $r=[FailureUi+Rect]::new();[void][FailureUi]::GetWindowRect($script:window,[ref]$r)
  $bitmap=[Drawing.Bitmap]::new($r.Right-$r.Left,$r.Bottom-$r.Top);$g=[Drawing.Graphics]::FromImage($bitmap);$dc=$g.GetHdc()
  try{[void][FailureUi]::PrintWindow($script:window,$dc,2)}finally{$g.ReleaseHdc($dc)}
  $bitmap.Save((Join-Path $work ($Name+'.png')));$g.Dispose();$bitmap.Dispose()
  $controls=@([FailureUi]::Children($script:window)|ForEach-Object{
    $c=[FailureUi+Rect]::new();[void][FailureUi]::GetWindowRect($_,[ref]$c)
    @{text=[FailureUi]::Text($_);class=[FailureUi]::Class($_);left=$c.Left-$r.Left;top=$c.Top-$r.Top;right=$c.Right-$r.Left;bottom=$c.Bottom-$r.Top}
  })
  $controls|ConvertTo-Json|Set-Content (Join-Path $work ($Name+'-controls.json')) -Encoding utf8
  $buttons=@($controls|Where-Object{$_.class-like '*Button*'})
  if($Name-like '*-failed'){
    $footer=($buttons|Measure-Object top -Minimum).Minimum-16
    $labels=@($controls|Where-Object{$_.class-like '*StaticText*'-and$_.text})
    foreach($label in $labels){Assert ($label.bottom-le$footer) '失败文字覆盖底栏。'}
    for($i=0;$i-lt$labels.Count;$i++){for($j=$i+1;$j-lt$labels.Count;$j++){
      $a=$labels[$i];$b=$labels[$j]
      Assert (-not($a.left-lt$b.right-and$b.left-lt$a.right-and$a.top-lt$b.bottom-and$b.top-lt$a.bottom)) '失败页文字发生重叠。'
    }}
  }
  for($i=0;$i-lt$buttons.Count;$i++){
    Assert ($buttons[$i].bottom-le($r.Bottom-$r.Top)-8) '失败页按钮超出窗口。'
    for($j=$i+1;$j-lt$buttons.Count;$j++){
      $a=$buttons[$i];$b=$buttons[$j]
      Assert (-not($a.left-lt$b.right-and$b.left-lt$a.right-and$a.top-lt$b.bottom-and$b.top-lt$a.bottom)) '失败页按钮发生重叠。'
    }
  }
}
function Launch([string]$Root,[string[]]$Extra=@()){
  $locale='zh';if($English){$locale='en'}
  $args=@(('/UILANG='+$locale),('/ROOT="'+$Root+'"'),'/TESTDELAY=1800')+$Extra
  if($WorkAreaHeight){$args+=('/WORKAREAHEIGHT='+$WorkAreaHeight)}
  $script:process=Start-Process -FilePath $Installer -ArgumentList $args -WindowStyle Normal -PassThru
  Wait-For {$script:window=[FailureUi]::Find();$script:window-ne[IntPtr]::Zero} '安装窗口未出现。'
  Wait-For {(Texts)-contains '安装位置'-or(Texts)-contains '当前位置'} '选项页未完成显示。'
}
function Close-Window {
  [void][FailureUi]::PostMessage($script:window,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
  Wait-For {-not[FailureUi]::IsWindow($script:window)} '结果窗口无法关闭。'
  Assert ($script:process.WaitForExit(10000)) '关闭窗口后进程未退出。'
}
function Worker([string]$Program,[string]$Root,[string]$Name){
  $rootParam='/DIR=';if($Program-eq$worker){$rootParam='/ROOT='}
  $session=Join-Path $work $Name;New-Item -ItemType Directory -Path $session -Force|Out-Null
  $p=Start-Process -FilePath $Program -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',($rootParam+'"'+$Root+'"'),('/SESSION="'+$session+'"'),('/LOG="'+$session+'/worker.log"')) -WindowStyle Hidden -PassThru
  Assert ($p.WaitForExit(120000)) '清理验证安装超时。';Assert ($p.ExitCode-eq0) '清理验证安装失败。'
}
try{
  foreach($stage in @('prepare','files','restore')){
    $target=Join-Path $work ($stage+'/ShenView')
    if($stage-eq'restore'){Worker $engine $target 'baseline-for-restore-failure'}
    Launch $target @('/FAIL='+$stage)
    Click '桌面快捷方式'
    if($stage-eq'restore'){Click '重新安装'}else{Click '安装'}
    if($stage-ne'prepare'){
      Wait-For {(Texts)-contains '正在恢复…'} '失败后未显示回退状态。'
      Capture ($stage+'-restoring')
      if($stage-eq'files'){Click '完成后关闭'}else{[void][FailureUi]::PostMessage($window,0x10,[IntPtr]::Zero,[IntPtr]::Zero)}
      Wait-For {[FailureUi]::IsIconic($window)} '执行期间关闭操作没有最小化窗口。'
    }
    Wait-For {(Texts)-contains '安装未完成'-or(Texts)-contains '重新安装未完成'-or(Texts)-contains '恢复未完成'} '没有独立失败页。'
    Wait-For {(Texts)-contains '查看日志'} '失败页没有日志入口。'
    Assert (-not[FailureUi]::IsIconic($window)) '失败时没有重新显示窗口。'
    Assert ((Texts)-contains '查看日志') '失败页没有日志入口。'
    Assert (-not([FailureUi]::Children($window)|Where-Object{[FailureUi]::Class($_)-like '*PathEdit*'})) '失败页仍显示安装选项。'
    Capture ($stage+'-failed')
    if($stage-eq'restore'){
      Assert (-not(Button '返回重试')) '恢复未完成时仍可直接重试。'
      Assert ([bool](Button '查看恢复副本')) '恢复未完成时没有副本入口。'
      $copies=@(Get-ChildItem -LiteralPath $recoveryRoot -Directory|Where-Object{$_.FullName-notin$existingCopies})
      Assert ($copies.Count-eq1) '恢复副本未保留。'
      $retained=$copies[0].FullName
    }else{
      Click '返回重试'
      Wait-For {(Texts)-contains '安装位置'} '返回重试没有回到选项页。'
      Assert ((Texts)-contains $target) '返回重试丢失安装目录。'
      $desktop=Button '桌面快捷方式'
      Assert ([FailureUi]::SendMessage($desktop,0xF0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()-eq1) '返回重试丢失快捷方式选择。'
      Assert (-not(Test-Path $key)) '返回选项时擅自开始了第二次安装。'
    }
    Close-Window
    $results.Add(@{name=$stage;passed=$true})
    if($stage-eq'restore'){
      Worker $engine $target 'repair-fixture';Worker $worker $target 'remove-fixture'
      $boundary=[IO.Path]::GetFullPath($recoveryRoot)+[IO.Path]::DirectorySeparatorChar
      Assert ($retained.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) '待清理副本超出验证目录。'
      $journal=Get-Content (Join-Path $retained 'journal.ini') -Raw
      Assert ($journal.Contains('target='+$target)) '副本不属于本轮验证。'
      $results.Add(@{name='retained-recovery-copy';path=$retained;passed=$true})
    }
  }
  $target=Join-Path $work 'success/ShenView'
  Launch $target @('/TESTPOLLSTART=2999')
  Click '安装'
  Wait-For {(Texts)-contains '完成后关闭'} '没有执行期间关闭按钮。'
  Wait-For {((Texts)-contains '操作耗时较长，仍在等待执行结果。请勿强制结束进程。')-or((Texts)-contains 'This is taking longer. Waiting for the result; do not force the process to stop.')} '耗时较长时没有保留等待状态。'
  Assert (-not(Button '返回重试')) '超时后提前开放了重试。'
  $results.Add(@{name='long-running-keeps-working';passed=$true})
  [void][FailureUi]::PostMessage($window,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
  Wait-For {[FailureUi]::IsIconic($window)} 'Alt+F4 关闭没有延后处理。'
  Wait-For {-not[FailureUi]::IsWindow($window)} '安装成功后没有自动关闭。'
  Assert ($process.WaitForExit(10000)) '成功关闭后进程未退出。'
  Assert ($process.ExitCode-eq0) '成功延后关闭返回了失败退出码。'
  Assert ((Test-Path (Join-Path $target 'ShenView.exe'))-and(Test-Path $key)) '延后关闭中断了安装。'
  $results.Add(@{name='close-on-success';passed=$true})
  Launch $target @('/MODE=uninstall','/FAIL=uninstall-files')
  Click '卸载'
  Wait-For {(Texts)-contains '正在恢复…'} '卸载失败时没有回退状态。'
  Capture 'uninstall-restoring'
  Click '完成后关闭'
  Wait-For {(Texts)-contains '卸载未完成'} '卸载失败后没有结果页。'
  Wait-For {(Texts)-contains '查看日志'} '卸载失败页没有日志入口。'
  Assert (-not[FailureUi]::IsIconic($window)) '卸载失败窗口未重新显示。'
  Capture 'uninstall-failed';Close-Window
  Assert (Test-Path (Join-Path $target 'ShenView.exe')) '卸载失败后程序未恢复。'
  Worker $worker $target 'cleanup-success'
  $results.Add(@{name='uninstall-restored';passed=$true})
  @{passed=$true;cases=$results;work=$work;installer=$Installer}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $work 'results.json') -Encoding utf8
  Write-Output $work
}finally{
  if($window-ne[IntPtr]::Zero-and[FailureUi]::IsWindow($window)){[void][FailureUi]::PostMessage($window,0x10,[IntPtr]::Zero,[IntPtr]::Zero)}
}
