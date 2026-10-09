// Reads a single-touch view of an evdev touchscreen and prints, per report,
// "d x y" (finger down), "m x y" (moved while down) or "u x y" (lifted),
// with x/y scaled to the given screen size. Meant to run as an Erlang port.
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

struct axis {
    int min, max;
};

static int read_axis(int fd, int code, int fallback, struct axis *out)
{
    struct input_absinfo info;
    if (ioctl(fd, EVIOCGABS(code), &info) == 0 || ioctl(fd, EVIOCGABS(fallback), &info) == 0) {
        out->min = info.minimum;
        out->max = info.maximum > info.minimum ? info.maximum : info.minimum + 1;
        return 0;
    }
    return -1;
}

static int scale(int value, struct axis a, int size)
{
    long v = (long)(value - a.min) * (size - 1) / (a.max - a.min);
    return v < 0 ? 0 : v >= size ? size - 1 : (int)v;
}

int main(int argc, char **argv)
{
    if (argc < 4) {
        fprintf(stderr, "usage: %s /dev/input/eventN width height\n", argv[0]);
        return 2;
    }
    int fd = open(argv[1], O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "open %s: %s\n", argv[1], strerror(errno));
        return 1;
    }
    int width = atoi(argv[2]), height = atoi(argv[3]);
    struct axis ax, ay;
    if (read_axis(fd, ABS_MT_POSITION_X, ABS_X, &ax) || read_axis(fd, ABS_MT_POSITION_Y, ABS_Y, &ay)) {
        fprintf(stderr, "no absolute axes on %s\n", argv[1]);
        return 1;
    }
    printf("i %d %d %d %d\n", ax.min, ax.max, ay.min, ay.max);
    fflush(stdout);

    int raw_x = 0, raw_y = 0, touching = 0, was_touching = 0, moved = 0;
    struct input_event ev;
    struct pollfd fds[2] = {{.fd = fd, .events = POLLIN}, {.fd = 0, .events = POLLIN}};
    for (;;) {
        // Exit when the port closes stdin, so no reader outlives the BEAM.
        if (poll(fds, 2, -1) < 0)
            continue;
        if (fds[1].revents) {
            char buf[64];
            if (read(0, buf, sizeof(buf)) <= 0)
                return 0;
        }
        if (!(fds[0].revents & POLLIN))
            continue;
        if (read(fd, &ev, sizeof(ev)) != sizeof(ev))
            break;
        if (ev.type == EV_ABS && (ev.code == ABS_MT_POSITION_X || ev.code == ABS_X)) {
            raw_x = ev.value;
            moved = 1;
        } else if (ev.type == EV_ABS && (ev.code == ABS_MT_POSITION_Y || ev.code == ABS_Y)) {
            raw_y = ev.value;
            moved = 1;
        } else if (ev.type == EV_KEY && ev.code == BTN_TOUCH) {
            touching = ev.value != 0;
        } else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
            int x = scale(raw_x, ax, width), y = scale(raw_y, ay, height);
            if (touching && !was_touching)
                printf("d %d %d\n", x, y);
            else if (touching && moved)
                printf("m %d %d\n", x, y);
            else if (!touching && was_touching)
                printf("u %d %d\n", x, y);
            fflush(stdout);
            was_touching = touching;
            moved = 0;
        }
    }
    return 0;
}
