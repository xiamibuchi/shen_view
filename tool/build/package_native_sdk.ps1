[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet("hdr","ffmpeg")][string]$Component,
  [string]$OutputDirectory = "",
  [string]$BuildRoot = ""
)
. (Join-Path $PSScriptRoot "../paths.ps1")
. (Join-Path $PSScriptRoot "native_cache.ps1")
$ErrorActionPreference = "Stop"
$lock = Get-NativeSdkLock
if ($lock.recipeSha256 -cne (Get-NativeSdkRecipeKey)) { throw "Update the SDK lock recipeSha256 before packaging" }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $ArtifactRoot ("native-sdk/" + $lock.version) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$stage = Join-Path $OutputDirectory $Component
Remove-NativeSdkBuildDirectory $stage $OutputDirectory
[IO.Directory]::CreateDirectory($stage) | Out-Null
$sourceStage = Join-Path $OutputDirectory "$Component-sources"
Remove-NativeSdkBuildDirectory $sourceStage $OutputDirectory
[IO.Directory]::CreateDirectory($sourceStage) | Out-Null
function Copy-SdkFile([string]$Source, [string]$Relative) {
  $destination = Join-Path $stage $Relative
  [IO.Directory]::CreateDirectory((Split-Path $destination)) | Out-Null
  Copy-Item -LiteralPath $Source -Destination $destination -Recurse -Force
}
if ($Component -eq "hdr") {
  $build = if ($BuildRoot) { [IO.Path]::GetFullPath($BuildRoot) } else { Join-Path $NativeBuildRoot "hdr-codecs" }
  $libraries = [ordered]@{
    "Release/viewer_lcms.lib"="viewer_lcms.lib"
    "Release/viewer_raw_lib.lib"="viewer_raw_lib.lib"
    "viewer-jpeg/Release/jpeg-static.lib"="jpeg-static.lib"
    "_deps/libaom-build/Release/aom.lib"="aom.lib"
    "_deps/viewer_avif-build/Release/avif_internal.lib"="avif_internal.lib"
    "_deps/ultrahdr-build/Release/uhdr-static.lib"="uhdr-static.lib"
  }
  foreach ($entry in $libraries.GetEnumerator()) { Copy-SdkFile (Join-Path $build $entry.Key) ("lib/" + $entry.Value) }
  Copy-SdkFile (Join-Path $build "_deps/viewer_avif-src/include/avif") "include/avif"
  foreach ($header in Get-ChildItem -LiteralPath (Join-Path $build "_deps/libaom-src/aom") -Filter "*.h") {
    Copy-SdkFile $header.FullName ("include/aom/" + $header.Name)
  }
  foreach ($header in @("jpeglib.h","jmorecfg.h","jerror.h")) {
    Copy-SdkFile (Join-Path $build "_deps/viewer_jpeg-src/src/$header") "include/$header"
  }
  Copy-SdkFile (Join-Path $build "viewer-jpeg/jconfig.h") "include/jconfig.h"
  Copy-SdkFile (Join-Path $build "_deps/viewer_libraw-src/libraw") "include/libraw"
  foreach ($header in @("lcms2.h","lcms2_plugin.h")) { Copy-SdkFile (Join-Path $build "_deps/viewer_lcms-src/include/$header") "include/$header" }
  Copy-SdkFile (Join-Path $build "_deps/ultrahdr-src/ultrahdr_api.h") "include/ultrahdr_api.h"
  Copy-SdkFile (Join-Path $build "ShenViewHdrConfig.cmake") "lib/cmake/ShenViewHdr/ShenViewHdrConfig.cmake"
  Copy-SdkFile (Join-Path $build "licenses") "licenses"
  $recipe = Get-Content -LiteralPath (Join-Path $RepositoryRoot "third_party/native-sdk/recipe.json") -Raw | ConvertFrom-Json
  foreach ($name in $recipe.hdrSources) {
    Copy-Item -LiteralPath (Join-Path $build "_deps/$name-src") -Destination (Join-Path $sourceStage $name) -Recurse
  }
} else {
  $build = if ($BuildRoot) { [IO.Path]::GetFullPath($BuildRoot) } else { Join-Path $NativeBuildRoot "ffmpeg/windows-x64" }
  Copy-SdkFile (Join-Path $build "runtime") "runtime"
  Remove-Item -LiteralPath (Join-Path $stage "runtime/viewer_hdr_video.exe"),(Join-Path $stage "runtime/manifest.json") -Force
  Remove-NativeSdkBuildDirectory (Join-Path $stage "runtime/licenses/build-recipe/hdr_video") $stage
  foreach ($directory in @("install/include","install/lib","sysroot/mingw64/include","sysroot/mingw64/lib")) {
    Copy-SdkFile (Join-Path $build $directory) $directory
  }
  [IO.Directory]::CreateDirectory((Join-Path $stage "install/bin")) | Out-Null
  # Consumers pass include/lib paths explicitly; upstream .pc/.la files embed producer paths.
  Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object { $_.Extension -in @(".pc",".la",".cmake") } | Remove-Item -Force
  Copy-Item -LiteralPath (Join-Path $NativeBuildRoot "ffmpeg/source/ffmpeg-9.0.2") -Destination (Join-Path $sourceStage "ffmpeg") -Recurse
  . (Join-Path $RepositoryRoot "third_party/ffmpeg/download.ps1")
  $binaryPackages = Get-Content -LiteralPath (Join-Path $RepositoryRoot "third_party/ffmpeg/windows-packages.lock.json") -Raw | ConvertFrom-Json
  $sources = Get-Content -LiteralPath (Join-Path $RepositoryRoot "third_party/native-sdk/windows-sources.lock.json") -Raw | ConvertFrom-Json
  $cache = Join-Path $NativeBuildRoot "native-sdk-sources"
  [IO.Directory]::CreateDirectory($cache) | Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $sourceStage "msys2")) | Out-Null
  foreach ($source in $sources) {
    if ($source.sha256 -cnotmatch "^[a-f0-9]{64}$") { throw "Invalid SDK source hash" }
    $binary = @($binaryPackages | Where-Object { $_.package -ceq $source.package })
    if ($binary.Count -ne 1 -or $binary[0].sha256 -ne $source.binarySha256) { throw "Source package does not match locked binary: $($source.package)" }
    $download = Join-Path $cache ([IO.Path]::GetFileName($source.url))
    $null = Get-VerifiedFfmpegDownload -Uri $source.url -Sha256 $source.sha256 -Destination $download
    Copy-Item -LiteralPath $download -Destination (Join-Path $sourceStage "msys2")
  }
}
Copy-SdkFile (Join-Path $RepositoryRoot "third_party/dependencies.lock.json") "recipe/dependencies.lock.json"
Copy-SdkFile (Join-Path $RepositoryRoot "third_party/native-sdk") "recipe/native-sdk"
Copy-SdkFile (Join-Path $RepositoryRoot "third_party/cmake") "recipe/cmake"
Copy-SdkFile (Join-Path $RepositoryRoot "third_party/ffmpeg") "recipe/ffmpeg"
Copy-SdkFile (Join-Path $PSScriptRoot "ffmpeg_dependencies.ps1") "recipe/ffmpeg_dependencies.ps1"
Copy-SdkFile $PSCommandPath "recipe/package_native_sdk.ps1"
Copy-Item -LiteralPath (Join-Path $stage "recipe") -Destination $sourceStage -Recurse
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceName = "shenview-$Component-sources-windows-x64.zip"
$sourceArchive = Join-Path $OutputDirectory $sourceName
if (Test-Path -LiteralPath $sourceArchive) { Remove-Item -LiteralPath $sourceArchive -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($sourceStage,$sourceArchive,[IO.Compression.CompressionLevel]::Optimal,$false)
$sourceSha = (Get-FileHash -LiteralPath $sourceArchive -Algorithm SHA256).Hash.ToLowerInvariant()
"$sourceSha  $sourceName" | Set-Content -LiteralPath (Join-Path $OutputDirectory "$Component-sources-SHA256SUMS.txt") -Encoding ASCII
$files = @(Get-NativeSdkFiles $stage | ForEach-Object {
  @{name=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $stage $_) -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$sourceCommit = & git -C $RepositoryRoot rev-parse HEAD
if ($LASTEXITCODE) { throw "Cannot record SDK source commit" }
@{schema=1;component=$Component;version=$lock.version;platform=$lock.platform;recipeSha256=$lock.recipeSha256;
  sourceCommit=$sourceCommit;sourceAsset=@{name=$sourceName;sha256=$sourceSha};files=$files} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stage "sdk-manifest.json") -Encoding UTF8
Assert-NativeSdk $stage $Component $lock
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = Join-Path $OutputDirectory $lock.components.$Component.asset
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($stage,$archive,[IO.Compression.CompressionLevel]::Optimal,$false)
$sha = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$sha  $([IO.Path]::GetFileName($archive))" | Set-Content -LiteralPath (Join-Path $OutputDirectory "$Component-SHA256SUMS.txt") -Encoding ASCII
Write-Host "SDK archive: $archive"
Write-Host "SDK SHA256: $sha"
