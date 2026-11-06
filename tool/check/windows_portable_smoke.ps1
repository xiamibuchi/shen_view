[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseDirectory)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$directory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$manifest = Get-Content -LiteralPath (Join-Path $directory 'release.json') -Raw | ConvertFrom-Json
if ($manifest.installerType -ne 'portable') { throw '需要独立便携包的 release.json。' }
if ([IO.Path]::GetFileName($manifest.package) -ne $manifest.package) { throw '包名不能包含路径。' }
$zip = Join-Path $directory $manifest.package
$expected = (Get-Content -LiteralPath (Join-Path $directory ($manifest.package + '.sha256')) -Raw).Trim()
$actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $manifest.package
if ($expected -cne $actual) { throw '便携包 SHA256 不匹配。' }
$work = Join-Path $NativeBuildRoot ('packaging/portable-smoke-' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip -DestinationPath $work
foreach ($name in @('ShenView.exe', 'LICENSE', 'codecs/licenses/imagemagick/NOTICE.txt',
    'codecs/licenses/7zip/LGPL-2.1.txt', 'codecs/licenses/hdr/LibRaw-LICENSE.CDDL',
    'codecs/licenses/ffmpeg/COPYING.LGPLv2.1', 'data/flutter_assets/NOTICES.Z', 'user-data')) {
  if (-not (Test-Path -LiteralPath (Join-Path $work $name))) { throw "便携包缺少：$name" }
}
if ((Get-Content -LiteralPath (Join-Path $work 'installation-mode') -Raw) -cne 'portable') { throw '便携模式标记不正确。' }
foreach ($name in @('settings.json', 'cache', 'install.ini', 'uninstall.exe', 'maintain.exe')) {
  if (Test-Path -LiteralPath (Join-Path $work $name)) { throw "便携包混入运行或安装状态：$name" }
}
if (@(Get-ChildItem -LiteralPath (Join-Path $work 'user-data') -Force).Count) { throw '便携包混入用户数据。' }
$app = (Get-Item -LiteralPath (Join-Path $work 'ShenView.exe')).VersionInfo
$version = @($app.FileMajorPart, $app.FileMinorPart, $app.FileBuildPart, $app.FilePrivatePart) -join '.'
if ($version -ne $manifest.windowsVersion) { throw 'EXE 版本与便携包清单不一致。' }
# Git checkouts may use LF or CRLF; compare the license text across platforms.
$packagedLicense = [IO.File]::ReadAllText((Join-Path $work 'LICENSE')).Replace([string][char]13 + [char]10, [string][char]10)
$sourceLicense = [IO.File]::ReadAllText((Join-Path $RepositoryRoot 'LICENSE')).Replace([string][char]13 + [char]10, [string][char]10)
if ($packagedLicense -cne $sourceLicense) { throw '项目许可不一致。' }
$ffmpeg = Join-Path $work 'codecs/ffmpeg'
$runtime = Get-Content -LiteralPath (Join-Path $ffmpeg 'manifest.json') -Raw | ConvertFrom-Json
foreach ($file in $runtime.files) {
  if ((Get-FileHash -LiteralPath (Join-Path $ffmpeg $file.name)).Hash -ne $file.sha256) { throw "FFmpeg 组件哈希不一致：$($file.name)" }
}
& (Join-Path $PSScriptRoot 'windows_codec_layout.ps1') -InstallRoot $work -OutputDirectory (Join-Path $directory 'smoke-codecs')
@{passed = $true; unpacked = $work; package = $manifest.package} | ConvertTo-Json |
  Set-Content -LiteralPath (Join-Path $directory 'smoke-results.json') -Encoding utf8
Write-Host "PASS: $zip"
