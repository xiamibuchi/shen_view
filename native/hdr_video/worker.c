#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/dovi_meta.h>
#include <libplacebo/options.h>
#include <libplacebo/utils/libav.h>
#include <libplacebo/vulkan.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#else
#include <signal.h>
#endif

#define MAGIC 0x31564853u
#define MAX_PATH_BYTES 32768u
#define MAX_PIXELS (4u * 1024u * 1024u)

typedef struct Job {
    uint32_t id, width, height, source_width, source_height;
    char *path;
} Job;

typedef struct State {
    pthread_mutex_t mutex;
    pthread_cond_t ready;
    Job *job;
    uint32_t active, cancelled;
    int stop, trim;
} State;

typedef struct Renderer {
    pl_log log;
    pl_vulkan vk;
    pl_renderer renderer;
    pl_options options;
} Renderer;

static uint32_t read32(const uint8_t *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static void write32(uint8_t *p, uint32_t n)
{
    for (int i = 0; i < 4; ++i) p[i] = (uint8_t)(n >> (8 * i));
}

static int cancelled(void *opaque)
{
    State *s = opaque;
    pthread_mutex_lock(&s->mutex);
    int result = s->stop || (s->active && s->active == s->cancelled);
    pthread_mutex_unlock(&s->mutex);
    return result;
}

static void *read_commands(void *opaque)
{
    State *s = opaque;
    uint8_t header[32];
    while (fread(header, 1, sizeof(header), stdin) == sizeof(header)) {
        const uint32_t op = read32(header + 4), id = read32(header + 8);
        if (read32(header) != MAGIC || !id) break;
        Job *job = NULL;
        if (op == 1) {
            uint32_t length = read32(header + 20);
            if (!length || length > MAX_PATH_BYTES) break;
            job = calloc(1, sizeof(*job));
            if (!job) break;
            job->id = id;
            job->width = read32(header + 12);
            job->height = read32(header + 16);
            job->source_width = read32(header + 24);
            job->source_height = read32(header + 28);
            job->path = malloc((size_t)length + 1);
            if (!job->path || fread(job->path, 1, length, stdin) != length ||
                memchr(job->path, 0, length)) {
                free(job->path); free(job); break;
            }
            job->path[length] = 0;
        }
        pthread_mutex_lock(&s->mutex);
        if (op == 1 && !s->active) {
            s->job = job;
            s->active = id;
            s->cancelled = 0;
        } else if (op == 2) {
            if (s->active == id) s->cancelled = id;
        } else if (op == 3) {
            s->trim = 1;
        } else {
            s->stop = 1;
        }
        pthread_cond_signal(&s->ready);
        int stop = s->stop;
        pthread_mutex_unlock(&s->mutex);
        if (stop) {
            if (job) { free(job->path); free(job); }
            break;
        }
    }
    pthread_mutex_lock(&s->mutex);
    s->stop = 1;
    pthread_cond_signal(&s->ready);
    pthread_mutex_unlock(&s->mutex);
    return NULL;
}

static void reset_renderer(Renderer *r)
{
    pl_renderer_destroy(&r->renderer);
    pl_options_free(&r->options);
    pl_vulkan_destroy(&r->vk);
}

static int ensure_renderer(Renderer *r)
{
    if (r->renderer) return 0;
    r->vk = pl_vulkan_create(r->log, pl_vulkan_params(.queue_count = 0));
    if (!r->vk) return -1;
    r->renderer = pl_renderer_create(r->log, r->vk->gpu);
    r->options = pl_options_alloc(r->log);
    if (!r->renderer || !r->options) {
        reset_renderer(r); return -1;
    }
    pl_options opts = r->options;
    opts->sigmoid_params = pl_sigmoid_default_params;
    opts->color_map_params = *pl_color_map_params(
        .tone_mapping_function = &pl_tone_map_clip,
        .tone_mapping_param = 0, .lut_size = 256,
        .contrast_recovery = 0.30f, .contrast_smoothness = 3.50f);
    opts->dither_params = *pl_dither_params(.method = PL_DITHER_BLUE_NOISE, .lut_size = 6);
    opts->params.upscaler = &pl_filter_spline36;
    opts->params.downscaler = &pl_filter_mitchell;
    opts->params.sigmoid_params = &opts->sigmoid_params;
    opts->params.color_map_params = &opts->color_map_params;
    opts->params.dither_params = &opts->dither_params;
    return 0;
}

static int first_frame(State *s, const Job *job, AVFrame *frame)
{
    int status = AVERROR_INVALIDDATA, stream = -1, drained = 0;
    AVFormatContext *format = avformat_alloc_context();
    AVCodecContext *decoder = NULL;
    AVPacket *packet = av_packet_alloc();
    if (!format || !packet) goto done;
    format->interrupt_callback = (AVIOInterruptCB){cancelled, s};
    if ((status = avformat_open_input(&format, job->path, NULL, NULL)) < 0 ||
        (status = avformat_find_stream_info(format, NULL)) < 0) goto done;
    for (unsigned i = 0; i < format->nb_streams; ++i) {
        if (format->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            stream = (int)i; break;
        }
    }
    if (stream < 0) { status = AVERROR_STREAM_NOT_FOUND; goto done; }
    const AVCodecParameters *parameters = format->streams[stream]->codecpar;
    if (parameters->width != job->source_width || parameters->height != job->source_height) {
        status = AVERROR_INVALIDDATA; goto done;
    }
    const AVCodec *codec = avcodec_find_decoder(parameters->codec_id);
    decoder = codec ? avcodec_alloc_context3(codec) : NULL;
    if (!decoder) { status = AVERROR_DECODER_NOT_FOUND; goto done; }
    if ((status = avcodec_parameters_to_context(decoder, parameters)) < 0) goto done;
    decoder->thread_count = 2;
    decoder->max_pixels = 128 * 1024 * 1024;
    if ((status = avcodec_open2(decoder, codec, NULL)) < 0) goto done;
    for (;;) {
        if (cancelled(s)) { status = AVERROR_EXIT; break; }
        status = avcodec_receive_frame(decoder, frame);
        if (status == 0) break;
        if (status != AVERROR(EAGAIN) || drained) break;
        do {
            status = av_read_frame(format, packet);
            if (status < 0 || packet->stream_index == stream) break;
            av_packet_unref(packet);
        } while (!cancelled(s));
        if (cancelled(s)) { status = AVERROR_EXIT; break; }
        if (status == AVERROR_EOF) {
            drained = 1;
            status = avcodec_send_packet(decoder, NULL);
        } else if (status >= 0) {
            status = avcodec_send_packet(decoder, packet);
        }
        av_packet_unref(packet);
        if (status < 0) break;
    }
done:
    av_packet_free(&packet);
    avcodec_free_context(&decoder);
    avformat_close_input(&format);
    return status;
}

static int render_frame(State *s, Renderer *r, const Job *job, AVFrame **result)
{
    int status = -1, mapped = 0;
    AVFrame *input = av_frame_alloc(), *output = av_frame_alloc();
    pl_tex input_tex[4] = {0}, output_tex[4] = {0};
    struct pl_frame image = {0}, target = {0};
    if (!input || !output || first_frame(s, job, input) < 0 ||
        input->width != job->source_width || input->height != job->source_height) goto done;
    if (cancelled(s)) goto done;
    const AVFrameSideData *side = av_frame_get_side_data(input, AV_FRAME_DATA_DOVI_METADATA);
    if (!side || side->size < sizeof(AVDOVIMetadata)) goto done;
    const AVDOVIRpuDataHeader *rpu = av_dovi_get_header((AVDOVIMetadata *)side->data);
    if (!rpu->disable_residual_flag || ensure_renderer(r) < 0 || cancelled(s)) goto done;
    pl_gpu gpu = r->vk->gpu;
    if (!pl_map_avframe_ex(gpu, &image, pl_avframe_params(.frame = input, .tex = input_tex))) goto done;
    mapped = 1;
    if (av_frame_copy_props(output, input) < 0) goto done;
    output->format = AV_PIX_FMT_RGBA64LE;
    output->width = job->width;
    output->height = job->height;
    output->colorspace = AVCOL_SPC_RGB;
    output->color_primaries = AVCOL_PRI_BT2020;
    output->color_trc = AVCOL_TRC_SMPTE2084;
    output->color_range = AVCOL_RANGE_JPEG;
    output->alpha_mode = AVALPHA_MODE_STRAIGHT;
    int changed = AV_SIDE_DATA_PROP_COLOR_DEPENDENT;
    if (input->width != output->width || input->height != output->height)
        changed |= AV_SIDE_DATA_PROP_SIZE_DEPENDENT;
    av_frame_side_data_remove_by_props(&output->side_data, &output->nb_side_data, changed);
    av_frame_remove_side_data(output, AV_FRAME_DATA_FILM_GRAIN_PARAMS);
    av_frame_remove_side_data(output, AV_FRAME_DATA_DISPLAYMATRIX);
    if (av_frame_get_buffer(output, 32) < 0) goto done;
    if (!pl_frame_recreate_from_avframe(gpu, &target, output_tex, output)) goto done;
    // Independent stills must not inherit peak/temporal data from the last file.
    pl_renderer_flush_cache(r->renderer);
    if (cancelled(s) || !pl_render_image(r->renderer, &image, &target, &r->options->params) ||
        !pl_download_avframe(gpu, &target, output) || cancelled(s)) goto done;
    *result = output;
    output = NULL;
    status = 0;
done:
    if (r->vk) {
        pl_gpu gpu = r->vk->gpu;
        if (mapped) pl_unmap_avframe(gpu, &image);
        for (int i = 0; i < 4; ++i) {
            pl_tex_destroy(gpu, &input_tex[i]);
            pl_tex_destroy(gpu, &output_tex[i]);
        }
        // Cancel acknowledgement must follow actual GPU/resource cleanup.
        pl_gpu_finish(gpu);
    }
    av_frame_free(&input);
    av_frame_free(&output);
    return status;
}

static int respond(uint32_t id, uint32_t status, const AVFrame *frame)
{
    uint8_t header[32] = {0};
    const char *error = "Dolby Vision frame could not be decoded";
    uint32_t width = frame ? frame->width : 0, height = frame ? frame->height : 0;
    uint32_t length = frame ? width * height * 8 : status == 1 ? (uint32_t)strlen(error) : 0;
    write32(header, MAGIC); write32(header + 4, status); write32(header + 8, id);
    write32(header + 12, width); write32(header + 16, height); write32(header + 20, length);
    write32(header + 24, frame ? 1 : 0);
    // Protocol format 1 is packed little-endian RGBA16, full-range BT.2020/PQ.
    write32(header + 28, frame ? (9u << 16 | 16u) : 0);
    if (fwrite(header, 1, sizeof(header), stdout) != sizeof(header)) return -1;
    if (frame) {
        for (uint32_t y = 0; y < height; ++y)
            if (fwrite(frame->data[0] + y * frame->linesize[0], 8, width, stdout) != width) return -1;
    } else if (length && fwrite(error, 1, length, stdout) != length) return -1;
    return fflush(stdout);
}

int main(void)
{
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#else
    signal(SIGPIPE, SIG_IGN);
#endif
    av_log_set_level(AV_LOG_ERROR);
    State s = {.mutex = PTHREAD_MUTEX_INITIALIZER, .ready = PTHREAD_COND_INITIALIZER};
    Renderer renderer = {0};
    renderer.log = pl_log_create(PL_API_VER, pl_log_params(.log_cb = pl_log_simple, .log_priv = stderr, .log_level = PL_LOG_WARN));
    pthread_t reader;
    if (pthread_create(&reader, NULL, read_commands, &s)) return 1;
    int result = 0;
    for (;;) {
        pthread_mutex_lock(&s.mutex);
        while (!s.job && !s.stop && !s.trim) pthread_cond_wait(&s.ready, &s.mutex);
        int stop = s.stop, trim = s.trim;
        s.trim = 0;
        Job *job = s.job; s.job = NULL;
        pthread_mutex_unlock(&s.mutex);
        if (trim) reset_renderer(&renderer);
        if (stop) { if (job) { free(job->path); free(job); } break; }
        if (!job) continue;
        AVFrame *frame = NULL;
        int valid = job->width && job->height && job->width <= 2048 && job->height <= 2048 &&
            (uint64_t)job->width * job->height <= MAX_PIXELS && job->source_width && job->source_height &&
            (uint64_t)job->source_width * job->source_height <= 128u * 1024u * 1024u;
        int status = valid ? render_frame(&s, &renderer, job, &frame) : -1;
        int was_cancelled = cancelled(&s);
        if (was_cancelled) av_frame_free(&frame);
        pthread_mutex_lock(&s.mutex);
        s.active = 0;
        pthread_mutex_unlock(&s.mutex);
        int sent = respond(job->id, was_cancelled ? 2 : status ? 1 : 0, frame);
        av_frame_free(&frame);
        free(job->path); free(job);
        if (sent) { result = 1; break; }
    }
    reset_renderer(&renderer);
    pl_log_destroy(&renderer.log);
    // On broken stdout the input reader can still block. Process exit closes it.
    return result;
}
