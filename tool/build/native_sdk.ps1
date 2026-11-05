function Get-NativeSdkLock {
  $lock = Get-Content -LiteralPath (Join-Path $RepositoryRoot "third_party/native-sdk.lock.json") -Raw | ConvertFrom-Json
  if ($lock.schema -ne 1 -or $lock.platform -cne "windows-x64" -or $lock.version -notmatch "^\d+\.\d+\.\d+$" -or
      $lock.recipeSha256 -cnotmatch "^[a-f0-9]{64}$") { throw "Invalid native SDK lock" }
  foreach ($component in @("hdr","ffmpeg")) {
    $entry = $lock.components.$component
    if ($entry.asset -cne "shenview-$component-sdk-windows-x64.zip" -or
        ($entry.sha256 -and $entry.sha256 -cnotmatch "^[a-f0-9]{64}$")) { throw "Invalid SDK asset: $component" }
  }
  return $lock
}

function Get-NativeSdkRecipeKey {
  $recipe = Get-Content -LiteralPath (Join-Path $RepositoryRoot "third_party/native-sdk/recipe.json") -Raw | ConvertFrom-Json
  $dependencies = Get-Content -LiteralPath (Join-Path $RepositoryRoot "third_party/dependencies.lock.json") -Raw | ConvertFrom-Json
  $records = @("native-sdk-recipe-v1:windows-x64:Release:MD")
  foreach ($name in $recipe.hdrSources) {
    $source = $dependencies.sources.$name
    $records += "$name`n$($source.url)`n$($source.sha256)`n$($source.sourceSubdir)"
  }
  foreach ($inputPath in $recipe.inputs) {
    $absolute = Join-Path $RepositoryRoot $inputPath
    [string[]]$files = if (Test-Path -LiteralPath $absolute -PathType Container) {
      @(Get-ChildItem -LiteralPath $absolute -File -Recurse | ForEach-Object { $_.FullName })
    } else { @((Get-Item -LiteralPath $absolute).FullName) }
    [Array]::Sort($files, [StringComparer]::Ordinal)
    foreach ($file in $files) {
      $relative = $file.Substring($RepositoryRoot.TrimEnd("/","\").Length + 1).Replace("\","/")
      $text = [IO.File]::ReadAllText($file).Replace("`r`n","`n")
      $records += $relative + "`n" + $text
    }
  }
  $hash = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($records -join "`n"))))).Replace("-","").ToLowerInvariant() }
  finally { $hash.Dispose() }
}

function Get-NativeSdkBuildPlan($Lock, $BaseLock) {
  $pending = @($Lock.components.hdr,$Lock.components.ffmpeg | Where-Object { -not $_.sha256 }).Count
  if ($pending -eq 1) { throw "Both SDK components must be published or pending together" }
  $build = $pending -eq 2
  if ($build -and $BaseLock -and
      ([version]$Lock.version -le [version]$BaseLock.version -or $Lock.recipeSha256 -ceq $BaseLock.recipeSha256)) {
    throw "Pending SDK requires a new version and changed dependency recipe"
  }
  return $build
}

function Remove-NativeSdkBuildDirectory([string]$Path, [string]$Parent) {
  $absolute = [IO.Path]::GetFullPath($Path)
  $allowed = [IO.Path]::GetFullPath($Parent).TrimEnd("/","\") + [IO.Path]::DirectorySeparatorChar
  if (-not $absolute.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw "Invalid SDK cleanup path: $absolute" }
  if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}

function Get-NativeSdkFiles([string]$Root) {
  @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.FullName -ne (Join-Path $Root "sdk-manifest.json") } |
    ForEach-Object { $_.FullName.Substring($Root.TrimEnd("/","\").Length + 1).Replace("\","/") } | Sort-Object)
}

function Assert-NativeSdk([string]$Root, [string]$Component, $Lock) {
  $manifest = Get-Content -LiteralPath (Join-Path $Root "sdk-manifest.json") -Raw -ErrorAction Stop | ConvertFrom-Json
  if ($manifest.schema -ne 1 -or $manifest.platform -cne $Lock.platform -or $manifest.component -cne $Component -or
      $manifest.version -cne $Lock.version -or $manifest.recipeSha256 -cne $Lock.recipeSha256) { throw "SDK identity mismatch: $Component" }
  $actual = @(Get-NativeSdkFiles $Root)
  $listed = @($manifest.files | ForEach-Object { $_.name } | Sort-Object)
  if (-not $listed.Count -or ($actual -join "`n") -cne ($listed -join "`n")) { throw "SDK file list mismatch: $Component" }
  $required = if ($Component -eq "hdr") {
    @("include/avif/avif.h","include/libraw/libraw.h","include/lcms2.h","include/ultrahdr_api.h",
      "lib/avif_internal.lib","lib/aom.lib","lib/uhdr-static.lib","lib/viewer_lcms.lib","lib/viewer_raw_lib.lib",
      "lib/jpeg-static.lib","lib/cmake/ShenViewHdr/ShenViewHdrConfig.cmake","licenses/hdr/LibRaw-LICENSE.CDDL")
  } else {
    @("runtime/ffmpeg.exe","runtime/ffprobe.exe","install/include/libavcodec/avcodec.h",
      "install/lib/libavcodec.dll.a","sysroot/mingw64/include/libplacebo/renderer.h",
      "runtime/licenses/COPYING.LGPLv2.1")
  }
  foreach ($name in $required) { if ($listed -cnotcontains $name) { throw "SDK missing required file: $name" } }
  foreach ($file in $manifest.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $Root $file.name) -Algorithm SHA256).Hash -ne $file.sha256) { throw "SDK file hash mismatch: $($file.name)" }
  }
}

function Expand-NativeSdkArchive([string]$Archive, [string]$Destination) {
  $Archive = (Resolve-Path -LiteralPath $Archive -ErrorAction Stop).Path
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    $seen = @{}
    foreach ($entry in $zip.Entries) {
      $name = $entry.FullName.Replace("\","/")
      if ($name -match "(^/|:|(^|/)\.\.(/|$))" -or $seen.ContainsKey($name) -or
          (($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw "Unsafe SDK archive entry: $name" }
      $seen[$name] = $true
    }
  } finally { $zip.Dispose() }
  [IO.Compression.ZipFile]::ExtractToDirectory($Archive,$Destination)
}

function Resolve-NativeSdkComponent([string]$Component, [string]$Mode = "Auto") {
  if ($Mode -eq "Auto" -and $env:SHENVIEW_NATIVE_BUILD_MODE) { $Mode = $env:SHENVIEW_NATIVE_BUILD_MODE }
  if ($Mode -notin @("Auto","Sdk","Source")) { throw "Invalid native dependency mode: $Mode" }
  $binding = "SHENVIEW_" + $Component.ToUpperInvariant() + "_SDK"
  if ($Mode -eq "Source") { [Environment]::SetEnvironmentVariable($binding,$null,"Process"); return $null }
  $lock = Get-NativeSdkLock
  if ($lock.recipeSha256 -cne (Get-NativeSdkRecipeKey)) { throw "SDK recipe changed. Build and validate a new SDK version, or explicitly select Source mode." }
  if ($env:SHENVIEW_NATIVE_SDK_ROOT) {
    $root = Join-Path ([IO.Path]::GetFullPath($env:SHENVIEW_NATIVE_SDK_ROOT)) $Component
    Assert-NativeSdk $root $Component $lock
  } else {
    $entry = $lock.components.$Component
    if (-not $entry.sha256) { throw "SDK is not published. Supply the candidate SDK root, or explicitly select Source mode." }
    $cache = Join-Path $NativeBuildRoot ("native-sdk/" + $lock.version + "-" + $entry.sha256)
    $root = Join-Path $cache $Component
    $valid = $false
    if (Test-Path -LiteralPath $root) { try { Assert-NativeSdk $root $Component $lock; $valid = $true } catch { Write-Warning $_.Exception.Message } }
    if (-not $valid) {
      [IO.Directory]::CreateDirectory($cache) | Out-Null
      . (Join-Path $RepositoryRoot "third_party/ffmpeg/download.ps1")
      $archive = Join-Path $cache $entry.asset
      $url = "https://github.com/xiamibuchi/shen_view/releases/download/native-sdk-v$($lock.version)/$($entry.asset)"
      $null = Get-VerifiedFfmpegDownload -Uri $url -Sha256 $entry.sha256 -Destination $archive
      Remove-NativeSdkBuildDirectory $root $cache
      Expand-NativeSdkArchive $archive $root
      Assert-NativeSdk $root $Component $lock
    }
  }
  [Environment]::SetEnvironmentVariable($binding,$root,"Process")
  return $root
}
