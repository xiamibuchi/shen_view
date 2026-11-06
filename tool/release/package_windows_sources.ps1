[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ReleaseDirectory,
  [string]$OutputDirectory = '',
  [string]$SevenZip = '7z.exe'
)

. (Join-Path $PSScriptRoot '../paths.ps1')
. (Join-Path $PSScriptRoot 'windows_source_helpers.ps1')
$ErrorActionPreference = 'Stop'
$release = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$manifest = Get-Content -LiteralPath (Join-Path $release 'release.json') -Raw | ConvertFrom-Json
$commit = & git -C $RepositoryRoot rev-parse HEAD
if ($LASTEXITCODE) { throw 'Cannot read source commit' }
$status = @(& git -C $RepositoryRoot status --porcelain --untracked-files=normal)
if ($LASTEXITCODE) { throw 'Cannot read source status' }
$package = Join-Path $release $manifest.package
Assert-ReleaseSourceInput $manifest $commit ($status.Count -ne 0) $package
$packageHash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
if ((Get-Content -LiteralPath (Join-Path $release 'SHA256SUMS.txt') -Raw).Trim() -cne "$packageHash  $($manifest.package)") {
  throw 'Portable package checksum mismatch'
}
$dependencies = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'third_party/dependencies.lock.json') -Raw | ConvertFrom-Json
$sdk = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'third_party/native-sdk.lock.json') -Raw | ConvertFrom-Json
$lockPath = Join-Path $RepositoryRoot 'third_party/release-sources.lock.json'
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$assets = @(Get-ReleaseSourceAssets $lock $dependencies $sdk)
$SevenZip = Resolve-ShenViewSevenZip $SevenZip
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $release 'sources' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count) { throw 'Use an empty source output directory' }
$cache = Join-Path $NativeBuildRoot 'release-sources/downloads'
[IO.Directory]::CreateDirectory($cache) | Out-Null
$stage = Join-Path $NativeBuildRoot ('release-sources/inspect-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage) | Out-Null
$records = @()
foreach ($asset in $assets) {
  $file = Get-ReleaseSourceFile $asset $cache
  & $SevenZip t $file -bso0 -bsp0
  if ($LASTEXITCODE) { throw "Source archive is damaged: $file" }
  $records += [ordered]@{id=$asset.id; location='remote'; name=[IO.Path]::GetFileName($file); url=$asset.url;
    sha256=$asset.sha256; bytes=(Get-Item -LiteralPath $file).Length; binarySha256=$asset.binarySha256}
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($package)
$notices = Join-Path $stage 'notices'
[IO.Directory]::CreateDirectory($notices) | Out-Null
$noticeRecords = @()
try {
  foreach ($entry in $zip.Entries) {
    $name = $entry.FullName.Replace('\','/')
    if ($name.StartsWith('/') -or $name.Contains(':') -or @($name.Split('/') | Where-Object { $_ -eq '..' }).Count) { throw 'Unsafe package entry' }
    if (-not $name.EndsWith('/') -and ($name -eq 'LICENSE' -or $name -eq 'data/flutter_assets/NOTICES.Z' -or $name.StartsWith('codecs/licenses/'))) {
      $target = Join-Path $notices $name
      [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
      [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
      $noticeRecords += @{name=$name;sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
  }
} finally { $zip.Dispose() }
foreach ($required in @('LICENSE','data/flutter_assets/NOTICES.Z','codecs/licenses/imagemagick/NOTICE.txt','codecs/licenses/7zip/ENGINE.txt','codecs/licenses/hdr/LibRaw-LICENSE.CDDL','codecs/licenses/ffmpeg/SOURCES.txt')) {
  if ($noticeRecords.name -cnotcontains $required) { throw "Missing runtime notice: $required" }
}
$noticeName = "ShenView-$($manifest.windowsVersion)-notices.zip"
$noticePath = Join-Path $OutputDirectory $noticeName
if (Test-Path -LiteralPath $noticePath) { Remove-Item -LiteralPath $noticePath -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($notices,$noticePath,[IO.Compression.CompressionLevel]::Optimal,$false)
$records += [ordered]@{id='notices';location='local';name=$noticeName;sha256=(Get-FileHash -LiteralPath $noticePath -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $noticePath).Length}
$source = [ordered]@{commit=$commit;url="https://github.com/xiamibuchi/shen_view/tree/$commit";
  archiveUrl="https://github.com/xiamibuchi/shen_view/archive/$commit.zip";
  instructionsUrl="https://github.com/xiamibuchi/shen_view/blob/$commit/docs/release/source-delivery.md"}
$delivery = [ordered]@{schema=2;sourceCommit=$commit;sourceDirty=$false;package=$manifest.package;packageSha256=$packageHash;
  sourceLockSha256=(Get-ReleaseSourceTextHash $lockPath);source=$source;assets=$records;notices=$noticeRecords}
if ((& git -C $RepositoryRoot rev-parse HEAD) -cne $commit -or @(& git -C $RepositoryRoot status --porcelain --untracked-files=normal).Count) {
  throw 'Source changed while collecting release materials'
}
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SOURCES.json'),($delivery | ConvertTo-Json -Depth 8),$utf8)
$checksums = @($records | Where-Object location -eq 'local' | ForEach-Object { "$($_.sha256)  $($_.name)" })
foreach ($name in @('SOURCES.json')) {
  $checksums += (Get-FileHash -LiteralPath (Join-Path $OutputDirectory $name) -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $name
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SOURCES-SHA256SUMS.txt'),($checksums -join "`n") + "`n",$utf8)
Write-Host "Source delivery ready: $OutputDirectory"
