import '../domain/image_format.dart';
import '../domain/viewer_settings.dart';
import 'hdr_input_metadata.dart';

/// Gates only the optional native HDR layer. SDR decoding and tone mapping
/// remain available, including when an input uses PQ or HLG encoding.
bool shouldUseHdrDisplay(
  ViewerSettings settings,
  ImageFormat format,
  HdrEncoding encoding,
) {
  if (!settings.autoHdr || encoding == HdrEncoding.sdr) return false;
  // RAW uses the same scene-linear encoding as EXR, but has its own control.
  if (format == ImageFormat.raw) return settings.hdrRaw;
  return switch (encoding) {
    HdrEncoding.sceneLinear => settings.hdrLinear,
    HdrEncoding.pq || HdrEncoding.hlg => settings.hdrPqHlg,
    HdrEncoding.gainMap => settings.hdrGainMap,
    HdrEncoding.dolbyVision => settings.hdrDolbyVision,
    HdrEncoding.sdr => false,
  };
}
