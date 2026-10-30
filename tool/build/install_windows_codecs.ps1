param([string]$SevenZip = '7z.exe')

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
$SevenZip = Resolve-ShenViewSevenZip $SevenZip
$lock = Get-Content (Join-Path $RepositoryRoot 'third_party/dependencies.lock.json') -Raw | ConvertFrom-Json
$root = Join-Path $NativeBuildRoot 'windows-codecs'
$downloads = Join-Path $root 'downloads'
[IO.Directory]::CreateDirectory($downloads) | Out-Null

function Get-Artifact($Artifact) {
  $file = Join-Path $downloads ([IO.Path]::GetFileName($Artifact.url))
  if (-not (Test-Path -LiteralPath $file)) {
    Invoke-WebRequest -UseBasicParsing -Uri $Artifact.url -OutFile $file
  }
  if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $Artifact.sha256) {
    throw "编解码器下载 SHA256 不符：$file"
  }
  return $file
}

$imageMagick = $lock.artifacts.imageMagickWindows
$sevenZipArtifact = $lock.artifacts.sevenZipWindows
$extractor = $lock.artifacts.innoextractWindows
$magickRoot = Join-Path $root "imagemagick-$($imageMagick.version)"
$archiveRoot = Join-Path $root "7zip-$($sevenZipArtifact.version)"
foreach ($entry in @(
  @{ Artifact = $imageMagick; Directory = $magickRoot; Binary = 'app/magick.exe' },
  @{ Artifact = $sevenZipArtifact; Directory = $archiveRoot; Binary = '7z.dll' }
)) {
  $marker = Join-Path $entry.Directory 'source.sha256'
  if ((Test-Path -LiteralPath (Join-Path $entry.Directory $entry.Binary)) -and
      (Test-Path -LiteralPath $marker) -and
      (Get-Content -LiteralPath $marker -Raw).Trim() -eq $entry.Artifact.sha256) { continue }
  $file = Get-Artifact $entry.Artifact
  [IO.Directory]::CreateDirectory($entry.Directory) | Out-Null
  if ($entry.Artifact -eq $imageMagick) {
    $extractorRoot = Join-Path $root "innoextract-$($extractor.version)"
    $extractorArchive = Get-Artifact $extractor
    Expand-Archive -LiteralPath $extractorArchive -DestinationPath $extractorRoot -Force
    & (Join-Path $extractorRoot 'innoextract.exe') --extract --silent --output-dir $entry.Directory $file
  } else {
    & $SevenZip x $file "-o$($entry.Directory)" -y -bso0 -bsp0
  }
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $entry.Directory $entry.Binary))) {
    throw "编解码器解包失败：$file"
  }
  [IO.File]::WriteAllText($marker, $entry.Artifact.sha256)
}
[pscustomobject]@{
  ImageMagickDirectory = Join-Path $magickRoot 'app'
  SevenZipDirectory = $archiveRoot
}
