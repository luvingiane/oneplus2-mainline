# Strategy: downstream 3.10 vs mainline

Decided 2026-10-25, before touching either phone. Evidence: pmaports
(`e6ff10d`, 2026-10-24), torvalds/linux (`21a7f44`, 7.3 + 7.4 merge window),
LineageOS `android_kernel_oneplus_msm8994` lineage-17.1 (3.10.108).

## The deciding fact

ztOS is Arch Linux ARM + systemd. **systemd 258 needs Linux ≥ 5.4, systemd 259
needs ≥ 5.10** (cgroup v1 removed, pidfd, new mount API). The only kernel with
working drivers for this phone is 3.10.108 (EOL 2017). So a downstream kernel
cannot run ztOS's userspace at all; it would mean a different distro (Alpine +
OpenRC, as the archived pmOS port did), no systemd units, and ztMETRO on fbdev
with no GPU (Adreno via kgsl needs Android blobs through libhybris).

## Options

| | A. Downstream 3.10 (LineageOS kernel) | B. Mainline 7.x (**chosen**) |
|---|---|---|
| Boot + screen | Works (mdss fb) | Boots with the msm8994 base; screen first via `simple-framebuffer` on the bootloader's splash, then MDP5+DSI (drivers exist, DT nodes + panel driver to write) |
| Touch | Works | Synaptics S3320 → mainline RMI4 (`syna,rmi4-i2c`), as on Sony Kitakami |
| GPU / ztMETRO | No DRM/KMS; GL only via libhybris | DRM/KMS + freedreno Adreno 430 (a4xx), Mesa GLES — ztMETRO runs as on the S9 |
| Audio | Works in kernel (WCD9330 + TFA9890 via Q6) | **Hard**: no WCD9330 driver, no msm8994 ADSP remoteproc. Shortcut to try: speaker = TFA9890 on an LPASS MI2S port, which `lpass-cpu` can drive without the DSP |
| Wi-Fi | qcacld-2.0 in kernel; needs CNSS + firmware | ath10k QCA6174 is mainline; **msm8994 PCIe controller is not** → port from downstream `pci-msm.c` (closest upstream: apq8084 / msm8996 cfgs) |
| Bluetooth | needs Android-style patch download | `hci_qca` (`qcom,qca6174-bt`) on BLSP UART — likely the easiest radio |
| GPS | needs Android loc HAL (QMI over IPC router) | needs msm8994 MSS remoteproc (port, close to msm8974 q6v5) + QMI LOC client over qrtr — last, most likely to block |
| Userspace | Not Arch/systemd → not ztOS | Arch Linux ARM + systemd → ztOS as is |
| Maintenance | Dead toolchain (GCC 6), no security fixes | Current kernel, shared with Nexus 6P / Sony / Lumia msm8994 boards |

## Plan

1. **Mainline is the product.** Base: `linux-postmarketos-qcom-msm8994`
   (pmOS, 6.16, maintained by Petr Vorel) rebased on the current mainline,
   plus a new `msm8994-oneplus-oneplus2.dts`.
2. **The downstream tree is the reference**, not the product: GPIOs,
   regulators, panel init commands, PCIe/PHY sequences, audio routing are read
   from `msm8994-mtp.dtsi` and the 3.10 drivers.
3. **Stock/LineageOS stays on the phone** (system, vendor, modem, persist)
   for firmware extraction and A/B comparison, as ztOS does on the S9.
4. **No flashing to start with**: the OP2 bootloader supports
   `fastboot boot <img>` (RAM only). Each test kernel is booted that way; boot
   is flashed only once it is stable, and only after confirmation.
5. Boot image: `Image.gz` + appended DTB, pagesize 4096, base 0, ramdisk
   offset 0x01000000, tags 0x100; DTB needs `qcom,msm-id = <207 0x20001>`
   (v2.1, to confirm) and OnePlus's 4-cell `qcom,board-id = <8 0 14049 HW>`.
6. Order (as asked): boot+screen → touch → audio → Wi-Fi → BT → GPS. If one
   blocks after reasonable attempts it is marked *Blocked* in STATUS.md and
   the next one starts.

## Reverse engineering: where it is expected

- **None** for boot, simplefb, touch, BT (drivers exist; DT work only).
- **Porting, not RE**, for display (panel driver generated from downstream
  DTS with `linux-mdss-dsi-panel-driver-generator`), PCIe (downstream source
  is GPL and available), MSS remoteproc.
- **Possible RE** only for audio if the WCD9330 is needed beyond the speaker
  (headphones/mic: register sequences from the downstream `wcd9330.c`), and for
  the TFA9890 if its container firmware (`tfa98xx.cnt`) is required at start.
  I will ask before starting any of it.
