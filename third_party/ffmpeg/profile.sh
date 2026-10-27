#!/usr/bin/env bash
# PNG and PCM encoders are internal pixel/audio transports, not export features.
ffmpeg_profile=(
  --enable-shared --disable-static --disable-debug --enable-small --optflags=-Os
  --disable-everything --disable-autodetect --disable-doc --disable-network
  --disable-avdevice --disable-ffplay --disable-iconv
  --enable-ffmpeg --enable-ffprobe --enable-zlib
  --enable-libdav1d --enable-libzimg --enable-libplacebo --enable-vulkan
  --enable-decoder=h264,hevc,libdav1d,mpeg4,mjpeg,png,vp8,vp9,webp,aac,aac_fixed,aac_latm,alac,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_f32le,pcm_f64le,mp3,flac,opus,vorbis,ac3,eac3
  --enable-parser=h264,hevc,av1,mpeg4video,mjpeg,png,vp8,vp9,aac,aac_latm,mpegaudio,flac,opus,vorbis,ac3
  --enable-demuxer=mov,matroska,ivf,hevc,h264,av1,mjpeg,image2,image2pipe,aac,wav,ogg
  --enable-encoder=png,rawvideo,wrapped_avframe,pcm_s16le,pcm_f32le
  --enable-muxer=image2pipe,rawvideo,pcm_s16le,pcm_f32le,null
  --enable-protocol=file,pipe
  --enable-filter=scale,setsar,zscale,tonemap,libplacebo,format,null,split,trim,setpts,select,fps,hwupload,hwdownload,alphamerge,alphaextract,overlay,transpose,hflip,vflip,pad,aresample,aformat,anull,atrim,asetpts,volume,atempo
)
