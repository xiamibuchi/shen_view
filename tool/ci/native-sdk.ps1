[CmdletBinding()]
param(
  [ValidateSet("Plan","Restore")][string]$Action = "Restore",
  [string]$BaseSha = "",
  [string]$CandidateDirectory = ""
)
. (Join-Path $PSScriptRoot "../paths.ps1")
. (Join-Path $PSScriptRoot "../build/native_cache.ps1")
$ErrorActionPreference = "Stop"
$lock = Get-NativeSdkLock
if ($lock.recipeSha256 -cne (Get-NativeSdkRecipeKey)) { throw "SDK recipe differs from lock; update recipeSha256 and SDK version" }
if ($Action -eq "Plan") {
  $base = $null
  if ($BaseSha) {
    if ($BaseSha -notmatch "^[a-fA-F0-9]{40}$") { throw "Invalid SDK plan base commit" }
    $path = "third_party/native-sdk.lock.json"
    $exists = & git -C $RepositoryRoot ls-tree --name-only $BaseSha -- $path
    if ($LASTEXITCODE) { throw "Cannot inspect SDK base lock" }
    if ($exists) {
      $base = (& git -C $RepositoryRoot show "$($BaseSha):$path") -join "`n" | ConvertFrom-Json
      if ($LASTEXITCODE) { throw "Cannot read SDK base lock" }
    }
  }
  $build = Get-NativeSdkBuildPlan $lock $base
  if ($env:GITHUB_OUTPUT) { "build=$($build.ToString().ToLowerInvariant())" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding UTF8 }
  Write-Host "SDK $($lock.version): source build required = $build"
  return
}
if ($CandidateDirectory) {
  $candidate = Join-Path $NativeBuildRoot ("native-sdk/candidate-" + $lock.recipeSha256)
  [IO.Directory]::CreateDirectory($candidate) | Out-Null
  foreach ($component in @("hdr","ffmpeg")) {
    $root = Join-Path $candidate $component
    Remove-NativeSdkBuildDirectory $root $candidate
    Expand-NativeSdkArchive (Join-Path $CandidateDirectory $lock.components.$component.asset) $root
    Assert-NativeSdk $root $component $lock
  }
  $env:SHENVIEW_NATIVE_SDK_ROOT = $candidate
  if ($env:GITHUB_ENV) { "SHENVIEW_NATIVE_SDK_ROOT=$candidate" | Add-Content -LiteralPath $env:GITHUB_ENV -Encoding UTF8 }
}
foreach ($component in @("hdr","ffmpeg")) {
  $root = Resolve-NativeSdkComponent $component "Sdk"
  Write-Host "Verified $component SDK: $root"
}
if ($env:GITHUB_ENV) { "SHENVIEW_NATIVE_BUILD_MODE=Sdk" | Add-Content -LiteralPath $env:GITHUB_ENV -Encoding UTF8 }
