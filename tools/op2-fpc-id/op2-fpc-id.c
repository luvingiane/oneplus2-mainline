/* op2-fpc-id: power up the OnePlus 2 FPC1020 (1V8_EN gpio41 high, reset gpio89 pulsed) and read its HWID
 * register (0xfc) over spidev. Experiment for compito 431: needs a kernel built with OP2_FPC and spidev.
 * Usage: op2-fpc-id [/dev/gpiochipN] [/dev/spidevB.C]   (defaults: /dev/gpiochip0, /dev/spidev0.0)
 * Prints the two HWID bytes; expected 0x020a/0x021a/0x021b/0x150a/0x150b/0x150f (fpc1020_regs.h:43). */
#include <fcntl.h>
#include <linux/gpio.h>
#include <linux/spi/spidev.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int line(int chip, int n, int v, const char *name) {
	struct gpiohandle_request r;
	memset(&r, 0, sizeof(r));
	r.lineoffsets[0] = n;
	r.flags = GPIOHANDLE_REQUEST_OUTPUT;
	r.default_values[0] = v;
	r.lines = 1;
	snprintf(r.consumer_label, sizeof(r.consumer_label), "%s", name);
	if (ioctl(chip, GPIO_GET_LINEHANDLE_IOCTL, &r) < 0) { perror(name); return -1; }
	return r.fd;
}

static void set(int fd, int v) {
	struct gpiohandle_data d;
	memset(&d, 0, sizeof(d));
	d.values[0] = v;
	ioctl(fd, GPIOHANDLE_SET_LINE_VALUES_IOCTL, &d);
}

int main(int argc, char **argv) {
	int chip = -1;
	for (int i = 0; i < 8 && argc <= 1; i++) {	/* the TLMM: the chip with the most lines (146+), label "...pinctrl" */
		char path[32];
		struct gpiochip_info ci;
		snprintf(path, sizeof(path), "/dev/gpiochip%d", i);
		int fd = open(path, O_RDWR);
		if (fd < 0) continue;
		if (!ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, &ci) && ci.lines >= 140 && ci.lines <= 200) {
			fprintf(stderr, "using %s (%s, %u lines)\n", path, ci.label, ci.lines);
			chip = fd;
			break;
		}
		close(fd);
	}
	if (argc > 1) chip = open(argv[1], O_RDWR);
	if (chip < 0) { perror("gpiochip"); return 1; }
	int en = line(chip, 41, 1, "fpc-1v8");
	int fp2050 = line(chip, 94, 1, "fpc-fp2050");	/* stock fpc,gpio_fp2050 = 0x5e = 94 (power IC) */
	int rst = line(chip, 89, 0, "fpc-reset");
	if (en < 0 || rst < 0 || fp2050 < 0) return 1;
	usleep(20000);
	set(rst, 1);	/* release reset (active low) */
	usleep(100000);
	int spi = open(argc > 2 ? argv[2] : "/dev/spidev0.0", O_RDWR);
	if (spi < 0) { perror("spidev"); return 1; }
	unsigned char tx[4] = { 0xfc, 0, 0, 0 }, rx[4] = { 0 };
	struct spi_ioc_transfer t = { .tx_buf = (unsigned long)tx, .rx_buf = (unsigned long)rx, .len = 4, .speed_hz = 4800000 };
	unsigned char mode = SPI_MODE_0;
	ioctl(spi, SPI_IOC_WR_MODE, &mode);
	if (ioctl(spi, SPI_IOC_MESSAGE(1), &t) < 0) { perror("spi xfer"); return 1; }
	printf("rx: %02x %02x %02x %02x  -> HWID (bytes 1,2: byte 0 is the command echo) = 0x%02x%02x\n", rx[0], rx[1], rx[2], rx[3], rx[1], rx[2]);
	set(en, 1);
	return 0;
}
