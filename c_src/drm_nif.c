// KMS presenter NIF for benchmarking: converts premultiplied RGBA8888 frames
// straight from a BEAM binary into a mapped dumb buffer (XRGB8888) and
// page-flips to it. No copies through a port.
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <drm/drm.h>
#include <drm/drm_fourcc.h>
#include <drm/drm_mode.h>
#include <erl_nif.h>

struct buf {
    uint32_t handle, pitch, fb_id;
    uint64_t size;
    uint8_t *map;
};

struct rect {
    int32_t x, y, w, h;
};

static struct rect rect_union(struct rect a, struct rect b)
{
    if (a.w <= 0 || a.h <= 0)
        return b;
    if (b.w <= 0 || b.h <= 0)
        return a;
    int32_t x0 = a.x < b.x ? a.x : b.x, y0 = a.y < b.y ? a.y : b.y;
    int32_t x1 = a.x + a.w > b.x + b.w ? a.x + a.w : b.x + b.w;
    int32_t y1 = a.y + a.h > b.y + b.h ? a.y + a.h : b.y + b.h;
    return (struct rect){x0, y0, x1 - x0, y1 - y0};
}

struct display {
    int fd;
    uint32_t crtc_id, connector_id, width, height, refresh;
    struct drm_mode_modeinfo mode;
    struct drm_mode_crtc saved;
    struct buf bufs[2];
    int back;
    int closed;
    // Partial presentation: full XRGB copy of the latest frame, and per buffer
    // the bounding box of mirror pixels it has not received yet.
    uint8_t *mirror;
    struct rect pending[2];
};

static ErlNifResourceType *display_type;

static int xioctl(int fd, unsigned long req, void *arg)
{
    int r;
    do {
        r = ioctl(fd, req, arg);
    } while (r == -1 && (errno == EINTR || errno == EAGAIN));
    return r;
}

static uint64_t now_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

static ERL_NIF_TERM error(ErlNifEnv *env, const char *what)
{
    return enif_make_tuple2(env, enif_make_atom(env, "error"),
                            enif_make_tuple2(env, enif_make_atom(env, what),
                                             enif_make_string(env, strerror(errno), ERL_NIF_LATIN1)));
}

static void release(struct display *d)
{
    if (d->closed)
        return;
    d->closed = 1;
    if (d->saved.fb_id) {
        struct drm_mode_crtc restore = {.crtc_id = d->crtc_id, .fb_id = d->saved.fb_id, .x = d->saved.x,
                                        .y = d->saved.y, .mode_valid = d->saved.mode_valid, .mode = d->saved.mode,
                                        .set_connectors_ptr = (uintptr_t)&d->connector_id, .count_connectors = 1};
        xioctl(d->fd, DRM_IOCTL_MODE_SETCRTC, &restore);
    }
    for (int i = 0; i < 2; i++) {
        struct buf *b = &d->bufs[i];
        if (b->map)
            munmap(b->map, b->size);
        if (b->fb_id)
            xioctl(d->fd, DRM_IOCTL_MODE_RMFB, &b->fb_id);
        if (b->handle) {
            struct drm_mode_destroy_dumb dd = {.handle = b->handle};
            xioctl(d->fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dd);
        }
    }
    xioctl(d->fd, DRM_IOCTL_DROP_MASTER, 0);
    close(d->fd);
    free(d->mirror);
    d->mirror = NULL;
}

static void display_dtor(ErlNifEnv *env, void *obj)
{
    (void)env;
    release(obj);
}

static int create_buf(int fd, struct buf *b, uint32_t w, uint32_t h)
{
    struct drm_mode_create_dumb c = {.width = w, .height = h, .bpp = 32};
    if (xioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &c))
        return -1;
    b->handle = c.handle;
    b->pitch = c.pitch;
    b->size = c.size;

    struct drm_mode_fb_cmd2 f = {.width = w, .height = h, .pixel_format = DRM_FORMAT_XRGB8888};
    f.handles[0] = c.handle;
    f.pitches[0] = c.pitch;
    if (xioctl(fd, DRM_IOCTL_MODE_ADDFB2, &f))
        return -1;
    b->fb_id = f.fb_id;

    struct drm_mode_map_dumb m = {.handle = c.handle};
    if (xioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &m))
        return -1;
    void *map = mmap(0, c.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, m.offset);
    if (map == MAP_FAILED)
        return -1;
    b->map = map;
    memset(b->map, 0, c.size);
    return 0;
}

// open(path) -> {:ok, ref, {width, height, pitch, refresh}} | {:error, reason}
static ERL_NIF_TERM nif_open(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    (void)argc;
    char path[256];
    if (enif_get_string(env, argv[0], path, sizeof(path), ERL_NIF_LATIN1) <= 0)
        return enif_make_badarg(env);

    struct display *d = enif_alloc_resource(display_type, sizeof(*d));
    memset(d, 0, sizeof(*d));
    d->closed = 1; // nothing to release until the fd is open
    ERL_NIF_TERM ref = enif_make_resource(env, d);
    enif_release_resource(d);

    d->fd = open(path, O_RDWR | O_CLOEXEC);
    if (d->fd < 0)
        return error(env, "open");
    d->closed = 0;
    if (xioctl(d->fd, DRM_IOCTL_SET_MASTER, 0))
        return error(env, "set_master");

    struct drm_mode_card_res res = {0};
    if (xioctl(d->fd, DRM_IOCTL_MODE_GETRESOURCES, &res))
        return error(env, "getresources");
    uint32_t conns[16], crtcs[16], encs[16], fbs[16];
    if (res.count_connectors > 16 || res.count_crtcs > 16 || res.count_encoders > 16 || res.count_fbs > 16)
        return error(env, "too_many_objects");
    res.connector_id_ptr = (uintptr_t)conns;
    res.crtc_id_ptr = (uintptr_t)crtcs;
    res.encoder_id_ptr = (uintptr_t)encs;
    res.fb_id_ptr = (uintptr_t)fbs;
    if (xioctl(d->fd, DRM_IOCTL_MODE_GETRESOURCES, &res))
        return error(env, "getresources");

    int found = 0;
    uint32_t encoder_id = 0;
    for (uint32_t i = 0; i < res.count_connectors && !found; i++) {
        struct drm_mode_get_connector conn = {.connector_id = conns[i]};
        if (xioctl(d->fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn))
            return error(env, "getconnector");
        if (conn.connection != 1 || conn.count_modes == 0 || conn.count_modes > 32 || conn.count_props > 64 ||
            conn.count_encoders > 16)
            continue;
        struct drm_mode_modeinfo modes[32];
        uint32_t props[64], cencs[16];
        uint64_t vals[64];
        conn.modes_ptr = (uintptr_t)modes;
        conn.props_ptr = (uintptr_t)props;
        conn.prop_values_ptr = (uintptr_t)vals;
        conn.encoders_ptr = (uintptr_t)cencs;
        if (xioctl(d->fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn))
            return error(env, "getconnector");
        d->mode = modes[0];
        d->connector_id = conn.connector_id;
        encoder_id = conn.encoder_id;
        found = 1;
    }
    if (!found) {
        errno = ENODEV;
        return error(env, "no_connected_display");
    }

    d->crtc_id = crtcs[0];
    if (encoder_id) {
        struct drm_mode_get_encoder enc = {.encoder_id = encoder_id};
        if (xioctl(d->fd, DRM_IOCTL_MODE_GETENCODER, &enc) == 0 && enc.crtc_id)
            d->crtc_id = enc.crtc_id;
    }
    d->saved.crtc_id = d->crtc_id;
    xioctl(d->fd, DRM_IOCTL_MODE_GETCRTC, &d->saved);

    d->width = d->mode.hdisplay;
    d->height = d->mode.vdisplay;
    d->refresh = d->mode.vrefresh;
    for (int i = 0; i < 2; i++)
        if (create_buf(d->fd, &d->bufs[i], d->width, d->height))
            return error(env, "create_buffer");

    struct drm_mode_crtc set = {.crtc_id = d->crtc_id, .fb_id = d->bufs[0].fb_id, .mode_valid = 1, .mode = d->mode,
                                .set_connectors_ptr = (uintptr_t)&d->connector_id, .count_connectors = 1};
    if (xioctl(d->fd, DRM_IOCTL_MODE_SETCRTC, &set))
        return error(env, "setcrtc");
    d->back = 1;
    d->mirror = calloc((size_t)d->width * d->height, 4);
    d->pending[0] = d->pending[1] = (struct rect){0, 0, (int32_t)d->width, (int32_t)d->height};

    ERL_NIF_TERM info = enif_make_tuple4(env, enif_make_uint(env, d->width), enif_make_uint(env, d->height),
                                         enif_make_uint(env, d->bufs[0].pitch), enif_make_uint(env, d->refresh));
    return enif_make_tuple3(env, enif_make_atom(env, "ok"), ref, info);
}

static int flip_to_back(struct display *d)
{
    struct drm_mode_crtc_page_flip flip = {.crtc_id = d->crtc_id, .fb_id = d->bufs[d->back].fb_id,
                                           .flags = DRM_MODE_PAGE_FLIP_EVENT};
    if (xioctl(d->fd, DRM_IOCTL_MODE_PAGE_FLIP, &flip))
        return -1;
    char ev[1024];
    if (read(d->fd, ev, sizeof(ev)) <= 0)
        return -1;
    d->back ^= 1;
    return 0;
}

// stage_region(ref, bgra_binary, x, y, w, h) -> :ok
// Copies the rectangle into the mirror and marks it stale in both buffers,
// without touching the display. Several stages can share one commit.
static ERL_NIF_TERM nif_stage_region(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    (void)argc;
    struct display *d;
    ErlNifBinary frame;
    struct rect r;
    if (!enif_get_resource(env, argv[0], display_type, (void **)&d) || !enif_inspect_binary(env, argv[1], &frame) ||
        !enif_get_int(env, argv[2], &r.x) || !enif_get_int(env, argv[3], &r.y) || !enif_get_int(env, argv[4], &r.w) ||
        !enif_get_int(env, argv[5], &r.h))
        return enif_make_badarg(env);
    if (d->closed || !d->mirror)
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_atom(env, "closed"));
    if (r.x < 0 || r.y < 0 || r.w <= 0 || r.h <= 0 || r.x + r.w > (int32_t)d->width ||
        r.y + r.h > (int32_t)d->height || frame.size != (size_t)r.w * r.h * 4)
        return enif_make_badarg(env);

    size_t mirror_row = (size_t)d->width * 4, len = (size_t)r.w * 4;
    for (int32_t y = 0; y < r.h; y++)
        memcpy(d->mirror + (size_t)(r.y + y) * mirror_row + (size_t)r.x * 4, frame.data + (size_t)y * len, len);
    d->pending[0] = rect_union(d->pending[0], r);
    d->pending[1] = rect_union(d->pending[1], r);
    return enif_make_atom(env, "ok");
}

// commit(ref) -> {copy_us, flip_us, rows}
// Brings the back buffer up to date from the mirror and flips to it.
static ERL_NIF_TERM nif_commit(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    (void)argc;
    struct display *d;
    if (!enif_get_resource(env, argv[0], display_type, (void **)&d))
        return enif_make_badarg(env);
    if (d->closed || !d->mirror)
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_atom(env, "closed"));

    uint64_t t0 = now_us();
    size_t mirror_row = (size_t)d->width * 4;
    struct buf *b = &d->bufs[d->back];
    struct rect todo = d->pending[d->back];
    for (int32_t y = todo.y; y < todo.y + todo.h; y++)
        memcpy(b->map + (size_t)y * b->pitch + (size_t)todo.x * 4, d->mirror + (size_t)y * mirror_row + (size_t)todo.x * 4,
               (size_t)todo.w * 4);
    d->pending[d->back] = (struct rect){0, 0, 0, 0};
    uint64_t t1 = now_us();

    if (flip_to_back(d))
        return error(env, "page_flip");
    uint64_t t2 = now_us();
    return enif_make_tuple3(env, enif_make_uint64(env, t1 - t0), enif_make_uint64(env, t2 - t1),
                            enif_make_int(env, todo.h > 0 ? todo.h : 0));
}

static ERL_NIF_TERM nif_close(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    (void)argc;
    struct display *d;
    if (!enif_get_resource(env, argv[0], display_type, (void **)&d))
        return enif_make_badarg(env);
    release(d);
    return enif_make_atom(env, "ok");
}

static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM info)
{
    (void)priv;
    (void)info;
    display_type = enif_open_resource_type(env, NULL, "drm_display", display_dtor, ERL_NIF_RT_CREATE, NULL);
    return display_type ? 0 : -1;
}

static ErlNifFunc funcs[] = {
    {"open", 1, nif_open, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"stage_region", 6, nif_stage_region, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"commit", 1, nif_commit, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"close", 1, nif_close, ERL_NIF_DIRTY_JOB_IO_BOUND},
};

ERL_NIF_INIT(Elixir.SqueezeNexus7.Display.Drm, funcs, load, NULL, NULL, NULL)
