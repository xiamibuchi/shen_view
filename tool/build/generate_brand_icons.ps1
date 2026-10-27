param(
  [string]$ImageMagick = 'magick'
)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
$magickPath = (Get-Command $ImageMagick -ErrorAction Stop).Source
$projectRoot = $RepositoryRoot

function Invoke-BrandMagick {
  param([string[]]$Arguments)
  & $magickPath @Arguments
  if ($LASTEXITCODE -ne 0) { throw "ImageMagick failed ($LASTEXITCODE)." }
}

Push-Location -LiteralPath $projectRoot
try {
  $pngDirectory = 'branding/png'
  New-Item -ItemType Directory -Force -Path $pngDirectory | Out-Null
  $sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256, 512, 1024)
  foreach ($size in $sizes) {
    $source = if ($size -le 40) {
      'branding/app-icon-small.svg'
    } else {
      'branding/app-icon.svg'
    }
    Invoke-BrandMagick @('-background', 'none', '-density', '384', $source,
      '-resize', "${size}x${size}", '-strip',
      "PNG32:$pngDirectory/shenview-$size.png")
  }

  foreach ($variant in @('mark-monochrome', 'mark-monochrome-light')) {
    Invoke-BrandMagick @('-background', 'none', '-density', '192',
      "branding/$variant.svg", '-resize', '512x512', '-strip',
      "PNG32:$pngDirectory/$variant.png")
  }

  # Keep each hand-selected small-size rendition in the ICO; do not let an
  # automatic ICO resizer derive tiny frames from the detailed large icon.
  $icoArguments = @()
  foreach ($size in @(16, 20, 24, 32, 40, 48, 64, 128, 256)) {
    $icoArguments += "$pngDirectory/shenview-$size.png"
  }
  $icoArguments += 'apps/viewer/windows/runner/resources/app_icon.ico'
  Invoke-BrandMagick $icoArguments

  # macOS app icons use an inset tile on a transparent square canvas.
  foreach ($size in @(16, 32, 64, 128, 256, 512, 1024)) {
    $source = if ($size -le 32) {
      'branding/app-icon-small.svg'
    } else {
      'branding/app-icon.svg'
    }
    $tileSize = [int][Math]::Round($size * 0.84)
    Invoke-BrandMagick @('-background', 'none', '-density', '384', $source,
      '-resize', "${tileSize}x${tileSize}", '-gravity', 'center',
      '-extent', "${size}x${size}", '-strip',
      "PNG32:apps/viewer/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png")
  }
  Write-Host 'ShenView PNG, Windows ICO and macOS AppIcon resources generated.'
} finally {
  Pop-Location
}
