/* op2-fpcd: the OnePlus 2's home key = the FPC1150B pad. Powers/resets the sensor, arms its finger detect
 * (cmd 0x24, rising edge on gpio90), and reports a touch as KEY_HOMEPAGE through uinput (ztMETRO: tap = Start,
 * long = switcher). Sequence from task 437's report (GPL FPC driver: ref/fpc1020_common.c). Needs a kernel with
 * OP2_FPC (spidev0.0, gpio 85-88 free) and CONFIG_INPUT_UINPUT. Runs as root.
 * Usage: op2-fpcd [-v]  (-v: log every event to stderr) */
#include <errno.h>
#include <fcntl.h>
#include <linux/gpio.h>
#include <linux/input.h>
#include <linux/spi/spidev.h>
#include <linux/uinput.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static int spi = -1, verbose;
static void us(long n) { struct timespec t = { n / 1000000, (n % 1000000) * 1000 }; nanosleep(&t, NULL); }
#define LOG(...) do { if (verbose) { fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static int out_line(int chip, int n, int v, const char *name) {
	struct gpiohandle_request r;
	memset(&r, 0, sizeof(r));
	r.lineoffsets[0] = n; r.flags = GPIOHANDLE_REQUEST_OUTPUT; r.default_values[0] = v; r.lines = 1;
	snprintf(r.consumer_label, sizeof(r.consumer_label), "%s", name);
	return ioctl(chip, GPIO_GET_LINEHANDLE_IOCTL, &r) < 0 ? -1 : r.fd;
}
static void set(int fd, int v) { struct gpiohandle_data d; memset(&d, 0, sizeof(d)); d.values[0] = v; ioctl(fd, GPIOHANDLE_SET_LINE_VALUES_IOCTL, &d); }

static int xfer2(const unsigned char *t1, int l1, unsigned char *rx, const unsigned char *tx, int n) {
	struct spi_ioc_transfer x[2];
	memset(x, 0, sizeof(x));
	x[0].tx_buf = (unsigned long)t1; x[0].len = l1; x[0].speed_hz = 4800000;
	x[1].rx_buf = (unsigned long)rx; x[1].tx_buf = (unsigned long)tx; x[1].len = n; x[1].speed_hz = 4800000;
	return ioctl(spi, SPI_IOC_MESSAGE(2), x);
}
static long rd(unsigned reg, int n) {
	unsigned char t1[2] = { reg, 0 }, rx[8] = { 0 };
	if (xfer2(t1, (reg == 0x14 || reg == 0xd0) ? 2 : 1, rx, NULL, n) < 0) return -1;
	long v = 0;
	for (int i = 0; i < n; i++) v = (v << 8) | rx[i];
	return v;
}
static int wr(unsigned reg, const unsigned char *d, int n) { unsigned char t1[1] = { reg }; return xfer2(t1, 1, NULL, d, n) < 0 ? -1 : 0; }
static int cmd(unsigned c) {
	unsigned char t = c;
	struct spi_ioc_transfer x;
	memset(&x, 0, sizeof(x));
	x.tx_buf = (unsigned long)&t; x.len = 1; x.speed_hz = 4800000;
	return ioctl(spi, SPI_IOC_MESSAGE(1), &x);
}

static int find_tlmm(void) {
	for (int i = 0; i < 8; i++) {
		char p[32]; struct gpiochip_info ci;
		snprintf(p, sizeof(p), "/dev/gpiochip%d", i);
		int fd = open(p, O_RDWR);
		if (fd < 0) continue;
		if (!ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, &ci) && ci.lines >= 140 && ci.lines <= 200) return fd;
		close(fd);
	}
	return -1;
}

static int sensor_init(int rst) {
	set(rst, 1); us(100); set(rst, 0); us(1000); set(rst, 1); us(1250);
	us(50000);
	if (rd(0x1c, 1) != 0xff) { LOG("no reboot flag after reset"); return -1; }
	long id = rd(0xfc, 2);
	LOG("HWID 0x%04lx", id);
	if (id != 0x150a && id != 0x150b && id != 0x150f) return -1;	/* FPC1150A/B/F share one setup (GPL driver fpc1020_common.c:711-713); A has 0x150b, B 0x150f */
	static const unsigned char r90[] = { 0x09 }, r68[] = { 8, 8, 8, 8, 0x14, 0x14, 0x14, 0x14 }, r8c[] = { 0x02 },
		ra0[] = { 5, 5 }, ra8[] = { 0x0f, 0x0a }, r5c[] = { 0x0b }, rd8[] = { 0, 1, 0x20, 0x20 }, rdc[] = { 0x19, 1, 0, 1 };
	if (wr(0x90, r90, 1) || wr(0x68, r68, 8) || wr(0x8c, r8c, 1) || wr(0xa0, ra0, 2) || wr(0xa8, ra8, 2) ||
	    wr(0x5c, r5c, 1) || wr(0xd8, rd8, 4) || wr(0xdc, rdc, 4)) return -1;
	return 0;
}

static int zones_down(void) {	/* finger present query: zones with a finger, > 1 = down */
	cmd(0x20);
	for (int i = 0; i < 25; i++) { us(5000); long s = rd(0x18, 1); if (s < 0) return -1; if (s & 0x80) break; }
	long z = rd(0xd4, 2);
	if (z < 0) return -1;
	return __builtin_popcountl(z & 0x0fff) > 1;
}

static int uinput_open(void) {
	int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
	if (fd < 0) fd = open("/dev/input/uinput", O_WRONLY | O_NONBLOCK);
	if (fd < 0) return -1;
	struct uinput_setup us_ = { .id = { .bustype = BUS_VIRTUAL, .vendor = 0x1d6b, .product = 0x0fc1, .version = 1 } };
	snprintf(us_.name, sizeof(us_.name), "op2 fingerprint home");
	ioctl(fd, UI_SET_EVBIT, EV_KEY); ioctl(fd, UI_SET_KEYBIT, KEY_HOMEPAGE); ioctl(fd, UI_SET_EVBIT, EV_SYN);
	if (ioctl(fd, UI_DEV_SETUP, &us_) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) return -1;
	return fd;
}
static void key(int fd, int v) {
	struct input_event e[2];
	memset(e, 0, sizeof(e));
	e[0].type = EV_KEY; e[0].code = KEY_HOMEPAGE; e[0].value = v;
	e[1].type = EV_SYN; e[1].code = SYN_REPORT;
	if (write(fd, e, sizeof(e)) < 0) perror("uinput write");
}

int main(int argc, char **argv) {
	verbose = argc > 1 && !strcmp(argv[1], "-v");
	int chip = find_tlmm();
	if (chip < 0) { fprintf(stderr, "no tlmm gpiochip\n"); return 1; }
	int en = out_line(chip, 41, 1, "fpc-1v8"), fp = out_line(chip, 94, 1, "fpc-fp2050"), rst = out_line(chip, 89, 1, "fpc-reset");
	if (en < 0 || fp < 0 || rst < 0) { fprintf(stderr, "gpio 41/94/89 busy\n"); return 1; }
	struct gpioevent_request er;
	memset(&er, 0, sizeof(er));
	er.lineoffset = 90; er.handleflags = GPIOHANDLE_REQUEST_INPUT; er.eventflags = GPIOEVENT_REQUEST_RISING_EDGE;
	snprintf(er.consumer_label, sizeof(er.consumer_label), "fpc-irq");
	if (ioctl(chip, GPIO_GET_LINEEVENT_IOCTL, &er) < 0) { perror("gpio90 event"); return 1; }
	int ev = er.fd;
	spi = -1;
	for (int i = 0; i < 60 && spi < 0; i++) { spi = open("/dev/spidev0.0", O_RDWR); if (spi < 0) sleep(1); }
	if (spi < 0) { perror("spidev0.0"); return 1; }
	unsigned char mode = SPI_MODE_0;
	ioctl(spi, SPI_IOC_WR_MODE, &mode);
	int ui = -1;
	for (int i = 0; i < 60 && ui < 0; i++) { ui = uinput_open(); if (ui < 0) sleep(1); }
	if (ui < 0) { perror("uinput"); return 1; }
	usleep(300000);
	for (;;) {
		if (sensor_init(rst) < 0) { LOG("init failed, retry in 3 s"); sleep(3); continue; }
		LOG("sensor ready, armed");
		int fails = 0;
		for (;;) {
			rd(0x1c, 1);	/* clear the interrupt, line goes low */
			cmd(0x24);	/* wait for finger present */
			struct pollfd p = { .fd = ev, .events = POLLIN };
			int r = poll(&p, 1, 3000);
			if (r > 0) {
				struct gpioevent_data d;
				if (read(ev, &d, sizeof(d)) < 0) continue;
				long s = rd(0x18, 1);
				LOG("irq, reg18=0x%02lx", s);
				if (s < 0) { if (++fails > 3) break; continue; }
				fails = 0;
				int down = zones_down();
				if (down != 1) { rd(0x1c, 1); continue; }	/* not a real touch */
				key(ui, 1);
				LOG("DOWN");
				int ups = 0;
				while (ups < 2) {
					us(30000);
					int z = zones_down();
					if (z < 0) break;
					ups = z ? 0 : ups + 1;
				}
				key(ui, 0);
				LOG("UP");
				us(60000);
			} else if (r < 0 && errno != EINTR) {
				break;
			} /* timeout: arm again */
		}
		LOG("spi errors, re-init");
		sleep(1);
	}
}
