# Flutter can launch Windows PowerShell with PowerShell 7's module search path.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
  Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1')
  Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Management/Microsoft.PowerShell.Management.psd1')
}
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ViewerRoot = Join-Path $RepositoryRoot 'apps/viewer'
$NativeBuildRoot = Join-Path $RepositoryRoot 'build'
$ArtifactRoot = Join-Path $RepositoryRoot 'artifacts'
. (Join-Path $PSScriptRoot 'toolchain.ps1')
