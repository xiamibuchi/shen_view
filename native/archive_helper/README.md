# Indexed archive helper

This read-only client uses the official [7-Zip SDK interfaces](https://www.7-zip.org/sdk.html),
with headers/source pinned to 25.01 and SHA-256 verified by CMake. Windows builds
load `7z.dll` adjacent to the helper; macOS builds compile the official Format7zF
shared-library bundle and load the adjacent `7z.so`. The engine is distributed
with the app, together with LGPL/unRAR notices. The application exposes no
user-installed archive plugin API.

Windows runtime packaging contains the helper and DLL, without 7z.exe. The
application bundles this pair in codecs/archive/ with its app-local
VC Runtime. Development builds keep the helper and engine adjacent in bin/.
The command-line tool is only a development fixture/probe dependency. SDK/source
25.01 is distinct from the separately supplied Windows engine version; the
packager records that version in licenses/7zip/ENGINE.txt. Commercial use and
redistribution obligations are documented in
[the archive licensing audit](../../docs/release/archive-licensing.md).
The license directory also carries the full LGPL 2.1 text and source notices;
release distributors must provide the corresponding LGPL-covered source,
modifications and build instructions through a valid distribution/offer.

Build on Windows with `tool/build/build_archive_helper.ps1`, or on macOS with
`sh tool/build/build_archive_helper.sh`. Windows Flutter builds also build/install the
helper automatically. macOS Flutter builds invoke a Runner shell phase after
Flutter embedding, build the requested architectures, package the engine and
helper, and sign the sandbox-inheriting helper with the app's identity (or
ad-hoc when no signing identity is enabled). CMake/Clang/make must be available
on the build machine; fetched SDK sources stay in CMake's build cache. Windows
build machines need a redistributable 7-Zip engine. CMake searches beside the
7z/7zz executable on PATH and under the system Program Files directory;
custom installations can set VIEWER_7ZIP_ENGINE in CMake.
Runtime machines do not need a 7-Zip installation. The macOS script accepts an
app bundle path as its optional first argument to copy and locally sign the
helper, engine and notices before the app's final signing step.

## Protocol

There are no command-line credentials. The long-lived helper accepts tab-delimited
commands on standard input. Paths and passwords are hexadecimal UTF-8; a `-`
password field means no password (an empty field represents an empty password).

- `open PATH PASSWORD MAX_ENTRIES MAX_NAME_BYTES` emits JSON `entry` events
  followed by `done` with `format`, `solid`, and `encrypted`.
- `read INDEX OUTPUT_PATH MAX_OUTPUT_BYTES MAX_WORK_BYTES` extracts that exact
  index to the application's generated pending destination. It emits optional
  progress and either `done` or a classified `error`.

- readMany MAX_TOTAL_OUTPUT_BYTES MAX_WORK_BYTES followed by 1 to 16 triples
  INDEX HEX_OUTPUT_PATH MAX_OUTPUT_BYTES extracts all indices in one SDK call.
  Indices are sorted before Extract; duplicate indices and normalized output
  paths are rejected. Per-entry and aggregate output limits apply during writes.
  A batch emits one done only after every requested entry succeeds; any failure
  emits error and removes all batch outputs. The Dart cache must still commit
  pending files only after this final success.

Both read and readMany return bytes (aggregate output bytes), workBytes (maximum
SDK completed progress observed), and extractCalls: 1. Work progress follows the
SDK's format-dependent units and is not a CPU-time or elapsed-time measurement.

Each command occupies one line. JSON output is one event per line. No file
contents, passwords or localized engine error messages are sent over stdout.
Cancellation terminates the isolated worker; a later request reopens the index.
Output is bounded during each write and committed by the Dart cache only after
the SDK validates extraction and actual size matches the indexed entry size.

The worker limits its own memory (Windows job / POSIX data limit), checks free
disk space during output, and bounds SDK extraction progress. The latter uses
the SDK's format-dependent progress unit: archive formats normally report
uncompressed bytes. The 60-second request watchdog remains a separate bound.

## Verified behavior and limitations

On Windows, `test/archive_session_test.dart` exercises ZIP/AES ZIP, duplicate
full names, Chinese/emoji paths, TAR, solid 7Z, RAR, non-solid/solid RAR5, cache
leases and shared limits, cancellation, nested sensitive lifetime and source
replacement. It skips native contracts if the helper has not been built.
macOS source and packaging are provided; they require validation on macOS.

An `IInArchive` remains open and already extracted entries are reused. Calls
are serialized and skipped solid-prefix entries are never written to disk.
readMany merges selected entries into one extraction pass, allowing useful
already-traversed solid-prefix entries to be retained without a second pass.
Separate calls can still restart the block dictionary; there are no cross-call
dictionary checkpoints. Large uncached forward/random jumps may therefore
repeat decompression and still require representative performance measurements.

When RAR/RAR5 omits kpidBlock, the pinned SDK's per-item kpidSolid predecessor
dependency flag supplies conservative group IDs. An explicit false flag starts
a block identified by that item's index; subsequent explicit true flags share
it. Directories or missing/invalid flags suppress fallback IDs until the next
explicit restart. The helper never derives a group from archive-level solid
alone. An engine-provided kpidBlock remains authoritative.

The native readMany probe in build/archive-helper/read-many-probe/results.json
used 32 entries of 256 KiB in one solid 7Z block: selecting indices 31/28/30/29
produced 1 MiB in one Extract call, with 8 MiB reported work. The solid RAR5
fixture selected 6/3/5/4 and produced 16 KiB in one call, with 25776 work units.
All seven RAR5 items exposed fallback block 0. Insufficient aggregate, entry or
work limits, duplicate index/path, and over-16 batches emitted errors with no
output files. These synthetic probes validate the protocol, not large-book
latency or image decoding.

Source-version checks compare size, modification time, and first/last 64 KiB
fingerprints before/after extraction; the stable cache key also includes the
entire indexed directory's names, indices, sizes, times, block and CRC fields.
An in-place middle-only mutation with deliberately preserved metadata may only
be caught by the SDK's data/CRC validation when that affected entry is read.
