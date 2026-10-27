/*
 * op2-gpio: minimal GPIO character-device tool (uAPI v1 line handles).
 *   op2-gpio list                         chips: name, label, lines
 *   op2-gpio set <label-substr> <line> <0|1>   drive a line (0-based)
 * The line is released after setting; the pin keeps its output state.
 */
#include <fcntl.h>
#include <linux/gpio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int open_chip(const char *want, struct gpiochip_info *ci)
{
	for (int i = 0; i < 16; i++) {
		char p[32];
		snprintf(p, sizeof(p), "/dev/gpiochip%d", i);
		int fd = open(p, O_RDWR);
		if (fd < 0) continue;
		if (ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, ci) == 0) {
			if (!want) printf("%s %s %s %u\n", p, ci->name, ci->label, ci->lines);
			else if (strstr(ci->label, want)) return fd;
		}
		close(fd);
	}
	return -1;
}

int main(int argc, char **argv)
{
	struct gpiochip_info ci;
	if (argc >= 2 && !strcmp(argv[1], "list")) { open_chip(NULL, &ci); return 0; }
	if (argc != 5 || strcmp(argv[1], "set")) {
		fprintf(stderr, "usage: op2-gpio list | set <label-substr> <line> <0|1>\n");
		return 2;
	}
	int fd = open_chip(argv[2], &ci);
	if (fd < 0) { fprintf(stderr, "no chip matching '%s'\n", argv[2]); return 1; }
	struct gpiohandle_request req;
	memset(&req, 0, sizeof(req));
	req.lineoffsets[0] = atoi(argv[3]);
	req.lines = 1;
	req.flags = GPIOHANDLE_REQUEST_OUTPUT;
	req.default_values[0] = atoi(argv[4]) ? 1 : 0;
	strcpy(req.consumer_label, "op2-gpio");
	if (ioctl(fd, GPIO_GET_LINEHANDLE_IOCTL, &req) < 0) { perror("GPIO_GET_LINEHANDLE"); return 1; }
	close(req.fd);
	return 0;
}
