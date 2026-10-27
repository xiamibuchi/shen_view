[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ReleaseDirectory,
  [switch]$SkipMachineInstall,
  [switch]$VerifyLaunch
)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = $RepositoryRoot
$release = [IO.Path]::GetFullPath($ReleaseDirectory)
$manifest = Get-Content -LiteralPath (Join-Path $release 'release.json') -Raw | ConvertFrom-Json
if (-not $manifest.PSObject.Properties['installerType'] -or $manifest.installerType -ne 'inno') {
  throw '此验证入口仅支持当前 Inno 发布包，请重新生成发布产物。'
}
$work = Join-Path $root ('build/packaging/smoke-' + [guid]::NewGuid().ToString('N'))
$allowed = [IO.Path]::GetFullPath((Join-Path $root 'build/packaging')) + [IO.Path]::DirectorySeparatorChar
if (-not ([IO.Path]::GetFullPath($work)).StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw '测试目录超出工作区。' }
[IO.Directory]::CreateDirectory($work) | Out-Null
$result = [Collections.Generic.List[string]]::new()

function Assert([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
  $result.Add($Message)
}
function RunViewer([string]$Exe, [string]$Argument) {
  $p = Start-Process -FilePath $Exe -ArgumentList $Argument -WindowStyle Hidden -PassThru -Wait
  if ($p.ExitCode -ne 0) { throw "文件关联命令失败：$Argument ($($p.ExitCode))" }
}
function CurrentDefaults {
  $values = foreach ($ext in @('.jpg', '.zip', '.cbz')) {
    $key = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
    $item = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    if ($item) { "$ext|$($item.ProgId)|$($item.Hash)" } else { "$ext|absent" }
  }
  return $values -join ';'
}
function OwnedCapabilities([string]$Exe, [switch]$Machine) {
  $hive = if ($Machine) { 'HKEY_LOCAL_MACHINE' } else { 'HKEY_CURRENT_USER' }
  $keys = Get-ChildItem -LiteralPath ("Registry::$hive\Software\ShenView\Associations") -ErrorAction SilentlyContinue
  foreach ($key in $keys) {
    $path = (Get-ItemProperty -LiteralPath $key.PSPath).ApplicationPath
    if ($path -eq $Exe) { return $key.PSPath }
  }
  return ''
}

$before = CurrentDefaults
$portableExe = ''
$extraExecutables = [Collections.Generic.List[string]]::new()
$installedRoot = Join-Path $work '安装 空间\ShenView'
$installerRan = $false
try {
  foreach ($line in Get-Content -LiteralPath (Join-Path $release 'SHA256SUMS.txt')) {
    $match = [regex]::Match($line, '^([0-9a-f]{64})  (.+)$')
    Assert $match.Success 'SHA256SUMS 格式有效'
    $actual = (Get-FileHash -LiteralPath (Join-Path $release $match.Groups[2].Value) -Algorithm SHA256).Hash
    Assert ($actual -eq $match.Groups[1].Value) ('哈希一致：' + $match.Groups[2].Value)
  }
  $zip = Get-ChildItem -LiteralPath $release -Filter '*portable.zip' | Select-Object -First 1
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $portable = Join-Path $work '便携 空间'
  [IO.Compression.ZipFile]::ExtractToDirectory($zip.FullName, $portable)
  $portableExe = Join-Path $portable 'ShenView.exe'
  Assert (Test-Path -LiteralPath $portableExe) 'ZIP 包可完整解压到中文及空格路径'
  Assert (-not (Test-Path -LiteralPath (Join-Path $portable 'settings.json'))) 'ZIP 不携带开发配置'
  Assert ((Get-Content -LiteralPath (Join-Path $portable 'installation-mode') -Raw).Trim() -eq 'portable') 'ZIP 包有显式便携标记'
  $ffmpegRoot = Join-Path $portable 'codecs/ffmpeg'
  $ffmpegManifest = Get-Content -LiteralPath (Join-Path $ffmpegRoot 'manifest.json') -Raw | ConvertFrom-Json
  foreach ($binary in $ffmpegManifest.files) {
    Assert ((Get-FileHash -LiteralPath (Join-Path $ffmpegRoot $binary.name) -Algorithm SHA256).Hash -eq $binary.sha256) ("FFmpeg 运行文件校验：$($binary.name)")
  }
  Assert (Test-Path -LiteralPath (Join-Path $portable 'codecs/licenses/ffmpeg/SOURCES.txt')) 'FFmpeg 源码来源、构建配方及许可证随包提供'
  $savedPath = $env:PATH
  try {
    $env:PATH = Join-Path $env:WINDIR 'System32'
    & (Join-Path $ffmpegRoot 'ffprobe.exe') -v error -show_entries stream=codec_name -of json (Join-Path $ViewerRoot 'testdata/photo_media/sequence.heic') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'FFprobe 在没有系统编解码器 PATH 时可运行'
    & (Join-Path $ffmpegRoot 'ffmpeg.exe') -v error -i (Join-Path $ViewerRoot 'testdata/photo_media/sequence.heic') -map '0:v:0' -frames:v 1 -f null -
    Assert ($LASTEXITCODE -eq 0) 'FFmpeg 在没有系统编解码器 PATH 时可解码 HEIF 主序列'
  } finally { $env:PATH = $savedPath }
  RunViewer $portableExe '--register-file-types=jpg,zip,cbz'
  $cap = OwnedCapabilities $portableExe
  Assert ($cap -ne '') '便携副本注册独立身份'
  foreach ($ext in @('.jpg', '.zip', '.cbz')) {
    $prog = Get-ItemPropertyValue -LiteralPath ($cap + '\FileAssociations') -Name $ext
    $command = Get-ItemPropertyValue -LiteralPath ("Registry::HKEY_CURRENT_USER\Software\Classes\$prog\shell\open\command") -Name '(default)'
    Assert ($command -eq ('"' + $portableExe + '" -- "%1"')) ("关联命令正确引用中文路径：$ext")
  }
  RunViewer $portableExe '--set-file-types=jpg,cbz'
  Assert ($null -eq (Get-ItemProperty -LiteralPath ($cap + '\FileAssociations')).PSObject.Properties['.zip']) '替换候选命令移除未选格式'
  RunViewer $portableExe '--register-file-types=zip'
  $other = Join-Path $work '另一便携副本'
  [IO.Directory]::CreateDirectory($other) | Out-Null
  Get-ChildItem -LiteralPath $portable -File | Where-Object { $_.Extension -in '.exe', '.dll' } | Copy-Item -Destination $other
  Set-Content -LiteralPath (Join-Path $other 'installation-mode') -Value 'portable' -Encoding ascii
  $otherExe = Join-Path $other 'ShenView.exe'
  $extraExecutables.Add($otherExe)
  RunViewer $otherExe '--register-file-types=jpg'
  $otherCap = OwnedCapabilities $otherExe
  Assert ($otherCap -ne '' -and $otherCap -ne $cap) '多个便携副本使用不同身份'
  RunViewer $portableExe '--remove-file-types'
  Assert (-not (Test-Path -LiteralPath $cap)) '便携副本取消注册后清理自有项'
  Assert (Test-Path -LiteralPath $otherCap) '取消一个便携副本不影响其他副本'
  RunViewer $otherExe '--remove-file-types'

  $scoopRoot = Join-Path $work 'scoop/apps/shenview'
  $scoopCurrent = Join-Path $scoopRoot 'current'
  foreach ($scoopVersion in @('1.0', '2.0')) {
    $dir = Join-Path $scoopRoot $scoopVersion
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    Get-ChildItem -LiteralPath $other -File | Where-Object { $_.Extension -in '.exe', '.dll' } | Copy-Item -Destination $dir
    Set-Content -LiteralPath (Join-Path $dir 'installation-mode') -Value 'scoop' -Encoding ascii
  }
  New-Item -ItemType Junction -Path $scoopCurrent -Target (Join-Path $scoopRoot '1.0') | Out-Null
  $scoopExe = Join-Path $scoopCurrent 'ShenView.exe'
  $extraExecutables.Add($scoopExe)
  RunViewer (Join-Path $scoopRoot '1.0/ShenView.exe') '--register-file-types=jpg,zip'
  $scoopCap = OwnedCapabilities $scoopExe
  Assert ($scoopCap -ne '') 'Scoop 从实际版本目录运行时注册 current 稳定路径'
  # Remove only this test-created junction, never its target directory.
  (Get-Item -LiteralPath $scoopCurrent).Delete()
  New-Item -ItemType Junction -Path $scoopCurrent -Target (Join-Path $scoopRoot '2.0') | Out-Null
  RunViewer (Join-Path $scoopRoot '2.0/ShenView.exe') '--repair-file-types'
  Assert ((OwnedCapabilities $scoopExe) -eq $scoopCap) 'Scoop 切换版本后保留同一关联身份'
  RunViewer $scoopExe '--remove-file-types'
  Assert (-not (Test-Path -LiteralPath $scoopCap)) 'Scoop 卸载入口清理稳定路径关联'
  Assert ((CurrentDefaults) -eq $before) '注册与取消注册不改写 UserChoice'
  $channelRoot = Join-Path $release $(if ($manifest.channelMetadataComplete) { 'channels' } else { 'channel-templates' })
  $scoopFile = Get-ChildItem -LiteralPath (Join-Path $channelRoot 'scoop') -File | Select-Object -First 1
  $scoop = Get-Content -LiteralPath $scoopFile.FullName -Raw | ConvertFrom-Json
  Assert ($scoop.persist -eq 'user-data') 'Scoop 持久化用户数据'
  Assert ($scoop.architecture.'64bit'.hash -eq (Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash) 'Scoop 清单哈希对应当前 ZIP'
  $dir = Join-Path $scoopRoot '2.0'
  & ([scriptblock]::Create($scoop.pre_install))
  Assert ((Get-Content -LiteralPath (Join-Path $dir 'installation-mode') -Raw).Trim() -eq 'scoop') 'Scoop 实际安装钩子写入模式'
  $persisted = Join-Path $dir 'user-data/keep.txt'
  [IO.File]::WriteAllText($persisted,'keep-on-upgrade')
  RunViewer $scoopExe '--register-file-types=jpg'
  $scoopCap = OwnedCapabilities $scoopExe
  $cmd = 'update'
  & ([scriptblock]::Create($scoop.pre_uninstall))
  Assert (Test-Path -LiteralPath $scoopCap) 'Scoop 更新钩子不移除关联'
  & ([scriptblock]::Create($scoop.pre_install))
  Assert ([IO.File]::ReadAllText($persisted) -eq 'keep-on-upgrade') 'Scoop 重复安装钩子保留用户数据'
  $cmd = 'uninstall'
  & ([scriptblock]::Create($scoop.pre_uninstall))
  Assert (-not (Test-Path -LiteralPath $scoopCap)) 'Scoop 实际卸载钩子清理关联'
  Assert (Test-Path -LiteralPath $persisted) 'Scoop 卸载钩子保留用户数据'
  if ($VerifyLaunch) {
    Add-Type -AssemblyName System.Drawing
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DistributionWindow {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window,out Rect rect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l);
}
'@
    foreach ($component in @('data','codecs')) { Copy-Item -LiteralPath (Join-Path $portable $component) -Destination $dir -Recurse }
    foreach ($appRoot in @($portable,$dir)) {
      $name = if ($appRoot -eq $portable) { 'portable' } else { 'scoop' }
      $userData = Join-Path $appRoot 'user-data'
      [IO.Directory]::CreateDirectory($userData) | Out-Null
      [IO.File]::WriteAllText((Join-Path $userData 'settings.json'),'{"settings":{"localeCode":"en","watchFolderChanges":false}}')
      $imagePath = Join-Path $appRoot 'release-probe.png'
      $probe = [Drawing.Bitmap]::new(256,256); $paint = [Drawing.Graphics]::FromImage($probe)
      try { $paint.Clear([Drawing.Color]::CornflowerBlue); $probe.Save($imagePath,[Drawing.Imaging.ImageFormat]::Png) } finally { $paint.Dispose(); $probe.Dispose() }
      $app = Start-Process -FilePath (Join-Path $appRoot 'ShenView.exe') -ArgumentList @('--',('"' + $imagePath + '"')) -WorkingDirectory $appRoot -WindowStyle Normal -PassThru
      try {
        $rendered = $false
        for ($attempt=0; $attempt -lt 100; $attempt++) {
          Start-Sleep -Milliseconds 150; $app.Refresh()
          if ($app.HasExited) { throw ('应用提前退出：' + $name) }
          if ($app.MainWindowHandle -eq [IntPtr]::Zero) { continue }
          [void][DistributionWindow]::SetForegroundWindow($app.MainWindowHandle)
          $bounds = [DistributionWindow+Rect]::new()
          [void][DistributionWindow]::GetWindowRect($app.MainWindowHandle,[ref]$bounds)
          $capture = [Drawing.Bitmap]::new(($bounds.Right-$bounds.Left),($bounds.Bottom-$bounds.Top))
          $graphics = [Drawing.Graphics]::FromImage($capture)
          try {
            $graphics.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$capture.Size)
            $pixel = $capture.GetPixel([int]($capture.Width/2),[int]($capture.Height/2))
            if ([Math]::Abs($pixel.R-100) -le 3 -and [Math]::Abs($pixel.G-149) -le 3 -and [Math]::Abs($pixel.B-237) -le 3) {
              $capture.Save((Join-Path $work ($name+'-opened-image.png')),[Drawing.Imaging.ImageFormat]::Png); $rendered=$true; break
            }
          } finally { $graphics.Dispose(); $capture.Dispose() }
        }
        Assert $rendered ($name+' 从最终 ZIP 启动并实际显示图片')
        Assert (-not (Test-Path -LiteralPath (Join-Path $appRoot 'settings.json'))) ($name+' 配置不写入程序根目录')
      } finally {
        $app.Refresh()
        if (-not $app.HasExited) {
          [void][DistributionWindow]::PostMessage($app.MainWindowHandle,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
          if (-not $app.WaitForExit(10000)) { throw ('验证应用没有正常关闭：' + $name) }
        }
      }
    }
  }
  if ($manifest.PSObject.Properties['installerType'] -and $manifest.installerType -eq 'inno') {
    $installerFile = Get-ChildItem -LiteralPath (Join-Path $channelRoot 'winget') -Filter '*.installer.yaml*' | Select-Object -First 1
    $installerText = Get-Content -LiteralPath $installerFile.FullName -Raw
    $exe = Get-ChildItem -LiteralPath $release -Filter '*setup.exe' | Select-Object -First 1
    Assert ($installerText.Contains('InstallerType: inno')) 'WinGet 使用 Inno 安装类型'
    Assert ($installerText.Contains('ProductCode: ShenView.Inno7_is1')) 'WinGet 使用当前卸载身份'
    Assert ($installerText.Contains('InstallLocation: /ROOT="<INSTALLPATH>"')) 'WinGet 自定义目录传入外层 ROOT'
    Assert ($installerText.Contains((Get-FileHash -LiteralPath $exe.FullName -Algorithm SHA256).Hash)) 'WinGet 清单哈希对应当前 EXE'
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
      $validationDir = Join-Path $work 'winget-schema'
      [IO.Directory]::CreateDirectory($validationDir) | Out-Null
      foreach ($file in Get-ChildItem -LiteralPath (Join-Path $channelRoot 'winget') -File) {
        $text = [IO.File]::ReadAllText($file.FullName).Replace('@DOWNLOAD_BASE_URL@','https://example.invalid/releases').Replace('@HOMEPAGE@','https://example.invalid').Replace('@LICENSE@','LicenseRef-LocalValidation')
        [IO.File]::WriteAllText((Join-Path $validationDir ($file.Name -replace '[.]in$','')),$text)
      }
      & $winget.Source validate --manifest $validationDir --disable-interactivity > (Join-Path $work 'winget-validate.log')
      if ($LASTEXITCODE -ne 0) { throw ('WinGet 清单验证未通过：' + [IO.File]::ReadAllText((Join-Path $work 'winget-validate.log'))) }
      $result.Add('WinGet 本地替换模板通过官方清单验证（不下载、不安装）')
    } else { $result.Add('SKIP：未安装 WinGet，未执行官方清单验证') }
  }

  $msix = Get-ChildItem -LiteralPath $release -Filter '*.msix' | Select-Object -First 1
  $archive = [IO.Compression.ZipFile]::OpenRead($msix.FullName)
  try {
    $entry = $archive.GetEntry('AppxManifest.xml')
    $reader = [IO.StreamReader]::new($entry.Open())
    try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $ns = [Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('uap', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')
    $types = @($xml.SelectNodes('//uap:FileType', $ns) | ForEach-Object { $_.InnerText })
    foreach ($ext in @($manifest.fileTypes.images) + @($manifest.fileTypes.archives)) {
      Assert ($types -contains ".$ext") ("MSIX 声明候选格式：.$ext")
    }
    Assert ($archive.GetEntry('AppxBlockMap.xml') -ne $null) 'MSIX 包含打包工具生成的完整性清单'
    Assert ($xml.Package.Identity.Version -eq $manifest.windowsVersion) 'MSIX 版本与发布版本一致'
    Assert ($xml.Package.Identity.ProcessorArchitecture -eq 'x64') 'MSIX 架构为 x64'
    Assert ($xml.Package.Properties.DisplayName -eq 'ShenView') 'MSIX 应用名称统一为 ShenView'
    Assert ($xml.Package.Applications.Application.Executable -eq 'ShenView.exe') 'MSIX 从根目录启动应用'
    $modeReader = [IO.StreamReader]::new($archive.GetEntry('installation-mode').Open())
    try { Assert ($modeReader.ReadToEnd().Trim() -eq 'msix') 'MSIX 包有独立数据模式标记' } finally { $modeReader.Dispose() }
    foreach ($required in @('codecs/imagemagick/magick.exe','codecs/archive/viewer_archive.exe','codecs/archive/7z.dll','codecs/viewer_raw.exe','data/app.so')) {
      Assert ($null -ne $archive.GetEntry($required)) ('MSIX 保留组件布局：' + $required)
    }
    Assert ($types.Count -eq (@($manifest.fileTypes.images) + @($manifest.fileTypes.archives)).Count) 'MSIX 格式声明无重复或额外格式'
  } finally { $archive.Dispose() }

  if ($SkipMachineInstall) {
    $result.Add('SKIP：未执行需要管理员权限的所有用户安装、升级与卸载测试')
    $result | Set-Content -LiteralPath (Join-Path $work 'results.txt') -Encoding UTF8
    Write-Host "便携包、关联隔离及 MSIX 结构验证通过，已跳过所有用户安装：$work"
    return
  }
  if (-not [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '所有用户安装测试需要管理员权限。请从管理员 PowerShell 运行，或显式传 -SkipMachineInstall 只验其余部分。'
  }
  if ((Test-Path -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\Software\ShenView\Installer') -or (Test-Path -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\ShenView\Installer')) {
    throw '已有 NSIS 安装记录，为保护已有安装，未执行安装器测试。请在干净环境运行。'
  }
  $installer = Get-ChildItem -LiteralPath $release -Filter '*setup.exe' | Select-Object -First 1
  $innoKey = 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\ShenView.Inno7_is1'
  if (Test-Path -LiteralPath $innoKey) { throw '已有 Inno 安装记录，请在干净环境执行所有用户安装验证。' }
  $unrelated = Join-Path $work '已有文件/ShenView'
  [IO.Directory]::CreateDirectory($unrelated) | Out-Null
  Set-Content -LiteralPath (Join-Path $unrelated 'keep.txt') -Value 'unrelated'
  $silent = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART')
  $p = Start-Process -FilePath $installer.FullName -ArgumentList ($silent + ('/ROOT="' + $unrelated + '"')) -WindowStyle Hidden -PassThru -Wait
  Assert ($p.ExitCode -ne 0) 'Inno 拒绝接管无关目录'
  Assert ((Get-Content -LiteralPath (Join-Path $unrelated 'keep.txt') -Raw).Trim() -eq 'unrelated') 'Inno 拒绝安装后保留无关文件'
  $p = Start-Process -FilePath $installer.FullName -ArgumentList ($silent + ('/ROOT="' + $installedRoot + '"')) -WindowStyle Hidden -PassThru -Wait
  $installerRan = $true
  Assert ($p.ExitCode -eq 0) 'Inno 静默安装成功'
  $installedExe = Join-Path $installedRoot 'ShenView.exe'
  Assert (Test-Path -LiteralPath $installedExe) 'Inno 使用根目录应用布局'
  Assert ((Get-ItemProperty -LiteralPath $innoKey).DisplayVersion -eq $manifest.windowsVersion) 'Inno 卸载记录版本匹配渠道清单'
  $cap = OwnedCapabilities $installedExe -Machine
  Assert ($cap -ne '') 'Inno 注册图片候选'
  RunViewer $installedExe '--register-file-types=zip'
  $p = Start-Process -FilePath $installer.FullName -ArgumentList ($silent + ('/ROOT="' + $installedRoot + '"')) -WindowStyle Hidden -PassThru -Wait
  Assert ($p.ExitCode -eq 0) 'Inno 静默重装成功'
  Assert ($null -ne (Get-ItemProperty -LiteralPath ($cap + '\FileAssociations')).PSObject.Properties['.zip']) 'Inno 重装保留格式选择'
  Set-Content -LiteralPath (Join-Path $installedRoot 'keep.txt') -Value 'user-owned'
  $p = Start-Process -FilePath (Join-Path $installedRoot 'uninstall.exe') -ArgumentList $silent -WindowStyle Hidden -PassThru -Wait
  Assert ($p.ExitCode -eq 0) 'Inno 静默卸载成功'
  Assert (-not (Test-Path -LiteralPath $installedExe)) 'Inno 卸载移除应用'
  Assert (Test-Path -LiteralPath (Join-Path $installedRoot 'keep.txt')) 'Inno 卸载保留非包文件'
  Assert (-not (Test-Path -LiteralPath $cap)) 'Inno 卸载清理关联'
  Assert (-not (Test-Path -LiteralPath $innoKey)) 'Inno 卸载清理安装记录'
  $installerRan = $false
  Assert ((CurrentDefaults) -eq $before) 'Inno 安装重装卸载不改写 UserChoice'
  $result | Set-Content -LiteralPath (Join-Path $work 'results.txt') -Encoding UTF8
  Write-Host "Inno 与分发验证通过：$work"
} finally {
  if ($portableExe -and (Test-Path -LiteralPath $portableExe)) { RunViewer $portableExe '--remove-file-types' }
  foreach ($exe in $extraExecutables) {
    if (Test-Path -LiteralPath $exe) { RunViewer $exe '--remove-file-types' }
  }
  if ($installerRan -and (Test-Path -LiteralPath (Join-Path $installedRoot 'Uninstall.exe'))) {
    $cleanupArguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART')
    $p = Start-Process -FilePath (Join-Path $installedRoot 'Uninstall.exe') -ArgumentList $cleanupArguments -WindowStyle Hidden -PassThru -Wait
  }
}
