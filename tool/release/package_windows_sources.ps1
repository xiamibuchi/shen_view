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
$cache = Join-Path $NativeBuildRoot 'release-sources/downloads'
[IO.Directory]::CreateDirectory($cache) | Out-Null
$stage = Join-Path $NativeBuildRoot ('release-sources/inspect-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage) | Out-Null
$records = @()
foreach ($asset in $assets) {
  $file = Get-ReleaseSourceFile $asset $cache
  & $SevenZip t $file -bso0 -bsp0
  if ($LASTEXITCODE) { throw "Source archive is damaged: $file" }
  $destination = Join-Path $OutputDirectory ([IO.Path]::GetFileName($file))
  Copy-Item -LiteralPath $file -Destination $destination -Force
  $records += [ordered]@{id=$asset.id; name=[IO.Path]::GetFileName($file); url=$asset.url;
    sha256=$asset.sha256; bytes=(Get-Item -LiteralPath $file).Length; binarySha256=$asset.binarySha256}
}

# A Git snapshot excludes build products and private untracked files, but includes our patches and helpers.
$sourceName = "ShenView-$($manifest.windowsVersion)-source.zip"
$sourcePath = Join-Path $OutputDirectory $sourceName
& git -C $RepositoryRoot archive --format=zip "--output=$sourcePath" $commit
if ($LASTEXITCODE) { throw 'Cannot archive ShenView source' }
$records += [ordered]@{id='shenview';name=$sourceName;url="https://github.com/xiamibuchi/shen_view/tree/$commit";
  sha256=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $sourcePath).Length}

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
$records += [ordered]@{id='notices';name=$noticeName;sha256=(Get-FileHash -LiteralPath $noticePath -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $noticePath).Length}
$delivery = [ordered]@{schema=1;sourceCommit=$commit;sourceDirty=$false;package=$manifest.package;packageSha256=$packageHash;
  sourceLockSha256=(Get-ReleaseSourceTextHash $lockPath);assets=$records;notices=$noticeRecords}
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SOURCES.json'),($delivery | ConvertTo-Json -Depth 8),$utf8)
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'docs/release/source-delivery.md') -Destination (Join-Path $OutputDirectory 'SOURCES.md') -Force
$checksums = @($records | ForEach-Object { "$($_.sha256)  $($_.name)" })
foreach ($name in @('SOURCES.json','SOURCES.md')) {
  $checksums += (Get-FileHash -LiteralPath (Join-Path $OutputDirectory $name) -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $name
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SOURCES-SHA256SUMS.txt'),($checksums -join "`n") + "`n",$utf8)
Write-Host "Source delivery ready: $OutputDirectory"
