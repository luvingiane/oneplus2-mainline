/*
 * op2-kick: keep the OnePlus 2's command-mode panel showing the framebuffer.
 *
 * The bootloader leaves the MDP set up (CTL0 -> DSI0, VIG0 reading the splash
 * buffer at 0x03400000, which is also simpledrm's framebuffer). A command-mode
 * panel only takes a new frame when the MDP is told to send one: write 1 to
 * CTL0's CTL_START (MDSS 0xfd900000 + 0x2000 + 0x1c). This does that at a fixed
 * rate until the proper MDP5/DSI driver replaces it.
 *
 *   op2-kick [hz]     (default 30)
 *   op2-kick te       one frame per rising edge of the panel's TE (GPIO 10),
 *                     as a real driver would pace a command-mode panel
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define CTL0_PAGE 0xfd902000UL
#define CTL_TOP   0x14
#define CTL_START 0x1c
#define TLMM_IO10 (0xfd511004UL + 0x10 * 10)	/* panel TE, GPIO 10, IN = bit 0 */

int main(int argc, char **argv)
{
	int te = argc > 1 && argv[1][0] == 't';
	int hz = (argc > 1 && !te) ? atoi(argv[1]) : 30;
	if (hz < 1 || hz > 120)
		hz = 30;
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *ctl = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
				      MAP_SHARED, fd, CTL0_PAGE);
	if (ctl == MAP_FAILED) { perror("mmap"); return 1; }
	if (ctl[CTL_TOP / 4] == 0) {
		fprintf(stderr, "op2-kick: CTL0 not set up by the bootloader\n");
		return 1;
	}
	if (te) {
		volatile uint32_t *tlmm = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, TLMM_IO10 & ~0xfffUL);
		if (tlmm == MAP_FAILED) { perror("mmap tlmm"); return 1; }
		tlmm += (TLMM_IO10 & 0xfff) / 4;
		struct timespec us50 = { 0, 50000 };
		unsigned long frames = 0, misses = 0;
		for (;;) {
			int i;
			for (i = 0; i < 400 && (*tlmm & 1); i++) nanosleep(&us50, NULL);	/* wait low  */
			for (i = 0; i < 400 && !(*tlmm & 1); i++) nanosleep(&us50, NULL);	/* wait high */
			if (i == 400) misses++;
			ctl[CTL_START / 4] = 1;
			if (++frames % 600 == 0)
				fprintf(stderr, "op2-kick: %lu frames, %lu without TE\n", frames, misses);
		}
	}
	struct timespec t = { 0, 1000000000L / hz };
	for (;;) {
		ctl[CTL_START / 4] = 1;
		nanosleep(&t, NULL);
	}
}
