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

| Part | Linux 7.3 | Notes |
|------|-----------|-------|
| CPU, RAM, eMMC, PMICs, RPM | works | 4 cores with the CAF-style `qcom,8994-arm-cortex-acc` bring-up (patch 0010) |
| Display (JDI JD35695, DSI command mode) | works | bootloader framebuffer + own panel driver (`kernel/panel/`) |
| Touchscreen, keys, alert slider | works | slider = `gpio-keys` F13/F15 |
| USB (device, NCM network + serial) | works when started from fastboot | after a normal boot the PC does not see the phone yet (see LOG.md) |
| Battery | works | `kernel/patches/0013` |
| Wi-Fi (QCA6174 on PCIe) | not yet | PCIe PHY PLL does not lock |
| Bluetooth | not yet | chip does not answer |
| Audio | not yet | needs the ADSP |
| GPU (Adreno 430) | in progress | TrustZone refuses the GPU SMMU set-up; Linux 6.12 with a VRAM carveout binds the GPU (`/dev/dri/renderD128`), first use still resets the phone |

Full per-component state: [STATUS.md](STATUS.md). Day-by-day work with commands,
register dumps and results: [LOG.md](LOG.md).

## Layout

| Path | What |
|------|------|
| `kernel/patches/` | patches for Linux 7.3 (most also apply to 6.12), applied in order |
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

`OP2_SERIAL` must be set for the helper scripts that talk to a phone. The second
phone of the two-phone set-up is recognised by its serial in `initramfs/init` and
`rootfs-overlay/usr/local/bin/op2-usb-watch` (`SECOND_PHONE_SERIAL`): put yours there.

## Upstream fixes found on the way

Several patches fix mainline bugs that are not OnePlus 2 specific, for example
`0024` (gcc-msm8994: `usb3_phy_aux_clk_src` without a parent map, NULL dereference on
`clk_set_rate`), `0025` (ocmem: PSGSC register stride of 1 byte instead of 4) and
`patches-612/0102` (a4xx looks up OCMEM on the DRM device instead of the GPU node).

## License

Kernel patches, device tree and the panel driver: GPL-2.0-only, as the Linux kernel.
Scripts and tools: GPL-2.0-only unless a file says otherwise.
