function Build-FfmpegDependencies {
if (-not $Bash) { $Bash = Resolve-ShenViewGitTool 'bin/bash.exe' } else { $Bash = Resolve-ShenViewTool $Bash }
$SevenZip = Resolve-ShenViewSevenZip $SevenZip
foreach ($program in @($Bash, $SevenZip, (Join-Path $CompilerDirectory 'gcc.exe'), (Join-Path $CompilerDirectory 'objdump.exe'))) {
  if (-not (Test-Path -LiteralPath $program)) { throw "缺少 FFmpeg 构建工具：$program" }
}
# Compiler changes and incomplete restored SDKs must not reuse old object files.
foreach ($name in @('build','install','sysroot')) {
  $clean = [IO.Path]::GetFullPath((Join-Path $work $name))
  $allowed = [IO.Path]::GetFullPath($work).TrimEnd('/','\') + [IO.Path]::DirectorySeparatorChar
  if (-not $clean.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid FFmpeg build cleanup path' }
  if (Test-Path -LiteralPath $clean) { Remove-Item -LiteralPath $clean -Recurse -Force }
}
if (-not $DownloadCache) { $DownloadCache = Join-Path $NativeBuildRoot 'ffmpeg/downloads' }
$DownloadCache = [IO.Path]::GetFullPath($DownloadCache)
[IO.Directory]::CreateDirectory($DownloadCache) | Out-Null
[IO.Directory]::CreateDirectory($work) | Out-Null
function Acquire($item) {
  $file = Join-Path $DownloadCache ([IO.Path]::GetFileName($item.url))
  Get-VerifiedFfmpegDownload -Uri $item.url -Sha256 $item.sha256 -Destination $file
}
function Extract([string]$Archive, [string]$Destination) {
  & $SevenZip x $Archive "-o$Destination" -y -bso0 -bsp0
  if ($LASTEXITCODE -ne 0) { throw "解压失败：$Archive" }
}
$source = Get-Content (Join-Path $recipe 'source.lock.json') -Raw | ConvertFrom-Json
$sourceArchive = Acquire $source
Extract $sourceArchive $DownloadCache
$sources = Join-Path $NativeBuildRoot 'ffmpeg/source'
Extract (Join-Path $DownloadCache ([IO.Path]::GetFileNameWithoutExtension($sourceArchive))) $sources
$sourceDirectory = Join-Path $sources 'ffmpeg-9.0.2'
$packages = Get-Content (Join-Path $recipe 'windows-packages.lock.json') -Raw | ConvertFrom-Json
foreach ($package in $packages) {
  $archive = Acquire $package
  Extract $archive $DownloadCache
  Extract (Join-Path $DownloadCache ([IO.Path]::GetFileNameWithoutExtension($archive))) (Join-Path $work 'sysroot')
}
$variableNames = @('SHENVIEW_FFMPEG_BUILD_ROOT', 'SHENVIEW_FFMPEG_SOURCE', 'SHENVIEW_FFMPEG_COMPILER')
$saved = @{}
foreach ($name in $variableNames) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
  $env:SHENVIEW_FFMPEG_BUILD_ROOT = $work.Replace([char]92, [char]47)
  $env:SHENVIEW_FFMPEG_SOURCE = $sourceDirectory.Replace([char]92, [char]47)
  $env:SHENVIEW_FFMPEG_COMPILER = ([IO.Path]::GetFullPath($CompilerDirectory)).Replace([char]92, [char]47)
  & $Bash (Join-Path $recipe 'build-windows.sh').Replace([char]92, [char]47)
  if ($LASTEXITCODE -ne 0) { throw "FFmpeg 编译失败：$LASTEXITCODE" }
} finally {
  foreach ($name in $variableNames) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
}
