/* op2-fpc-touch: FPC1150B (HWID 0x150b) finger detection over spidev, from task 437's sequence of the GPL FPC driver
 * (ref/fpc1020_common.c: reset :355-363, setup 1150 :1021-1105, finger present query :1651-1693).
 * Usage: op2-fpc-touch [poll|irq] [seconds]   (default: poll 30)
 *   poll: cmd 0x20 FINGER_PRESENT_QUERY, wait COMMAND_DONE (reg 0x18 bit7), read reg 0xd4 zones; down if zones > 1
 *   irq : cmd 0x24 WAIT_FOR_FINGER_PRESENT, then reg 0x18 bit0 FINGER_DOWN; always read reg 0x1c to clear
 * Prints "DITO GIU'"/"DITO SU" transitions. Needs a kernel with OP2_FPC (spidev0.0) and gpio41/94/89 free. */
#include <fcntl.h>
#include <linux/gpio.h>
#include <linux/spi/spidev.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static int spi;
static int line(int chip, int n, int v, const char *name) {
	struct gpiohandle_request r;
	memset(&r, 0, sizeof(r));
	r.lineoffsets[0] = n; r.flags = GPIOHANDLE_REQUEST_OUTPUT; r.default_values[0] = v; r.lines = 1;
	snprintf(r.consumer_label, sizeof(r.consumer_label), "%s", name);
	if (ioctl(chip, GPIO_GET_LINEHANDLE_IOCTL, &r) < 0) { perror(name); exit(1); }
	return r.fd;
}
static void set(int fd, int v) { struct gpiohandle_data d; memset(&d, 0, sizeof(d)); d.values[0] = v; ioctl(fd, GPIOHANDLE_SET_LINE_VALUES_IOCTL, &d); }
static void us(long n) { struct timespec t = { n / 1000000, (n % 1000000) * 1000 }; nanosleep(&t, NULL); }

/* register read: t1 = [reg] (+1 dummy for 0x14 and 0xd0), t2 = n bytes (big-endian on the wire) */
static long rd(unsigned reg, int n) {
	unsigned char t1[2] = { reg, 0 }, rx[8] = { 0 };
	struct spi_ioc_transfer x[2] = {
		{ .tx_buf = (unsigned long)t1, .len = (reg == 0x14 || reg == 0xd0) ? 2 : 1, .speed_hz = 4800000 },
		{ .rx_buf = (unsigned long)rx, .len = n, .speed_hz = 4800000 } };
	if (ioctl(spi, SPI_IOC_MESSAGE(2), x) < 0) { perror("spi read"); exit(1); }
	long v = 0;
	for (int i = 0; i < n; i++) v = (v << 8) | rx[i];
	return v;
}
static void wr(unsigned reg, const unsigned char *d, int n) {
	unsigned char t1[1] = { reg };
	struct spi_ioc_transfer x[2] = {
		{ .tx_buf = (unsigned long)t1, .len = 1, .speed_hz = 4800000 },
		{ .tx_buf = (unsigned long)d, .len = n, .speed_hz = 4800000 } };
	if (ioctl(spi, SPI_IOC_MESSAGE(2), x) < 0) { perror("spi write"); exit(1); }
}
static void cmd(unsigned c) {
	unsigned char t = c;
	struct spi_ioc_transfer x = { .tx_buf = (unsigned long)&t, .len = 1, .speed_hz = 4800000 };
	if (ioctl(spi, SPI_IOC_MESSAGE(1), &x) < 0) { perror("spi cmd"); exit(1); }
}

int main(int argc, char **argv) {
	const char *mode = argc > 1 ? argv[1] : "poll";
	int secs = argc > 2 ? atoi(argv[2]) : 30, chip = -1;
	for (int i = 0; i < 8; i++) {
		char p[32]; struct gpiochip_info ci;
		snprintf(p, sizeof(p), "/dev/gpiochip%d", i);
		int fd = open(p, O_RDWR);
		if (fd < 0) continue;
		if (!ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, &ci) && ci.lines >= 140 && ci.lines <= 200) { chip = fd; break; }
		close(fd);
	}
	if (chip < 0) { fprintf(stderr, "no tlmm chip\n"); return 1; }
	int en = line(chip, 41, 1, "fpc-1v8"), fp = line(chip, 94, 1, "fpc-fp2050"), rst = line(chip, 89, 1, "fpc-reset");
	(void)en; (void)fp;
	spi = open("/dev/spidev0.0", O_RDWR);
	if (spi < 0) { perror("spidev"); return 1; }
	unsigned char m = SPI_MODE_0;
	ioctl(spi, SPI_IOC_WR_MODE, &m);
	usleep(20000);
	set(rst, 1); us(100); set(rst, 0); us(1000); set(rst, 1); us(1250);	/* driver's reset pulse */
	usleep(50000);
	printf("irq-after-reset reg 0x1c = 0x%02lx (expected 0xff)\n", rd(0x1c, 1));
	printf("HWID reg 0xfc = 0x%04lx\n", rd(0xfc, 2));
	/* FPC1150B setup (fpc1020_write_sensor_1150_setup) */
	static const unsigned char r90[] = { 0x09 }, r68[] = { 8, 8, 8, 8, 0x14, 0x14, 0x14, 0x14 }, r8c[] = { 0x02 },
		ra0[] = { 5, 5 }, ra8[] = { 0x0f, 0x0a }, r5c[] = { 0x0b }, rd8[] = { 0, 1, 0x20, 0x20 }, rdc[] = { 0x19, 1, 0, 1 };
	wr(0x90, r90, 1); wr(0x68, r68, 8); wr(0x8c, r8c, 1); wr(0xa0, ra0, 2); wr(0xa8, ra8, 2);
	wr(0x5c, r5c, 1); wr(0xd8, rd8, 4); wr(0xdc, rdc, 4);
	printf("FPC_STATUS reg 0x14 = 0x%02lx (expected 0x1e)\n", rd(0x14, 1));
	if (!strcmp(mode, "capture")) {	/* wait for a finger, then one 208x80 image to /tmp/finger.pgm (task 437: fpc1020_capture.c) */
		static const unsigned char crop[] = { 0x00, 0xd0, 0x00, 0x50 }, a8[] = { 0x0f, 0x1e }, a0[] = { 0x0a, 0x02 };
		wr(0x54, crop, 4); wr(0xa8, a8, 2); wr(0xa0, a0, 2);
		printf("metti il dito sul pad (%d s)\n", secs); fflush(stdout);
		time_t until = time(NULL) + secs; int present = 0;
		while (time(NULL) < until && !present) {
			rd(0x1c, 1); cmd(0x20);
			for (int i = 0; i < 25; i++) { usleep(5000); if (rd(0x18, 1) & 0x80) break; }
			present = __builtin_popcountl(rd(0xd4, 2) & 0x0fff) > 1;
			usleep(30000);
		}
		if (!present) { printf("nessun dito\n"); return 2; }
		usleep(100000);
		rd(0x1c, 1);
		cmd(0xc0);	/* CAPTURE_IMAGE */
		int ok = 0;
		for (int i = 0; i < 200 && !ok; i++) { usleep(5000); ok = (rd(0x18, 1) & 0x20) != 0; }
		printf("capture done: %s\n", ok ? "si" : "no (timeout)");
		static unsigned char img[16640], t1[2] = { 0xc4, 0x00 };
		struct spi_ioc_transfer x[2] = {
			{ .tx_buf = (unsigned long)t1, .len = 2, .speed_hz = 4800000 },
			{ .rx_buf = (unsigned long)img, .len = sizeof(img), .speed_hz = 4800000 } };
		if (ioctl(spi, SPI_IOC_MESSAGE(2), x) < 0) { perror("spi image"); return 1; }
		printf("irq reg 0x1c after read = 0x%02lx\n", rd(0x1c, 1));
		FILE *f = fopen("/tmp/finger.pgm", "wb");
		fprintf(f, "P5\n80 208\n255\n"); fwrite(img, 1, sizeof(img), f); fclose(f);
		long sum = 0; int mn = 255, mx = 0;
		for (unsigned i = 0; i < sizeof(img); i++) { sum += img[i]; if (img[i] < mn) mn = img[i]; if (img[i] > mx) mx = img[i]; }
		printf("image: mean %ld min %d max %d -> /tmp/finger.pgm\n", sum / (long)sizeof(img), mn, mx);
		return 0;
	}
	int down = 0; time_t end = time(NULL) + secs;
	printf("modo %s per %d s: tocca il pad home\n", mode, secs);
	fflush(stdout);
	while (time(NULL) < end) {
		int now = 0;
		rd(0x1c, 1);	/* clear */
		if (!strcmp(mode, "irq")) {
			cmd(0x24);
			for (int i = 0; i < 25; i++) { usleep(20000); long s = rd(0x18, 1); if (s & 1) { now = 1; break; } }
		} else {
			cmd(0x20);
			for (int i = 0; i < 25; i++) { usleep(5000); if (rd(0x18, 1) & 0x80) break; }
			long z = rd(0xd4, 2) & 0x0fff, st = rd(0x18, 1);
			now = __builtin_popcountl(z) > 1;
			static long lastz = -1;
			if (z != lastz) { printf("  zone mask 0x%03lx (reg18=0x%02lx, zone=%d)\n", z, st, __builtin_popcountl(z)); fflush(stdout); lastz = z; }
		}
		if (now != down) { down = now; printf("%s\n", down ? "DITO GIU'" : "DITO SU"); fflush(stdout); }
		usleep(20000);
	}
	printf("fine; stato finale %s\n", down ? "giu" : "su");
	return 0;
}
