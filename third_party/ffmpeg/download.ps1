function Get-VerifiedFfmpegDownload {
  [CmdletBinding()]
  param([string]$Uri, [string]$Sha256, [string]$Destination, [int]$RetryDelaySeconds = 2)
  if ((Test-Path -LiteralPath $Destination -PathType Leaf) -and
      (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -eq $Sha256) { return $Destination }
  $temporary = $Destination + '-' + [guid]::NewGuid().ToString('N') + '.partial'
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Write-Host "Downloading $Uri (attempt $attempt/3)"
      Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $temporary -TimeoutSec 90 -ErrorAction Stop
      if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $Sha256) { throw "SHA256 mismatch: $Uri" }
      Move-Item -LiteralPath $temporary -Destination $Destination -Force
      return $Destination
    } catch {
      if ($attempt -eq 3) { throw "Download failed after 3 attempts: $Uri. $($_.Exception.Message)" }
      Write-Warning "Download failed: $Uri. $($_.Exception.Message) Retrying."
      if ($RetryDelaySeconds) { Start-Sleep -Seconds ($RetryDelaySeconds * $attempt) }
    } finally {
      if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
  }
}
