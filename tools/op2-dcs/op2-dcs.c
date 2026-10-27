/*
 * op2-dcs: send DSI commands to the OnePlus 2 panel through the DSI0
 * controller's command DMA, on the link the bootloader left running (no DRM
 * driver). Registers poked through /dev/mem; the command buffer is a physical
 * page inside the reserved splash region (the MDP SMMU is bypassed in this
 * state, as the bootloader uses it: DMA_BASE is physical).
 *
 *   op2-dcs read <cmd> [n]              DCS read (BTA), print the answer
 *   op2-dcs send [-hs] <dtype> <b...>   one packet, data type in hex (05 15 39 29 ...)
 *   op2-dcs seq <file>                  lines "dtype wait_ms bytes...", '#' comments,
 *                                       "lp"/"hs" switch the mode, "reset" pulses
 *   op2-dcs reset                       panel reset: high 11 ms, low 2 ms, high 12 ms
 *
 * DSI0 6G registers (actual offset = mainline macro + 4): CMD_DMA_CTRL 0x3c,
 * DMA_BASE 0x48, DMA_LEN 0x4c, RDBK_DATA0 0x6c, TRIG_DMA 0x90,
 * INTR_CTRL 0x110 (CMD_DMA_DONE bit 0, BTA_DONE bit 20, W1C).
 * Panel reset: GPIO 78, TLMM io register 0xfd511004 + 0x10 * 78, bit 1.
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define DSI_BASE  0xfd998000UL
#define BUF_PHYS  0x03c00000UL	/* inside cont_splash_mem, past the framebuffer */
#define TLMM_IO78 (0xfd511004UL + 0x10 * 78)

#define CMD_DMA_CTRL 0x3c
#define DMA_BASE     0x48
#define DMA_LEN      0x4c
#define RDBK_DATA0   0x6c
#define TRIG_DMA     0x90
#define INTR_CTRL    0x110
#define LOW_POWER    0x04000000u
#define IRQ_DMA_DONE 0x00000001u
#define IRQ_BTA_DONE 0x00100000u
#define IRQ_STATUS   0x01110101u	/* status bits (W1C) of INTR_CTRL */

static volatile uint32_t *dsi, *tlmm;
static volatile uint8_t *buf;
static int lp = 1;

static void *map(int fd, unsigned long phys)
{
	void *p = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, phys & ~0xfffUL);
	if (p == MAP_FAILED) { perror("mmap"); exit(1); }
	return (uint8_t *)p + (phys & 0xfff);
}

static void msleep(int ms)
{
	struct timespec t = { ms / 1000, (ms % 1000) * 1000000L };
	nanosleep(&t, NULL);
}

static int is_long(int dt) { return dt == 0x39 || dt == 0x29 || dt == 0x0a; }

/* one packet; returns 0 on DMA done (and BTA done when bta) */
static int send(int dt, const uint8_t *b, int n, int bta)
{
	int lng = is_long(dt), len, i;
	buf[0] = lng ? n & 0xff : (n > 0 ? b[0] : 0);
	buf[1] = lng ? n >> 8 : (n > 1 ? b[1] : 0);
	buf[2] = dt;			/* virtual channel 0 */
	buf[3] = 0x80 | (lng ? 0x40 : 0) | (bta ? 0x20 : 0);
	len = 4;
	if (lng) {
		for (i = 0; i < n; i++)
			buf[4 + i] = b[i];
		len += n;
	}
	while (len & 3)
		buf[len++] = 0xff;
	__sync_synchronize();

	uint32_t ctl = dsi[CMD_DMA_CTRL / 4];
	dsi[CMD_DMA_CTRL / 4] = lp ? (ctl | LOW_POWER) : (ctl & ~LOW_POWER);
	uint32_t ic = dsi[INTR_CTRL / 4];
	dsi[INTR_CTRL / 4] = (ic & ~IRQ_STATUS) | IRQ_DMA_DONE | IRQ_BTA_DONE;	/* clear */
	dsi[DMA_BASE / 4] = BUF_PHYS;
	dsi[DMA_LEN / 4] = len;
	__sync_synchronize();
	dsi[TRIG_DMA / 4] = 1;

	uint32_t want = IRQ_DMA_DONE | (bta ? IRQ_BTA_DONE : 0);
	for (i = 0; i < 200; i++) {
		if ((dsi[INTR_CTRL / 4] & want) == want)
			break;
		msleep(1);
	}
	ic = dsi[INTR_CTRL / 4];
	dsi[INTR_CTRL / 4] = (ic & ~IRQ_STATUS) | (ic & want);
	if (i == 200) {
		fprintf(stderr, "dt %02x: timeout (INTR_CTRL %08x)\n", dt, ic);
		return -1;
	}
	return 0;
}

static void reset_panel(void)
{
	tlmm[0] = 2; msleep(11);	/* high */
	tlmm[0] = 0; msleep(2);		/* low  */
	tlmm[0] = 2; msleep(12);	/* high */
}

static int parse_bytes(char **v, int c, uint8_t *b)
{
	int n = 0;
	for (int i = 0; i < c && n < 256; i++)
		b[n++] = strtoul(v[i], NULL, 16);
	return n;
}

static int run_seq(const char *path)
{
	FILE *f = fopen(path, "r");
	char line[1024];
	int errs = 0, cnt = 0;
	if (!f) { perror(path); return 1; }
	while (fgets(line, sizeof(line), f)) {
		char *tok[260]; int nt = 0;
		char *p = strtok(line, " \t\r\n");
		while (p && nt < 260) { if (*p == '#') break; tok[nt++] = p; p = strtok(NULL, " \t\r\n"); }
		if (!nt) continue;
		if (!strcmp(tok[0], "lp")) { lp = 1; continue; }
		if (!strcmp(tok[0], "hs")) { lp = 0; continue; }
		if (!strcmp(tok[0], "reset")) { reset_panel(); continue; }
		if (nt < 2) continue;
		uint8_t b[256];
		int dt = strtoul(tok[0], NULL, 16), wait = atoi(tok[1]);
		int n = parse_bytes(tok + 2, nt - 2, b);
		if (send(dt, b, n, 0)) errs++;
		cnt++;
		if (wait) msleep(wait);
	}
	fclose(f);
	printf("sent %d packets, %d errors\n", cnt, errs);
	return errs ? 1 : 0;
}

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: op2-dcs read <cmd> [n] | send [-hs] <dtype> <bytes..> | seq <file> | reset\n");
		return 2;
	}
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	dsi = map(fd, DSI_BASE);
	buf = map(fd, BUF_PHYS);
	tlmm = map(fd, TLMM_IO78);

	if (!strcmp(argv[1], "reset")) { reset_panel(); return 0; }
	if (!strcmp(argv[1], "seq") && argc > 2) return run_seq(argv[2]);
	if (!strcmp(argv[1], "send") && argc > 2) {
		int a = 2;
		if (!strcmp(argv[a], "-hs")) { lp = 0; a++; }
		uint8_t b[256];
		int dt = strtoul(argv[a], NULL, 16);
		int n = parse_bytes(argv + a + 1, argc - a - 1, b);
		return send(dt, b, n, 0) ? 1 : 0;
	}
	if (!strcmp(argv[1], "read") && argc > 2) {
		uint8_t cmd = strtoul(argv[2], NULL, 16);
		int n = argc > 3 ? atoi(argv[3]) : 1;
		uint8_t mrs[2] = { n, 0 };
		if (send(0x37, mrs, 2, 0))	/* set maximum return packet size */
			return 1;
		for (int i = 0; i < 4; i++) dsi[(RDBK_DATA0 / 4) + i] = 0;
		if (send(0x06, &cmd, 1, 1))	/* DCS read, bus turnaround */
			return 1;
		printf("read %02x:", cmd);
		for (int i = 0; i < 4; i++) printf(" %08x", dsi[(RDBK_DATA0 / 4) + i]);
		printf("\n");
		return 0;
	}
	fprintf(stderr, "bad arguments\n");
	return 2;
}
