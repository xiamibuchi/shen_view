$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ViewerRoot = Join-Path $RepositoryRoot 'apps/viewer'
$NativeBuildRoot = Join-Path $RepositoryRoot 'build'
$ArtifactRoot = Join-Path $RepositoryRoot 'artifacts'
. (Join-Path $PSScriptRoot 'toolchain.ps1')
