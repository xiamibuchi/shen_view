[CmdletBinding()]
param(
  [string]$Compiler = '',
  [string]$PayloadDirectory = '',
  [string]$Version = '',
  [string]$OutputDirectory = '',
  [string]$Dart = 'dart',
  [string]$SignTool = '',
  [string]$CertificateThumbprint = '',
  [switch]$ReleaseBuild,
  [switch]$Validation
)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Dart = Resolve-ShenViewFlutterTool $Dart
if (-not $Compiler) {
  $candidates = @(Join-Path $RepositoryRoot 'build/packaging/tools/inno-7.1.0/ISCC.exe')
  $candidates += @(Get-ShenViewProgramDirectories | ForEach-Object { Join-Path $_ 'Inno Setup 7/ISCC.exe' })
  $Compiler = Resolve-ShenViewTool ISCC.exe -Candidates $candidates
} else {
  $Compiler = Resolve-ShenViewTool $Compiler
}
$compilerVersion = (& $Compiler --version) -join ''
if ($compilerVersion -notmatch '^7[.]') { throw ('需要 Inno Setup 7，实际为: ' + $compilerVersion) }
if (-not $Version) {
  $line = Get-Content -LiteralPath (Join-Path $ViewerRoot 'pubspec.yaml') | Where-Object { $_.StartsWith('version:') }
  $Version = $line.Substring(8).Trim().Replace('+', '.')
}
$parsedVersion = [version]$Version
if ($parsedVersion.Revision -lt 0) { throw '版本必须包含四部分。' }
if ($Validation -and ($ReleaseBuild -or $CertificateThumbprint)) { throw 'validation 不能作为签名发布包。' }
if ($CertificateThumbprint -and -not (Test-Path -LiteralPath $SignTool)) { throw '签名需要 -SignTool 指定 signtool.exe。' }
$mode = if ($Validation) { 'validation' } elseif ($ReleaseBuild) { 'release' } else { 'preview' }
$work = Join-Path $RepositoryRoot ('build/packaging/inno7/' + $mode)
$output = Join-Path $ArtifactRoot ('installers/inno7/' + $Version + '/' + $mode)
if ($OutputDirectory) {
  if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $RepositoryRoot $OutputDirectory }
  $output = [IO.Path]::GetFullPath($OutputDirectory)
}
New-Item -ItemType Directory -Force -Path $work, $output | Out-Null
if (-not $PayloadDirectory) {
  $PayloadDirectory = Join-Path $work 'payload'
  if (Test-Path -LiteralPath $PayloadDirectory) { throw '暂存目录已存在，请传入已验证的 -PayloadDirectory。' }
}
if (-not (Test-Path -LiteralPath $PayloadDirectory)) {
  $cmake = Get-Command cmake -ErrorAction SilentlyContinue
  $cmakePath = if ($cmake) { $cmake.Source } else {
    $visualStudio = & (Resolve-ShenViewVsWhere) -latest -products '*' -property installationPath
    Join-Path $visualStudio 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
  }
  & (Join-Path $PSScriptRoot '../build/build_hdr_codecs.ps1') -CMake $cmakePath
  & (Join-Path $PSScriptRoot '../build/package_windows_codecs.ps1')
  New-Item -ItemType Directory -Path $PayloadDirectory | Out-Null
  $release = Join-Path $ViewerRoot 'build/windows/x64/runner/Release'
  Get-ChildItem -LiteralPath $release -File | Where-Object { $_.Extension -in '.exe','.dll' -or $_.Name -eq 'native_assets.json' } | Copy-Item -Destination $PayloadDirectory
  foreach ($directory in @('data','codecs')) { Copy-Item -LiteralPath (Join-Path $release $directory) -Destination $PayloadDirectory -Recurse }
  $vswhere = (Resolve-ShenViewVsWhere)
  $visualStudio = & $vswhere -latest -products '*' -property installationPath
  $runtime = Get-ChildItem -LiteralPath (Join-Path $visualStudio 'VC/Redist/MSVC') -Directory -Recurse |
    Where-Object { $_.Name -like 'Microsoft.VC*.CRT' -and $_.Parent.Name -eq 'x64' } | Sort-Object FullName -Descending | Select-Object -First 1
  if (-not $runtime) { throw '没有找到 x64 VC Runtime。' }
  Get-ChildItem -LiteralPath $runtime.FullName -Filter '*.dll' | Copy-Item -Destination $PayloadDirectory
}
$PayloadDirectory = (Resolve-Path -LiteralPath $PayloadDirectory).Path
$appInfo = (Get-Item -LiteralPath (Join-Path $PayloadDirectory 'ShenView.exe')).VersionInfo
if ($appInfo.FileDescription -ne 'ShenView' -or $appInfo.ProductName -ne 'ShenView') {
  throw '载荷中的程序名称不是 ShenView，请重新构建 Windows 应用后打包。'
}
$requiredSpaceMB = [long][Math]::Ceiling((Get-ChildItem -LiteralPath $PayloadDirectory -Recurse -File | Measure-Object Length -Sum).Sum / 1MB) + 64
$peFiles = @(Get-ChildItem -LiteralPath $PayloadDirectory -Recurse -File | Where-Object { $_.Extension -in '.exe','.dll' -and $_.Name -notlike 'unins*' })
foreach ($peFile in $peFiles) {
  $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($peFile.FullName))
  try {
    if ($reader.ReadUInt16() -ne 0x5a4d) { throw ('无效 PE 文件: ' + $peFile.FullName) }
    $reader.BaseStream.Position = 0x3c
    $offset = $reader.ReadInt32()
    $reader.BaseStream.Position = $offset
    if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw ('不是 x64 程序: ' + $peFile.FullName) }
  } finally { $reader.Dispose() }
}
$fileList = Get-ChildItem -LiteralPath $PayloadDirectory -Recurse -File | Where-Object { $_.Name -notlike 'unins*' -and $_.Extension -ne '.pdb' } |
  ForEach-Object { $_.FullName.Substring($PayloadDirectory.Length + 1) }
[IO.File]::WriteAllLines((Join-Path $work 'payload-files.txt'), $fileList, [Text.UTF8Encoding]::new($false))
foreach ($required in @('ShenView.exe','flutter_windows.dll','data/app.so','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll',
    'codecs/archive/viewer_archive.exe','codecs/archive/7z.dll','codecs/archive/msvcp140.dll','codecs/archive/vcruntime140.dll','codecs/archive/vcruntime140_1.dll',
    'codecs/imagemagick/magick.exe','codecs/imagemagick/CORE_RL_heif_.dll','codecs/imagemagick/viewer_heif_gainmap.exe','codecs/viewer_raw.exe','codecs/ffmpeg/ffmpeg.exe')) {
  if (-not (Test-Path -LiteralPath (Join-Path $PayloadDirectory $required))) { throw ('缺少运行文件: ' + $required) }
}
Push-Location -LiteralPath $ViewerRoot
try {
  $formatText = & $Dart run tool/export_windows_formats.dart
  if ($LASTEXITCODE -ne 0) { throw '格式清单导出失败。' }
  $formats = ($formatText -join '') | ConvertFrom-Json
} finally { Pop-Location }
function Define([string]$Name, [string]$Value) { '#define ' + $Name + ' "' + $Value.Replace('"','""') + '"' }
$definitions = @(
  (Define 'ProductVersion' $Version), (Define 'PayloadPath' $PayloadDirectory),
  ('#define RequiredSpaceMB ' + $requiredSpaceMB),
  (Define 'WorkOutput' $work), (Define 'PackageOutput' $output),
  (Define 'PayloadList' (Join-Path $work 'payload-files.txt')),
  (Define 'ProductIcon' (Join-Path $ViewerRoot 'windows/runner/resources/app_icon.ico')),
  (Define 'BrandImage' (Join-Path $RepositoryRoot 'branding/png/shenview-64.png')),
  (Define 'ImageFormats' ($formats.images -join ',')), (Define 'ArchiveFormats' ($formats.archives -join ',')),
  (Define 'EnginePath' (Join-Path $work 'ShenView-Setup.exe')),
  (Define 'UninstallWorkerPath' (Join-Path $work 'ShenView-Uninstall.exe')),
  (Define 'MaintenancePath' (Join-Path $work 'maintenance.exe'))
)
if ($Validation) { $definitions += '#define ValidationBuild' }
if ($ReleaseBuild) { $definitions += '#define ReleaseBuild' }
$config = Join-Path $work 'config.iss'
[IO.File]::WriteAllLines($config, $definitions, [Text.UTF8Encoding]::new($false))
$source = Join-Path $RepositoryRoot 'packaging/windows/inno'
foreach ($step in @(@('uninstall-worker.iss',''),@('frontend.iss','--define=MaintenanceBuild'),@('engine.iss',''),@('frontend.iss',''))) {
  $arguments = @('--quiet', ('--define=ConfigPath=' + $config))
  if ($step[1]) { $arguments += $step[1] }
  & $Compiler @arguments (Join-Path $source $step[0])
  if ($LASTEXITCODE -ne 0) { throw ('Inno 编译失败: ' + $step[0]) }
  if ($CertificateThumbprint) {
    $signedPath = switch ($step[0]) {
      'uninstall-worker.iss' { Join-Path $work 'ShenView-Uninstall.exe' }
      'engine.iss' { Join-Path $work 'ShenView-Setup.exe' }
      default {
        if ($step[1]) { Join-Path $work 'maintenance.exe' }
        elseif ($ReleaseBuild) { Join-Path $output ('ShenView-' + $Version + '-windows-x64-setup.exe') }
        else { Join-Path $output ('ShenView-' + $Version + '-windows-x64-inno7-preview.exe') }
      }
    }
    # Each worker must be signed before the next compiler step embeds it.
    & $SignTool sign /sha1 $CertificateThumbprint /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $signedPath
    if ($LASTEXITCODE -ne 0) { throw ('Inno 签名失败: ' + $signedPath) }
    & $SignTool verify /pa $signedPath
    if ($LASTEXITCODE -ne 0) { throw ('Inno 签名验证失败: ' + $signedPath) }
  }
}
$artifactName = if ($ReleaseBuild) { 'ShenView-' + $Version + '-windows-x64-setup.exe' } else { 'ShenView-' + $Version + '-windows-x64-inno7-' + $mode + '.exe' }
$artifact = Join-Path $output $artifactName
$hash = Get-FileHash -LiteralPath $artifact -Algorithm SHA256
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'), $hash.Hash.ToLowerInvariant() + '  ' + (Split-Path $artifact -Leaf))
@{ version=$Version; validation=[bool]$Validation; signed=[bool]$CertificateThumbprint; engine=$compilerVersion; package=$artifact; payload=$PayloadDirectory; x64PayloadFiles=$peFiles.Count } |
  ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'build.json') -Encoding utf8
Write-Output $artifact
