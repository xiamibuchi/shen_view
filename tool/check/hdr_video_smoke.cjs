const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const helper = process.argv[2] || path.join(root, 'build/ffmpeg/windows-x64/runtime/viewer_hdr_video.exe');
const sample = Buffer.from(path.join(root, 'apps/viewer/testdata/formats/hdr_dovi_p81.hevc'));
console.log(JSON.stringify({ helper, vulkanDriver: process.env.VK_DRIVER_FILES,
  softwareVulkan: process.env.SHENVIEW_ALLOW_SOFTWARE_VULKAN }));
const child = spawn(helper, [], { stdio: ['pipe', 'pipe', 'pipe'] });
let output = Buffer.alloc(0);
let errors = '';
let complete = false;
const timer = setTimeout(() => {
  console.error('HDR native smoke timed out.');
  child.kill();
  process.exitCode = 1;
}, 40000);
child.stderr.on('data', bytes => {
  errors = (errors + bytes.toString()).slice(-32768);
});
child.stdin.on('error', error => {
  console.error(error.message);
  process.exitCode = 1;
});
child.on('error', error => {
  clearTimeout(timer);
  console.error(error.message);
  process.exitCode = 1;
});
child.stdout.on('data', bytes => {
  output = Buffer.concat([output, bytes]);
  if (output.length < 32) return;
  const words = Array.from({ length: 8 }, (_, i) => output.readUInt32LE(i * 4));
  if (words[5] > 384 * 192 * 8) {
    child.kill();
    process.exitCode = 1;
    return;
  }
  if (output.length < 32 + words[5]) return;
  try {
    assert.deepEqual(words, [0x31564853, 0, 1, 384, 192, 384 * 192 * 8, 1, (9 << 16) | 16]);
    complete = true;
  } catch (error) {
    console.error(error.message, output.subarray(32).toString());
    process.exitCode = 1;
  }
  child.stdin.end();
});
child.on('close', code => {
  clearTimeout(timer);
  if (code !== 0 || !complete) {
    console.error(`HDR native smoke failed (exit ${code}).\n${errors}`);
    process.exitCode = 1;
  } else {
    console.log('HDR native smoke decoded a 384x192 Dolby Vision frame.');
  }
});
const header = Buffer.alloc(32);
[0x31564853, 1, 1, 384, 192, sample.length, 384, 192]
  .forEach((value, i) => header.writeUInt32LE(value, i * 4));
child.stdin.write(Buffer.concat([header, sample]));
