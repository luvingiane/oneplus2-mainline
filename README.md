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

**19 working · 3 partial · 9 broken · 7 untested**

*Working* means 100% of the feature, tried on the phone; *Partial* says in the notes what is missing. Same wording as the ztOS device pages ([devices.ztos.online](https://devices.ztos.online)).

**20 working · 2 partial · 10 broken · 6 untested**

*Working* means 100% of the feature, tried on the phone; *Partial* says in the notes what is missing. Same wording as the ztOS device pages ([devices.ztos.online](https://devices.ztos.online)).

| Category | Feature | Status | Notes |
|---|---|---|---|
| Boot | Mainline kernel boot (7.3), from RAM and from flash | 🟢 Working | `fastboot boot` and the boot partition; cold start reaches the ztMETRO shell |
| Boot | Boot logo | 🟢 Working | Arch Linux logo in the `LOGO` partition (`tools/boot-logo`) |
| Boot | CPU, 4 × A53 | 🟢 Working | CAF-style ACC bring-up (patch 0010), fixed clock of about 1.5 GHz |
| Boot | CPU, 4 × A57 | 🔴 Broken | they come up with a real clock but the boot becomes intermittent (3 of 4 starts); left off |
| Boot | CPU frequency scaling | 🔴 Broken | no cpufreq: clock driver and OPP table are drafts, a 1 V / 1536 MHz try crashed the boot |
| Display | Panel (JD35695, 1080p, DSI command mode) | 🟢 Working | own panel driver (`kernel/panel`), MDP5 + DSI |
| Display | GPU (Adreno 430) | 🟢 Working | hardware OpenGL ES 3.0 (freedreno) draws the whole UI; needs patches 0130 + 0144 (identity IOVA, TZ refuses the SMMU) |
| Input | Touchscreen (Synaptics S3320) | 🟢 Working | multi-touch; GPIO 74 must stay on |
| Input | Power and volume keys | 🟢 Working | screenshot on power + volume up, volume with the screen off |
| Input | Capacitive touch keys | 🟡 Partial | events arrive and the left key acts as Home; the other key is not checked |
| Input | Alert slider | 🟢 Working | `gpio-keys` F13/F15 |
| Audio | Loudspeaker | 🟢 Working | ADSP + q6 quaternary MI2S → TFA9890 |
| Audio | Earpiece, headphone jack, microphones | 🔴 Broken | WCD9330 codec: the SLIMbus never enumerates (capability exchange times out), no mainline codec driver |
| Audio | Audio of a phone call | 🔴 Broken | needs the modem-to-codec path on SLIMbus |
| Audio | Ringtone | 🔴 Broken | the phone does not ring on an incoming call (the caller does hear ringing); cause not found yet |
| Modem | Modem start and SIM | 🟢 Working | MSS + ADSP remoteproc, `rmtfs`, QMI DPM opens `DATA5_CNTL`, USIM session (`scripts/op2-modem-up.sh`) |
| Modem | Mobile network (LTE) and operator name | 🟢 Working | registers on LTE; signal bars and operator in ztOS |
| Modem | SMS | 🟢 Working | read from the SIM storage |
| Modem | Phone calls | 🟡 Partial | ringing, answering and hanging up work (a QMI VOICE client is needed so the network alerts the phone); no voice audio yet |
| Modem | Mobile data | 🔴 Broken | no packet path: the MSM8994 IPA v2 has no mainline driver |
| Modem | Airplane mode | 🟢 Working | stops the modem (`AT+CFUN=4` crashes its firmware): `scripts/op2-airplane.sh` |
| Modem | Second SIM | ⚪ Untested |  |
| Network | Wi-Fi (QCA6174 on PCIe1) | 🟢 Working | ath10k scans and associates (patches 0149-0165) |
| Network | Bluetooth | 🟢 Working | controller over UART, audio over Bluetooth tried and working; the factory BD address is invalid and must be set |
| Network | USB networking (device mode) | 🟢 Working | NCM + ssh; a watchdog can send the phone back to fastboot when no USB link comes up |
| Network | USB host (OTG) | ⚪ Untested |  |
| Location | GPS | 🔴 Broken | not started (lives in the modem: QMI LOC) |
| Camera | Front camera (OV5648) | 🔴 Broken | CSIPHY/CSID/ISPIF/VFE lined up with the vendor driver, the CSID test pattern passes, but no MIPI packets from the sensor (PHY status 0) |
| Camera | Rear camera (OV13860) | 🔴 Broken | draft driver in `kernel/patches-73` (0189, 0190), never run |
| Sensors | Ambient light | 🟢 Working | ADSP sensor manager through `tools/op2-sensord` |
| Sensors | Proximity | 🔴 Broken | returns a constant value even when covered (not understood yet) |
| Sensors | Accelerometer, gyroscope, magnetometer | ⚪ Untested | the ADSP streams them (`op2-sensord watch`), not checked; no auto-rotation |
| Sensors | Hall sensor | ⚪ Untested | `SW_MACHINE_COVER` on GPIO 75 |
| Sensors | Fingerprint reader | ⚪ Untested |  |
| Power | Battery and charging | 🟢 Working | `kernel/patches/0013` + APSD re-run |
| Power | Temperature and thermal throttling | 🟢 Working | 16 TSENS zones from the fuses; `op2-thermal.py` throttles the PLL post-dividers |
| Power | Vibration | ⚪ Untested | PMI8994 haptic as an `FF_RUMBLE` input device, not felt by hand yet |
| Power | Notification LED | 🟢 Working | PMI8994 LPG, red/green/blue |

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
