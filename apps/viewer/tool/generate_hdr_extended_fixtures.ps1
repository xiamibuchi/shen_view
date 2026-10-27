param(
  [string]$Dart = 'dart',
  [string]$Ffmpeg = 'ffmpeg',
  [string]$DoviTool = '../../build/hdr-codecs/dovi-tool/dovi_tool.exe'
)
. (Join-Path $PSScriptRoot '../../../tool/paths.ps1')
$ErrorActionPreference = 'Stop'
$Dart = Resolve-ShenViewFlutterTool $Dart
& $Dart run tool/generate_hdr_phase2_fixtures.dart
if ($LASTEXITCODE -ne 0) { throw 'PQ/HLG 生成失败。' }
& ../../build/hdr-codecs/bin/viewer_gainmap.exe fixture testdata/formats/hdr_gain_map.jpg
if ($LASTEXITCODE -ne 0) { throw 'Gain Map 生成失败。' }
# Explicitly convert RGB to BT.2020 non-constant-luminance YCbCr before AV1
# encoding. The old ImageMagick 9/16/0 path produced 12-bit GBR with a limited
# range tag; ImageMagick's own decoder hid the disagreement with other readers.
# Main-profile 10-bit 4:2:0 with consistent full-range tags is more portable.
foreach ($chart in @(@{ Name = 'pq'; Transfer = 'smpte2084' }, @{ Name = 'hlg'; Transfer = 'arib-std-b67' })) {
  $stem = 'hdr_' + $chart.Name
  $transfer = $chart.Transfer
  $destination = [IO.Path]::GetFullPath("testdata/formats/$stem.avif")
  $temporary = [IO.Path]::GetFullPath("../../build/hdr-codecs/$stem.$([guid]::NewGuid()).avif")
  try {
    & $Ffmpeg -hide_banner -loglevel error -y -i "testdata/formats/$stem.png" `
      -vf "zscale=pin=bt2020:tin=${transfer}:min=gbr:rin=full:p=bt2020:t=${transfer}:m=bt2020nc:r=full,format=yuv420p10le" `
      -frames:v 1 -c:v libaom-av1 -still-picture 1 -cpu-used 6 -crf 0 `
      -color_range pc -color_primaries bt2020 -color_trc $transfer -colorspace bt2020nc $temporary
    if ($LASTEXITCODE -ne 0) { throw "$stem AVIF 生成失败。" }
    # A previewer can memory-map the existing file. Avoid truncating it; publish
    # a completed file atomically, and do not replace identical fixtures.
    if ([IO.File]::Exists($destination)) {
      if ((Get-FileHash -LiteralPath $temporary).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
        [IO.File]::Replace($temporary, $destination, $null)
      }
    } else {
      [IO.File]::Move($temporary, $destination)
    }
  } finally {
    if ([IO.File]::Exists($temporary)) { Remove-Item -LiteralPath $temporary }
  }
}
& $Ffmpeg -hide_banner -loglevel error -y -i testdata/formats/hdr_pq.png `
  -vf 'zscale=pin=bt2020:tin=smpte2084:min=gbr:rin=full:p=bt2020:t=smpte2084:m=bt2020nc:r=limited,format=yuv420p10le' `
  -frames:v 1 -c:v libx265 -preset ultrafast -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc `
  -x265-params 'pools=2:frame-threads=1:repeat-headers=1:hdr10=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020' `
  -f hevc ../../build/hdr-codecs/base.hevc
if ($LASTEXITCODE -ne 0) { throw 'HEVC 基础层生成失败。' }
& $DoviTool generate --json tool/hdr_dovi_fixture.json --profile 8.1 --rpu-out ../../build/hdr-codecs/fixture-rpu.bin
if ($LASTEXITCODE -ne 0) { throw 'Dolby RPU 生成失败。' }
& $DoviTool inject-rpu -i ../../build/hdr-codecs/base.hevc -r ../../build/hdr-codecs/fixture-rpu.bin -o testdata/formats/hdr_dovi_p81.hevc
if ($LASTEXITCODE -ne 0) { throw 'Dolby Vision 测试静帧生成失败。' }
