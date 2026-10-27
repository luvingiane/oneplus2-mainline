/*
 * gpu-memwrite: the smallest GPU job, without Mesa. Submits a command
 * buffer straight to the msm driver and waits for its fence.
 *   gpu-memwrite nop     one CP_NOP (only the kernel's own fence write)
 *   gpu-memwrite write   two CP_MEM_WRITE into a buffer, then read it back
 *   gpu-memwrite idle    CP_WAIT_FOR_IDLE, then the two writes
 * Tells whether the GPU can write to memory at all (the first draw hangs).
 * Build on the phone: cc -O2 -o gpu-memwrite gpu-memwrite.c -I/usr/include/drm
 * (msm_drm.h copied from our kernel tree next to this file).
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include "msm_drm.h"

#define PKT3(op, cnt) (0xc0000000u | (((cnt) - 1) << 16) | (((op) & 0xff) << 8))
#define CP_NOP 16
#define CP_WAIT_FOR_IDLE 38
#define CP_MEM_WRITE 61

static int fd;

static uint32_t bo_new(uint32_t size)
{
	struct drm_msm_gem_new req = { .size = size, .flags = MSM_BO_WC };

	if (ioctl(fd, DRM_IOCTL_MSM_GEM_NEW, &req)) { perror("GEM_NEW"); exit(1); }
	return req.handle;
}

static uint64_t bo_info(uint32_t handle, uint32_t what)
{
	struct drm_msm_gem_info req = { .handle = handle, .info = what };

	if (ioctl(fd, DRM_IOCTL_MSM_GEM_INFO, &req)) { perror("GEM_INFO"); exit(1); }
	return req.value;
}

static uint32_t *bo_map(uint32_t handle, uint32_t size)
{
	void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
		       bo_info(handle, MSM_INFO_GET_OFFSET));

	if (p == MAP_FAILED) { perror("mmap"); exit(1); }
	return p;
}

int main(int argc, char **argv)
{
	const char *mode = argc > 1 ? argv[1] : "write";
	struct drm_msm_param gp = { .pipe = MSM_PIPE_3D0, .param = MSM_PARAM_GPU_ID };
	uint32_t cmd, dst, *c, *d, n = 0;
	uint64_t cmd_iova, dst_iova;

	fd = open("/dev/dri/renderD128", O_RDWR);
	if (fd < 0) { perror("renderD128"); return 1; }
	if (!ioctl(fd, DRM_IOCTL_MSM_GET_PARAM, &gp))
		printf("GPU id %llu\n", (unsigned long long)gp.value);

	cmd = bo_new(4096);
	dst = bo_new(4096);
	cmd_iova = bo_info(cmd, MSM_INFO_GET_IOVA);
	dst_iova = bo_info(dst, MSM_INFO_GET_IOVA);
	c = bo_map(cmd, 4096);
	d = bo_map(dst, 4096);
	d[0] = d[1] = 0xdeadbeef;
	printf("mode %s, cmd iova %#llx, dst iova %#llx\n", mode,
	       (unsigned long long)cmd_iova, (unsigned long long)dst_iova);

	if (!strcmp(mode, "nop")) {
		c[n++] = PKT3(CP_NOP, 1);
		c[n++] = 0;
	} else {
		if (!strcmp(mode, "idle")) {
			c[n++] = PKT3(CP_WAIT_FOR_IDLE, 1);
			c[n++] = 0;
		}
		c[n++] = PKT3(CP_MEM_WRITE, 2);
		c[n++] = (uint32_t)dst_iova;
		c[n++] = 0x12345678;
		c[n++] = PKT3(CP_MEM_WRITE, 2);
		c[n++] = (uint32_t)dst_iova + 4;
		c[n++] = 0xcafef00d;
	}

	struct drm_msm_gem_submit_bo bos[2] = {
		{ .flags = MSM_SUBMIT_BO_READ, .handle = cmd, .presumed = cmd_iova },
		{ .flags = MSM_SUBMIT_BO_WRITE, .handle = dst, .presumed = dst_iova },
	};
	struct drm_msm_gem_submit_cmd sc = {
		.type = MSM_SUBMIT_CMD_BUF, .submit_idx = 0, .submit_offset = 0,
		.size = n * 4,
	};
	struct drm_msm_gem_submit sub = {
		.flags = MSM_PIPE_3D0, .nr_bos = 2, .nr_cmds = 1,
		.bos = (uintptr_t)bos, .cmds = (uintptr_t)&sc, .queueid = 0,
	};
	/* the phone may reset on the submit: get what we know onto the disk */
	printf("cmd:");
	for (uint32_t i = 0; i < n; i++)
		printf(" %08x", c[i]);
	printf("\nsubmitting\n");
	fflush(stdout);
	sync();
	if (ioctl(fd, DRM_IOCTL_MSM_GEM_SUBMIT, &sub)) { perror("GEM_SUBMIT"); return 1; }
	printf("submitted %u dwords, fence %u\n", n, sub.fence);
	fflush(stdout);

	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	struct drm_msm_wait_fence w = {
		.fence = sub.fence, .queueid = 0,
		.timeout = { .tv_sec = now.tv_sec + 3, .tv_nsec = now.tv_nsec },
	};
	int r = ioctl(fd, DRM_IOCTL_MSM_WAIT_FENCE, &w);
	printf("fence wait: %s\n", r ? strerror(errno) : "done");
	printf("dst[0] %#010x (expect 0x12345678), dst[1] %#010x (expect 0xcafef00d)\n",
	       d[0], d[1]);
	return r ? 2 : 0;
}
