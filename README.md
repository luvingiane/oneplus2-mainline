# OnePlus 2 on mainline Linux (for ztOS)

[Italiano](README.it.md)

Bring-up of the **OnePlus 2** (ONE A2003, Qualcomm MSM8994 / Snapdragon 810) on
mainline Linux, to run [ztOS](https://github.com/luvingiane/ztOS) (Arch Linux ARM +
ztMETRO) as a home device. Kernel patches, device tree, boot image tooling, small
on-phone tools and the complete bring-up diary.

> Experimental. Everything here was tested on two phones of the same model. Images
> are normally booted from RAM (`fastboot boot`); nothing is written to the phone
> unless you flash it yourself. Back up your partitions first (see
> [docs/BACKUP.md](docs/BACKUP.md)) and never touch the modem/EFS partitions.

## Status (short)

Latest milestone (2026-11-03): the hardware GPU renders the ztOS UI on mainline 7.3, see
[docs/MILESTONE-2026-11-03.md](docs/MILESTONE-2026-11-03.md).

| Part | Linux 7.3 | Notes |
|------|-----------|-------|
| CPU, RAM, eMMC, PMICs, RPM | works | 4 cores with the CAF-style `qcom,8994-arm-cortex-acc` bring-up (patch 0010); no cpufreq yet (the 4 A53 cores run at a fixed clock of about 1.5 GHz) and the A57 cluster is not brought online |
| Display (JDI JD35695, DSI command mode) | works | bootloader framebuffer + own panel driver (`kernel/panel/`) |
| Touchscreen, keys, alert slider | works | slider = `gpio-keys` F13/F15 |
| USB (device, NCM network + serial) | works when started from fastboot | after a normal boot the PC does not see the phone yet (see LOG.md) |
| Battery | works | `kernel/patches/0013` |
| Wi-Fi (QCA6174 on PCIe) | works | the chip is on **PCIe1**, not PCIe0 (patches 0149-0158, 0162, 0164, 0165; DT `op2-wifi.dtsi` with `OP2_WIFI_PCIE1 OP2_WIFI_BOOT`); ath10k scans and associates, see [docs/MILESTONE-2026-11-05-wifi.md](docs/MILESTONE-2026-11-05-wifi.md). Firmware must be in the initramfs and `CONFIG_FW_LOADER_USER_HELPER` off. Starts rfkill-blocked |
| Bluetooth | works | QCA6174 over UART (`op2-bt.dtsi`, patch 0161): needs the WL_EN GPIO high, the version read at 115200 baud and the QCA rampatch/nvm in the initramfs. The factory BD address is invalid: set one |
| SoC temperature | works | 16 TSENS zones calibrated from the fuses (patch 0159, `op2-tsens.dtsi`); the A57 cluster resets near 118 C, `rootfs-overlay/usr/local/bin/op2-thermal.py` throttles the PLL post-dividers |
| Vibration, hall sensor | present | PMI8994 haptic as an input FF_RUMBLE device (patch 0163); hall on GPIO 75 as `SW_MACHINE_COVER` (StyleSwap cover). Not checked by hand yet |
| Audio | loudspeaker works | ADSP boots (`op2-adsp.dtsi`), q6 quaternary MI2S -> TFA9890 amplifier (`op2-audio.dtsi`, patch 0029); the WCD9330 codec (mics, earpiece, jack) has no mainline driver |
| GPU (Adreno 430) | works on 7.3 and 6.12 | **7.3: hardware GL renders the whole ztMETRO UI from the eMMC, no hang, no failed submit** (patches `0130` + `0144`: a VM with a no-op MMU, IOVA == physical; cmdline `msm.identity_iova=1 msm.op2_gpu_phys=1 cma=768M`; Mesa freedreno FD430 with `FD_MESA_DEBUG=sysmem`, the OCMEM/GMEM path is still refused by TrustZone), see [docs/MILESTONE-2026-11-03.md](docs/MILESTONE-2026-11-03.md). 6.12: SMMU attached + physical addresses (`patches-612/0104`). GPU clock is fixed at 300 MHz |
| Modem, SIM, calls, SMS | works (call audio not yet) | MSS + ADSP remoteproc, `rmtfs` on the raw modem partitions, then a QMI DPM request opens `DATA5_CNTL` (`/dev/wwan0qmi0`, needs `CONFIG_WWAN` + `RPMSG_WWAN_CTRL`) and AT answers on `/dev/wwan0at0`. LTE registration, SMS (SIM storage), ringing and answering. A QMI VOICE client must be registered or the network is never alerted. `scripts/op2-modem-up.sh`, `op2-modem-watch.sh`, `tools/qmux`. The modem-to-codec voice path (SLIMbus) is missing |
| Mobile data | not working | no packet path yet: the MSM8994 IPA v2 has no mainline driver (research in LOG.md) |
| Airplane mode | works | `AT+CFUN=4` (and a deregistration) crash the modem firmware on this phone while it is registered, so `scripts/op2-airplane.sh` stops the modem remoteproc and starts it again in the order that avoids the "stalled initialization" loop |
| Light and proximity sensors | partial | ADSP sensor manager through `tools/op2-sensord`; light works, proximity returns a constant value (not understood yet) |
| Cameras | not working | front OV5648: CAMSS/CSID/ISPIF/VFE lined up with the vendor driver, still no MIPI packets (PHY status 0); rear OV13860: draft driver in `kernel/patches-73` (0189, 0190), untested |
| Boot logo | works | Arch Linux logo in the `LOGO` partition (`tools/boot-logo/build_arch_logo.py`, flashed with `fastboot flash LOGO`, upper case) |

Full per-component state: [STATUS.md](STATUS.md). Day-by-day work with commands,
register dumps and results: [LOG.md](LOG.md).

## Layout

| Path | What |
|------|------|
| `kernel/patches/` | patches for Linux 7.3 (most also apply to 6.12), applied in order |
| `kernel/patches-73/` | patches only for 7.3 (GPU on physical addresses, camss, PCIe/DSI work); pass them with `EXTRA_PATCHES=$PWD/kernel/patches-73` |
| `kernel/patches-612/` | patches only for 6.12 (GPU on a VRAM carveout, bring-up trace) |
| `kernel/dts/` | `msm8994-oneplus-oneplus2.dts` and `op2-*.dtsi`, switched with `DTS_DEFINES` (`OP2_DISPLAY`, `OP2_SMP`, `OP2_USBPHY`, `OP2_WIFI`, `OP2_GPU`, ...) |
| `kernel/panel/` | the panel driver |
| `kernel/oneplus2*.config` | config fragments on top of postmarketOS's msm8994 config |
| `scripts/` | `build-kernel.sh`, `build-boot.sh` (boot image for `fastboot boot`), backup and test helpers |
| `initramfs/` | the initramfs `init` (USB gadget, network, root switch) |
| `rootfs-overlay/` | files added to the ztOS root file system (USB watchdog service, sudoers rule for the power menu) |
| `tools/` | small C/Python tools used on the phone (register peeks, panel commands, GPU tests) |
| `docs/` | strategy, hardware, backups |

## Build

Needs an aarch64 cross toolchain (`build/toolchain/`, ARM GNU 14.2), the kernel
source in `build/linux-7.3` (or 6.12 with `KSRC=`) and postmarketOS's
`linux-postmarketos-qcom-msm8994` config in `research/pmaports/` (see the scripts).

```bash
DTS_DEFINES="OP2_DISPLAY OP2_SMP OP2_USBPHY" bash scripts/build-kernel.sh
bash scripts/build-boot.sh my-image --cmdline "op2.root=/dev/mmcblk1p43"
fastboot boot out/my-image.img        # RAM only
```

With the hardware GPU (7.3):

```bash
EXTRA_PATCHES=$PWD/kernel/patches-73 \
DTS_DEFINES="OP2_DISPLAY OP2_SMP OP2_USBPHY OP2_GPU OP2_GPU_RPMCLK" bash scripts/build-kernel.sh
bash scripts/build-boot.sh gpu --cmdline "msm.identity_iova=1 msm.op2_gpu_phys=1 arm64.late_cpu_conflicts=warn op2.gpuhw=1 cma=768M op2.root=/dev/mmcblk1p43"
```

If the kernel tree was built on another machine, make sure `scripts/dtc/dtc` and `scripts/mod/modpost`
are executable: otherwise `make` fails and the DTBs stay stale (`build-kernel.sh` now stops on a failed `make`).

`OP2_SERIAL` must be set for the helper scripts that talk to a phone. A second
phone on the same computer is booted with `op2.net=44` on its command line (`initramfs/init`) and
recognised by its serial in `rootfs-overlay/usr/local/bin/op2-usb-watch` (`SECOND_PHONE_SERIAL`): put yours there.

## Booting something other than ztOS

The kernel, the device tree and the initramfs do not depend on ztOS: `scripts/build-boot.sh` makes a boot image whose
initramfs mounts the root given in `op2.root=` (an ext4 partition of the phone's eMMC) and starts that system's init.
Any aarch64 root filesystem with systemd and a recent userland should be a candidate; the phone-specific pieces
(modem services, sensors, airplane helper, USB watch) are plain files under `rootfs-overlay/` and can be dropped or kept.
Not tried with another system yet: this is the goal once the hardware list above is done. Always boot from RAM first
(`fastboot boot`), flash only after it works.

## Upstream fixes found on the way

Several patches fix mainline bugs that are not OnePlus 2 specific, for example
`0024` (gcc-msm8994: `usb3_phy_aux_clk_src` without a parent map, NULL dereference on
`clk_set_rate`), `0025` (ocmem: PSGSC register stride of 1 byte instead of 4) and
`patches-612/0102` (a4xx looks up OCMEM on the DRM device instead of the GPU node).

## License

Kernel patches, device tree and the panel driver: GPL-2.0-only, as the Linux kernel.
Scripts and tools: GPL-2.0-only unless a file says otherwise.
