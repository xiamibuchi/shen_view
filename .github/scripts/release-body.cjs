const fs = require('node:fs');
const path = require('node:path');

const start = '<!-- shenview-release:start -->';
const end = '<!-- shenview-release:end -->';

function releaseNotes(version) {
  const directory = path.join(__dirname, '../../docs/release/notes');
  return {
    zh: fs.readFileSync(path.join(directory, version + '.zh-CN.md'), 'utf8').trim(),
    en: fs.readFileSync(path.join(directory, version + '.en.md'), 'utf8').trim(),
  };
}

function draftBody(previous, manifest, delivery, pr, notes = releaseNotes(manifest.version)) {
  const base = 'https://github.com/xiamibuchi/shen_view';
  const download = base + '/releases/download/v' + manifest.version + '/';
  const link = name => download + name;
  const notices = 'ShenView-' + manifest.windowsVersion + '-notices.zip';
  const body = [start,
    'Windows x64 · 便携预览版 · 未签名 · 构建 ' + manifest.windowsVersion, '',
    '## 下载', '',
    '| 文件 | 用途 |', '| --- | --- |',
    '| [Windows x64 便携版 ZIP](' + link(manifest.package) + ') | 普通用户下载，完整解压后运行 |',
    '| [ZIP 的 SHA256 校验文件](' + link(manifest.package + '.sha256') + ') | 核对下载是否完整 |', '',
    '最低系统：Windows 10 2004（19041），支持 Windows 11。此版本不提供安装器或 MSIX。', '',
    notes.zh, '',
    '## 使用说明与已知限制', '',
    '- 完整解压 ZIP，再以普通权限运行 `ShenView.exe`；不要直接在压缩包内运行。',
    '- 更新时解压到新目录，再迁移旧目录中的 `user-data`。备份后删除该目录可清除便携版用户数据。',
    '- 本版未签名，Windows 可能显示 SmartScreen 提示。请核对下载来源与 SHA256；校验值不能替代发布者签名，请勿关闭系统安全防护。',
    '- 复杂 SVG 需要 Microsoft Edge WebView2 Runtime。',
    '- HDR 为实验功能，物理 HDR 屏幕、高光、跨屏及恢复尚未完成验收；SDR 回退结果不替代实屏兼容结论。', '',
    '## 源码与许可', '',
    '[本版本源码](' + delivery.source.url + ') · [源码 ZIP](' + delivery.source.archiveUrl + ') · ' +
      '[许可、重建与替换说明](' + delivery.source.instructionsUrl + ')', '',
    '[第三方源码索引 SOURCES.json](' + link('SOURCES.json') + ') · ' +
      '[许可快照](' + link(notices) + ') · [索引与许可校验](' + link('SOURCES-SHA256SUMS.txt') + ')', '',
    '普通用户只需下载应用 ZIP。ShenView 使用 Apache-2.0；第三方组件保留各自许可。', '',
    '<details>', '<summary>第三方对应源码与构建信息</summary>', '',
    ...delivery.assets.filter(asset => asset.location === 'remote').map(asset => '- [' + asset.name + '](' + asset.url + ')'), '',
    'SOURCES.json 记录固定源码链接、SHA256、大小及对应二进制哈希；SOURCES-SHA256SUMS.txt 校验索引和许可快照。', '',
    '- Source commit: `' + manifest.sourceCommit + '`',
    '- Release PR: [#' + pr.number + '](' + base + '/pull/' + pr.number + ')',
    '- [构建清单 release.json](' + link('release.json') + ')', '',
    '</details>', '',
    '<details>', '<summary>English</summary>', '',
    '[Download Windows x64 portable ZIP](' + link(manifest.package) + ') · ' +
      '[SHA256 checksum](' + link(manifest.package + '.sha256') + ')', '',
    notes.en, '',
    'Requires Windows 10 version 2004 (19041) or later, x64. Extract the entire ZIP and run ShenView.exe as a standard user. No installer or MSIX is included.', '',
    'For updates, extract into a new directory and migrate user-data. Back up user-data before deleting it to reset portable settings and cache.', '',
    'This preview is unsigned and may trigger SmartScreen warnings. Verify the source and checksum; checksums do not replace publisher signing. Do not disable Windows security protections. Complex SVG requires Microsoft Edge WebView2 Runtime.', '',
    'HDR is experimental. Physical HDR displays, highlights, cross-screen transitions and recovery remain unverified. SDR fallback tests do not establish physical-HDR compatibility.', '',
    'Source links, third-party licenses and rebuilding instructions are available above. Ordinary users only need the application ZIP.', '',
    '</details>', end].join('\n');

  previous = previous || '';
  const from = previous.indexOf(start);
  const to = previous.indexOf(end);
  if ((from < 0) !== (to < 0) || (from >= 0 && to < from)) throw new Error('Malformed release section');
  if (from >= 0) return previous.slice(0, from) + body + previous.slice(to + end.length);

  const sourceStart = '<!-- shenview-source-links:start -->';
  const sourceEnd = '<!-- shenview-source-links:end -->';
  const sourceFrom = previous.indexOf(sourceStart);
  const sourceTo = previous.indexOf(sourceEnd);
  if ((sourceFrom < 0) !== (sourceTo < 0) || (sourceFrom >= 0 && sourceTo < sourceFrom)) throw new Error('Malformed source-links section');
  if (sourceFrom >= 0) previous = previous.slice(0, sourceFrom) + previous.slice(sourceTo + sourceEnd.length);
  // Strip only known generated lines when migrating drafts; retain maintainer additions.
  const legacy = /^(Windows x64 portable preview \(unsigned\).*|Source commit: .*|Release PR: #\d+|Download: https:\/\/github\.com\/xiamibuchi\/shen_view\/releases\/tag\/v.*|Unsigned portable ZIP: .*|Windows may show SmartScreen warnings\..*|Do not disable Windows security protections\..*|Before publishing:.*|- (Verify the final portable package|Verify linked sources|Verify all source assets|Confirm unsigned-package|Complete minimum-Windows).*|Extract the entire ZIP\..*|This draft (is not evidence|does not certify).*|Source delivery: download every source asset.*|See SOURCES\.md for .*|完整解压后以普通权限运行。.*|HDR is experimental;.*|HDR 为实验功能，实屏高光、跨屏与恢复尚未验收。.*|公开前仍须完成最终包复验、附件与源码链接核对及中英文说明审阅。)$/;
  const extra = previous.split(/\r?\n/).filter(line => !legacy.test(line)).join('\n').trim();
  return body + (extra ? '\n\n' + extra : '');
}

module.exports = { draftBody };
