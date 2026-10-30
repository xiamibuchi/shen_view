param(
  [string]$ReleaseDirectory = '',
  [string]$ImageMagickDirectory = '',
  [string]$SevenZipDirectory = ''
)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
if (-not $ImageMagickDirectory -or -not $SevenZipDirectory) {
  $lockedCodecs = & (Join-Path $PSScriptRoot 'install_windows_codecs.ps1')
  if (-not $ImageMagickDirectory) { $ImageMagickDirectory = $lockedCodecs.ImageMagickDirectory }
  if (-not $SevenZipDirectory) { $SevenZipDirectory = $lockedCodecs.SevenZipDirectory }
}
if (-not $ReleaseDirectory) { $ReleaseDirectory = Join-Path $ViewerRoot 'build/windows/x64/runner/Release' }
$ReleaseDirectory = [IO.Path]::GetFullPath($ReleaseDirectory)
$codecs = Join-Path $ReleaseDirectory 'codecs'
if (Test-Path $codecs) {
  $releaseRoot = [IO.Path]::GetFullPath((Resolve-Path $ReleaseDirectory).Path)
  $codecRoot = [IO.Path]::GetFullPath($codecs)
  if (-not $codecRoot.StartsWith($releaseRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '编解码器目录必须位于 Release 目录内。'
  }
  Remove-Item -LiteralPath $codecs -Recurse -Force
}
New-Item -ItemType Directory -Path $codecs | Out-Null
$magickDirectory = Join-Path $codecs 'imagemagick'
$archiveDirectory = Join-Path $codecs 'archive'
New-Item -ItemType Directory -Path $magickDirectory,$archiveDirectory | Out-Null

Get-ChildItem $ImageMagickDirectory -File | Where-Object {
  $_.Extension -in @('.exe', '.dll', '.xml', '.icc') -and $_.Name -notlike 'unins*'
} | Copy-Item -Destination $magickDirectory
Copy-Item (Join-Path $ImageMagickDirectory 'modules') -Destination $magickDirectory -Recurse

Copy-Item (Join-Path $SevenZipDirectory '7z.dll') -Destination $archiveDirectory

$archiveHelper = Join-Path $NativeBuildRoot 'archive-helper/bin/viewer_archive.exe'
& (Join-Path $PSScriptRoot 'build_archive_helper.ps1') -SevenZipEngine (Join-Path $SevenZipDirectory '7z.dll')
if ($LASTEXITCODE -ne 0) { throw '压缩包读取组件构建失败。' }
Copy-Item -LiteralPath $archiveHelper -Destination $archiveDirectory

# Each child process needs its own app-local CRT; the viewer's parent directory is not searched.
$visualStudio = & (Resolve-ShenViewVsWhere) -latest -products '*' -property installationPath
$runtime = Get-ChildItem -LiteralPath (Join-Path $visualStudio 'VC/Redist/MSVC') -Directory -Recurse |
  Where-Object { $_.Name -like 'Microsoft.VC*.CRT' -and $_.Parent.Name -eq 'x64' } |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $runtime) { throw '没有找到解码子进程所需的 x64 VC Runtime。' }
foreach ($name in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
  foreach ($destination in @($codecs,$archiveDirectory)) {
    Copy-Item -LiteralPath (Join-Path $runtime.FullName $name) -Destination $destination
  }
}

$licenseDirectory = Join-Path $codecs 'licenses'
New-Item -ItemType Directory -Path $licenseDirectory -Force | Out-Null
& (Join-Path $PSScriptRoot 'build_ffmpeg.ps1')
$ffmpegRuntime = Join-Path $NativeBuildRoot 'ffmpeg/windows-x64/runtime'
Copy-Item -LiteralPath $ffmpegRuntime -Destination (Join-Path $codecs 'ffmpeg') -Recurse
Copy-Item -LiteralPath (Join-Path $ffmpegRuntime 'licenses') -Destination (Join-Path $licenseDirectory 'ffmpeg') -Recurse
$svgRoot = Join-Path $NativeBuildRoot 'svg-codecs'
if (-not (Test-Path -LiteralPath (Join-Path $svgRoot 'bin/resvg.exe'))) { throw '缺少 SVG 解码器，请先构建 Windows 应用。' }
Copy-Item -LiteralPath (Join-Path $svgRoot 'bin/resvg.exe') -Destination $codecs
Copy-Item -LiteralPath (Join-Path $svgRoot 'licenses/resvg') -Destination $licenseDirectory -Recurse
$imageMagickLicenses = Join-Path $licenseDirectory 'imagemagick'
New-Item -ItemType Directory -Path $imageMagickLicenses -Force | Out-Null
Copy-Item (Join-Path $ImageMagickDirectory 'License.txt') -Destination $imageMagickLicenses
Copy-Item (Join-Path $ImageMagickDirectory 'NOTICE.txt') -Destination $imageMagickLicenses
$sevenZipLicenses = Join-Path $licenseDirectory '7zip'
New-Item -ItemType Directory -Path $sevenZipLicenses -Force | Out-Null
Copy-Item (Join-Path $SevenZipDirectory 'License.txt') -Destination $sevenZipLicenses
Copy-Item (Join-Path $SevenZipDirectory 'readme.txt') -Destination $sevenZipLicenses
$archiveNotices = Join-Path $NativeBuildRoot 'archive-helper/licenses/7zip'
if (-not (Test-Path -LiteralPath $archiveNotices)) { throw '缺少压缩包读取组件许可证，请重新构建 archive helper。' }
Copy-Item (Join-Path $archiveNotices '*') -Destination $sevenZipLicenses -Force
$sevenZipVersion = (Get-Item -LiteralPath (Join-Path $SevenZipDirectory '7z.dll')).VersionInfo.ProductVersion
$sevenZipSourceVersion = $sevenZipVersion.Replace('.', '')
@(
  "7-Zip Windows engine version: $sevenZipVersion",
  'This release includes parts of 7-Zip, primarily licensed under GNU LGPL 2.1 or later.',
  'Copyright (C) Igor Pavlov. Additional BSD and unRAR terms are included in Engine-License.txt.',
  'Project and source downloads: https://www.7-zip.org/',
  "Official corresponding source: https://github.com/ip7z/7zip/releases/download/$sevenZipVersion/7z$sevenZipSourceVersion-src.tar.xz",
  'The packaged engine is copied from SevenZipDirectory; custom engine suppliers must provide their corresponding source.'
) | Set-Content -LiteralPath (Join-Path $sevenZipLicenses 'ENGINE.txt') -Encoding UTF8

$gainMap = Join-Path $NativeBuildRoot 'hdr-codecs/bin/viewer_gainmap.exe'
if (Test-Path -LiteralPath $gainMap) {
  Copy-Item -LiteralPath $gainMap -Destination $codecs
  $hdrNotices = Join-Path $NativeBuildRoot 'hdr-codecs/licenses/hdr'
  if (-not (Test-Path -LiteralPath $hdrNotices)) { throw '缺少 HDR 组件许可证，请重新配置 HDR codec 构建。' }
  Copy-Item -LiteralPath $hdrNotices -Destination $licenseDirectory -Recurse
}
$heifGainMap = Join-Path $NativeBuildRoot 'hdr-codecs/bin/viewer_heif_gainmap.exe'
if (Test-Path -LiteralPath $heifGainMap) { Copy-Item -LiteralPath $heifGainMap -Destination $magickDirectory }
$raw = Join-Path $NativeBuildRoot 'hdr-codecs/bin/viewer_raw.exe'
if (Test-Path -LiteralPath $raw) { Copy-Item -LiteralPath $raw -Destination $codecs }
$avifRoot = Join-Path $NativeBuildRoot 'avif-codecs'
if (-not (Test-Path -LiteralPath (Join-Path $avifRoot 'bin/viewer_avif_animation.exe'))) {
  $avifRoot = Join-Path $NativeBuildRoot 'hdr-codecs'
}
$avifAnimation = Join-Path $avifRoot 'bin/viewer_avif_animation.exe'
if (-not (Test-Path -LiteralPath $avifAnimation)) { throw '缺少 AVIF 动画组件，请先运行 tool/build/build_hdr_codecs.ps1。' }
Copy-Item -LiteralPath $avifAnimation -Destination $codecs
$avifNotices = Join-Path $avifRoot 'licenses/hdr'
Copy-Item -LiteralPath $avifNotices -Destination $licenseDirectory -Recurse -Force

$licenseReadme = @(
  'Third-party license notices',
  '',
  'ImageMagick: https://imagemagick.org/ (imagemagick/License.txt, imagemagick/NOTICE.txt)',
  '7-Zip: https://www.7-zip.org/ (7zip/License.txt, 7zip/readme.txt)',
  'FFmpeg playback profile: https://ffmpeg.org/ (ffmpeg/, ../ffmpeg/SOURCES.txt)',
  'Image helpers: libultrahdr, libjpeg-turbo, libavif, libaom, Little CMS, libheif, LibRaw (hdr/)'
) -join [Environment]::NewLine
Set-Content -LiteralPath (Join-Path $licenseDirectory 'README.txt') -Value $licenseReadme -Encoding UTF8

$files = Get-ChildItem $ReleaseDirectory -Recurse -File
$bytes = ($files | Measure-Object Length -Sum).Sum
[PSCustomObject]@{
  releaseDirectory = (Resolve-Path $ReleaseDirectory).Path
  codecDirectory = (Resolve-Path $codecs).Path
  fileCount = $files.Count
  bytes = $bytes
  megabytes = [math]::Round($bytes / 1MB, 2)
} | ConvertTo-Json
