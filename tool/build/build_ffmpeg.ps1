param(
  [string]$DownloadCache = '',
  [string]$CompilerDirectory = '',
  [string]$Bash = '',
  [string]$SevenZip = '7z.exe'
)
. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
# Flutter can launch Windows PowerShell with PowerShell 7's module search path.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
  Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1')
  Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Management/Microsoft.PowerShell.Management.psd1')
}
$recipe = Join-Path $RepositoryRoot 'third_party/ffmpeg'
$work = Join-Path $NativeBuildRoot 'ffmpeg/windows-x64'
$runtime = Join-Path $work 'runtime'
$manifestPath = Join-Path $runtime 'manifest.json'
$workerSource = Join-Path $RepositoryRoot 'native/hdr_video/worker.c'
$workerIdentity = (Get-FileHash -LiteralPath $workerSource -Algorithm SHA256).Hash + ':' + (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
function Resolve-CompilerDirectory {
  if ($CompilerDirectory) { return (Resolve-Path -LiteralPath $CompilerDirectory).Path }
  return Split-Path (Resolve-ShenViewTool 'gcc.exe')
}
function Build-HdrWorker {
  $script:CompilerDirectory = Resolve-CompilerDirectory
  $compiler = Join-Path $CompilerDirectory 'gcc.exe'
  if (-not (Test-Path -LiteralPath $compiler)) { throw "缺少 HDR helper 编译器：$compiler" }
  $target = Join-Path $work 'install/bin/viewer_hdr_video.exe'
  $compileArgs = @('-std=c11', '-O2', '-Wall', $workerSource,
    '-I', (Join-Path $work 'install/include'), '-I', (Join-Path $work 'sysroot/mingw64/include'),
    '-L', (Join-Path $work 'install/lib'), '-L', (Join-Path $work 'sysroot/mingw64/lib'),
    '-lavformat', '-lavcodec', '-lavutil', '-lplacebo', '-o', $target)
  & $compiler @compileArgs
  if ($LASTEXITCODE -ne 0) { throw 'HDR helper 编译失败' }
  return $target
}
function Update-RuntimeNotices {
  $extra = Join-Path $recipe 'licenses/zimg/COPYING'
  if ((Get-FileHash -LiteralPath $extra -Algorithm SHA256).Hash -ne '7637386B5F81E8A719CA336233149005E5FA28B5E6054EA7B67DE49355B0AD40') { throw 'zimg 许可校验失败' }
  $notices = Join-Path $runtime 'licenses/dependencies'
  [IO.Directory]::CreateDirectory($notices) | Out-Null
  Copy-Item -LiteralPath (Join-Path $recipe 'licenses/zimg') -Destination $notices -Recurse -Force
  $workerRecipe = Join-Path $runtime 'licenses/build-recipe/hdr_video'
  [IO.Directory]::CreateDirectory($workerRecipe) | Out-Null
  Copy-Item -LiteralPath $workerSource -Destination $workerRecipe -Force
  $buildOnly = Join-Path $notices 'nasm'
  if (Test-Path -LiteralPath $buildOnly) {
    $absolute = [IO.Path]::GetFullPath($buildOnly)
    if (-not $absolute.StartsWith([IO.Path]::GetFullPath($runtime) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '许可目录超出 FFmpeg 运行目录' }
    Remove-Item -LiteralPath $absolute -Recurse -Force
  }
}
$identity = ((@('source.lock.json', 'windows-packages.lock.json', 'profile.sh', 'build-windows.sh', 'patches/libplacebo-lazy-vulkan.patch') | ForEach-Object {
  (Get-FileHash -LiteralPath (Join-Path $recipe $_) -Algorithm SHA256).Hash
}) -join ':')
if (Test-Path -LiteralPath $manifestPath) {
  $existing = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $valid = $existing.identity -eq $identity
  foreach ($file in $existing.files) {
    $path = Join-Path $runtime $file.name
    if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) { $valid = $false }
  }
  if ($valid) {
    if ($existing.workerIdentity -ne $workerIdentity -or -not (Test-Path -LiteralPath (Join-Path $runtime 'viewer_hdr_video.exe'))) {
      $binary = Build-HdrWorker
      Copy-Item -LiteralPath $binary -Destination $runtime -Force
      $imports = @(& (Join-Path $CompilerDirectory 'objdump.exe') -p $binary | Select-String -SimpleMatch 'DLL Name:' | ForEach-Object { $_.Line.Split(':')[-1].Trim().ToLowerInvariant() })
      foreach ($import in $imports) {
        if (-not (Test-Path -LiteralPath (Join-Path $runtime $import)) -and -not (Test-Path -LiteralPath (Join-Path $env:WINDIR "System32/$import")) -and -not $import.StartsWith('api-ms-win-')) { throw "HDR helper 缺少依赖：$import" }
      }
      $existing.files = @($existing.files | Where-Object { $_.name -ne 'viewer_hdr_video.exe' }) + @([pscustomobject]@{
        name = 'viewer_hdr_video.exe'; bytes = (Get-Item -LiteralPath $binary).Length; sha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash; imports = $imports
      })
      $existing | Add-Member -NotePropertyName workerIdentity -NotePropertyValue $workerIdentity -Force
      $existing.runtimeBytes = ($existing.files | Measure-Object bytes -Sum).Sum
      $existing | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    }
    Update-RuntimeNotices; Write-Host "FFmpeg 精简运行组件已校验：$runtime"; return
  }
}
$CompilerDirectory = Resolve-CompilerDirectory
if (-not $Bash) { $Bash = Resolve-ShenViewGitTool 'bin/bash.exe' } else { $Bash = Resolve-ShenViewTool $Bash }
$SevenZip = Resolve-ShenViewSevenZip $SevenZip
foreach ($program in @($Bash, $SevenZip, (Join-Path $CompilerDirectory 'gcc.exe'), (Join-Path $CompilerDirectory 'objdump.exe'))) {
  if (-not (Test-Path -LiteralPath $program)) { throw "缺少 FFmpeg 构建工具：$program" }
}
if (-not $DownloadCache) { $DownloadCache = Join-Path $NativeBuildRoot 'ffmpeg/downloads' }
$DownloadCache = [IO.Path]::GetFullPath($DownloadCache)
[IO.Directory]::CreateDirectory($DownloadCache) | Out-Null
[IO.Directory]::CreateDirectory($work) | Out-Null
function Acquire($item) {
  $file = Join-Path $DownloadCache ([IO.Path]::GetFileName($item.url))
  if (-not (Test-Path -LiteralPath $file)) { Invoke-WebRequest -UseBasicParsing -Uri $item.url -OutFile $file }
  if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.sha256) { throw "下载文件 SHA256 不符：$file" }
  return $file
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
$null = Build-HdrWorker
if (Test-Path -LiteralPath $runtime) {
  $resolved = [IO.Path]::GetFullPath($runtime)
  $allowed = [IO.Path]::GetFullPath($work) + [IO.Path]::DirectorySeparatorChar
  if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'FFmpeg 输出目录超出构建目录' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
[IO.Directory]::CreateDirectory($runtime) | Out-Null
$lookup = @{}
foreach ($directory in @((Join-Path $work 'install/bin'), (Join-Path $work 'sysroot/mingw64/bin'))) {
  Get-ChildItem -LiteralPath $directory -File | ForEach-Object { $lookup[$_.Name.ToLowerInvariant()] = $_.FullName }
}
$pending = [Collections.Generic.Queue[string]]::new()
$pending.Enqueue('ffmpeg.exe')
$pending.Enqueue('ffprobe.exe')
$pending.Enqueue('viewer_hdr_video.exe')
$seen = @{}
$files = @()
while ($pending.Count -gt 0) {
  $name = $pending.Dequeue().ToLowerInvariant()
  if ($seen.ContainsKey($name)) { continue }
  $seen[$name] = $true
  if (-not $lookup.ContainsKey($name)) { throw "缺少运行依赖：$name" }
  $path = $lookup[$name]
  Copy-Item -LiteralPath $path -Destination $runtime
  $imports = @(& (Join-Path $CompilerDirectory 'objdump.exe') -p $path | Select-String -SimpleMatch 'DLL Name:' | ForEach-Object { $_.Line.Split(':')[-1].Trim().ToLowerInvariant() })
  foreach ($import in $imports) {
    if ($lookup.ContainsKey($import)) { $pending.Enqueue($import) }
    elseif (-not (Test-Path -LiteralPath (Join-Path $env:WINDIR "System32/$import")) -and -not $import.StartsWith('api-ms-win-') -and -not $import.StartsWith('ext-ms-win-')) { throw "未解析的依赖：$name -> $import" }
  }
  $files += [pscustomobject]@{ name = $name; bytes = (Get-Item -LiteralPath $path).Length; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash; imports = $imports }
}
$licenses = Join-Path $runtime 'licenses'
[IO.Directory]::CreateDirectory($licenses) | Out-Null
Get-ChildItem -LiteralPath $sourceDirectory -Filter 'COPYING*' -File | Copy-Item -Destination $licenses
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'LICENSE.md') -Destination $licenses
Copy-Item -LiteralPath (Join-Path $work 'sysroot/mingw64/share/licenses') -Destination (Join-Path $licenses 'dependencies') -Recurse
Copy-Item -LiteralPath $recipe -Destination (Join-Path $licenses 'build-recipe') -Recurse
$notice = @(
  'ShenView playback-only FFmpeg 9.0.2 (dynamic libraries; no video export encoders).',
  "FFmpeg corresponding source: $($source.url)",
  'Exact source hash, build recipe and dependency package URLs are in build-recipe/.',
  'Dependency sources and build recipes: https://github.com/msys2/MINGW-packages and https://packages.msys2.org/',
  'FFmpeg: https://ffmpeg.org/ ; third-party copyright/license texts: dependencies/.',
  'These separately loaded libraries may be replaced with ABI-compatible modified builds.'
) -join [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $licenses 'SOURCES.txt'), $notice, [Text.UTF8Encoding]::new($false))
$version = & (Join-Path $runtime 'ffmpeg.exe') -version
if ($LASTEXITCODE -ne 0) { throw 'FFmpeg 运行组件启动失败' }
$manifest = [ordered]@{ version = '9.0.2'; platform = 'windows-x64'; profile = 'playback'; identity = $identity; workerIdentity = $workerIdentity; files = @($files | Sort-Object name); runtimeBytes = ($files | Measure-Object bytes -Sum).Sum; versionOutput = @($version) }
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Update-RuntimeNotices
Write-Host "FFmpeg 精简运行组件：$runtime"
