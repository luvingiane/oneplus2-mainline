/*
 * op2-touchled: visible touch feedback on the OnePlus 2 while the screen is
 * not driven by a real display stack yet. Finds the touchscreen input device
 * by name and lights the notification LED's green channel while a finger is
 * down (BTN_TOUCH / tracking id), off when it is lifted. Also prints each
 * touch-down position.
 *   op2-touchled [name-substring]   (default "s3320")
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define LED "/sys/class/leds/op2:green/brightness"

static void led(int on)
{
	int fd = open(LED, O_WRONLY);
	if (fd >= 0) { write(fd, on ? "255" : "0", on ? 3 : 1); close(fd); }
}

int main(int argc, char **argv)
{
	const char *want = argc > 1 ? argv[1] : "s3320";
	char path[64], name[128];
	int fd = -1;
	for (int i = 0; i < 16 && fd < 0; i++) {
		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		int f = open(path, O_RDONLY);
		if (f < 0) continue;
		name[0] = 0;
		ioctl(f, EVIOCGNAME(sizeof(name)), name);
		if (strstr(name, want)) fd = f; else close(f);
	}
	if (fd < 0) { fprintf(stderr, "op2-touchled: no input device matching '%s'\n", want); return 1; }
	printf("op2-touchled: %s (%s)\n", path, name); fflush(stdout);
	struct input_event ev; int x = -1, y = -1, down = 0, n = 0;
	while (read(fd, &ev, sizeof(ev)) == sizeof(ev)) {
		if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_X) x = ev.value;
		if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_Y) y = ev.value;
		if (ev.type == EV_KEY && ev.code == BTN_TOUCH) {
			down = ev.value; led(down);
			if (!down) { printf("touch %d up\n", n); fflush(stdout); }
		}
		if (ev.type == EV_SYN && down == 1) {
			printf("touch %d down x=%d y=%d\n", ++n, x, y); fflush(stdout);
			down = 2;
		}
	}
	return 0;
}
