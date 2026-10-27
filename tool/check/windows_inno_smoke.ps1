[CmdletBinding()]
param([Parameter(Mandatory)][string]$BuildDirectory)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class InnoDirectoryLock {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
  public static extern SafeFileHandle CreateFile(string name,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
}
'@
$buildInfo = Get-Content -LiteralPath (Join-Path $BuildDirectory 'build.json') -Raw | ConvertFrom-Json
if (-not $buildInfo.validation) { throw '自动安装验证只允许 validation 构建。' }
$engine = Join-Path $RepositoryRoot 'build/packaging/inno7/validation/ShenView-Setup.exe'
$worker = Join-Path $RepositoryRoot 'build/packaging/inno7/validation/ShenView-Uninstall.exe'
$testRoot = Join-Path $RepositoryRoot ('build/packaging/inno7-smoke/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$installRoot = Join-Path $testRoot 'ShenView'
$session = Join-Path $testRoot 'session'
New-Item -ItemType Directory -Path $session -Force | Out-Null
$results = [Collections.Generic.List[object]]::new()
$key = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/ShenView.Inno7.Validation_is1'
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Run-Engine([string]$Target, [string]$Name, [string[]]$Extra = @()) {
  $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/NOCANCEL',('/DIR="' + $Target + '"'),
    ('/SESSION="' + $session + '"'),'/STARTMENU=0','/DESKTOP=0','/UILANG=zh','/FORMATS=png,jpg',
    ('/LOG="' + (Join-Path $testRoot ($Name + '.log')) + '"')) + $Extra
  $process = Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -PassThru
  if (-not $process.WaitForExit(120000)) { throw ('安装验证超时: ' + $Name) }
  $results.Add(@{ name=$Name; exitCode=$process.ExitCode })
  return $process.ExitCode
}
$nonempty = Join-Path $testRoot 'unrelated'
New-Item -ItemType Directory -Path $nonempty | Out-Null
[IO.File]::WriteAllText((Join-Path $nonempty 'keep.txt'),'unrelated')
Assert ((Run-Engine $nonempty 'reject-unrelated') -ne 0) '非空无关目录未被拦截。'
Assert ((Get-Content (Join-Path $nonempty 'keep.txt') -Raw) -eq 'unrelated') '无关文件被修改。'
$statusFile=Join-Path $session 'status.ini'
[IO.File]::WriteAllText($statusFile,"[result]`r`nstate=waiting-for-probe`r`n",[Text.Encoding]::Unicode)
$statusLock=[IO.File]::Open($statusFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
  $statusProbe=Start-Process -FilePath $engine -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES',('/DIR="'+$nonempty+'"'),('/SESSION="'+$session+'"')) -WindowStyle Hidden -PassThru
  $pendingReady=$false
  for($attempt=0;$attempt-lt200;$attempt++){
    try {$pendingReady=[IO.File]::ReadAllText($statusFile+'.pending').Contains('state=failed')} catch {}
    if($pendingReady){break};Start-Sleep -Milliseconds 25
  }
  Assert $pendingReady '未能建立最终状态写入占用条件。'
  Start-Sleep -Milliseconds 250
} finally {$statusLock.Dispose()}
if(-not $statusProbe.WaitForExit(10000)){throw '解除状态文件占用后执行程序未退出。'}
Assert ($statusProbe.ExitCode-ne0) '无关目录状态探针错误地安装成功。'
Assert ([IO.File]::ReadAllText($statusFile).Contains('state=failed')) '短暂占用导致最终状态丢失。'
$results.Add(@{name='status-publish-retries-transient-reader-lock';exitCode=$statusProbe.ExitCode})
Assert ((Run-Engine $installRoot 'install') -eq 0) '安装失败。'
Assert (Test-Path -LiteralPath (Join-Path $installRoot 'ShenView.exe')) '缺少安装后的主程序。'
Assert ((Get-ItemProperty -LiteralPath $key).InstallLocation -eq $installRoot) '安装位置记录错误。'
Assert (-not(Test-Path (Join-Path $installRoot 'install.ini'))) '新安装仍生成 install.ini。'
Assert ((Get-ItemProperty -LiteralPath $key).'Inno Setup: Language' -eq 'zh') '安装语言未保存到注册表。'
Assert ((Get-ItemProperty -LiteralPath $key).'Inno Setup: Selected Tasks' -eq '') '快捷方式选择未保存到注册表。'
Assert ((Get-Content (Join-Path $installRoot 'installation-mode') -Raw) -eq 'portable') '验证数据没有隔离。'
$installedHash = (Get-FileHash -LiteralPath (Join-Path $installRoot 'ShenView.exe')).Hash
Assert ($installedHash -eq (Get-FileHash -LiteralPath (Join-Path $buildInfo.payload 'ShenView.exe')).Hash) '部署内容与输入不一致。'
Assert ((Run-Engine $installRoot 'reinstall') -eq 0) '同版本重装失败。'
Set-ItemProperty -LiteralPath $key -Name DisplayVersion -Value '999.0.0.0'
try {
  Assert ((Run-Engine $installRoot 'registry-version-blocks-downgrade') -ne 0) '没有根据卸载记录阻止降级。'
  Assert ((Get-ItemProperty -LiteralPath $key).DisplayVersion -eq '999.0.0.0') '降级失败改变了版本记录。'
  Assert ((Get-FileHash -LiteralPath (Join-Path $installRoot 'ShenView.exe')).Hash -eq $installedHash) '降级失败改变了程序文件。'
} finally {Set-ItemProperty -LiteralPath $key -Name DisplayVersion -Value $buildInfo.version}
$probe=Join-Path $installRoot 'headless-worker.exe'
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32/ping.exe') -Destination $probe
$decoder=Start-Process -FilePath $probe -ArgumentList @('-t','127.0.0.1') -WindowStyle Hidden -PassThru
try {
  Start-Sleep -Milliseconds 500
  Assert (-not $decoder.HasExited) '未能建立后台解码进程测试条件。'
  Assert ((Run-Engine $installRoot 'headless-decoder-blocks-install') -ne 0) '没有窗口的解码进程未被安装引擎检测到。'
  $blocked=Start-Process -FilePath $buildInfo.package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES',('/ROOT="'+$installRoot+'"')) -WindowStyle Hidden -PassThru
  if(-not $blocked.WaitForExit(15000)){throw '后台解码进程运行时静默前端未退出。'}
  Assert ($blocked.ExitCode -ne 0 -and -not $decoder.HasExited) '静默前端没有阻止操作，或强制结束了解码进程。'
  $results.Add(@{name='headless-decoder-blocks-public-frontend';exitCode=$blocked.ExitCode})
} finally {
  if(-not $decoder.HasExited){Stop-Process -Id $decoder.Id}
  if(-not $decoder.WaitForExit(10000)){throw '测试用后台进程没有退出，不能删除其程序文件。'}
  $decoder.Dispose()
  Remove-Item -LiteralPath $probe
}
$directoryLock = [InnoDirectoryLock]::CreateFile((Join-Path $installRoot 'ShenView.exe'),1,3,[IntPtr]::Zero,3,0,[IntPtr]::Zero)
try {
  Assert (-not $directoryLock.IsInvalid) '未能建立目录占用验证条件。'
  Assert ((Run-Engine $installRoot 'locked-reinstall' @('/LANG=zh')) -ne 0) '目录被占用时仍报告重装成功。'
  $failureState = Get-Content -LiteralPath (Join-Path $session 'status.ini') -Raw
  Assert ($failureState.Contains('检查权限后重试。')) '目录占用的中文原因被覆盖或截断。'
  Assert ($failureState.Contains('state=failed')) '目录占用没有报告失败状态。'
  Assert ((Get-FileHash -LiteralPath (Join-Path $installRoot 'ShenView.exe')).Hash -eq $installedHash) '目录占用失败损坏了原应用。'
  $blockedFrontend = Start-Process -FilePath $buildInfo.package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/ROOT="' + $installRoot + '"'),'/UILANG=zh') -WindowStyle Hidden -PassThru
  if (-not $blockedFrontend.WaitForExit(30000)) {throw '目录占用后的公开静默前端没有退出。'}
  Assert ($blockedFrontend.ExitCode -ne 0) '目录占用后的公开静默前端返回了成功。'
  $results.Add(@{name='public-silent-failure-exit';exitCode=$blockedFrontend.ExitCode})
} finally {$directoryLock.Dispose()}
Assert ((Run-Engine $installRoot 'retry-after-unlock') -eq 0) '解除占用后重试失败。'
Assert ((Run-Engine $installRoot 'failed-update' @('/FAIL=1')) -ne 0) '注入失败没有使操作失败。'
Assert ((Get-Content -LiteralPath (Join-Path $session 'status.ini') -Raw).Contains('Injected validation failure before file deployment.')) '失败恢复覆盖了具体原因。'
Assert ((Get-FileHash -LiteralPath (Join-Path $installRoot 'ShenView.exe')).Hash -eq $installedHash) '失败后主程序未恢复。'
Assert ((Get-ItemProperty -LiteralPath $key).DisplayVersion -eq $buildInfo.version) '失败后版本记录未恢复。'
[IO.File]::WriteAllText((Join-Path $installRoot 'personal.txt'),'keep')
New-Item -ItemType Directory -Path (Join-Path $installRoot 'test-user') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $installRoot 'test-user/settings.json'),'{"settings":{"localeCode":"zh"},"history":["keep"]}')
$process = Start-Process -FilePath $worker -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/ROOT="' + $installRoot + '"'),('/SESSION="' + $session + '"')) -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(120000)) { throw '卸载超时。' }
Assert ($process.ExitCode -eq 0) '卸载失败。'
Assert (-not (Test-Path -LiteralPath (Join-Path $installRoot 'ShenView.exe'))) '卸载后仍有主程序。'
Assert ((Get-Content (Join-Path $installRoot 'personal.txt') -Raw) -eq 'keep') '卸载删除了个人文件。'
Assert (Test-Path -LiteralPath (Join-Path $installRoot 'test-user/settings.json')) '卸载删除了设置。'
$results.Add(@{name='uninstall-preserves-user-data';exitCode=$process.ExitCode})
$missingRoot=Join-Path $testRoot 'missing-app/ShenView'
New-Item -ItemType Directory -Path $missingRoot -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $missingRoot 'install.ini'),("[install]"+[Environment]::NewLine+"identity=ShenView.Inno7.Validation"+[Environment]::NewLine+"version="+$buildInfo.version))
[IO.File]::WriteAllText((Join-Path $missingRoot 'payload-files.txt'),'ShenView.exe')
Assert ((Run-Engine $missingRoot 'reinstall-with-missing-app-directory') -eq 0) '应用目录缺失时无法重新安装。'
$process=Start-Process -FilePath $worker -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES',('/ROOT="'+$missingRoot+'"')) -WindowStyle Hidden -PassThru
if(-not $process.WaitForExit(120000)){throw '缺失目录重装验证的卸载超时。'}
Assert ($process.ExitCode -eq 0) '缺失目录重装后无法卸载。'
$silentRoot = Join-Path $testRoot 'silent/ShenView'
$process = Start-Process -FilePath $buildInfo.package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/ROOT="' + $silentRoot + '"'),'/UILANG=en') -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(120000)) { throw '公开前端静默安装超时。' }
Assert ($process.ExitCode -eq 0) '公开前端静默安装失败。'
$preferences = Get-Content -LiteralPath (Join-Path $silentRoot 'test-user/settings.json') -Raw | ConvertFrom-Json
Assert ($preferences.settings.localeCode -eq 'en') '静默安装的显式语言没有保存。'
$settingsFile = Join-Path $silentRoot 'test-user/settings.json'
$preserved = '{"settings":{"localeCode":"en","keep":"中文\"quoted","value":1.2e-3},"history":["a",{"nested":[true,null,5]}],"other":"leave"}'
[IO.File]::WriteAllText($settingsFile,$preserved,[Text.UTF8Encoding]::new($false))
$process = Start-Process -FilePath $buildInfo.package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/ROOT="' + $silentRoot + '"'),'/UILANG=zh') -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(120000)) { throw '语言合并验证超时。' }
Assert ($process.ExitCode -eq 0) '语言合并验证安装失败。'
Assert ([IO.File]::ReadAllText($settingsFile) -eq $preserved.Replace('"localeCode":"en"','"localeCode":"zh"')) '语言合并改变了其他设置或历史。'
$broken = '{broken JSON'
[IO.File]::WriteAllText($settingsFile,$broken,[Text.UTF8Encoding]::new($false))
$process = Start-Process -FilePath $buildInfo.package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/ROOT="' + $silentRoot + '"'),'/UILANG=en') -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(120000)) { throw '损坏配置验证超时。' }
Assert ($process.ExitCode -eq 0) '损坏配置应保留并报告，不能破坏已经完成的安装。'
Assert ([IO.File]::ReadAllText($settingsFile) -eq $broken) '安装器覆盖了损坏的已有配置。'
$results.Add(@{name='language-merge-preserves-other-data';exitCode=0})
$results.Add(@{name='invalid-config-is-not-overwritten';exitCode=0})
$process = Start-Process -FilePath (Join-Path $silentRoot 'uninstall.exe') -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/MODE=uninstall',('/ROOT="' + $silentRoot + '"')) -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(120000)) { throw '静默验证副本卸载超时。' }
Assert ($process.ExitCode -eq 0) '静默验证副本卸载失败。'
for($attempt=0;$attempt -lt 100 -and (Test-Path (Join-Path $silentRoot 'uninstall.exe'));$attempt++){Start-Sleep -Milliseconds 100}
Assert (-not(Test-Path (Join-Path $silentRoot 'uninstall.exe'))) '静默卸载后维护程序未清理。'
$results.Add(@{name='maintenance-silent-uninstall-exit-and-cleanup';exitCode=$process.ExitCode})
$results.Add(@{name='public-frontend-silent-install';exitCode=0})
@{ passed=$true; testRoot=$testRoot; results=$results } | ConvertTo-Json -Depth 5 |
  Set-Content -LiteralPath (Join-Path $BuildDirectory 'smoke-results.json') -Encoding utf8
Write-Output ('PASS: ' + $testRoot)
