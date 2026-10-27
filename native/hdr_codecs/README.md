# Optional HDR codecs

`viewer_avif_animation` is a persistent libavif decoder for AVIF image sequences.
It uses a bounded metadata handshake followed by frame-index requests on stdin
and premultiplied sRGB RGBA frames on stdout. Little CMS 2.17 handles ICC/CICP
color conversion; PQ/HLG sequences use a fixed 203-nit reference white and SDR
tone mapping. Progressive layers are not animation frames.
Windows and macOS app builds provision and bundle this helper and its notices
automatically. For a standalone build, configure with `-DSHENVIEW_AVIF_ONLY=ON`
and build target `viewer_avif_animation`.

`viewer_gainmap` is an optional helper process for Ultra HDR / ISO 21496 gain-map
JPEG and AVIF files. `viewer_heif_gainmap` handles HEIF `tmap` items by decoding
the two linked HEVC images and applying the ISO 21496 metadata. Both helpers
return bounded linear RGBA float32 pixels over stdout; the
Flutter process treats a missing helper or a failed decode as an SDR fallback.
The helper is intentionally isolated from the UI process so malformed JPEGs and
codec allocation failures cannot take down the viewer.

`viewer_raw` develops full sensor data with LibRaw, camera white balance and
AHD demosaicing. Its SDR and linear HDR outputs share a bounded exposure
normalization from the full-resolution RGB histogram (top 1% excluded, at most
four stops of gain, no gain for empty/near-black frames). The HDR output keeps
unclipped floating-point highlights; the SDR output applies the display curve.
Changing automatic HDR only changes presentation, not the RAW exposure.

The Windows build pins libultrahdr v1.4.0 and libjpeg-turbo 3.1.1. The HEIF helper
loads the ImageMagick/libheif runtime from the same `codecs` directory, so it does
not add a second HEVC library or a process-global decoder. Configure and
build from the repository root with:

```powershell
powershell -ExecutionPolicy Bypass -File tool/build/build_hdr_codecs.ps1
```

On macOS, use the same CMake project with Xcode and a native architecture:

```sh
cmake -S native/hdr_codecs -B build/hdr-codecs -G Xcode
cmake --build build/hdr-codecs --config Release --target viewer_gainmap viewer_heif_gainmap viewer_raw viewer_avif_animation
```

The helper is optional and must be packaged with its dependency notices.
libultrahdr is Apache-2.0 with its documented third-party notices;
libjpeg-turbo is IJG/BSD-style licensed. Keep the upstream `LICENSE` and
`NOTICE` files next to the helper in a release package. FFmpeg/ffprobe used for
Dolby Vision and HEVC are separate optional components and retain their own
license obligations.
