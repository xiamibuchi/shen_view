param([string]$Helper = '../../build/avif-codecs/bin/viewer_avif_animation.exe')
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Helper)) {
  $Helper = '../../build/hdr-codecs/bin/viewer_avif_animation.exe'
}
$fixtures = @(
  @('format_animated.avif', '-1', '8', '13'),
  @('format_animated_finite.avif', '1', '8', '13'),
  @('format_animated_pq.avif', '-1', '10', '16'),
  @('format_animated_hlg.avif', '-1', '12', '18'),
  @('format_animated_icc.avif', '-1', '8', '13', 'icc'),
  @('format_single_frame.avif', '-1', '8', '13', 'single'),
  @('format_progressive.avif', '-1', '8', '13', 'progressive')
)
foreach ($fixture in $fixtures) {
  $output = Join-Path 'testdata/formats' $fixture[0]
  $arguments = $fixture[1..($fixture.Count - 1)]
  & $Helper fixture $output @arguments
  if ($LASTEXITCODE -ne 0) { throw "AVIF 样本生成失败：$output" }
}
