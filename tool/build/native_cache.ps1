function Get-NativeInputKey([string]$Root, [string[]]$Inputs, [string]$Toolchain) {
  $records = @($Toolchain)
  foreach ($inputPath in $Inputs) {
    $absolute = Join-Path $Root $inputPath
    [string[]]$files = if (Test-Path -LiteralPath $absolute -PathType Container) {
      @(Get-ChildItem -LiteralPath $absolute -Recurse -File | ForEach-Object { $_.FullName })
    } else { @((Get-Item -LiteralPath $absolute -ErrorAction Stop).FullName) }
    # .NET Framework and modern .NET use different default culture collations.
    [Array]::Sort($files, [StringComparer]::Ordinal)
    foreach ($file in $files) {
      $relative = $file.Substring($Root.TrimEnd('/','\').Length + 1).Replace('\','/')
      $records += $relative + ':' + (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
  }
  $hash = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($records -join "`n"))))).Replace('-','').ToLowerInvariant() }
  finally { $hash.Dispose() }
}

function Get-NativeCacheFiles([string]$Root, [string[]]$Directories) {
  foreach ($directory in $Directories) {
    Get-ChildItem -LiteralPath (Join-Path $Root $directory) -File -Recurse -ErrorAction Stop |
      ForEach-Object { $_.FullName.Substring($Root.TrimEnd('/','\').Length + 1).Replace('\','/') }
  }
}

function Write-NativeCacheManifest([string]$Root, [string]$Key, [string[]]$Directories) {
  $files = @(Get-NativeCacheFiles $Root $Directories | Sort-Object | ForEach-Object {
    @{name=$_; sha256=(Get-FileHash -LiteralPath (Join-Path $Root $_) -Algorithm SHA256).Hash}
  })
  if (-not $files.Count) { throw 'Native cache is empty' }
  @{schema=1;key=$Key;files=$files} | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $Root 'cache-manifest.json') -Encoding UTF8
}

function Test-NativeCacheManifest([string]$Root, [string]$Key, [string[]]$Directories, [string[]]$Required) {
  try {
    $manifest = Get-Content -LiteralPath (Join-Path $Root 'cache-manifest.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($manifest.schema -ne 1 -or $manifest.key -cne $Key -or -not @($manifest.files).Count) { return $false }
    $actual = @(Get-NativeCacheFiles $Root $Directories | Sort-Object)
    $listed = @($manifest.files | ForEach-Object { $_.name } | Sort-Object)
    if (($actual -join "`n") -cne ($listed -join "`n")) { return $false }
    foreach ($name in $Required) { if ($listed -cnotcontains $name) { return $false } }
    foreach ($file in $manifest.files) {
      if ((Get-FileHash -LiteralPath (Join-Path $Root $file.name) -Algorithm SHA256).Hash -ne $file.sha256) { return $false }
    }
    return $true
  } catch { return $false }
}

function Test-NativeIncrementalBuild([string]$Root, [string]$BuildKey, [string[]]$Directories, [string[]]$Required) {
  try {
    $state = Get-Content -LiteralPath (Join-Path $Root 'build-state.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($state.schema -ne 1 -or $state.key -cne $BuildKey -or -not (Test-Path -LiteralPath (Join-Path $Root 'CMakeCache.txt'))) { return $false }
    $manifest = Get-Content -LiteralPath (Join-Path $Root 'cache-manifest.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    return Test-NativeCacheManifest $Root $manifest.key $Directories $Required
  } catch { return $false }
}

function Get-HdrDependencyKey([string]$CMake, [string]$Generator, [string]$Architecture) {
  $installation = & (Resolve-ShenViewVsWhere) -latest -products '*' -property installationPath
  if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'Visual Studio not found' }
  $compiler = Get-ChildItem -LiteralPath (Join-Path $installation 'VC/Tools/MSVC') -Directory |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
  $cl = Join-Path $compiler.FullName 'bin/Hostx64/x64/cl.exe'
  $sdkRoot = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Windows Kits/10/Include'
  $sdk = Get-ChildItem -LiteralPath $sdkRoot -Directory | Where-Object { $_.Name -match '^10\.' } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
  $cmakeVersion = & $CMake --version
  if ($LASTEXITCODE) { throw 'Cannot identify CMake' }
  $toolchain = @($Architecture,$Generator,$cmakeVersion[0],(Get-FileHash $cl -Algorithm SHA256).Hash,$sdk.Name,$env:ImageVersion) -join ':'
  Get-NativeInputKey $RepositoryRoot @('native/hdr_codecs/CMakeLists.txt','third_party/cmake','third_party/dependencies.lock.json',
    'tool/build/build_hdr_codecs.ps1','tool/build/native_cache.ps1','tool/toolchain.ps1','tool/paths.ps1') $toolchain
}

function Get-HdrCacheKey([string]$CMake, [string]$Generator, [string]$Architecture) {
  $dependencies = Get-HdrDependencyKey $CMake $Generator $Architecture
  Get-NativeInputKey $RepositoryRoot @('native/hdr_codecs') $dependencies
}

function Get-FfmpegCacheKey([string]$CompilerDirectory) {
  $compiler = Join-Path $CompilerDirectory 'gcc.exe'
  $version = & $compiler -dumpfullversion
  if ($LASTEXITCODE) { throw 'Cannot identify GCC version' }
  $target = & $compiler -dumpmachine
  if ($LASTEXITCODE) { throw 'Cannot identify GCC target' }
  $toolchain = @($version,$target,(Get-FileHash $compiler -Algorithm SHA256).Hash,$env:ImageVersion) -join ':'
  Get-NativeInputKey $RepositoryRoot @('third_party/ffmpeg','tool/build/build_ffmpeg.ps1',
    'tool/build/native_cache.ps1','tool/toolchain.ps1','tool/paths.ps1') $toolchain
}

$FfmpegCacheDirectories = @('runtime','install/include','install/lib','install/bin',
  'sysroot/mingw64/include','sysroot/mingw64/lib')
$FfmpegCacheRequired = @('runtime/manifest.json','runtime/ffmpeg.exe','runtime/ffprobe.exe',
  'runtime/viewer_hdr_video.exe','runtime/licenses/COPYING.LGPLv2.1',
  'install/include/libavcodec/avcodec.h','install/lib/libavcodec.dll.a',
  'sysroot/mingw64/include/libplacebo/renderer.h')

$HdrCacheDirectories = @('bin','licenses')
$HdrCacheRequired = @('bin/viewer_gainmap.exe','bin/viewer_heif_gainmap.exe','bin/viewer_raw.exe','bin/viewer_avif_animation.exe',
  'licenses/hdr/LibRaw-LICENSE.CDDL','licenses/hdr/libavif-LICENSE','licenses/hdr/lcms2-LICENSE',
  'licenses/hdr/libaom-LICENSE','licenses/hdr/libaom-PATENTS','licenses/hdr/libultrahdr-LICENSE',
  'licenses/hdr/Adobe-Gain-Map-NOTICE','licenses/hdr/libjpeg-turbo-LICENSE.md')
