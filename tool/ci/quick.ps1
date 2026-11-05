[CmdletBinding()]
param([string]$Flutter = 'flutter')
. (Join-Path $PSScriptRoot '../paths.ps1')
. (Join-Path $PSScriptRoot 'prepare.ps1')
$ErrorActionPreference = 'Stop'
$Flutter = Resolve-ShenViewFlutterTool $Flutter
Invoke-CiPreparation $Flutter
& (Join-Path $PSScriptRoot '../check/check.ps1') -Flutter $Flutter -Mode Static
if ($LASTEXITCODE) { throw 'Static checks failed' }
