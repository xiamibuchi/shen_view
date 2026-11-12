#!/usr/bin/env python3
"""Copy macOS codec workers and their Mach-O dependency closure into an app."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def run(*command):
    return subprocess.check_output(command, text=True).strip()


def dependencies(binary):
    lines = run("otool", "-L", str(binary)).splitlines()[1:]
    return [line.strip().split(" (", 1)[0] for line in lines]


def architectures(binary):
    return set(run("lipo", "-archs", str(binary)).split())


def minimum_os(binary):
    output = run("vtool", "-show-build", str(binary))
    match = re.search(r"\bminos (\d+\.\d+)", output)
    if not match:
        raise RuntimeError(f"Cannot read macOS minimum version: {binary}")
    return tuple(map(int, match.group(1).split(".")))


def source_for(dependency, original):
    if dependency.startswith("@loader_path/"):
        path = original.parent / dependency.removeprefix("@loader_path/")
    elif dependency.startswith("@rpath/"):
        name = dependency.removeprefix("@rpath/")
        candidates = [original.parent / name,
                      Path("/opt/homebrew/lib") / name,
                      Path("/usr/local/lib") / name]
        path = next((candidate for candidate in candidates if candidate.exists()), None)
        if path is None:
            raise RuntimeError(f"Cannot resolve {dependency} used by {original}")
    elif dependency.startswith("/"):
        path = Path(dependency)
    else:
        raise RuntimeError(f"Unsupported dependency {dependency} used by {original}")
    if not path.is_file():
        raise RuntimeError(f"Missing dependency {dependency} used by {original}")
    return path


def copy_notices(app, source, imagemagick):
    notices = app / "Contents/Resources/codecs/licenses"
    ffmpeg = notices / "ffmpeg"
    ffmpeg.mkdir(parents=True, exist_ok=True)
    for pattern in ("COPYING*", "LICENSE.md"):
        for file in source.glob(pattern):
            shutil.copy2(file, ffmpeg / file.name)
    recipe = ffmpeg / "build-recipe"
    recipe.mkdir(exist_ok=True)
    lock = Path(__file__).resolve().parents[2] / "third_party/ffmpeg/source.lock.json"
    shutil.copy2(lock, recipe / "source.lock.json")
    shutil.copy2(Path(__file__).resolve().parents[2] / "third_party/ffmpeg/profile.sh",
                 recipe / "profile.sh")
    (ffmpeg / "SOURCES.txt").write_text(
        "FFmpeg 9.0.2 built from the source and playback profile in build-recipe/.\n"
        "Dynamically linked dependencies are listed in manifest.json beside the workers.\n"
        "They were supplied by the build host and redistributed with the app.\n")
    magick = notices / "imagemagick"
    magick.mkdir(parents=True, exist_ok=True)
    shutil.copy2(imagemagick / "LICENSE", magick / "LICENSE")
    (magick / "SOURCES.txt").write_text(
        "ImageMagick runtime and coder modules: https://imagemagick.org/\n"
        "Dynamically linked dependencies are listed in the codec manifest.\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--imagemagick", type=Path, required=True)
    parser.add_argument("--archs", nargs="+", required=True)
    parser.add_argument("--min-os", required=True)
    parser.add_argument("--sign", default="-")
    args = parser.parse_args()

    app = args.app.resolve()
    ffmpeg = args.ffmpeg.resolve()
    imagemagick = args.imagemagick.resolve()
    root = app / "Contents/MacOS/codecs"
    libraries = root / "lib"
    resources = app / "Contents/Resources/codecs"
    for binary in (ffmpeg / "install/bin/ffmpeg", ffmpeg / "install/bin/ffprobe",
                   imagemagick / "bin/magick"):
        missing = set(args.archs) - architectures(binary)
        if missing:
            raise RuntimeError(f"{binary} has no {', '.join(sorted(missing))} slice")
        if minimum_os(binary) > tuple(map(int, args.min_os.split(".")[:2])):
            raise RuntimeError(f"{binary} requires macOS {minimum_os(binary)} "
                               f"but the app targets {args.min_os}")
    for managed in (root / "ffmpeg", root / "imagemagick", libraries,
                    resources / "imagemagick"):
        if managed.exists():
            shutil.rmtree(managed)
    libraries.mkdir(parents=True, exist_ok=True)
    pending = []
    visited = set()
    copied = {}
    manifest = []

    def schedule(source, target):
        source = source.resolve()
        if target in visited:
            return
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists() or target.is_symlink():
            target.unlink()
        shutil.copy2(source, target)
        pending.append((source, target))
        visited.add(target)

    schedule(ffmpeg / "install/bin/ffmpeg", root / "ffmpeg/ffmpeg")
    schedule(ffmpeg / "install/bin/ffprobe", root / "ffmpeg/ffprobe")
    schedule(imagemagick / "bin/magick", root / "imagemagick/magick")
    modules = imagemagick / "lib/ImageMagick/modules-Q16HDRI"
    required_coders = (
        "bmp", "dds", "dng", "exr", "gif", "hdr", "heic", "icon", "info",
        "jpeg", "jxl", "png", "psd", "rgb", "svg", "tiff", "webp",
    )
    for category in ("coders",):
        module_resources = resources / "imagemagick/modules" / category
        module_resources.mkdir(parents=True, exist_ok=True)
        for name in required_coders:
            module = modules / category / (name + ".so")
            if not module.is_file():
                raise RuntimeError(f"Missing ImageMagick coder: {module}")
            target = root / "imagemagick/modules" / category / module.name
            schedule(module, target)
            (module_resources / (module.stem + ".la")).write_text(
                f"dlname='{module.name}'\n"
                f"library_names='{module.name}'\n"
                "old_library=''\n"
                "dependency_libs=''\n"
                "installed=yes\n"
                "libdir=''\n"
            )
            link = module_resources / module.name
            if link.is_symlink():
                link.unlink()
            link.symlink_to(os.path.relpath(target, module_resources))

    config = imagemagick / "etc/ImageMagick-7"
    if not config.is_dir():
        raise RuntimeError(f"ImageMagick configuration missing: {config}")
    shutil.copytree(config, resources / "imagemagick", dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("*.la"))

    while pending:
        original, target = pending.pop(0)
        missing = set(args.archs) - architectures(original)
        if missing:
            raise RuntimeError(f"{original} has no {', '.join(sorted(missing))} slice")
        if minimum_os(original) > tuple(map(int, args.min_os.split(".")[:2])):
            raise RuntimeError(f"{original} requires macOS {minimum_os(original)} "
                               f"but the app targets {args.min_os}")
        for dependency in dependencies(original):
            if dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            if dependency == str(original) or Path(dependency).name == target.name and \
                    target.suffix == ".dylib":
                continue
            resolved = source_for(dependency, original)
            name = Path(dependency).name
            bundled = libraries / name
            digest = hashlib.sha256(resolved.read_bytes()).hexdigest()
            if name in copied and copied[name] != digest:
                raise RuntimeError(f"Conflicting dylib name: {name}")
            copied[name] = digest
            schedule(resolved, bundled)
            relative = os.path.relpath(bundled, target.parent)
            subprocess.run(["install_name_tool", "-change", dependency,
                            "@loader_path/" + relative, str(target)], check=True)
        if target.suffix == ".dylib":
            subprocess.run(["install_name_tool", "-id",
                            "@loader_path/" + target.name, str(target)], check=True)
        subprocess.run(["codesign", "--force", "--sign", args.sign, str(target)],
                       check=True, stdout=subprocess.DEVNULL)
        manifest.append({"path": str(target.relative_to(root)),
                         "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                         "archs": sorted(architectures(target)),
                         "minimumMacOS": ".".join(map(str, minimum_os(target)))})

    source = ffmpeg / "source/ffmpeg-9.0.2"
    copy_notices(app, source, imagemagick)
    (resources / "manifest.json").write_text(json.dumps({"files": sorted(manifest,
        key=lambda entry: entry["path"])}, ensure_ascii=False, indent=2) + "\n")
    for entry in manifest:
        binary = root / entry["path"]
        for dependency in dependencies(binary):
            if dependency.startswith(("/opt/homebrew/", "/usr/local/")):
                raise RuntimeError(f"Host dependency remains in {binary}: {dependency}")
        subprocess.run(["codesign", "--verify", str(binary)], check=True,
                       stdout=subprocess.DEVNULL)

    sample = Path(__file__).resolve().parents[2] / "apps/viewer/testdata/formats/format_static.jpg"
    environment = {**os.environ, "PATH": "/usr/bin:/bin",
                   "MAGICK_CONFIGURE_PATH": str(resources / "imagemagick"),
                   "MAGICK_CODER_MODULE_PATH": str(resources / "imagemagick/modules/coders"),
                   "MAGICK_FILTER_MODULE_PATH": str(resources / "imagemagick/modules/filters")}
    with tempfile.TemporaryDirectory() as smoke_directory:
        decoded = subprocess.run([str(root / "imagemagick/magick"), str(sample),
                                  "-depth", "8", "png32:-"], cwd=smoke_directory,
                                 env=environment, check=True, capture_output=True)
    if not decoded.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("Bundled ImageMagick did not decode JPEG to PNG")
    hdr_sample = Path(__file__).resolve().parents[2] / "apps/viewer/testdata/formats/hdr_gradient.exr"
    with tempfile.TemporaryDirectory() as smoke_directory:
        floated = subprocess.run([str(root / "imagemagick/magick"), str(hdr_sample),
                                  "-format", "FVHDR32 %w %h\n", "-write", "info:-",
                                  "-define", "quantum:format=floating-point",
                                  "-depth", "32", "-endian", "LSB", "rgba:-"],
                                 cwd=smoke_directory, env=environment, check=True,
                                 capture_output=True)
    if not floated.stdout.startswith(b"FVHDR32 512 270\n"):
        raise RuntimeError("Bundled ImageMagick did not emit HDR float pixels")
    probe_sample = Path(__file__).resolve().parents[2] / "apps/viewer/testdata/photo_media/sequence.heic"
    probed = subprocess.run([str(root / "ffmpeg/ffprobe"), "-v", "error",
                             "-show_entries", "stream=codec_name", "-of", "json",
                             str(probe_sample)], env=environment, check=True,
                            capture_output=True)
    if "hevc" not in probed.stdout.decode():
        raise RuntimeError("Bundled FFprobe did not read HEIF video")
    print(f"Bundled {len(manifest)} macOS codec binaries and libraries")


if __name__ == "__main__":
    main()
