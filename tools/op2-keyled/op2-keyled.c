/*
 * op2-keyled: visible key feedback on the OnePlus 2 while the screen is
 * not driven by a real display stack yet. Opens all /dev/input/event*
 * devices, checks for EV_KEY capability (poll), flashes the notification
 * LED in a different colour per key and prints each event to stdout.
 *
 * Volume up blue, volume down green, power red, alert slider top yellow,
 * middle cyan, bottom purple (KEY_F13 / release / KEY_F15, see the DTS),
 * anything else white. Written by the helper LLM, slider codes adapted.
 *
 * LED: /sys/class/leds/op2:{red,green,blue}/brightness (0-255).
 * The red LED has the 'heartbeat' trigger: save it and write 'none'
 * in 'trigger' before using it, restore it at exit.
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/input-event-codes.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define LED "/sys/class/leds/op2:%s/brightness"

static int led_fd[3];
static int led_on[3];
static char red_trigger_saved[32];

static void led_init(void)
{
	const char *c[3] = {"red", "green", "blue"};
	for (int i = 0; i < 3; i++) {
		char p[64];
		snprintf(p, sizeof(p), LED, c[i]);
		led_fd[i] = open(p, O_WRONLY);
	}
	int tfd = open("/sys/class/leds/op2:red/trigger", O_RDWR);
	if (tfd >= 0) {
		ssize_t n = read(tfd, red_trigger_saved, sizeof(red_trigger_saved) - 1);
		if (n > 0) {
			red_trigger_saved[n] = 0;
			for (char *q = red_trigger_saved; *q; q++) if (*q == '\n') *q = 0;
		}
		write(tfd, "none", 5);
		close(tfd);
	}
}

static void led_set(int r, int g, int b)
{
	if (r == led_on[0] && g == led_on[1] && b == led_on[2]) return;
	if (led_fd[0] >= 0) { write(led_fd[0], r ? "255" : "0", r ? 3 : 1); led_on[0] = r; }
	if (led_fd[1] >= 0) { write(led_fd[1], g ? "255" : "0", g ? 3 : 1); led_on[1] = g; }
	if (led_fd[2] >= 0) { write(led_fd[2], b ? "255" : "0", b ? 3 : 1); led_on[2] = b; }
}

static void flash(int r, int g, int b)
{
	led_set(r, g, b);
	usleep(100000);
	led_set(0, 0, 0);
}

static void restore_red_trigger(void)
{
	led_set(0, 0, 0);
	int tfd = open("/sys/class/leds/op2:red/trigger", O_RDWR);
	if (tfd >= 0) {
		write(tfd, red_trigger_saved, strlen(red_trigger_saved));
		close(tfd);
	}
}

static void sig_handler(int signum)
{
	restore_red_trigger();
	exit(0);
}

int main(int argc, char **argv)
{
	struct pollfd fds[16];
	int nfds = 0;
	char names[16][128];

	signal(SIGINT, sig_handler);
	signal(SIGTERM, sig_handler);

	for (int i = 0; i < 16; i++) {
		char path[64];
		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		int f = open(path, O_RDONLY | O_NONBLOCK);
		if (f < 0) continue;

		unsigned char evbit[(EV_CNT + 7) / 8];
		if (ioctl(f, EVIOCGBIT(0, sizeof(evbit)), evbit) < 0 || !(evbit[EV_KEY / 8] & (1 << (EV_KEY % 8)))) {
			close(f); continue;
		}

		names[nfds][0] = 0;
		ioctl(f, EVIOCGNAME(sizeof(names[nfds])), names[nfds]);
		fds[nfds].fd = f;
		fds[nfds].events = POLLIN;
		printf("op2-keyled: monitoring %s (%s)\n", path, names[nfds]); fflush(stdout);
		nfds++;
	}

	if (nfds == 0) { fprintf(stderr, "op2-keyled: no devices with EV_KEY\n"); return 1; }
	led_init();

	struct input_event ev;
	while (1) {
		if (poll(fds, nfds, -1) < 0) break;
		for (int i = 0; i < nfds; i++) {
			if (!(fds[i].revents & POLLIN)) continue;
			while (read(fds[i].fd, &ev, sizeof(ev)) == sizeof(ev)) {
				if (ev.type != EV_KEY || ev.value == 2) continue;
				if (ev.code >= BTN_MISC && ev.code < KEY_OK) continue; /* touch/buttons: op2-touchled */
				printf("%s: key %d (0x%x) %s\n", names[i], ev.code, ev.code, ev.value ? "down" : "up"); fflush(stdout);
				/* alert slider: an end position is a held key,
				 * leaving it (release) means middle */
				if (!ev.value) {
					if (ev.code == KEY_F13 || ev.code == KEY_F15)
						flash(0, 1, 1);	/* cyan: middle */
					continue;
				}
				switch (ev.code) {
				case KEY_VOLUMEUP:   flash(0, 0, 1); break; /* blue */
				case KEY_VOLUMEDOWN: flash(0, 1, 0); break; /* green */
				case KEY_POWER:      flash(1, 0, 0); break; /* red */
				case KEY_F13:        flash(1, 1, 0); break; /* yellow: slider top */
				case KEY_F15:        flash(1, 0, 1); break; /* purple: slider bottom */
				default:             flash(1, 1, 1); break; /* white */
				}
			}
		}
	}
	restore_red_trigger();
	return 0;
}
