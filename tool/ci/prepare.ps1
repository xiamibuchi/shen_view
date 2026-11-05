function Run([string]$Program, [string[]]$Arguments) {
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed: $Program $Arguments ($LASTEXITCODE)" }
}

function Invoke-CiPreparation([string]$Flutter) {
  $dartName = if ($env:OS -eq 'Windows_NT') { 'dart.bat' } else { 'dart' }
  $dart = Join-Path (Split-Path $Flutter) $dartName
  Push-Location $ViewerRoot
  try {
    Run $Flutter @('pub','get','--enforce-lockfile')
    Run $Flutter @('gen-l10n')
    Run $dart @('run','tool/generate_license_exclusions.dart')
    $base = if ($env:CI_BASE_SHA) { $env:CI_BASE_SHA } else { 'HEAD' }
    $changed = @(& git -C $RepositoryRoot diff --name-only --diff-filter=ACMR $base -- '*.dart')
    if ($LASTEXITCODE) { throw 'Cannot list changed Dart files' }
    $files = @($changed | ForEach-Object { Join-Path $RepositoryRoot $_ } | Where-Object { Test-Path -LiteralPath $_ })
    if ($files.Count) { Run $dart (@('format','--output=none','--set-exit-if-changed') + $files) }
    Run git @('diff','--exit-code','--','lib/l10n','lib/src/application/license_exclusions.g.dart','pubspec.lock')
  } finally { Pop-Location }
}
