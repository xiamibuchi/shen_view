[CmdletBinding()]
param([Parameter(Mandatory)][string]$BuildDirectory)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$buildInfo = Get-Content (Join-Path $BuildDirectory 'build.json') -Raw | ConvertFrom-Json
if (-not $buildInfo.validation) { throw '事务验证只允许独立 validation 身份。' }
$engine = Join-Path $RepositoryRoot 'build/packaging/inno7/validation/ShenView-Setup.exe'
$worker = Join-Path $RepositoryRoot 'build/packaging/inno7/validation/ShenView-Uninstall.exe'
$work = Join-Path $RepositoryRoot ('build/packaging/inno7-transactions/' + [guid]::NewGuid().ToString('N'))
$original = Join-Path $work '旧目录/ShenView'
$moved = Join-Path $work '迁移目标/ShenView'
$session = Join-Path $work 'session'
New-Item -ItemType Directory -Path $session -Force | Out-Null
$key = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/ShenView.Inno7.Validation_is1'
$recoveryRoot=Join-Path $env:LOCALAPPDATA 'ShenView-Inno7-Validation/Installer/Transactions'
$results = [Collections.Generic.List[object]]::new()
$shell = New-Object -ComObject WScript.Shell
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ShenView Inno7 Validation.lnk'
$start = Join-Path ([Environment]::GetFolderPath('Programs')) 'ShenView Inno7 Validation.lnk'
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) {throw $Message} }
function Run-Operation([string]$Program,[string]$Root,[string]$Name,[string[]]$Extra=@()) {
  $rootArgument = if ($Program -eq $worker) {'/ROOT='} else {'/DIR='}
  $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',($rootArgument+'"'+$Root+'"'),
    ('/SESSION="'+$session+'"'),('/LOG="'+(Join-Path $work ($Name+'.log'))+'"'),'/UILANG=zh','/FORMATS=png,jpg','/DESKTOP=1','/STARTMENU=1')+$Extra
  $proc = Start-Process $Program -ArgumentList $arguments -WindowStyle Hidden -PassThru
  if (-not $proc.WaitForExit(120000)) {throw ('事务验证超时: '+$Name)}
  $state=Get-Content (Join-Path $session 'status.ini') -Raw
  $results.Add(@{name=$Name;exitCode=$proc.ExitCode;state=$state})
  return $proc.ExitCode
}
function Assert-Original {
  Assert ((Get-FileHash (Join-Path $original 'ShenView.exe')).Hash -eq $script:appHash) '旧应用未恢复。'
  foreach($name in $script:metadataHashes.Keys) {
    Assert ((Get-FileHash (Join-Path $original $name)).Hash -eq $script:metadataHashes[$name]) ('旧安装记录未恢复: '+$name)
  }
  Assert ((Get-ItemProperty $key).InstallLocation.TrimEnd([char]92) -eq $original) '卸载记录没有指回旧目录。'
  Assert ((Get-ItemProperty $key).DisplayVersion -eq $buildInfo.version) '卸载记录中的版本未恢复。'
  Assert ((Get-ItemProperty $key).'Inno Setup: Language' -eq 'zh') '安装语言未恢复。'
  Assert ((Get-ItemProperty $key).'Inno Setup: Selected Tasks' -eq 'desktopicon,startmenuicon') '快捷方式选择未恢复。'
  $associations=Get-ItemProperty 'HKCU:/Software/ShenView/Inno7Validation/ShenView/Associations/ShenView.Machine/FileAssociations'
  Assert ($associations.'.png' -eq 'ShenView.Machine.png' -and $associations.'.jpg' -eq 'ShenView.Machine.jpg') '关联选择未恢复。'
  Assert ($shell.CreateShortcut($desktop).TargetPath -eq (Join-Path $original 'ShenView.exe')) '桌面快捷方式未恢复。'
  Assert ($shell.CreateShortcut($start).TargetPath -eq (Join-Path $original 'ShenView.exe')) '开始菜单快捷方式未恢复。'
  Assert ((Get-Content (Join-Path $original 'test-user/settings.json') -Raw) -eq $script:settings) '旧设置或历史被更改。'
}

Assert (-not (Test-Path $key)) '已有 validation 安装，请先使用其维护界面卸载再运行。'
foreach($stage in @('files','associations','cleanup')) {
  $emptyTarget=Join-Path $work ('first-fail-'+$stage+'/ShenView')
  Assert ((Run-Operation $engine $emptyTarget ('first-install-fail-'+$stage) @('/FAIL='+$stage)) -ne 0) ('首装故障未失败: '+$stage)
  Assert (-not (Test-Path (Join-Path $emptyTarget 'ShenView.exe'))) '首装失败后残留主程序。'
  Assert (-not (Test-Path $key)) '首装失败后残留卸载记录。'
  Assert (-not (Test-Path $desktop)) '首装失败后残留桌面快捷方式。'
  Assert (-not (Test-Path $start)) '首装失败后残留开始菜单快捷方式。'
}
Assert ((Run-Operation $engine $original 'install') -eq 0) '安装失败。'
$rootEntries=@(Get-ChildItem -LiteralPath $original | Sort-Object Name | Select-Object Name,Length,Mode)
Assert ($rootEntries.Name -contains 'ShenView.exe') '主程序未直接部署到安装根目录。'
Assert (-not(Test-Path (Join-Path $original 'app')) -and -not(Test-Path (Join-Path $original 'maintain.exe'))) '安装目录仍有多余的 app 层或维护程序。'
Assert (-not(Test-Path (Join-Path $original 'install.ini'))) '新安装仍有 install.ini。'
$appHash=(Get-FileHash (Join-Path $original 'ShenView.exe')).Hash
$metadataHashes=@{}
foreach($name in @('payload-files.txt','uninstall.exe')) {
  $metadataHashes[$name]=(Get-FileHash (Join-Path $original $name)).Hash
}
New-Item -ItemType Directory -Path (Join-Path $original 'test-user'),(Join-Path $original 'user-data') -Force | Out-Null
$settings='{"settings":{"localeCode":"zh"},"history":["reading-position"]}'
[IO.File]::WriteAllText((Join-Path $original 'test-user/settings.json'),$settings)
[IO.File]::WriteAllText((Join-Path $original 'user-data/session.json'),'{"page":17}')
[IO.File]::WriteAllText((Join-Path $original 'personal.txt'),'keep-personal')
foreach($stage in @('files','associations','shortcuts','cleanup')) {
  Assert ((Run-Operation $engine $original ('reinstall-fail-'+$stage) @('/FAIL='+$stage)) -ne 0) ('重装故障未失败: '+$stage)
  Assert-Original
  Assert ((Get-Content (Join-Path $session 'status.ini') -Raw).Contains('state=failed')) '重装失败的恢复状态不正确。'
}
Assert (-not(Test-Path $recoveryRoot)) '恢复完成后仍保留了不需要的事务副本。'
Assert ((Run-Operation $engine $original 'failed-restore-retains-recovery-copy' @('/FAIL=restore')) -ne 0) '恢复故障未失败。'
$recoveryState=Get-Content (Join-Path $session 'status.ini') -Raw
Assert ($recoveryState.Contains('state=recovery-failed')) '恢复未完成没有单独报告。'
$retained=@(Get-ChildItem -LiteralPath $recoveryRoot -Directory)
Assert ($retained.Count -eq 1) '恢复失败后没有保留唯一的恢复副本。'
$retainedPath=[IO.Path]::GetFullPath($retained[0].FullName)
$recoveryBoundary=[IO.Path]::GetFullPath($recoveryRoot)+[IO.Path]::DirectorySeparatorChar
Assert ($retainedPath.StartsWith($recoveryBoundary,[StringComparison]::OrdinalIgnoreCase) -and $retained[0].Name -match '^[A-F0-9-]{36}$') '恢复副本路径不在受控事务目录中。'
Assert ($recoveryState.Contains($retainedPath)) '恢复失败没有提供副本位置。'
Assert ((Get-FileHash (Join-Path $retainedPath 'files/ShenView.exe')).Hash -eq $appHash) '恢复副本没有保存原程序。'
$recoveryAcl=Get-Acl -LiteralPath $retainedPath
Assert ($recoveryAcl.AreAccessRulesProtected) '事务目录未保护权限继承。'
Assert ($recoveryAcl.Sddl -notmatch ';;;(?:BU|AU|WD)\)') '事务目录允许普通其他用户访问。'
$recoveryEvidence=@{path=$retainedPath;sddl=$recoveryAcl.Sddl;protected=$recoveryAcl.AreAccessRulesProtected}
Assert ((Run-Operation $engine $original 'retry-after-restore-failure') -eq 0) '恢复故障后无法重试。'
Assert-Original
$journal=Get-Content (Join-Path $retainedPath 'journal.ini') -Raw
Assert ($journal.Contains('source='+$original)) '待清理的恢复副本不属于本轮验证。'
Remove-Item -LiteralPath $retainedPath -Recurse -Force
Remove-Item -LiteralPath ('HKCU:/Software/ShenView/InstallerTransactions/'+$retained[0].Name) -Recurse -Force
foreach($path in @($recoveryRoot,(Split-Path $recoveryRoot))){if(Test-Path -LiteralPath $path){[IO.Directory]::Delete($path,$false)}}
Assert ((Run-Operation $engine $moved 'migration-needs-confirmation') -ne 0) '未确认迁移也更换了目录。'
Assert-Original
foreach($stage in @('data','cleanup')) {
  $failedTarget = Join-Path $work ('failed-'+$stage+'/ShenView')
  Assert ((Run-Operation $engine $failedTarget ('migration-fail-'+$stage) @('/MIGRATE=1',('/FAIL='+$stage))) -ne 0) ('迁移故障未失败: '+$stage)
  Assert-Original
  Assert (-not (Test-Path (Join-Path $failedTarget 'ShenView.exe'))) '迁移失败留下了新安装。'
  Assert (-not (Test-Path $failedTarget)) '迁移失败后残留空目录，阻止同位置重试。'
}
foreach($stage in @('uninstall-start','uninstall-files','uninstall-record')) {
  Assert ((Run-Operation $worker $original $stage @('/FAIL='+$stage)) -ne 0) ('卸载故障未失败: '+$stage)
  Assert-Original
}
$lockedProgram=[IO.File]::Open((Join-Path $original 'ShenView.exe'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
  Assert ((Run-Operation $worker $original 'uninstall-locked-file') -ne 0) '文件占用时卸载仍报告成功。'
  Assert-Original
  Assert ((Get-Content (Join-Path $session 'status.ini') -Raw).Contains('state=failed')) '文件占用后的卸载没有完整恢复。'
} finally {$lockedProgram.Dispose()}

$lockedFile=[IO.File]::Open((Join-Path $original 'personal.txt'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try { Assert ((Run-Operation $engine $moved 'migration-success' @('/MIGRATE=1')) -eq 0) '迁移失败。' }
finally {$lockedFile.Dispose()}
Assert ((Get-FileHash (Join-Path $moved 'ShenView.exe')).Hash -eq $appHash) '新目录主程序错误。'
Assert (-not (Test-Path (Join-Path $original 'ShenView.exe'))) '旧目录没有卸载应用。'
Assert (-not (Test-Path (Join-Path $original 'unins000.exe'))) '旧目录残留卸载程序。'
Assert ((Get-Content (Join-Path $moved 'test-user/settings.json') -Raw) -eq $settings) '迁移没有继承设置和历史。'
Assert ((Get-Content (Join-Path $moved 'user-data/session.json') -Raw) -eq '{"page":17}') '迁移没有继承应用目录中的用户数据。'
Assert ((Get-Content (Join-Path $original 'personal.txt') -Raw) -eq 'keep-personal') '跳过的文件没有保留在原处。'
Assert ((Get-Content (Join-Path $session 'status.ini') -Raw).Contains('skipped=1')) '被占用的数据没有报告跳过。'
Assert ($shell.CreateShortcut($desktop).TargetPath -eq (Join-Path $moved 'ShenView.exe')) '迁移后桌面快捷方式地址没有更新。'
Assert ($shell.CreateShortcut($start).TargetPath -eq (Join-Path $moved 'ShenView.exe')) '迁移后开始菜单快捷方式地址没有更新。'
Assert ((Get-ItemProperty $key).InstallLocation.TrimEnd([char]92) -eq $moved) '迁移后卸载目录不正确。'
Assert ((Get-ItemProperty $key).UninstallString.Contains('uninstall.exe')) '系统卸载入口未使用维护界面。'
Assert ((Run-Operation $worker $moved 'uninstall-success') -eq 0) '卸载失败。'
Assert (-not (Test-Path (Join-Path $moved 'ShenView.exe'))) '卸载后仍有应用。'
Assert (Test-Path (Join-Path $moved 'test-user/settings.json')) '卸载删除了设置。'
Assert (Test-Path (Join-Path $moved 'user-data/session.json')) '卸载删除了应用目录内用户数据。'
Assert (-not (Test-Path $key)) '卸载后记录未移除。'
Assert (-not (Test-Path $desktop)) '卸载后桌面快捷方式未移除。'
Assert (-not (Test-Path $start)) '卸载后开始菜单快捷方式未移除。'
Assert (Test-Path (Join-Path $moved '.shenview-user-data')) '卸载后没有标记保留数据的归属。'
Assert ((Run-Operation $engine $moved 'reinstall-after-uninstall-with-user-data') -eq 0) '卸载保留数据后无法在原位置重装。'
Assert ((Get-Content (Join-Path $moved 'test-user/settings.json') -Raw) -eq $settings) '原位置重装覆盖了保留的数据。'
Assert ((Run-Operation $worker $moved 'uninstall-after-data-root-reinstall') -eq 0) '保留数据重装后的卸载失败。'
$repairRoot=Join-Path $work '损坏安装/ShenView'
New-Item -ItemType Directory -Path $repairRoot -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $repairRoot '.shenview-user-data'),'ShenView.Inno7.Validation')
[IO.File]::WriteAllText((Join-Path $repairRoot 'personal.txt'),'preserve-partial-data')
Copy-Item -LiteralPath (Join-Path $buildInfo.payload 'ShenView.exe') -Destination (Join-Path $repairRoot 'ShenView.exe')
Assert ((Run-Operation $engine $repairRoot 'repair-needs-confirmation') -ne 0) '损坏安装未经确认就被覆盖。'
Assert ((Run-Operation $engine $repairRoot 'repair-failure' @('/REPAIR=1','/FAIL=files')) -ne 0) '修复故障未失败。'
Assert ((Get-FileHash (Join-Path $repairRoot 'ShenView.exe')).Hash -eq $appHash) '修复失败未恢复原文件。'
Assert (-not(Test-Path (Join-Path $repairRoot 'install.ini'))) '修复失败留下了新的安装记录。'
Assert ((Run-Operation $engine $repairRoot 'repair-success' @('/REPAIR=1')) -eq 0) '损坏安装修复失败。'
Assert ((Get-Content (Join-Path $repairRoot 'personal.txt') -Raw) -eq 'preserve-partial-data') '修复覆盖了个人文件。'
Assert ((Run-Operation $worker $repairRoot 'uninstall-repaired-install') -eq 0) '修复后的安装无法卸载。'
$legacyRoot=Join-Path $work '旧预览结构/ShenView'
$codecRoot=Join-Path $work '组件目录升级/ShenView'
Assert ((Run-Operation $engine $codecRoot 'install-obsolete-codec-fixture') -eq 0) '组件升级样例安装失败。'
$oldCodec=Join-Path $codecRoot 'codecs/7z.dll'
Copy-Item -LiteralPath (Join-Path $codecRoot 'codecs/archive/7z.dll') -Destination $oldCodec
$codecManifest=Join-Path $codecRoot 'payload-files.txt'
Add-Content -LiteralPath $codecManifest -Value 'codecs\7z.dll'
$oldManifestHash=(Get-FileHash $codecManifest).Hash
$oldCodecHash=(Get-FileHash $oldCodec).Hash
$personalCodec=Join-Path $codecRoot 'codecs/personal.txt'
[IO.File]::WriteAllText($personalCodec,'keep-unmanaged')
Assert ((Run-Operation $engine $codecRoot 'codec-layout-cleanup-failure' @('/FAIL=cleanup')) -ne 0) '组件清理故障未失败。'
Assert ((Get-FileHash $oldCodec).Hash-eq$oldCodecHash -and (Get-FileHash $codecManifest).Hash-eq$oldManifestHash) '清理失败未恢复旧组件与清单。'
Assert ((Run-Operation $engine $codecRoot 'codec-layout-cleanup-success') -eq 0) '组件目录升级失败。'
Assert (-not(Test-Path $oldCodec)) '重装未清理旧清单中的平铺 DLL。'
Assert (Test-Path (Join-Path $codecRoot 'codecs/archive/7z.dll')) '新组件 DLL 被误清理。'
Assert ((Get-Content $personalCodec -Raw)-eq'keep-unmanaged') '组件清理删除了清单以外的用户文件。'
Assert ((Run-Operation $worker $codecRoot 'uninstall-codec-layout-fixture') -eq 0) '组件目录升级样例卸载失败。'
Assert ((Run-Operation $engine $legacyRoot 'install-legacy-layout-fixture') -eq 0) '旧结构样例安装失败。'
$legacyBoundary=[IO.Path]::GetFullPath($legacyRoot)+[IO.Path]::DirectorySeparatorChar
New-Item -ItemType Directory -Path (Join-Path $legacyRoot 'app') -Force | Out-Null
$topNames=@(@(Get-Content (Join-Path $legacyRoot 'payload-files.txt') | ForEach-Object {($_ -split '[\\/]')[0]})+'installation-mode' | Sort-Object -Unique)
foreach($name in $topNames){
  $from=[IO.Path]::GetFullPath((Join-Path $legacyRoot $name));$to=[IO.Path]::GetFullPath((Join-Path $legacyRoot ('app/'+$name)))
  Assert ($from.StartsWith($legacyBoundary,[StringComparison]::OrdinalIgnoreCase) -and $to.StartsWith($legacyBoundary,[StringComparison]::OrdinalIgnoreCase)) '旧结构样例移动路径越界。'
  if(Test-Path -LiteralPath $from){Move-Item -LiteralPath $from -Destination $to}
}
Move-Item -LiteralPath (Join-Path $legacyRoot 'uninstall.exe') -Destination (Join-Path $legacyRoot 'maintain.exe')
$legacyIni=Join-Path $legacyRoot 'install.ini'
[IO.File]::WriteAllLines($legacyIni,@('[install]','identity=ShenView.Inno7.Validation',('version='+$buildInfo.version),'language=zh','formats=png,jpg','desktop=1','startmenu=1'))
foreach($name in @('Inno Setup: Language','Inno Setup: Selected Tasks')){Remove-ItemProperty -LiteralPath $key -Name $name}
foreach($path in @($desktop,$start)){$link=$shell.CreateShortcut($path);$link.TargetPath=Join-Path $legacyRoot 'app/ShenView.exe';$link.Save()}
Set-ItemProperty -LiteralPath $key -Name UninstallString -Value ('"'+(Join-Path $legacyRoot 'maintain.exe')+'" /MODE=uninstall /ROOT="'+$legacyRoot+'"')
$legacyIniHash=(Get-FileHash $legacyIni).Hash
Assert ((Run-Operation $engine $legacyRoot 'legacy-layout-failure-restores-old-structure' @('/FAIL=cleanup')) -ne 0) '旧结构转换故障未失败。'
Assert ((Get-FileHash $legacyIni).Hash -eq $legacyIniHash) '旧结构转换失败未恢复安装记录。'
Assert ((Test-Path (Join-Path $legacyRoot 'app/ShenView.exe')) -and (Test-Path (Join-Path $legacyRoot 'maintain.exe'))) '旧结构转换失败未恢复旧程序。'
Assert (-not(Test-Path (Join-Path $legacyRoot 'ShenView.exe')) -and -not(Test-Path (Join-Path $legacyRoot 'uninstall.exe'))) '旧结构转换失败留下新结构文件。'
Assert ($shell.CreateShortcut($desktop).TargetPath -eq (Join-Path $legacyRoot 'app/ShenView.exe')) '旧结构转换失败未恢复快捷方式。'
Assert ((Run-Operation $engine $legacyRoot 'legacy-layout-to-flat-success') -eq 0) '旧结构转换失败。'
Assert ((Test-Path (Join-Path $legacyRoot 'ShenView.exe')) -and (Test-Path (Join-Path $legacyRoot 'uninstall.exe'))) '转换后主程序或卸载器不在根目录。'
Assert (-not(Test-Path (Join-Path $legacyRoot 'app')) -and -not(Test-Path (Join-Path $legacyRoot 'maintain.exe'))) '转换后仍有旧 app 层或维护程序。'
Assert (-not(Test-Path $legacyIni)) '转换后仍残留旧 install.ini。'
Assert ((Get-ItemProperty $key).'Inno Setup: Language' -eq 'zh') '旧安装选择未迁入注册表。'
Assert ($shell.CreateShortcut($desktop).TargetPath -eq (Join-Path $legacyRoot 'ShenView.exe')) '转换后快捷方式仍指向旧 app 路径。'
Assert ((Run-Operation $worker $legacyRoot 'uninstall-converted-layout' @('/PURGE=1')) -eq 0) '新结构卸载失败。'
$purgeRoot=Join-Path $work '完全卸载/ShenView'
$purgeUser=$purgeRoot+'.user-data'
Assert ((Run-Operation $engine $purgeRoot 'install-for-complete-uninstall') -eq 0) '完全卸载样例安装失败。'
foreach($name in @('unins000.exe','unins000.dat','shenview-install-root')) {
  Assert (-not(Test-Path (Join-Path $purgeRoot $name))) ('新安装仍产生冗余文件: '+$name)
  [IO.File]::WriteAllText((Join-Path $purgeRoot $name),'old-preview-fixture')
}
Assert ((Run-Operation $engine $purgeRoot 'remove-legacy-maintenance-files') -eq 0) '旧维护文件迁移失败。'
foreach($name in @('unins000.exe','unins000.dat','shenview-install-root')) {
  Assert (-not(Test-Path (Join-Path $purgeRoot $name))) ('旧维护文件未清理: '+$name)
}
New-Item -ItemType Directory -Path (Join-Path $purgeRoot 'test-user'),(Join-Path $purgeRoot 'empty-folder'),(Join-Path $purgeUser 'cache'),(Join-Path $purgeUser 'MSIX') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $purgeRoot 'test-user/settings.json'),$settings)
[IO.File]::WriteAllText((Join-Path $purgeRoot 'personal.txt'),'purge-personal')
[IO.File]::WriteAllText((Join-Path $purgeUser 'settings.json'),$settings)
[IO.File]::WriteAllBytes((Join-Path $purgeUser 'cache/data.bin'),[byte[]](0,1,0,255,34))
[IO.File]::WriteAllText((Join-Path $purgeUser 'MSIX/keep.txt'),'other-distribution')
$renamed=Join-Path ([Environment]::GetFolderPath('Desktop')) ('ShenView-transaction-'+[guid]::NewGuid().ToString('N')+'.lnk')
$customLink=$shell.CreateShortcut($renamed); $customLink.TargetPath=Join-Path $purgeRoot 'ShenView.exe'; $customLink.Save()
function Assert-PurgeRestored {
  Assert ((Get-FileHash (Join-Path $purgeRoot 'ShenView.exe')).Hash -eq $appHash) '完全卸载失败未恢复主程序。'
  Assert ((Get-Content (Join-Path $purgeRoot 'personal.txt') -Raw) -eq 'purge-personal') '完全卸载失败未恢复个人文件。'
  Assert (Test-Path (Join-Path $purgeRoot 'empty-folder')) '完全卸载失败未恢复空目录。'
  Assert ((Get-Content (Join-Path $purgeUser 'settings.json') -Raw) -eq $settings) '完全卸载失败未恢复用户配置。'
  Assert (([IO.File]::ReadAllBytes((Join-Path $purgeUser 'cache/data.bin')) -join ',') -eq '0,1,0,255,34') '完全卸载失败未恢复缓存字节。'
  Assert ((Get-ItemProperty $key).InstallLocation.TrimEnd([char]92) -eq $purgeRoot) '完全卸载失败未恢复系统记录。'
  Assert (Test-Path $renamed) '完全卸载失败未恢复改名快捷方式。'
}
foreach($stage in @('purge-root','purge-data')) {
  Assert ((Run-Operation $worker $purgeRoot ('complete-uninstall-fail-'+$stage) @('/PURGE=1',('/FAIL='+$stage))) -ne 0) '完全卸载故障未失败。'
  Assert-PurgeRestored
  Assert ((Get-Content (Join-Path $session 'status.ini') -Raw).Contains('state=failed')) '完全卸载失败没有完整恢复。'
}
Assert ((Run-Operation $worker $purgeRoot 'complete-uninstall-wrong-user' @('/PURGE=1','/OWNER=unrelated-test-user')) -ne 0) '完全卸载接受了其他用户的身份。'
Assert-PurgeRestored
$lockedPurge=[IO.File]::Open((Join-Path $purgeUser 'settings.json'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
$recoveryCount=@(Get-ChildItem -LiteralPath $recoveryRoot -Directory -ErrorAction SilentlyContinue).Count
try { Assert ((Run-Operation $worker $purgeRoot 'complete-uninstall-backup-blocked' @('/PURGE=1')) -ne 0) '无法备份用户数据时仍删除了安装。' }
finally {$lockedPurge.Dispose()}
Assert-PurgeRestored
Assert (@(Get-ChildItem -LiteralPath $recoveryRoot -Directory -ErrorAction SilentlyContinue).Count -eq $recoveryCount) '删除前备份失败留下了不需要的恢复副本。'
$outside=Join-Path $work 'external-sentinel'
New-Item -ItemType Directory -Path $outside -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $outside 'keep.txt'),'external-content')
$junction=[IO.Path]::GetFullPath((Join-Path $purgeRoot 'linked-folder'))
Assert ($junction.StartsWith([IO.Path]::GetFullPath($purgeRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) '目录链接测试路径越界。'
New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
try {
  Assert ((Run-Operation $worker $purgeRoot 'complete-uninstall-reparse-blocked' @('/PURGE=1')) -ne 0) '完全卸载错误地跟随了目录链接。'
  Assert ((Get-Content (Join-Path $outside 'keep.txt') -Raw) -eq 'external-content') '完全卸载影响了链接外部的文件。'
  Assert-PurgeRestored
} finally {Remove-Item -LiteralPath $junction -Force}
$lockedPurge=[IO.File]::Open((Join-Path $purgeUser 'cache/data.bin'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try { Assert ((Run-Operation $worker $purgeRoot 'complete-uninstall-delete-blocked' @('/PURGE=1')) -ne 0) '用户数据被占用时仍报告卸载成功。' }
finally {$lockedPurge.Dispose()}
Assert-PurgeRestored
Assert ((Run-Operation $worker $purgeRoot 'complete-uninstall-success' @('/PURGE=1')) -eq 0) '完全卸载失败。'
Assert (-not(Test-Path $purgeRoot)) '完全卸载后安装目录仍存在。'
Assert (-not(Test-Path (Join-Path $purgeUser 'settings.json'))) '完全卸载后设置未清理。'
Assert (-not(Test-Path (Join-Path $purgeUser 'cache'))) '完全卸载后缓存未清理。'
Assert ((Get-Content (Join-Path $purgeUser 'MSIX/keep.txt') -Raw) -eq 'other-distribution') '完全卸载影响了其他渠道的数据。'
foreach($path in @($key,$desktop,$start,$renamed)) { Assert (-not(Test-Path $path)) ('完全卸载后残留: '+$path) }
Assert (@(Get-ChildItem -LiteralPath $work -Directory -Recurse -Filter '*.recovery-*').Count -eq 0) '安装目录旁仍产生恢复副本。'
Assert (-not(Test-Path $recoveryRoot)) '操作结束后未清理临时事务目录。'
@{passed=$true;testRoot=$work;rootEntries=$rootEntries;recovery=$recoveryEvidence;results=$results} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $BuildDirectory 'transaction-results.json') -Encoding utf8
Write-Output ('PASS: '+$work)
