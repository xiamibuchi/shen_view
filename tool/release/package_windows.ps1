[CmdletBinding()]
param(
  [string]$Flutter = 'flutter',
  [string]$InnoCompiler = '',
  [string]$PayloadDirectory = '',
  [string]$WindowsSdkBin = '',
  [string]$RuntimeDirectory = '',
  [string]$DownloadBaseUrl = '',
  [string]$Homepage = '',
  [string]$License = '',
  [string]$Publisher = '',
  [string]$CertificateThumbprint = '',
  [switch]$Unsigned,
  [switch]$SkipBuild,
  [switch]$SkipCodecs
)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = $RepositoryRoot
$Flutter = (Resolve-ShenViewFlutterTool $Flutter)
if ($InnoCompiler) { $InnoCompiler = (Get-Command $InnoCompiler -ErrorAction Stop).Source }
if ($PayloadDirectory) { $PayloadDirectory = (Resolve-Path -LiteralPath $PayloadDirectory).Path }
if ($WindowsSdkBin) { $WindowsSdkBin = [IO.Path]::GetFullPath($WindowsSdkBin) }
if ($RuntimeDirectory) { $RuntimeDirectory = [IO.Path]::GetFullPath($RuntimeDirectory) }
Push-Location -LiteralPath $ViewerRoot
try {
  function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program 失败，退出码 $LASTEXITCODE" }
  }
  function SaveText([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
  }
  function ResetBuildDirectory([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    $allowed = [IO.Path]::GetFullPath((Join-Path $root 'build/packaging')) + [IO.Path]::DirectorySeparatorChar
    if (-not $absolute.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw "暂存目录超出 build/packaging：$absolute" }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
    [IO.Directory]::CreateDirectory($absolute) | Out-Null
  }
  function Xml([string]$Text) { [Security.SecurityElement]::Escape($Text) }
  function Render([string]$Template, [hashtable]$Values) {
    $text = [IO.File]::ReadAllText($Template)
    foreach ($key in $Values.Keys) { $text = $text.Replace("@$key@", [string]$Values[$key]) }
    return $text
  }
  function Sign([string]$Path) {
    if (-not $Unsigned) {
      Run $signTool @('sign', '/sha1', $CertificateThumbprint, '/fd', 'SHA256', '/tr', 'http://timestamp.digicert.com', '/td', 'SHA256', $Path)
      Run $signTool @('verify', '/pa', $Path)
    }
  }
  if (-not $Unsigned -and -not $CertificateThumbprint) { throw '请提供 -CertificateThumbprint；仅本地测试时显式传 -Unsigned。' }
  if ($Unsigned -and $CertificateThumbprint) { throw '-Unsigned 与 -CertificateThumbprint 不能同时使用。' }
  $metadata = Get-Content -LiteralPath (Join-Path $root 'packaging/windows/product.json') -Raw | ConvertFrom-Json
  if ($Publisher) { $metadata.publisher = $Publisher }
  $versionMatch = [regex]::Match([IO.File]::ReadAllText((Join-Path $ViewerRoot 'pubspec.yaml')), '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
  if (-not $versionMatch.Success) { throw 'pubspec.yaml 必须使用 major.minor.patch+build 版本格式。' }
  $parts = @(1..4 | ForEach-Object { [int]$versionMatch.Groups[$_].Value })
  if (@($parts | Where-Object { $_ -gt 65535 }).Count) { throw 'Windows 版本的每一部分必须小于等于 65535。' }
  $version = $parts[0..2] -join '.'
  $fileVersion = $parts -join '.'
  if (-not $WindowsSdkBin) {
    $sdk = Get-ChildItem -LiteralPath (Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Windows Kits/10/bin') -Directory |
      Where-Object { $_.Name -match '^10\.0\.\d+\.0$' } | Sort-Object { [version]$_.Name } -Descending |
      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64/makeappx.exe') } | Select-Object -First 1
    if (-not $sdk) { throw '未找到 Windows SDK makeappx.exe，请传 -WindowsSdkBin。' }
    $WindowsSdkBin = Join-Path $sdk.FullName 'x64'
  }
  $makeAppx = Join-Path $WindowsSdkBin 'makeappx.exe'
  $signTool = Join-Path $WindowsSdkBin 'signtool.exe'
  if (-not $RuntimeDirectory -and -not $PayloadDirectory) {
    $vswhere = Resolve-ShenViewVsWhere
    $visualStudio = & $vswhere -latest -products '*' -property installationPath
    $runtime = Get-ChildItem -LiteralPath (Join-Path $visualStudio 'VC/Redist/MSVC') -Directory -Recurse |
      Where-Object { $_.FullName -match '\\x64\\Microsoft\.VC\d+\.CRT$' } | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $runtime) { throw '未找到 x64 VC Runtime，请传 -RuntimeDirectory。' }
    $RuntimeDirectory = $runtime.FullName
  }
  $cmake = Get-Command cmake -ErrorAction SilentlyContinue
  $cmakePath = if ($cmake) { $cmake.Source } else {
    $vswhere = Resolve-ShenViewVsWhere
    $visualStudio = & $vswhere -latest -products '*' -property installationPath
    Join-Path $visualStudio 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
  }
  $work = Join-Path $root 'build/packaging/windows-x64'
  if ($PayloadDirectory -and ($PayloadDirectory -eq $work -or $PayloadDirectory.StartsWith($work + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) {
    throw '输入载荷不能位于将被清理的 build/packaging/windows-x64 暂存目录。'
  }
  ResetBuildDirectory $work
  $payload = Join-Path $work 'payload'
  $portable = Join-Path $work 'portable'
  $msix = Join-Path $work 'msix'
  $flavor = if ($Unsigned) { 'unsigned' } else { 'signed' }
  $out = Join-Path $root "artifacts/releases/$fileVersion/windows-x64/$flavor"
  [IO.Directory]::CreateDirectory($out) | Out-Null
  $dart = Join-Path (Split-Path -Parent $Flutter) 'dart.bat'
  $formatText = & $dart run tool/export_windows_formats.dart
  if ($LASTEXITCODE -ne 0) { throw '导出格式列表失败。' }
  $formats = ($formatText -join '') | ConvertFrom-Json
  SaveText (Join-Path $work 'file-types.json') ($formats | ConvertTo-Json -Depth 8)
  if (-not $PayloadDirectory -and -not $SkipBuild) { Run $Flutter @('build', 'windows', '--release', '--no-pub') }
  if (-not $PayloadDirectory -and -not $SkipCodecs) {
    & (Join-Path $PSScriptRoot '../build/build_hdr_codecs.ps1') -CMake $cmakePath
    & (Join-Path $PSScriptRoot '../build/package_windows_codecs.ps1')
  }
  $release = Join-Path $ViewerRoot 'build/windows/x64/runner/Release'
  [IO.Directory]::CreateDirectory($payload) | Out-Null
  if ($PayloadDirectory) {
    foreach ($personal in @('settings.json','user-data','cache','installation-mode','install.ini','uninstall.exe','maintain.exe')) {
      if (Test-Path -LiteralPath (Join-Path $PayloadDirectory $personal)) { throw ('输入目录含运行或安装状态，不能作为干净载荷：' + $personal) }
    }
    Get-ChildItem -LiteralPath $PayloadDirectory | Copy-Item -Destination $payload -Recurse
  } else {
    Get-ChildItem -LiteralPath $release -File | Where-Object { $_.Extension -in '.exe', '.dll' -or $_.Name -eq 'native_assets.json' } |
      Copy-Item -Destination $payload
    foreach ($directory in @('data', 'codecs')) { Copy-Item -LiteralPath (Join-Path $release $directory) -Destination $payload -Recurse }
    Get-ChildItem -LiteralPath $RuntimeDirectory -File -Filter '*.dll' | Copy-Item -Destination $payload
  }
  Get-ChildItem -LiteralPath $payload -Recurse -File | Where-Object { $_.Name -like 'unins*' -or $_.Extension -eq '.pdb' } | Remove-Item -Force
  $appInfo = (Get-Item -LiteralPath (Join-Path $payload 'ShenView.exe')).VersionInfo
  $appVersion = @($appInfo.FileMajorPart,$appInfo.FileMinorPart,$appInfo.FileBuildPart,$appInfo.FilePrivatePart) -join '.'
  if ([version]$appVersion -ne [version]$fileVersion) { throw ('载荷版本与 pubspec.yaml 不一致：' + $appVersion + ' / ' + $fileVersion) }
  foreach ($required in @('ShenView.exe', 'flutter_windows.dll', 'data/app.so', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
      'codecs/imagemagick/magick.exe', 'codecs/archive/7z.dll', 'codecs/archive/viewer_archive.exe', 'codecs/resvg.exe',
      'codecs/viewer_gainmap.exe', 'codecs/imagemagick/viewer_heif_gainmap.exe', 'codecs/viewer_raw.exe',
      'codecs/viewer_avif_animation.exe', 'codecs/licenses',
      'codecs/ffmpeg/ffmpeg.exe', 'codecs/ffmpeg/ffprobe.exe',
      'codecs/ffmpeg/manifest.json', 'codecs/ffmpeg/licenses/SOURCES.txt', 'codecs/licenses/ffmpeg')) {
    if (-not (Test-Path -LiteralPath (Join-Path $payload $required))) { throw "发布文件缺失：$required" }
  }
  if (-not $Unsigned) {
    $certificate = Get-Item -LiteralPath "Cert:/CurrentUser/My/$CertificateThumbprint" -ErrorAction Stop
    if ($certificate.Subject -ne $metadata.publisher) { throw 'MSIX Publisher 必须与签名证书 Subject 一致，请使用 -Publisher。' }
    Get-ChildItem -LiteralPath $payload -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' } | ForEach-Object { Sign $_.FullName }
    # Authenticode changes PE bytes; keep the shipped manifest about the shipped files.
    $ffmpegManifestPath = Join-Path $payload 'codecs/ffmpeg/manifest.json'
    $ffmpegManifest = Get-Content -LiteralPath $ffmpegManifestPath -Raw | ConvertFrom-Json
    foreach ($binary in $ffmpegManifest.files) {
      $binary | Add-Member -NotePropertyName unsignedSha256 -NotePropertyValue $binary.sha256
      $binaryPath = Join-Path $payload ('codecs/ffmpeg/' + $binary.name)
      $binary.sha256 = (Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash
      $binary.bytes = (Get-Item -LiteralPath $binaryPath).Length
    }
    $ffmpegManifest.runtimeBytes = ($ffmpegManifest.files | Measure-Object bytes -Sum).Sum
    $ffmpegManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ffmpegManifestPath -Encoding UTF8
  }
  Copy-Item -LiteralPath $payload -Destination $portable -Recurse
  SaveText (Join-Path $portable 'installation-mode') 'portable'
  [IO.Directory]::CreateDirectory((Join-Path $portable 'user-data')) | Out-Null
  SaveText (Join-Path $portable 'README-portable.txt') "ShenView $version portable: extract the entire archive before running ShenView.exe. Settings and archive cache are stored in user-data. File associations are optional in Settings > General. Remove associations before moving or deleting this copy. Complex SVG requires Microsoft Edge WebView2 Runtime."
  $zipName = "ShenView-$fileVersion-windows-x64-portable.zip"
  $exeName = "ShenView-$fileVersion-windows-x64-setup.exe"
  $msixName = "ShenView-$fileVersion-windows-x64.msix"
  $zipPath = Join-Path $out $zipName
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::CreateFromDirectory($portable, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)

  $innoArguments = @{PayloadDirectory=$payload; Version=$fileVersion; OutputDirectory=$out; ReleaseBuild=$true; Dart=$dart}
  if ($InnoCompiler) { $innoArguments.Compiler = $InnoCompiler }
  if (-not $Unsigned) { $innoArguments.SignTool = $signTool; $innoArguments.CertificateThumbprint = $CertificateThumbprint }
  & (Join-Path $PSScriptRoot 'package_windows_inno.ps1') @innoArguments | Out-Host

  Copy-Item -LiteralPath $payload -Destination $msix -Recurse
  SaveText (Join-Path $msix 'installation-mode') 'msix'
  $imageTypes = ($formats.images | ForEach-Object { '<uap:FileType>.' + $_ + '</uap:FileType>' }) -join ''
  $archiveTypes = ($formats.archives | ForEach-Object { '<uap:FileType>.' + $_ + '</uap:FileType>' }) -join ''
  $manifest = Render (Join-Path $root 'packaging/windows/msix/AppxManifest.xml') @{
    PACKAGE_NAME = Xml $metadata.packageName; PUBLISHER = Xml $metadata.publisher; VERSION = $fileVersion
    DISPLAY_NAME = Xml $metadata.displayName; PUBLISHER_NAME = Xml $metadata.publisherDisplayName
    MINIMUM_WINDOWS = $metadata.minimumWindowsVersion; IMAGE_TYPES = $imageTypes; ARCHIVE_TYPES = $archiveTypes
  }
  SaveText (Join-Path $msix 'AppxManifest.xml') $manifest
  Add-Type -AssemblyName System.Drawing
  [IO.Directory]::CreateDirectory((Join-Path $msix 'Assets')) | Out-Null
  $source = [Drawing.Image]::FromFile((Join-Path $root 'branding/png/shenview-256.png'))
  try {
    foreach ($logo in @(@('StoreLogo', 50), @('Square44x44Logo', 44), @('Square150x150Logo', 150))) {
      $bitmap = [Drawing.Bitmap]::new([int]$logo[1], [int]$logo[1])
      $graphics = [Drawing.Graphics]::FromImage($bitmap)
      try {
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($source, 0, 0, [int]$logo[1], [int]$logo[1])
        $bitmap.Save((Join-Path $msix ('Assets/' + $logo[0] + '.png')), [Drawing.Imaging.ImageFormat]::Png)
      } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
  } finally { $source.Dispose() }
  Run $makeAppx @('pack', '/d', $msix, '/p', (Join-Path $out $msixName), '/o') | Set-Content -LiteralPath (Join-Path $work 'makeappx.log') -Encoding UTF8
  Sign (Join-Path $out $msixName)

  $exeHash = (Get-FileHash -LiteralPath (Join-Path $out $exeName) -Algorithm SHA256).Hash
  $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $channelReady = $DownloadBaseUrl -ne '' -and $Homepage -ne '' -and $License -ne '' -and -not $Unsigned
  foreach ($uri in @($DownloadBaseUrl, $Homepage) | Where-Object { $_ }) {
    $parsed = $null
    if (-not [Uri]::TryCreate($uri, [UriKind]::Absolute, [ref]$parsed) -or $parsed.Scheme -ne 'https' -or $parsed.Query -or $parsed.Fragment) { throw '下载基址与项目主页必须是无查询串的 HTTPS URL。' }
  }
  $baseUrl = if ($DownloadBaseUrl) { $DownloadBaseUrl.TrimEnd('/') } else { '@DOWNLOAD_BASE_URL@' }
  $homeUrl = if ($Homepage) { $Homepage } else { '@HOMEPAGE@' }
  $licenseValue = if ($License) { $License } else { '@LICENSE@' }
  $channelOut = Join-Path $out $(if ($channelReady) { 'channels' } else { 'channel-templates' })
  foreach ($kind in @('installer', 'defaultLocale', 'version')) {
    $template = Join-Path $root "packaging/channels/winget/$kind.yaml.in"
    $values = @{
      PACKAGE_ID = $metadata.wingetId; VERSION = $fileVersion; MINIMUM_WINDOWS = $metadata.minimumWindowsVersion
      INSTALLER_URL = (($baseUrl + '/' + $exeName) | ConvertTo-Json -Compress)
      SHA256 = $exeHash; LICENSE = ($licenseValue | ConvertTo-Json -Compress); HOMEPAGE = ($homeUrl | ConvertTo-Json -Compress)
    }
    $suffix = if ($channelReady) { '.yaml' } else { '.yaml.in' }
    $locale = if ($kind -eq 'defaultLocale') { '.locale.zh-CN' } elseif ($kind -eq 'installer') { '.installer' } else { '' }
    SaveText (Join-Path $channelOut ("winget/" + $metadata.wingetId + $locale + $suffix)) (Render $template $values)
  }
  $scoop = Render (Join-Path $root 'packaging/channels/scoop/shenview.json.in') @{
    VERSION = $fileVersion; SHA256 = $zipHash
    ZIP_URL = ($baseUrl + '/' + $zipName).Replace('\', '\\').Replace('"', '\"')
    HOMEPAGE = $homeUrl.Replace('\', '\\').Replace('"', '\"'); LICENSE = $licenseValue.Replace('\', '\\').Replace('"', '\"')
  }
  $scoop | ConvertFrom-Json | Out-Null
  $suffix = if ($channelReady) { '.json' } else { '.json.in' }
  SaveText (Join-Path $channelOut "scoop/shenview$suffix") $scoop
  $hashes = foreach ($name in @($exeName, $msixName, $zipName)) {
    $hash = Get-FileHash -LiteralPath (Join-Path $out $name) -Algorithm SHA256
    $hash.Hash.ToLowerInvariant() + '  ' + $name
  }
  SaveText (Join-Path $out 'SHA256SUMS.txt') ($hashes -join [Environment]::NewLine)
  SaveText (Join-Path $out 'release.json') (@{
    version = $version; windowsVersion = $fileVersion; architecture = 'x64'; signed = -not $Unsigned
    channelMetadataComplete = $channelReady; minimumWindowsVersion = $metadata.minimumWindowsVersion
    publisher = $metadata.publisher; fileTypes = $formats; webView2RuntimeRequiredForComplexSvg = $true
    installerType = 'inno'; productCode = 'ShenView.Inno7_is1'; payloadSource = $(if ($PayloadDirectory) { $PayloadDirectory } else { $release })
  } | ConvertTo-Json -Depth 8)
  if (-not $channelReady) { Write-Warning '当前是本地测试产物/渠道模板。正式发布需可信签名、下载基址、项目主页和软件许可；未签名 MSIX 不能直接安装。' }
  Write-Host "Windows 发布产物：$out"
} finally { Pop-Location }
