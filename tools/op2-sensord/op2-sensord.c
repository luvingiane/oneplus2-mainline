/*
 * op2-sensord: the OnePlus 2's sensors (behind the ADSP sensor core) for ztMETRO.
 *
 * Replaces ztoscsf-sensord (the Galaxy S9's SSP hub) with the same contract:
 *   - publishes each sensor's last reading under /run/ztoscsf-sensors/
 *     (light, accel, gyro, mag, prox; light also as iio:device0/in_illuminance_input);
 *   - when auto brightness is on, turns lux into a goal and tells the shell
 *     ("brightness-auto N" on ztmetro.ctl); the light sensor is off while the screen is off.
 *
 * Lines on /run/ztoscsf-sensord.ctl (anyone may write):
 *	screen off | on
 *	auto on | off          (remembered)
 *	opentone on | off      (accepted and ignored: this sensor reports no colour temperature)
 *	watch NAME [MS]        also stream accel | gyro | mag | prox, for the next five seconds
 *	unwatch NAME
 *
 * The sensors are asked of SNS_SMGR (QMI service 256 v1 instance 50 on the ADSP, over QRTR) with
 * BUFFERING requests (the encoding is the one of the sdm660-mainline qcom_smgr driver). This needs the
 * sensor registry server (sns-reg) to be running, as the DSP waits for it.
 * Units published: light "lux 0 0 0 0 0"; accel milli-m/s2; gyro milli-rad/s; mag milli-gauss (unverified);
 * prox "raw near": raw counts and 1 when something is near (thresholds OP2_PROX_NEAR/OP2_PROX_FAR, defaults 400/250: to be calibrated on the phone); streamed while the screen is off.
 * The brightness code (lux -> goal) is taken from ztoscsf-sensord.c, with its AMOLED curve: the OnePlus 2
 * panel is an LCD, so the curve is a first guess.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <libqrtr.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define CTL	"/run/ztoscsf-sensord.ctl"
#define OUT	"/run/ztoscsf-sensors"
#define STATE	"/var/lib/ztoscsf-sensord/state"

static char root[128], ctl_path[192], out_path[192], state_path[192];

static void at(char *buf, size_t size, const char *path) {
	snprintf(buf, size, "%s%s", root, path);
}

static volatile sig_atomic_t stopping;
static bool screen_on = true, auto_on = true;
/* proximity: raw counts from which something is near, and below which it is gone (OP2_PROX_NEAR / OP2_PROX_FAR) */
static int prox_near_th = 400, prox_far_th = 250;
static bool prox_is_near;

static uint64_t now_ns(void) {
	struct timespec ts;
	clock_gettime(CLOCK_BOOTTIME, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static void publish(const char *name, const char *text) {
	char path[256], tmp[264];
	snprintf(path, sizeof(path), "%s/%s", out_path, name);
	snprintf(tmp, sizeof(tmp), "%s.new", path);
	FILE *f = fopen(tmp, "w");
	if (f) {
		fputs(text, f);
		fclose(f);
		rename(tmp, path);
	}
}

/* --- brightness -------------------------------------------------------- */

static double lux_smooth = -1;
static int goal = -1;	/* tenths of a percent L*; -1 before the first reading */

/* whether any shell took it */
static bool shell(const char *line) {
	bool sent = false;
	glob_t g;
	char pattern[192];
	at(pattern, sizeof(pattern), "/run/user/*/ztmetro.ctl");
	if (glob(pattern, 0, NULL, &g) == 0) {
		for (size_t i = 0; i < g.gl_pathc; i++) {
			int fd = open(g.gl_pathv[i], O_WRONLY | O_NONBLOCK);	/* no shell, no write */
			if (fd >= 0) {
				if (write(fd, line, strlen(line)) < 0) {
					/* the shell is busy; the next reading tries again */
				} else {
					sent = true;
				}
				close(fd);
			}
		}
	}
	globfree(&g);
	return sent;
}

/* The goal only: the shell walks to it at its own limited speed. A goal the
 * shell did not get (it is not up yet, at boot) is asked for again by the next
 * reading. */
static void brightness_show(int permille) {
	char line[40];
	goal = permille;
	snprintf(line, sizeof(line), "brightness-auto %d\n", permille);
	if (!shell(line)) {
		goal = -1;
	}
}

/* AMOLED brightness from ambient light: nits for the room, from Samsung's
 * auto table (framework-res) at its bins' centres, then as percent L* of the
 * panel's peak, which is what the shell's brightness means. PANEL_PEAK_NITS is
 * a model value: the panel has not been measured. It is one constant. */
#define PANEL_PEAK_NITS	400.0
#define AUTO_FLOOR_L	18.03	/* the panel's own floor: auto never darkens pixels */

static int lux_to_permille(double lux) {
	static const struct { double lux, nits; } curve[] = {
		{ 1, 10 }, { 7, 25 }, { 55, 110 }, { 700, 170 }, { 1400, 250 }, { 2500, 400 },
	};
	int n = sizeof(curve) / sizeof(curve[0]);
	double nits = curve[0].nits;
	if (lux >= curve[n - 1].lux) {
		nits = curve[n - 1].nits;
	} else if (lux > curve[0].lux) {
		for (int i = 1; i < n; i++) {
			if (lux <= curve[i].lux) {
				double t = (log10(lux) - log10(curve[i - 1].lux)) /
					(log10(curve[i].lux) - log10(curve[i - 1].lux));
				nits = curve[i - 1].nits + (curve[i].nits - curve[i - 1].nits) * t;
				break;
			}
		}
	}
	double l = 116.0 * cbrt(nits / PANEL_PEAK_NITS) - 16.0;
	if (l < AUTO_FLOOR_L) l = AUTO_FLOOR_L;
	if (l > 100.0) l = 100.0;
	return (int)lround(l * 10.0);
}

/* One reading a second, followed in log terms (as the eye sees it). The goal
 * moves only when the room has been different enough for long enough: a hand or
 * a shadow passing over the sensor does nothing, and darker waits longer than
 * brighter. The glide itself is the shell's. */
#define LIGHT_SMOOTH	0.35	/* share of each reading taken */
#define LIGHT_STEP	30	/* tenths of L* the goal must move by */
#define LIGHT_UP_NS	4000000000ULL
#define LIGHT_DOWN_NS	8000000000ULL

static int light_way;		/* the way the room is pulling: -1, 0, 1 */
static uint64_t light_since;

static void light_decide(void) {
	if (!auto_on || !screen_on || lux_smooth < 0) {
		return;
	}
	int target = lux_to_permille(pow(10.0, lux_smooth) - 1.0);
	if (goal < 0) {	/* the first since the screen came on, or the shell came up */
		light_way = 0;
		brightness_show(target);
		return;
	}
	int way = abs(target - goal) < LIGHT_STEP ? 0 : target > goal ? 1 : -1;
	if (way != light_way) {
		light_way = way;
		light_since = now_ns();
	}
	if (way != 0 && now_ns() - light_since >= (way > 0 ? LIGHT_UP_NS : LIGHT_DOWN_NS)) {
		light_way = 0;
		brightness_show(target);
	}
}

static void light(uint32_t lux) {
	double l = log10((double)lux + 1.0);
	lux_smooth = lux_smooth < 0 ? l : lux_smooth + (l - lux_smooth) * LIGHT_SMOOTH;
	light_decide();
}


/* --- the sensors, asked of SNS_SMGR ---------------------------------------- */

#define SMGR_SERVICE	256
#define SMGR_INSTANCE	50
#define MSG_BUFFERING	0x21
#define MSG_BUFFERING_IND	0x22

static struct sensor {
	const char *name;
	int id, dtype, hz;
	bool on, wanted;
	time_t until;	/* a watch runs out */
} sensors[] = {
	{ "light", 0x28, 1, 2 },
	{ "accel", 0x00, 0, 5 },
	{ "gyro", 0x0a, 0, 5 },
	{ "mag", 0x14, 0, 5 },
	{ "prox", 0x28, 0, 5 },
};
#define N_SENSORS (int)(sizeof(sensors) / sizeof(sensors[0]))

static int sock = -1;
static uint32_t smgr_node, smgr_port;
static bool smgr_up;
static uint16_t txn;

static bool smgr_find(void) {
	char buf[256];
	struct sockaddr_qrtr sq;
	socklen_t sl;
	struct qrtr_packet pkt;
	if (sock < 0) {
		sock = qrtr_open(0);
		if (sock < 0) {
			return false;
		}
	}
	if (qrtr_new_lookup(sock, SMGR_SERVICE, 1, SMGR_INSTANCE) < 0) {
		return false;
	}
	while (qrtr_poll(sock, 500) > 0) {
		sl = sizeof(sq);
		ssize_t n = recvfrom(sock, buf, sizeof(buf), 0, (struct sockaddr *)&sq, &sl);
		if (n <= 0 || qrtr_decode(&pkt, buf, n, &sq) < 0) {
			continue;
		}
		if (pkt.type == QRTR_TYPE_NEW_SERVER && pkt.service == SMGR_SERVICE && pkt.node) {
			smgr_node = pkt.node;
			smgr_port = pkt.port;
			return true;
		}
	}
	return false;
}

static void smgr_buffering(int index, bool add) {
	const struct sensor *s = &sensors[index];
	uint8_t m[64];
	unsigned n = 7;
	uint32_t rate = (uint32_t)s->hz * 65536;
	m[n++] = 0x01; m[n++] = 1; m[n++] = 0; m[n++] = index;			/* report id */
	m[n++] = 0x02; m[n++] = 1; m[n++] = 0; m[n++] = add ? 1 : 2;		/* add / delete */
	m[n++] = 0x03; m[n++] = 4; m[n++] = 0;
	memcpy(m + n, &rate, 4); n += 4;
	if (add) {
		m[n++] = 0x04; m[n++] = 9; m[n++] = 0;
		m[n++] = 1; m[n++] = s->id; m[n++] = s->dtype;
		m[n++] = 3; m[n++] = 0; m[n++] = s->hz; m[n++] = 0; m[n++] = 1; m[n++] = 0;
	} else {
		m[n++] = 0x04; m[n++] = 1; m[n++] = 0; m[n++] = 0;
	}
	m[0] = 0; m[1] = ++txn & 0xff; m[2] = txn >> 8; m[3] = MSG_BUFFERING; m[4] = 0;
	m[5] = (n - 7) & 0xff; m[6] = (n - 7) >> 8;
	if (qrtr_sendto(sock, smgr_node, smgr_port, m, n) < 0) {
		fprintf(stderr, "op2-sensord: send failed: %s\n", strerror(errno));
	}
}

static void sensor_set(int i, bool on) {
	if (!smgr_up || on == sensors[i].on) {
		return;
	}
	sensors[i].on = on;
	smgr_buffering(i, on);
}

static void sensors_apply(void) {
	for (int i = 0; i < N_SENSORS; i++) {
		/* the proximity sensor is the one that runs with the screen OFF: the shell asks it whether the phone
		 * is in a pocket before a wake that nobody asked for (a call, a touched key) is allowed to light it */
		bool want = i == 0 ? screen_on && (auto_on || sensors[0].wanted) :
			i == 4 ? sensors[i].wanted || !screen_on : screen_on && sensors[i].wanted;
		sensor_set(i, want);
	}
}

static void status(void) {
	char text[64];
	snprintf(text, sizeof(text), "auto=%s\nscreen=%s\nopentone=off\n", auto_on ? "on" : "off",
		screen_on ? "on" : "off");
	publish("status", text);
}

static void record(int i, const int32_t *v) {
	char text[96];
	switch (i) {
	case 0: {	/* light: Q16 lux */
		uint32_t lux = v[0] < 0 ? 0 : (uint32_t)(v[0] / 65536);
		static uint32_t last = ~0u;
		light(lux);
		uint32_t step = last == ~0u ? 0 : last / 20 < 2 ? 2 : last / 20;
		if (last != ~0u && (lux > last ? lux - last : last - lux) < step) {
			return;
		}
		last = lux;
		snprintf(text, sizeof(text), "%u 0 0 0 0 0\n", lux);
		publish("light", text);
		snprintf(text, sizeof(text), "%u\n", lux);
		publish("iio:device0/in_illuminance_input", text);
		return;
	}
	case 4:
		/* raw counts (the TMD277x's 10 bits: 1023 is saturated) and, second, whether something is near,
		 * with a gap between the two thresholds so a reading that wobbles does not flicker */
		if (v[0] >= prox_near_th) {
			prox_is_near = true;
		} else if (v[0] <= prox_far_th) {
			prox_is_near = false;
		}
		snprintf(text, sizeof(text), "%d %d\n", v[0], prox_is_near ? 1 : 0);
		break;
	default:
		snprintf(text, sizeof(text), "%d %d %d\n", (int)((int64_t)v[0] * 1000 / 65536),
			(int)((int64_t)v[1] * 1000 / 65536), (int)((int64_t)v[2] * 1000 / 65536));
	}
	publish(sensors[i].name, text);
}

static void indication(const uint8_t *b, int len) {
	if (len < 7 || b[0] != 4 || (b[3] | b[4] << 8) != MSG_BUFFERING_IND) {
		return;
	}
	int sensor = -1;
	const uint8_t *samples = NULL;
	unsigned nsamples = 0;
	for (int o = 7; o + 3 <= len;) {
		unsigned t = b[o], l = b[o + 1] | b[o + 2] << 8;
		if (o + 3 + (int)l > len) {
			return;
		}
		if (t == 0x02 && l >= 4) {	/* metadata: report id of the client isnt carried, sensor + type are */
			unsigned id = b[o + 4], dtype = b[o + 5];
			for (int k = 0; k < N_SENSORS; k++) {
				if (sensors[k].id == (int)id && sensors[k].dtype == (int)dtype) {
					sensor = k;
				}
			}
		} else if (t == 0x03 && l >= 1) {
			nsamples = b[o + 3];
			samples = b + o + 4;
			if (nsamples * 16 + 1 > l) {
				nsamples = 0;
			}
		}
		o += 3 + l;
	}
	if (sensor >= 0 && nsamples) {
		int32_t v[3];
		memcpy(v, samples + (nsamples - 1) * 16, 12);
		record(sensor, v);
	}
}

/* --- control --------------------------------------------------------------- */

static void save(void) {
	FILE *f = fopen(state_path, "w");
	if (f) {
		fprintf(f, "auto %s\n", auto_on ? "on" : "off");
		fclose(f);
	}
}

static void command(char *line, bool persist) {
	char what[16] = "", value[16] = "";
	int ms = 0;
	if (sscanf(line, "%15s %15s %d", what, value, &ms) < 2) {
		return;
	}
	if (strcmp(what, "screen") == 0) {
		screen_on = strcmp(value, "off") != 0;
		if (screen_on && !sensors[4].wanted) {
			/* the stream stops with the screen on: what the file says must not stay "near" for the next time */
			prox_is_near = false;
			publish("prox", "0 0\n");
		}
		goal = -1;
		lux_smooth = -1;
	} else if (strcmp(what, "auto") == 0) {
		auto_on = strcmp(value, "on") == 0;
		goal = -1;
		if (persist) {
			save();
		}
	} else if (strcmp(what, "watch") == 0 || strcmp(what, "unwatch") == 0) {
		for (int i = 1; i < N_SENSORS; i++) {
			if (strcmp(value, sensors[i].name) == 0) {
				sensors[i].wanted = what[0] == 'w';
				sensors[i].until = time(NULL) + 5;
			}
		}
	}
	sensors_apply();
	status();
}

static void stop(int sig) {
	stopping = 1;
}

int main(void) {
	char line[128], path[256], buf[2048];
	signal(SIGTERM, stop);
	signal(SIGINT, stop);
	setvbuf(stderr, NULL, _IOLBF, 0);
	if (getenv("OP2_PROX_NEAR")) prox_near_th = atoi(getenv("OP2_PROX_NEAR"));
	if (getenv("OP2_PROX_FAR")) prox_far_th = atoi(getenv("OP2_PROX_FAR"));
	const char *env = getenv("ZTOSCSF_ROOT");
	snprintf(root, sizeof(root), "%s", env ? env : "");
	at(ctl_path, sizeof(ctl_path), CTL);
	at(out_path, sizeof(out_path), OUT);
	at(state_path, sizeof(state_path), STATE);
	at(path, sizeof(path), "/var/lib/ztoscsf-sensord");
	mkdir(path, 0755);
	mkdir(out_path, 0755);
	snprintf(path, sizeof(path), "%s/iio:device0", out_path);
	mkdir(path, 0755);
	publish("iio:device0/name", "op2-smgr-als\n");
	FILE *f = fopen(state_path, "r");
	while (f && fgets(line, sizeof(line), f)) {
		command(line, false);
	}
	if (f) {
		fclose(f);
	}
	at(path, sizeof(path), "/run/zrnperfd.status");
	f = fopen(path, "r");
	while (f && fgets(line, sizeof(line), f)) {
		if (strncmp(line, "screen=", 7) == 0) {
			screen_on = strncmp(line + 7, "off", 3) != 0;
		}
	}
	if (f) {
		fclose(f);
	}
	unlink(ctl_path);
	mkfifo(ctl_path, 0666);
	chmod(ctl_path, 0666);
	int ctl = open(ctl_path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
	status();
	uint64_t retry = 0;
	while (!stopping) {
		if (!smgr_up && now_ns() >= retry) {
			retry = now_ns() + 5000000000ULL;
			if (smgr_find()) {
				smgr_up = true;
				fprintf(stderr, "op2-sensord: sensor manager at %u:%u\n", smgr_node, smgr_port);
				for (int i = 0; i < N_SENSORS; i++) {
					sensors[i].on = false;
				}
				sensors_apply();
			}
		}
		struct pollfd p[2] = { { ctl, POLLIN, 0 }, { sock, POLLIN, 0 } };
		int r = poll(p, sock >= 0 && smgr_up ? 2 : 1, 1000);
		if (r > 0 && (p[0].revents & POLLIN)) {
			ssize_t n = read(ctl, buf, sizeof(buf) - 1);
			if (n > 0) {
				buf[n] = 0;
				for (char *l = strtok(buf, "\n"); l; l = strtok(NULL, "\n")) {
					command(l, true);
				}
			}
		}
		if (r > 0 && smgr_up && (p[1].revents & POLLIN)) {
			struct sockaddr_qrtr sq;
			socklen_t sl = sizeof(sq);
			ssize_t n = recvfrom(sock, buf, sizeof(buf), 0, (struct sockaddr *)&sq, &sl);
			if (n > 0) {
				indication((const uint8_t *)buf, (int)n);
			}
		}
		time_t now = time(NULL);
		for (int k = 1; k < N_SENSORS; k++) {
			if (sensors[k].wanted && sensors[k].until && sensors[k].until < now) {
				sensors[k].wanted = false;
				sensors_apply();
			}
		}
	}
	for (int i = 0; i < N_SENSORS; i++) {
		sensor_set(i, false);
	}
	return 0;
}
