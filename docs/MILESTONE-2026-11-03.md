# Milestone 2026-11-03: Adreno 430 GPU rendering the ztOS UI on mainline 7.3

The OnePlus 2 (MSM8994) now runs the ztMETRO shell on **mainline Linux 7.3 with
the hardware GPU** (freedreno / Mesa `FD430`, GLES 3.0), booting from the eMMC
(`boot` partition), with no hang and no failed submit.

## What was wrong, and the fixes

| Symptom | Root cause | Fix |
|---|---|---|
| Every GPU submit returned `-ENOMEM` (`MESA: submit failed: -12`), screen showed noise | Patch 0130 dropped the GPU address space (`gpu->vm = NULL`, TrustZone refuses the GPU SMMU secure set-up), but the 7.x submit path needs a VM (`UERR(ENOMEM, "no VM")`) | `0130-op2-gpu-phys.patch`: a VM whose MMU does nothing (map/unmap are no-ops, IOVA == physical, range 1 MiB..4 GiB) |
| After that, first submit hung the GPU (`hangcheck`) and the CPU locked up | `msm_gem_get_iova()` (used by `MSM_INFO_GET_IOVA`, so by the addresses Mesa puts in the command stream) allocated arbitrary IOVAs while the submit looked for physical ones | `0144-msm-gem-submit-identity-iova.patch`: `msm_gem_get_vma_locked()` uses the physical range when `msm.identity_iova=1`, and `msm_gem_get_iova()` goes through it |
| Screen black with the default Mesa path | The GMEM/OCMEM tile path is not usable (TrustZone refuses the OCMEM lock) | `FD_MESA_DEBUG=sysmem` in the session environment |
| `-ENOMEM` again after some minutes | Without an SMMU every GPU buffer is physically contiguous; the default 128 MiB CMA fills up | `cma=768M` on the kernel command line |
| Kernel dies at 1.6 s in `a4xx_hw_init` after the first VBIF write | The GPU DTB variant without the SMMU node (`OP2_GPU_NOIOMMU`) was built: the SMMU attach is what unlocks the VBIF | build with `OP2_DISPLAY OP2_SMP OP2_USBPHY OP2_GPU OP2_GPU_RPMCLK` (no `NOIOMMU`) |

Kernel command line used:

```
msm.identity_iova=1 msm.op2_gpu_phys=1 arm64.late_cpu_conflicts=warn op2.gpuhw=1 cma=768M
```

`rootfs-overlay/etc/ztos/session.env` selects the hardware GPU only when
`op2.gpuhw=1` is on the command line (software llvmpipe otherwise).

## Build trap worth knowing

If the kernel tree was built on another machine (WSL, a shared drive), host
tools such as `scripts/dtc/dtc` and `scripts/mod/modpost` can lose their
executable bit. `make` then fails with `Error 126` and the DTBs are silently
stale. `scripts/build-kernel.sh` now stops with an error when `make` fails.

## Measurements (4 x Cortex-A53 online, no cpufreq)

| Item | Result |
|---|---|
| CPU | cores stay at the bootloader clock (about 600 MHz); a Python loop of 1M iterations takes 2.3 s per core; the four A57 are not online |
| GPU, full-screen textured quad (1080x1920) | 9.1 ms (clock fixed at 300 MHz) |
| Texture upload, 8 MiB | 4.9 ms |
| Upload and use in the same frame | about 200 ms (first use of a fresh texture, CPU bound) |
| UI | compositor animations run at 60 fps; app work (page turns, input) is CPU bound |

## Known issues and next steps

- No CPU frequency scaling yet (the clock driver for the two clusters is drafted, untested).
- The A57 cluster is not brought online in this configuration.
- GPU clock is fixed at 300 MHz (devfreq off); the 600 MHz OPP needs its rail raised first.
- USB networking does not come up after a plain boot from the eMMC (it does after `fastboot boot` / `fastboot continue`).
- Display: command-mode panel shows `pp done time out` messages around the first frames.
- Wi-Fi (PCIe PHY PLL does not lock) and Bluetooth (QCA6174 over UART) are still open.

## Tools added

- `tools/gpu-test/gles-probe.py`: step-by-step correctness probe (clear, quad, textures).
- `tools/gpu-test/gles-bench.py`: CPU / upload / draw timings, to tell the GPU from everything else.
