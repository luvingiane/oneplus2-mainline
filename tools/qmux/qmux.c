/* Minimal QMUX client for a WWAN QMI port (/dev/wwan0qmi0 from rpmsg_wwan_ctrl, DATA5_CNTL).
 *   qmux <dev> <service> <msg_id hex> [type:hexvalue ...]
 * Allocates a client id through CTL, sends one request, prints every TLV of the responses/indications
 * for WAIT seconds (default 3), then releases the client id. service: decimal (1 WDS, 2 DMS, 3 NAS, 5 WMS, 11 UIM).
 *   qmux <dev> provision   : activate the primary GW provisioning session on the first USIM app (UIM 0x0038)
 *   qmux <dev> online      : DMS Set Operating Mode = online
 * Build: scripts/build-qmux.sh */
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int fd;
static uint8_t txn;

static int build(uint8_t *b, uint8_t svc, uint8_t cid, unsigned msg, int argc, char **argv)
{
	unsigned n = 0, o;
	b[n++] = 0x01; n += 2; b[n++] = 0x00; b[n++] = svc; b[n++] = cid;
	b[n++] = 0x00;				/* QMI flags: request */
	if (svc == 0) b[n++] = ++txn; else { b[n++] = ++txn; b[n++] = 0; }
	b[n++] = msg & 0xff; b[n++] = msg >> 8;
	o = n; n += 2;
	for (int i = 0; i < argc; i++) {
		unsigned t = strtoul(argv[i], 0, 16);
		const char *h = strchr(argv[i], ':') + 1;
		unsigned len = strlen(h) / 2;
		b[n++] = t; b[n++] = len & 0xff; b[n++] = len >> 8;
		for (unsigned k = 0; k < len; k++) { unsigned v; sscanf(h + 2 * k, "%2x", &v); b[n++] = v; }
	}
	unsigned plen = n - o - 2;
	b[o] = plen & 0xff; b[o + 1] = plen >> 8;
	b[1] = (n - 1) & 0xff; b[2] = (n - 1) >> 8;
	return n;
}

static int rx(uint8_t *r, int ms, int quiet, unsigned *svc_out, unsigned *msg_out)
{
	struct pollfd p = { fd, POLLIN, 0 };
	if (poll(&p, 1, ms) <= 0) return -1;
	int n = read(fd, r, 2048);
	if (n < 12) return -2;
	unsigned svc = r[4], cid = r[5], flags = r[6];
	unsigned msg;
	unsigned txn_len = svc == 0 ? 1 : 2;
	unsigned mo = 7 + txn_len;
	msg = r[mo] | r[mo + 1] << 8;
	unsigned plen = r[mo + 2] | r[mo + 3] << 8;
	if (svc_out) *svc_out = svc;
	if (msg_out) *msg_out = msg;
	if (!quiet) {
		printf("svc=%u cid=%u %s msg=0x%04x len=%u\n", svc, cid, svc == 0 ? (flags & 2 ? "IND" : "RESP") : (flags & 4 ? "IND" : "RESP"), msg, plen);
		for (unsigned o = mo + 4; o + 3 <= (unsigned)n && o < mo + 4 + plen;) {
			unsigned t = r[o], l = r[o + 1] | r[o + 2] << 8;
			printf("  tlv 0x%02x len %u:", t, l);
			for (unsigned k = 0; k < l && k < 128; k++) printf(" %02x", r[o + 3 + k]);
			if (t == 0x02 && msg != 0 && l == 4) printf("  [result=%u error=%u]", r[o+3] | r[o+4] << 8, r[o+5] | r[o+6] << 8);
			putchar('\n');
			o += 3 + l;
		}
	}
	return n;
}


/* send one request to a service and return the response payload offset in r (or -1) */
static int transact(uint8_t svc, uint8_t cid, unsigned msg, int targc, char **targv, uint8_t *r, unsigned *plen)
{
	uint8_t b[2048];
	int n = build(b, svc, cid, msg, targc, targv);
	if (write(fd, b, n) != n) return -1;
	for (int i = 0; i < 5; i++) {
		int k = rx(r, 3000, 1, 0, 0);
		if (k < 0) return -1;
		if (r[4] != svc) continue;
		unsigned mo = 7 + (svc == 0 ? 1 : 2);
		if ((unsigned)(r[mo] | r[mo + 1] << 8) != msg) continue;
		*plen = r[mo + 2] | r[mo + 3] << 8;
		return mo + 4;
	}
	return -1;
}

static int alloc_cid(uint8_t svc)
{
	uint8_t r[2048]; unsigned pl; char tl[16]; char *t[1] = { tl };
	snprintf(tl, sizeof tl, "01:%02x", svc);
	int o = transact(0, 0, 0x0022, 1, t, r, &pl);
	if (o < 0) return -1;
	for (unsigned e = o; e + 3 <= o + pl;) {
		unsigned ty = r[e], l = r[e + 1] | r[e + 2] << 8;
		if (ty == 0x01 && l == 2 && r[e + 3] == svc) return r[e + 4];
		e += 3 + l;
	}
	return -1;
}

static int cmd_online(void)
{
	uint8_t r[2048]; unsigned pl; char *t[1] = { "01:00" };
	int cid = alloc_cid(2);
	if (cid < 0) { puts("no DMS client"); return 2; }
	int o = transact(2, cid, 0x002e, 1, t, r, &pl);
	printf("DMS set operating mode online: %s\n", o < 0 ? "no response" : "sent");
	return o < 0;
}

static int cmd_provision(void)
{
	uint8_t r[2048]; unsigned pl;
	int cid = alloc_cid(11);
	if (cid < 0) { puts("no UIM client"); return 2; }
	int o = transact(11, cid, 0x002f, 0, NULL, r, &pl);
	if (o < 0) { puts("no card status"); return 2; }
	for (unsigned e = o; e + 3 <= o + pl;) {
		unsigned ty = r[e], l = r[e + 1] | r[e + 2] << 8;
		if (ty == 0x10) {
			uint8_t *d = r + e + 3; unsigned i = 8, slots = d[i++];
			for (unsigned sl = 0; sl < slots; sl++) {
				i += 5; unsigned napps = d[i++];
				for (unsigned a = 0; a < napps; a++) {
					unsigned type = d[i], st = d[i + 1], alen = d[i + 6];
					uint8_t *aid = d + i + 7;
					i += 7 + alen + 7;
					if (type == 2) {
						char tl2[80], tl1[16], *t[2] = { tl1, tl2 };
						snprintf(tl1, sizeof tl1, "01:0001");
						int p = snprintf(tl2, sizeof tl2, "10:%02x%02x", sl + 1, alen);
						for (unsigned k = 0; k < alen && p < 70; k++) p += snprintf(tl2 + p, sizeof tl2 - p, "%02x", aid[k]);
						int q = transact(11, cid, 0x0038, 2, t, r, &pl);
						printf("USIM app state %u -> provisioning %s\n", st, q < 0 ? "no response" : "sent");
						return q < 0;
					}
				}
			}
		}
		e += 3 + l;
	}
	puts("no USIM app found");
	return 2;
}

int main(int argc, char **argv)
{
	if (argc < 3) { fprintf(stderr, "usage: %s dev service msg_id [type:hexvalue ...] | dev provision | dev online\n", argv[0]); return 1; }
	fd = open(argv[1], O_RDWR);
	if (fd < 0) { perror("open"); return 1; }
	if (!strcmp(argv[2], "provision")) return cmd_provision();
	if (!strcmp(argv[2], "online")) return cmd_online();
	if (argc < 4) { fprintf(stderr, "usage: %s dev service msg_id [type:hexvalue ...]\n", argv[0]); return 1; }
	unsigned svc = strtoul(argv[2], 0, 0), msg = strtoul(argv[3], 0, 16);
	uint8_t b[2048], r[2048];
	int n;
	uint8_t cid = 0;
	if (svc) {
		char *t[1]; char tl[16]; snprintf(tl, sizeof tl, "01:%02x", svc); t[0] = tl;
		n = build(b, 0, 0, 0x0022, 1, t);
		if (write(fd, b, n) != n) { perror("write ctl"); return 1; }
		for (int i = 0; i < 5; i++) {
			int k = rx(r, 3000, 1, 0, 0);
			if (k < 0) { puts("(timeout allocating CID)"); return 2; }
			for (unsigned o = 7 + 1 + 4; o + 3 <= (unsigned)k;) {
				unsigned ty = r[o], l = r[o + 1] | r[o + 2] << 8;
				if (ty == 0x01 && l == 2 && r[o + 3] == svc) cid = r[o + 4];
				if (ty == 0x02 && l == 4 && (r[o+3] | r[o+4] << 8)) printf("CTL allocate error %u\n", r[o+5] | r[o+6] << 8);
				o += 3 + l;
			}
			if (cid) break;
		}
		if (!cid) { puts("no client id"); return 2; }
		printf("client id %u for service %u\n", cid, svc);
	}
	n = build(b, svc, cid, msg, argc - 4, argv + 4);
	if (write(fd, b, n) != n) { perror("write"); return 1; }
	int wait = getenv("WAIT") ? (int)(atof(getenv("WAIT")) * 1000) : 3000;
	while (rx(r, wait, 0, 0, 0) >= 0)
		;
	if (svc) {
		char tl[16]; char *t[1] = { tl }; snprintf(tl, sizeof tl, "01:%02x%02x", svc, cid);
		n = build(b, 0, 0, 0x0023, 1, t);
		write(fd, b, n);
		rx(r, 500, 1, 0, 0);
	}
	return 0;
}
