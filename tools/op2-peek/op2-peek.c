/*
 * op2-peek: dump 32-bit registers through /dev/mem, one "addr value" per line.
 *   op2-peek <start> <length> [<start> <length> ...]   (hex or decimal)
 * Reads one word at a time (volatile), so it is safe on device registers
 * that only allow 32-bit access. Do not point it at TrustZone-owned blocks
 * (the SMMUs at 0xfd9cc000 / 0xfd9d5000 reset the phone).
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	for (int i = 1; i + 1 < argc; i += 2) {
		unsigned long start = strtoul(argv[i], NULL, 0);
		unsigned long len = strtoul(argv[i + 1], NULL, 0);
		unsigned long base = start & ~0xfffUL;
		unsigned long maplen = ((start + len + 0xfff) & ~0xfffUL) - base;
		volatile uint32_t *m = mmap(NULL, maplen, PROT_READ, MAP_SHARED, fd, base);
		if (m == MAP_FAILED) { perror("mmap"); return 1; }
		for (unsigned long a = start; a < start + len; a += 4)
			printf("0x%08lx 0x%08x\n", a, m[(a - base) / 4]);
		munmap((void *)m, maplen);
	}
	return 0;
}
