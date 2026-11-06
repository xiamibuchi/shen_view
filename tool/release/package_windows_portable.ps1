[CmdletBinding()]
param(
  [string]$Flutter = 'flutter',
  [string]$PayloadDirectory = '',
  [string]$RuntimeDirectory = '',
  [switch]$SkipBuild,
  [switch]$SkipCodecs
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'package_windows.ps1') -PortableOnly -Unsigned @PSBoundParameters
