function Get-ReleaseSourceTextHash {
  param([string]$Path)
  $text = [IO.File]::ReadAllText($Path).Replace([string][char]13 + [char]10, [string][char]10)
  $hash = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','').ToLowerInvariant() }
  finally { $hash.Dispose() }
}

function Get-ReleaseSourceAssets {
  param($SourceLock, $Dependencies, $SdkLock)
  $ids = @('imagemagick-windows', '7zip', 'hdr-sdk', 'ffmpeg-sdk')
  if ($SourceLock.schema -ne 2 -or $SourceLock.assets.Count -ne $ids.Count) { throw 'Invalid release source lock' }
  foreach ($id in $ids) {
    $asset = @($SourceLock.assets | Where-Object { $_.id -ceq $id })
    if ($asset.Count -ne 1) { throw "Missing or duplicate source: $id" }
    $asset = $asset[0]
    $inputObject = if ($id.EndsWith('-sdk')) { $SdkLock } else { $Dependencies }
    foreach ($segment in $asset.input.Split('.')) {
      if (-not $inputObject.PSObject.Properties[$segment]) { throw "Unknown binary input: $($asset.input)" }
      $inputObject = $inputObject.$segment
    }
    if ($inputObject -ne $asset.binarySha256) { throw "Source lock is stale for binary: $id" }
    if ($id -eq '7zip' -and $Dependencies.sources.viewer_7zip.sha256 -ne $asset.sha256) { throw '7-Zip helper headers and engine source differ' }
    $tag = if ($id.EndsWith('-sdk')) { 'native-sdk-v' + [regex]::Escape($SdkLock.version) } else { 'third-party-sources-v[1-9][0-9]*' }
    if ($asset.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $asset.bytes -le 0 -or
        $asset.url -cnotmatch ('^https://github.com/xiamibuchi/shen_view/releases/download/' + $tag + '/[A-Za-z0-9_.-]+$')) {
      throw "Invalid source URL or hash: $id"
    }
    $asset
  }
}

function Get-ReleaseSourceFile {
  param($Asset, [string]$CacheDirectory)
  $name = [IO.Path]::GetFileName($Asset.url)
  $destination = Join-Path $CacheDirectory $name
  if ((Test-Path -LiteralPath $destination -PathType Leaf) -and
      (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $Asset.sha256) { return $destination }
  $temporary = $destination + '-' + [guid]::NewGuid().ToString('N') + '.partial'
  $chunk = $temporary + '.chunk'
  try {
    # The complete ImageMagick Windows sources are large; keep them out of PR builds.
    if ($Asset.PSObject.Properties['bytes']) {
      $output = [IO.File]::Open($temporary,[IO.FileMode]::CreateNew)
      try {
        for ([long]$offset = 0; $offset -lt $Asset.bytes; $offset += 8MB) {
          $end = [Math]::Min($offset + 8MB - 1, $Asset.bytes - 1)
          & curl.exe --fail --location --retry 2 --connect-timeout 30 --max-time 120 --silent --show-error --range "$offset-$end" --output $chunk $Asset.url
          if ($LASTEXITCODE -ne 0 -or (Get-Item -LiteralPath $chunk).Length -ne $end - $offset + 1) { throw "Source range download failed: $($Asset.id)" }
          $inputFile = [IO.File]::OpenRead($chunk)
          try { $inputFile.CopyTo($output) } finally { $inputFile.Dispose() }
        }
      } finally { $output.Dispose() }
    } else {
      & curl.exe --fail --location --retry 2 --connect-timeout 30 --max-time 120 --silent --show-error --output $temporary $Asset.url
      if ($LASTEXITCODE -ne 0) { throw "Source download failed: $($Asset.id)" }
    }
    if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $Asset.sha256) { throw "Source SHA256 mismatch: $name" }
    Move-Item -LiteralPath $temporary -Destination $destination -Force
    return $destination
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    if (Test-Path -LiteralPath $chunk -PathType Leaf) { Remove-Item -LiteralPath $chunk -Force }
  }
}

function Assert-ReleaseSourceInput {
  param($Manifest, [string]$Commit, [bool]$Dirty, [string]$PackagePath)
  if ($Dirty -or $Manifest.sourceDirty -ne $false -or $Manifest.sourceCommit -cne $Commit -or $Manifest.installerType -cne 'portable') {
    throw 'Source delivery requires a clean portable package of the current commit'
  }
  if ($Manifest.windowsVersion -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' -or
      $Manifest.package -cne "ShenView-$($Manifest.windowsVersion)-windows-x64-portable.zip" -or
      [IO.Path]::GetFileName($PackagePath) -cne $Manifest.package) { throw 'Invalid portable package name' }
}
