$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../paths.ps1")
. (Join-Path $PSScriptRoot "../build/native_sdk.ps1")
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("shenview-sdk-test-" + [guid]::NewGuid().ToString("N"))
$savedRepository = $RepositoryRoot
$savedBuild = $NativeBuildRoot
$savedMode = $env:SHENVIEW_NATIVE_BUILD_MODE
$savedSdk = $env:SHENVIEW_NATIVE_SDK_ROOT
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "SDK assertion failed: $Message" } }
function Reject([scriptblock]$Action) {
  $failed = $false
  try { & $Action } catch { $failed = $true }
  Assert $failed "invalid input was accepted"
}
try {
  [IO.Directory]::CreateDirectory((Join-Path $testRoot "repo/third_party/native-sdk")) | Out-Null
  $RepositoryRoot = Join-Path $testRoot "repo"
  $NativeBuildRoot = Join-Path $testRoot "build"
  $env:SHENVIEW_NATIVE_BUILD_MODE = ""
  $env:SHENVIEW_NATIVE_SDK_ROOT = ""
  [IO.File]::WriteAllText((Join-Path $RepositoryRoot "third_party/dependencies.lock.json"),
    '{"sources":{"lib":{"url":"https://example.invalid/lib.tar","sha256":"fixed"}}}')
  [IO.File]::WriteAllText((Join-Path $RepositoryRoot "third_party/native-sdk/recipe.json"),
    '{"hdrSources":["lib"],"inputs":["recipe.txt"]}')
  $recipePath = Join-Path $RepositoryRoot "recipe.txt"
  [IO.File]::WriteAllText($recipePath,"build`r`nRelease`r`n")
  $recipe = Get-NativeSdkRecipeKey
  [IO.File]::WriteAllText($recipePath,"build`nRelease`n")
  Assert ($recipe -ceq (Get-NativeSdkRecipeKey)) "recipe differs across checkout line endings"
  [IO.File]::WriteAllText($recipePath,"changed`n")
  Assert ($recipe -cne (Get-NativeSdkRecipeKey)) "recipe change not detected"
  [IO.File]::WriteAllText($recipePath,"build`nRelease`n")
  $lock = [pscustomobject]@{schema=1;version="1.0.0";platform="windows-x64";recipeSha256=$recipe;components=@{
    hdr=@{asset="shenview-hdr-sdk-windows-x64.zip";sha256=$null}
    ffmpeg=@{asset="shenview-ffmpeg-sdk-windows-x64.zip";sha256=$null}}}
  $lockPath = Join-Path $RepositoryRoot "third_party/native-sdk.lock.json"
  $lock | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $lockPath -Encoding UTF8
  Assert (Get-NativeSdkBuildPlan $lock $null) "bootstrap SDK must be built"
  $base = [pscustomobject]@{version="1.0.0";recipeSha256=$recipe}
  Reject { Get-NativeSdkBuildPlan $lock $base }
  $base.version = "0.9.0"
  Reject { Get-NativeSdkBuildPlan $lock $base }
  $base.recipeSha256 = "old-recipe"
  Assert (Get-NativeSdkBuildPlan $lock $base) "new SDK recipe must be built"
  $lock.components.hdr.sha256 = "a" * 64
  Reject { Get-NativeSdkBuildPlan $lock $base }
  $lock.components.ffmpeg.sha256 = "b" * 64
  Assert (-not (Get-NativeSdkBuildPlan $lock $base)) "published SDK must skip dependency builds"
  $lock.components.hdr.sha256 = $null
  $lock.components.ffmpeg.sha256 = $null
  Assert ($null -eq (Resolve-NativeSdkComponent "hdr" "Source")) "explicit source mode"
  Reject { Resolve-NativeSdkComponent "hdr" "Sdk" }
  $sdk = Join-Path $testRoot "moved SDK/hdr"
  $required = @("include/avif/avif.h","include/libraw/libraw.h","include/lcms2.h","include/ultrahdr_api.h",
    "lib/avif_internal.lib","lib/aom.lib","lib/uhdr-static.lib","lib/viewer_lcms.lib","lib/viewer_raw_lib.lib",
    "lib/jpeg-static.lib","lib/cmake/ShenViewHdr/ShenViewHdrConfig.cmake","licenses/hdr/LibRaw-LICENSE.CDDL")
  foreach ($name in $required) {
    $file = Join-Path $sdk $name
    [IO.Directory]::CreateDirectory((Split-Path $file)) | Out-Null
    [IO.File]::WriteAllText($file,$name)
  }
  $manifest = @{schema=1;version=$lock.version;platform=$lock.platform;component="hdr";recipeSha256=$recipe;files=@(
    Get-NativeSdkFiles $sdk | ForEach-Object { @{name=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $sdk $_) -Algorithm SHA256).Hash} })}
  $manifestPath = Join-Path $sdk "sdk-manifest.json"
  $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
  Assert-NativeSdk $sdk "hdr" $lock
  $env:SHENVIEW_NATIVE_SDK_ROOT = Split-Path $sdk
  Assert ((Resolve-NativeSdkComponent "hdr" "Sdk") -eq $sdk) "relocated candidate rejected"
  $manifest.platform = "windows-arm64"
  $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
  Reject { Assert-NativeSdk $sdk "hdr" $lock }
  $manifest.platform = "windows-x64"
  $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
  $file = Join-Path $sdk $required[0]
  [IO.File]::WriteAllText($file,"corrupt")
  Reject { Assert-NativeSdk $sdk "hdr" $lock }
  [IO.File]::WriteAllText($file,$required[0])
  [IO.File]::WriteAllText((Join-Path $sdk "unexpected"),"extra")
  Reject { Assert-NativeSdk $sdk "hdr" $lock }
  Remove-Item -LiteralPath (Join-Path $sdk "unexpected")
  Remove-Item -LiteralPath $file
  Reject { Assert-NativeSdk $sdk "hdr" $lock }
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  foreach ($unsafe in @("../escape","/absolute","C:/absolute","duplicate")) {
    $zipPath = Join-Path $testRoot "unsafe.zip"
    $zip = [IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
    $null = $zip.CreateEntry($unsafe)
    if ($unsafe -eq "duplicate") { $null = $zip.CreateEntry("DUPLICATE") }
    $zip.Dispose()
    Reject { Expand-NativeSdkArchive $zipPath (Join-Path $testRoot "extract") }
    Assert (-not (Test-Path -LiteralPath (Join-Path $testRoot "extract"))) "unsafe archive extracted"
    Remove-Item -LiteralPath $zipPath
  }
  Reject { Remove-NativeSdkBuildDirectory $testRoot $testRoot }
  Write-Output "PASS: SDK recipe identity, line endings, explicit source mode, relocation, architecture, corruption, missing/extra files and unsafe archives"
} finally {
  $RepositoryRoot = $savedRepository
  $NativeBuildRoot = $savedBuild
  $env:SHENVIEW_NATIVE_BUILD_MODE = $savedMode
  $env:SHENVIEW_NATIVE_SDK_ROOT = $savedSdk
  $absolute = [IO.Path]::GetFullPath($testRoot)
  $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd("/","\") + [IO.Path]::DirectorySeparatorChar
  if (-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $absolute -Leaf) -notlike "shenview-sdk-test-*") { throw "Invalid SDK test cleanup path" }
  if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
