# Log

Chronological. Commands and the output that mattered.

## 2026-10-25 — Phase 0: research (phones charging, not on USB)

Host: Manjaro, kernel 7.1.13, adb/fastboot 37.0.0 (android-tools), clang/lld,
mkbootimg, dtc, pmbootstrap present; no aarch64 gcc, no qemu-user (build with
`LLVM=1`).

```
$ adb devices -l        -> (empty)
$ fastboot devices -l   -> (empty)
$ lsusb                 -> no 2a70 (OnePlus) / 05c6 (Qualcomm) / 18d1 (fastboot)
```
A background watcher polls `lsusb` every 3 s for those vendor IDs.

### pmaports (gitlab.postmarketos.org, e6ff10d, 2026-10-24)
- `device/archived/device-oneplus-oneplus2` + `linux-oneplus-oneplus2`:
  **archived**, kernel 3.10.108 from LineageOS `android_kernel_oneplus_msm8994`
  @0178fae, built with GCC 6. Wiki status: screen/touch/battery OK; Wi-Fi, BT,
  GPS, audio, 3D broken.
- `device/testing/linux-postmarketos-qcom-msm8994`: **mainline 6.16**, for
  MSM8994/8992 (maintainer Petr Vorel). Used by `huawei-angler` (Nexus 6P) and
  `lg-bullhead` (Nexus 5X): fastboot, appended DTB, pagesize 4096.
- Note: postmarketos.org web/wiki/pkgs now answer with a 301 to `*.nura.eco`;
  the git server still answers on its own name. Not followed.

### Mainline (torvalds 21a7f44, v7.3 + 7.4 merge window)
`arch/arm64/boot/dts/qcom/`: msm8994.dtsi + angler, Sony Kitakami ×5,
Lumia cityman; msm8992 bullhead, h815, libra, talkman. **No oneplus2.**

msm8994.dtsi has: CPUs, GCC, MMCC, RPM/rpmpd, pinctrl, SPMI, BLSP i2c/spi/uart,
eMMC/SD (sdhci), USB dwc3, SMEM, hwlock. **Missing**: MDSS/DSI, GPU,
PCIe, any remoteproc, audio.

Drivers that know msm8994: `gcc-msm8994`, `mmcc-msm8994`, `clk-smd-rpm`,
`pinctrl-msm8994`, `smd-rpm`, MDP5 `msm8x94_config` (rev 9), DSI
`msm8994_dsi_cfg`, DSI PHY 20nm, a4xx catalog chip id 0x04030002 (A430).
Not present: `pcie-qcom` msm8994 compatible, `qcom_q6v5_mss`/`pas`
msm8994, WCD9330 codec.

libra/kitakami show the display route without a panel driver:
`simple-framebuffer` at 0x3400000 on the bootloader's splash (plus MDSS clocks
kept on).

### LineageOS sources (lineage-17.1)
- device: `vendor.qcom.bluetooth.soc=rome` (QCA6174 BT), `BOARD_WLAN_DEVICE :=
  qcwcn`, `init.tfa.sh` + `tfa98xx.cnt`, Synaptics keylayout,
  firmware list incl. `a420_pm4.fw a420_pfp.fw`, BT `rampatch_tlv_3.2.tlv`.
- BoardConfig: `Image.gz-dtb`, base 0, pagesize 4096, ramdisk 0x01000000,
  tags 0x100, boot partition 64 MiB.
- kernel `oneplus2_defconfig`: `CONFIG_PCI_MSM CONFIG_CNSS_PCI
  CONFIG_QCA_CLD_WLAN` (Wi-Fi QCA6174 on PCIe), `CONFIG_WCD9330_CODEC
  CONFIG_SND_SOC_MSM8994`, `CONFIG_TOUCHSCREEN_SYNAPTICS_S3320_I2C_RMI`,
  `CONFIG_MSM_PIL_MSS_QDSP6V5`, `CONFIG_QPNP_SMBCHARGER CONFIG_QPNP_FG`.
- board DTS `msm8994-mtp.dtsi`: `bt_qca6174`, panel `dsi_jdi_1080_vid`
  (also `dsi_jd35695_1080_cmd`), S3320 @0x20 on i2c f9924000 (irq 96, reset 31,
  1v8 74), S1302 keys on f9928000 (irq 67), TFA9890 @0x36 on f9967000,
  `msm8994-tomtom-mtp-snd-card`, `&pcie0`, `&cnss`.
- `qcom,board-id = <8 0 14049 11..14>` (OnePlus 4-cell board id).

### systemd vs the downstream kernel
systemd 258: minimum Linux 5.4 (cgroup v1 removed); 259: minimum 5.10.
→ Arch Linux ARM cannot boot on 3.10. **Decision: mainline**
([docs/STRATEGY.md](docs/STRATEGY.md)).

## 2026-10-25 — Stage 1 prep (no phone yet)

- Kernel: Linux 7.3 (kernel.org tarball, sha256 OK), Arm GNU toolchain
  14.2.rel1 (sha256 OK, same as ztOS), config = pmOS msm8994 +
  `kernel/oneplus2.config` (simpledrm, USB configfs NCM/ACM built in,
  pstore/ramoops, qcom watchdog, RMI4, panic=10).
- DTS `kernel/dts/msm8994-oneplus-oneplus2.dts`: msm-id `<207 0x20001>`,
  board-id `<8 0 14049 rev>` built for rev 11–14 and all appended
  (LK picks the match); simple-framebuffer at 0x03400000 1080×1920 r8g8b8;
  OnePlus reserved regions (0x6200000, 0x6300000, 0xe900000) and ramoops at
  0xac000000 (OnePlus's own, so Android/TWRP can read a crashed boot's log).
- busybox 1.37.0 static: needed `CONFIG_SHA1_HWACCEL`/`SHA256_HWACCEL` off
  (x86-only code), and `{ yes || :; } | make oldconfig` under pipefail.
- **Boot addresses.** lk2nd's copy of CAF LK (`project/msm8994.mk`):
  `ABOOT_IGNORE_BOOT_HEADER_ADDRS`, kernel64 0x80000, tags/DTB 0x02500000,
  ramdisk 0x02700000. First build: `image_size` 37.75 MiB → would run over
  the DTB. `.BTF` was 6.4 MiB of it: `DEBUG_INFO_BTF` and `ACPI` off →
  ```
  kernel image_size 30 MiB: ends at 0x1ed0000, DTB at 0x2500000
  out/op2-s1-simplefb.img  13680640 bytes  kernel 7.3.0-oneplus2
  ```
  Header now carries the same three addresses.
- Panel drivers generated from the downstream DTB with
  linux-mdss-dsi-panel-driver-generator: `kernel/panel/` (JDI 1080p video,
  JD35695 1080p cmd). Which one this phone has: bootloader cmdline at recon.
- Host has no sudo and no uucp group → the test initramfs runs udhcpd, so
  NetworkManager configures 172.16.42.2 by itself; shell via telnet
  (`scripts/psh.py`).
- lk2nd (msm8916-mainline) has an msm8994 target (angler, h815): fallback if
  the OnePlus LK misbehaves with mainline.

## 2026-10-25 ~11:04 — first phone on USB (`<phone-B>`)

```
lsusb: 2a70:9011 OnePlus ... Android   (MTP + mass storage + ADB)
adb:   unauthorized -> device (after `adb kill-server`)
ro.product.model ONE A2003   ro.rom.version H2OS V2.5.1   ro.oxygen.version 3.6.1
ro.build.fingerprint OnePlus/OnePlus2/OnePlus2:6.0.1/MMB29M/1447858500:user/release-keys
uname 3.10.84-perf+ (2017-10-24)   ro.crypto.state unencrypted   sys.oem_unlock_allowed 0
su: not found; /proc/cmdline, by-name: permission denied (no root)
fb0 msm_fb_panel_info: panel_name=jd35695 1080p cmd mode dsi panel
input: synaptics,s3320  synaptics,s1302  fpc1020  gpio-keys
cpuinfo: 4x 0xd03 (A53) + 4x 0xd07 (A57), MSM8994
/sdcard: Android 281M, Download 41M, DCIM 4.4M, ... (~330 MB)
battery: level 3, USB powered, charging
```
- **Panel is command mode** → simple-framebuffer alone shows a frozen
  splash. initramfs now finds the CTL the bootloader set up (CTL_TOP at
  +0x14) and writes CTL_START (+0x1c) once a second for 60 s
  (`op2.kick=0` disables it). Offsets from downstream `mdss_mdp_hwio.h`.
- User asked to cut power use: airplane mode via
  `settings put global airplane_mode_on 1` + `am broadcast ... AIRPLANE_MODE`
  (Wi-Fi off, radio POWER_OFF, BT state 10 = off), location off, brightness 0,
  third-party apps force-stopped, `am kill-all`, `dumpsys deviceidle force-idle`
  (mState=IDLE). `svc wifi/data disable` had no effect as shell. All undone
  by turning airplane mode off / rebooting.

## 2026-10-25 — phone `<phone-B>` is B (target); media saved

- Owner: `<phone-B>` = phone B (working display, the target); bootloader
  **unlocked** (to confirm in fastboot); battery worn, ~1.5 A even on a 30 W
  charger (the OP2 has no fast charge: 5 V / 2 A at best).
- USB dropped twice for a few seconds; uptime showed no reboot (cable/port).
- `scripts/pull-media.sh B-target` at 10 % battery:
  ```
  /sdcard/./: 627 files pulled, 0 skipped. 3.8 MB/s (351061485 bytes in 88.203s)
  phone: find /sdcard/ -type f | wc -l -> 627    host: 627 files
  ```
  (the script first counted 0 on the phone: `/sdcard` is a symlink and
  `find /sdcard` does not follow it; fixed to `/sdcard/`).
- Partition backup needs root. Official TWRP for oneplus2 on dl.twrp.me:
  newest `twrp-3.2.1-0-oneplus2.img`; usable RAM-only with `fastboot boot`.

## 2026-10-25 ~11:52 — TWRP for the partition backup (owner's choice)

```
build/twrp/twrp-3.2.1-0-oneplus2.img   22712320 bytes   (dl.twrp.me, not in git)
sha256 343691d4e85d24896afe2bd7ab6125a5047a70aa1fb4bfbb2b1cd54f744a20c9 = published .sha256
gpg: Good signature from "TeamWin <admin@teamw.in>", key 1D8597D7891A43DF, 2017-12-10
file: Android bootimg, kernel 0x8000, ramdisk 0x1000000, page 4096
```
Plan: battery >= 20 % → `adb reboot bootloader` → `fastboot oem device-info`
→ `fastboot boot` TWRP (RAM only) → `scripts/backup-partitions.sh B-target`
→ `adb reboot`. Note: TWRP may write its settings file to /data/media/0/TWRP.

## 2026-10-25 ~12:00 — bootloader check: **locked**

`adb reboot bootloader` at 18 % battery, then:
```
$ fastboot oem device-info
(bootloader) Device tampered: false
(bootloader) Device unlocked: false
(bootloader) Charger screen enabled: false
(bootloader) console_locked: 1
$ fastboot getvar all
version:0.5  kernel:lk  product:msm8994  max-download-size:0x20000000
userdata 0xdbf7fbe00 (~55 GiB) ext4, system 0xa0000000, cache 0x10000000
```
Fastboot USB id 18d1:d00d. Stopped there as agreed (no `fastboot boot`):
`fastboot reboot` back to Android, airplane mode still on, Doze forced again.
Unlocking (`fastboot oem unlock`) needs the "OEM unlocking" switch in
Developer options first and **wipes userdata/cache**; it does not touch
modem, persist, modemst1/2, fsg or the bootloaders. Media already saved.

## 2026-10-25 ~12:05 — unlock, TWRP in RAM, partition backup

- `fastboot oem unlock` (owner's go-ahead, media already saved) → `OKAY`;
  phone rebooted, wiped userdata, came back in fastboot after ~108 s:
  `Device unlocked: true`, `Device tampered: false`.
- `fastboot boot twrp-3.2.1-0-oneplus2.img` (RAM only) → adb `recovery`,
  uid 0, 43 partitions. `recovery` partition still holds the stock OnePlus
  recovery (its hash ≠ TWRP); nothing was written to any partition.
- Two backup attempts lost adb: TWRP switches USB to MTP ~40 s after start
  (re-enumeration), and one unexplained reset into TWRP again (PMIC:
  power-off reason PS_HOLD, i.e. software reset, not undervoltage; pstore
  empty). Uptime afterwards stable. Script fixed: `ls -1` for partition names,
  stop as soon as adb is gone.
- Third run: **40 partitions, every image's sha256 = sha256 computed on the
  phone**, plus `system` (2.5 GiB) the same way. Skipped: userdata (just
  wiped), cache. Backup in `backup/B-target/` (not in git), `SHA256SUMS`
  re-checked on disk. Critical ones: persist 32 MiB, modem 80 MiB,
  modemst1/2, fsg, fsc, sec, DDR, sbl1, aboot, rpm, tz, hyp, pmic, devinfo.

## 2026-10-25 ~12:19–12:40 — first mainline RAM boots: no userspace

- `op2-s1-simplefb.img` (`fastboot boot`, 12:19:29): `Booting OKAY`, phone
  left USB and never came back; no NCM, no reset in 120 s+. Owner forced it
  off and back to fastboot.
- Stock boot.img (from the backup): header kernel 0x8000, ramdisk 0x1000000,
  tags 0x100, page 4096, **dt_size 0** (appended DTBs). 12 stock DTBs:
  msm-id `0xcf` × {0x10000, 0x20000, 0x20001} × board-id `<8 0 14049 11..14>`,
  pmic-id `0x10009 0x1000a 0 0`. Ours now mirrors that: 12 DTBs, one msm-id
  each (`scripts/build-kernel.sh`).
- Display note: the panel is command mode, so whatever the kernel draws is
  never sent to it; the screen cannot show progress. Diagnostics must come
  over USB, or from the phone's own behaviour.
- pstore after the hang: TWRP's 3.10 kernel attaches ramoops at 0xac000000
  (`ramoops: attached 0x100000@0xac000000`), finds no valid header and
  re-initialises it; no /dev/mem in TWRP. Nothing recovered (a forced
  power-off loses RAM anyway).
- New probes: init can return to fastboot by itself — IMEM restart reason
  0xfe87f65c = 0x77665500 (`FASTBOOT_MODE`, lk2nd target/msm8994/init.c,
  downstream `qcom,msm-imem-restart_reason@65c`), then `reboot -f`.
  `op2.probe=early` (right after mounts), `op2.probe=usb` (after 45 s of
  USB), deadman too. Kernel: soft/hard lockup + hung task → panic → reset
  (`BOOTPARAM_*_PANIC=1`, ints in 7.x).
- `op2-probe-early.img` (12:31:34): left USB, **not back after 180 s** →
  the kernel dies before userspace, and before the lockup detectors.
- Suspect: mainline msm8994.dtsi has `psci { method = "hvc"; }` and
  `enable-method = "psci"`; OnePlus's downstream uses
  `enable-method = "qcom,8994-arm-cortex-acc"` (no PSCI). If this phone's
  hypervisor does not answer PSCI over HVC, the first PSCI call in
  setup_arch hangs. Built `op2-probe-early-nopsci.img` (OP2_NO_PSCI: psci
  node and CPU enable-methods deleted; CPU0 only; restart via PS_HOLD).

## 2026-10-25 ~12:38–12:55 — PSCI was the hang; USB does not come up

- `op2-probe-early-nopsci.img` (12:38:01): **back in fastboot by itself at
  t=36 s** → mainline 7.3 boots on the OP2 and runs our init; the IMEM
  fastboot reboot works. Cause of the earlier hangs: msm8994.dtsi's
  PSCI-over-HVC, which this phone's hypervisor does not implement
  (downstream uses `qcom,8994-arm-cortex-acc`). `OP2_NO_PSCI` is now on.
- `op2-s1c.img` (full init, deadman 150 s): **no USB device at all**, and no
  return to fastboot after 9 min. Either a hard hang, or a reset into Android
  (wiped: setup wizard, USB charge-only → invisible). Owner put it back in
  fastboot.
- TWRP's ramoops (`/sys/module/ramoops/parameters`): 0xac000000, 1 MiB,
  record 4096, console 262144, ftrace 4096, ecc 0 (no pmsg in 3.10). Our DTS
  now uses that exact layout so TWRP keeps our zones.
- init sets the IMEM restart reason to fastboot as its first action, so a
  later watchdog/panic reset lands in fastboot with RAM intact.
- `scripts/cycle.sh`: boot → USB logs, or wait for fastboot → TWRP in RAM →
  pull pstore → back to fastboot. Running with `op2-s1d.img`.

## 2026-10-25 ~13:10–13:38 — bisect: the watchdog hangs the phone

Self-returning stop images (`op2.stop=<stage>`: reach the stage, wait 5 s,
IMEM fastboot + `reboot -f`):
```
13:11:00 stop=wd      HANG   (after `watchdog -t 5 -T 30 /dev/watchdog`)
13:35:39 stop=gadget  PASS   (watchdog not started; configfs gadget built,
                              not bound) — back in fastboot 13:37:26
```
- Starting the APSS watchdog (`qcom_wdt`, 0xf9017000, probed fine at boot)
  freezes the phone for good, no bite, no reset. Probably owned by TZ on this
  firmware. init no longer starts it (`op2.wdt=1` to try again). Consequence:
  a hang still needs the power key.
- The owner sees "fastboot" on the screen all the time: the panel is command
  mode, so it keeps the bootloader's last picture while our kernel runs. The
  host's USB log is the only truth (left USB 13:35:40 = our kernel running).
- Background runner was stopped from the app during the bisect; next stage
  (`stop=udc`, then the full image) not run yet.

### CORRECTION (owner, 2026-10-25 ~13:40)
The return to fastboot at 13:37:26 after `stop=gadget` was the **owner
pressing the keys**, not the probe. So `stop=gadget: PASS` is void. Asked
whether the 12:38:35 return of `op2-probe-early-nopsci` was also manual: if
so, the conclusions "userspace reached", "PSCI was the cause" and "IMEM
fastboot reboot works" are void too, and no mainline image is proven to
reach init. Until a signal the phone gives by itself is seen (USB, LED,
backlight), every result is "unknown", not PASS.

## 2026-10-25 ~13:50–14:05 — control test: the bootloader path works

- `op2-control-stock.img`: **stock OnePlus 3.10 kernel** (from boot.img
  backup, stock header 0x8000/0x1000000/0x100) + our initramfs (busybox +
  `tools/reboot-bl`: reboot(2) RESTART2 "bootloader"). 13:52:52 boot →
  left USB → owner: "sta bootando android" without touching it. So LK's
  `fastboot boot` path and our initramfs work; the stock kernel's reboot
  went to Android (the "bootloader" reason was not kept, but a reboot is a
  visible signal anyway). → The problem is our kernel / DTB, not LK.
- Owner: every earlier "return to fastboot" was manual; s1f showed no LED and
  no backlight change → our kernel never reached the LED driver.
- Size suspect: stock Image 16.9 MB; ours 31 MB, image_size 30 MiB, ending at
  0x1ed0000. aboot.img holds 0x01e00000 and 0x02000000 (the Nexus 6P DTB/
  ramdisk addresses) besides CAF's 0x02500000/0x02700000: if this LK puts the
  DTB at 0x01e00000, our kernel overruns it by ~0.8 MiB.
- Kernel trimmed (`-Os`; no NFS, kprobes, uprobes, ftrace, profiling,
  KALLSYMS_ALL, MD, SCSI; sound as modules): **Image 20.2 MB, image_size
  19.8 MiB, ends 0x1440000**. Images: `op2-small-early` (reboot as soon as init
  runs), `op2-small-full`.

## 2026-10-25 13:59 — FIRST MAINLINE BOOT (verified)

`op2-small-early.img` (trimmed kernel, image_size 19.8 MiB, no PSCI,
`op2.probe=early`): 13:59:00 boot → 13:59:01 left USB → **13:59:31 back on
USB as 2a70:f003 (Android starting)**. Owner confirms: phone not touched.
→ Linux 7.3 reaches our init on the OnePlus 2 and its reboot (IMEM fastboot
magic + `reboot -f` via PS_HOLD) works; LK ignores the magic after this kind
of reset and boots Android, as it did for the stock kernel's RESTART2.
**Root cause of all earlier hangs: kernel size.** At image_size 30 MiB the
kernel (loaded at 0x80000) reached 0x1ed0000, over the DTB this LK places at
0x01e00000 (the value found in aboot.img). `scripts/build-boot.sh` must now
refuse images ending above 0x01e00000.
Still open: whether PSCI is really unsupported (no-PSCI kept for now), the
watchdog finding (unproven, done with the oversized kernel).

## 2026-10-25 ~14:06–14:15 — shell on mainline, first picture, LED

`op2-small-shell.img` (no deadman). Host kernel log:
```
14:05:45 usb 1-3: New USB device found, idVendor=18d1, idProduct=d001
14:05:45 usb 1-3: Product: OnePlus 2 op2boot
14:05:45 cdc_ncm 1-3:1.0 usb0: register 'cdc_ncm' ... CDC NCM, 02:00:00:0b:02:02
```
NetworkManager profile `op2-usb` (host MAC 02:00:00:0b:02:02, 172.16.42.2/24,
never default) brings the link up by itself. Phone shell (`scripts/psh.py`):
```
Linux (none) 7.3.0-oneplus2 #5 SMP PREEMPT ... aarch64
model: OnePlus 2    mem: 3687892 kB    cpus online: 0
LK cmdline adds: androidboot.project_name=14049 androidboot.hw_version=14
  mdss_mdp.panel=1:dsi:0:qcom,mdss_dsi_jd35695_1080p_cmd ddr Hynix maxcpus=8
leds: op2:blue op2:green op2:red   fb0: simpledrmdrmfb 1080,1920 bpp=24
devices_deferred: (empty) — RPM, rpmpd, gcc, mmcc all bound
```
- WLED rejected: `invalid value for 'qcom,current-boost-limit'` (980; WLED4
  table 105/280/450/620/970/...) → 970.
- MDP state left by LK: CTL0 top 0x00021F20 (DSI0, command mode), VIG0
  src0 0x03400000, stride 0xCA8 (3240), size 0x07800438 (1920×1080),
  fmt 0x0002243F (RGB888); INTF timing engines off (command mode).
- **Picture:** `zcat /pattern24.raw.gz > /dev/fb0; devmem 0xfd90201c 32 1`
  (CTL0 + CTL_START) → owner sees the three bands with the white border.
  Owner also sees the LED blinking (red heartbeat over green+blue).
- `tools/op2-kick` (mmap /dev/mem, CTL0 CTL_START at 30 Hz) pushed to the
  running phone with ncat, started: owner sees the kernel console (tty0 on
  simpledrm's fbdev) with a counter updating every second. **The screen is
  usable** until the MDP5/DSI driver is done.

## 2026-10-25 ~14:15–14:45 — touch: controller alive, not sensing (blocked)

DTS: S3320 on blsp1_i2c2 @0x20 (`syna,rmi4-i2c`), IRQ GPIO 96, L22 3.0 V
(RPM, now with a 100 mA load vote → HPM), 1.8 V I/O via GPIO 74 (fixed
regulator), reset GPIO 31 hog high; i2c2 without DMA (BLSP BAM fails -22).
Results:
- `rmi4_f01: found RMI device, manufacturer: Synaptics, product: s3320,
  fw id: 2307489` → F01/F12/F55 bound, input "Synaptics s3320" (evdev now
  built in). Probe at boot is flaky (`set page failed: -6` some boots);
  re-bind later always works.
- **No touch events, no IRQ ever** (GPIO 96 idle high), with or without:
  F01 soft reset (0x26←1), hard reset pulse on GPIO 31 (devmem
  0xfd5111f4), F01_CTRL0 = 0x1c (TWRP's value; DTS `syna,nosleep-mode`
  was 1 = *allow sleep*, now 2), L22 HPM, frame kicks off/30/60 Hz.
- PDT: F34, F01 (cmd 0x26, ctrl 0x0e, data 0x04), F12 (ctrl 0x14, data 0x06),
  F54 (page 1), F1A (page 2), F55 (page 3), **F51 (page 4, OnePlus custom)**.
- **Control: TWRP (OnePlus 3.10) in RAM** → touch works (IRQs 74 idle →
  139 after taps). Register dump pages 0–4 identical to mainline except
  F01_CTRL0 (0x1c vs 0x04/0x38) and page-1 F54 data counters that run under
  TWRP and stay still under mainline: the controller is not scanning.
- TWRP takes the display over with "Continuous splash enabled" (no panel
  re-init); its touch driver: soft reset, mode 0x84, IRQ level-low, then on
  unblank a reset pulse — nothing we do not do. Rails in TWRP: L22 3.0 V on,
  L14 1.8 V (DSI vdd) on, S4 on, LAB/IBB off.
- Display is **in-cell** (Nura/pmOS wiki: "IPS LCD In-Cell"): touch sensing
  is time-shared with the JD35695 (Novatek) driver IC. Panel TE on GPIO 10
  (mainline: plain GPIO input; OnePlus: `mdp_vsync`), ESD-TE GPIO 108,
  external LCD bias IC enabled by PMI8994 GPIO 7 / GPIO 3.
- GPIO config of all 142 accessible TLMM pins dumped under mainline
  (`logs/touch/gpio-mainline.txt`) for a later diff against downstream.
Not found yet. Strongest remaining lead: in-cell sync between DDIC and touch
needs the display path as the downstream MDSS runs it (TE on GPIO 10 as
`mdp_vsync`, proper DSI host), i.e. the real display driver.
- Display driver gap: mainline has the DSI 20nm PHY for msm8994 but **no
  20nm DSI PLL**; downstream has `dsi_pll_clock_register_20nm`. Porting it is
  the way to a proper MDP5/DSI pipeline (days, not hours).
- Nura (= postmarketOS renamed): OnePlus 2 archived, 3.10 only, "Mainline:
  no"; nothing reusable beyond what pmaports already had.

## 2026-10-25 ~14:45–15:15 — real display driver (MDP5 + DSI), SSH

Display path in `kernel/dts/op2-display.dtsi` (`DTS_DEFINES=OP2_DISPLAY`):
fixed clocks `dsi0pll` 147.218 MHz / `dsi0pllbyte` 110.4135 MHz standing in
for the bootloader's DSI0 PLL (MMCC pclk0/byte0 cfg 0x100: PLL, div 1),
MDSS 0xfd900000 (SPI 83), MDP5 0xfd901000, DSI0 0xfd998000, 20nm PHY
0xfd998300/500/780, panel `oneplus,oneplus2-jd35695` (reset GPIO 78), TE
GPIO 10 `mdp_vsync`, rails L12/L14/L28 (always on), MDP SMMU
(`qcom,msm-iommu-v1`, TZ secure id 1, ns context 0xfd9d4000, SPI 47).
Kernel patches (`kernel/patches/`, applied by build-kernel.sh):
- 0001 **mainline bug**: msm8992/msm8994 missing from the UBWC table →
  msm-mdss probe -EINVAL on every Snapdragon 810/808 board. Upstreamable.
- 0002 hack: MDSS GDSC always on (the DSI PLL sits in it).
- 0003 hack: 20nm PHY keeps the bootloader's PHY+PLL (no host PHY reset,
  no PHY reprogramming), but clock-lane pre/post = 0x3e/0x20 (downstream
  panel DTS / bootloader CLKOUT_TIMING_CTRL 0x203E). Without the reset skip:
  `Failed to enable dsi byte clk` -16.
Result: `msm_mdp: MDP5 version v1.9`, IOMMU accepted by TZ, card1-DSI-1,
msmdrmfb, DSI commands acknowledged (dsi_isr counts), no pp-done timeouts
after the first two — **but the screen is black** (owner), also with
`panel_oneplus2_jd35695.keep=1` (no reset, no init), and stays fully dark
with WLED at 4095 and a white framebuffer → the backlight/panel goes dark
when DRM takes over. DSI reads from the panel (power mode, ID) get no
answer (-61) in every variant.
DSI register diff bootloader vs msm (`logs/dsi/`, `scripts/dump-dsi.sh`):
CLKOUT_TIMING_CTRL fixed (0x203E), EOT now on as bootloader; remaining:
TRIG_CTRL 0x4 → 0x80001004 (TE wait + block DMA within frame), MDP_CTRL2
burst bit, TIMEOUT_STATUS 1. PLL 0x160/0x168 differ but are calibration
results (CORE_VCO_TUNE, CORE_KVCO_CODE).
Panel driver: generated driver + `keep` parameter and a DCS status
read-back after init.

SSH: key `keys/op2_ed25519` (not in git), static dropbear 2026.94
(GPG-verified, password auth compiled out), root with that key in the
initramfs; `scripts/op2-ssh` / `keys/ssh_config` (host op2). Konsole windows
opened on the owner's desktop: live log + shell.

## 2026-10-25 ~15:15–15:35 — why DRM gives black; panel re-init by hand

- WLED (regmap 0-03): module on (0xd846=0x80), sinks 0+1 on (0xd946=0x30)
  at the bootloader's 2048; the mainline driver wrote its brightness to
  strings 2/3 (0xd977/0xd987) → needs `qcom,enabled-strings = <0 1>`.
- DRM pipeline: CTL0 → LM2 → PP2 (tear check on) → same INTF as the
  bootloader; DMA0 pipe fetches from IOVA 0x2000. MDP SMMU context 0
  (0xfd9d4000) is enabled (SCTLR 0x10E7, TTBR0 0x1078A000) but a forced
  fetch from the unmapped IOVA 0x80000000 (+CTL flush/start) raises **no
  fault**: MDP traffic does not go through our context bank, so it reads
  physical 0x2000.. → black frames; the DSI command DMA also uses IOVAs on
  6G, so panel commands/reads were garbage too. SMR/S2CR (global space
  0xfd9cc000) and the secure banks 0xfd9d5000/0xfd9d6000 are TZ-only: any
  read resets the phone (it comes back to fastboot by itself).
  → The DRM path is blocked on TZ's SMMU routing (same wall will hit the GPU).
- `tools/op2-dcs`: DSI command DMA by hand on the bootloader's link
  (physical buffer 0x03c00000, CMD_DMA_CTRL 0x14000000, TRIG_DMA). Writes
  work; DCS reads (BTA) time out and wedge lane 0 until reboot.
- Panel reset (GPIO 78: 1/11 ms, 0/2 ms, 1/12 ms) + downstream on-sequence
  (25 packets, 0 errors, `research/jd35695-on.seq`): the owner saw the
  console flash, then the screen went dark and stayed dark (also with a white
  framebuffer, CABC off 55 00, dimming off 53 24, 51 ff). Touch still not
  scanning (IRQ count stays at the reset's 1) — but tested with the panel dark.
- Back to the known-good state: bootloader panel + frame kick.

## 2026-10-25 ~16:00–17:45 — touch: PMIC diff, panel re-init window, TE

- PMIC full diff mainline vs TWRP (`tools/pmic-diff.py`, `logs/pmic/`):
  L16 (2.7 V, OnePlus "always-on, GPS power fix") off under mainline → now
  always on; pm8994 MPP4 = HDMI HPD; differing PMIC GPIOs are NFC/SD/haptics/
  keys; PMI GPIO 7/3 (LCD power enables) differ only in pull. L22 runs in LPM
  under TWRP (our HPM vote was not needed). Mainline's SPMI regulator driver
  would switch "unused" bootloader rails off after 30 s → added
  `regulator_ignore_unused`.
- WLED: `qcom,enabled-strings = <0 1>` (brightness now lands on strings 0/1),
  CABC removed. After the panel re-init the WLED stays on (no faults) but the
  panel goes dark: it is the panel that switches off, not the backlight.
- Touch during the lit window right after reset + on-sequence, owner rubbing
  the screen: 0 IRQs in 10 s.
- TE: never seen on GPIO 10 (panel TE) nor GPIO 108 (ESD-TE), neither in the
  bootloader state nor after `35 00`; `op2-kick te` (TE-paced kick):
  "600 frames, 600 without TE".
Reading: the panel, as driven by us (bootloader init or our init + free
running kicks), does not run the way the downstream MDSS runs it (no TE), and
the in-cell touch does not scan. Most promising route: a working DRM pipeline
— blocked by the TZ SMMU — via scanout/DSI buffers with IOVA == physical
address (the hardware bypasses the SMMU). Helper agent (gemini/) asked to
analyse the downstream MDP SMMU programming, display↔touch coupling and to
design that patch.

## 2026-10-25 ~17:50–18:00 — FOUND: GPIO 74; screen + TOUCH work

- Screen dark in every image since ~14:40. Known-good `op2-small-shell.img`
  (14:05) still showed the bands → regression. Bisect: current image minus
  the touch DT parts → picture back.
- Cause: GPIO 74 (OnePlus "synaptics,1v8-gpio") is left **output high** by the
  bootloader (cfg 0x2C0, io 3). Our `regulator-fixed` without
  `regulator-boot-on` drove it low at probe and high again only when the
  touch driver took it: that dip kills the in-cell panel (and the touch with
  it). Fix: `regulator-boot-on` + `regulator-always-on`; GPIO 31 no longer
  hogged (bootloader: input, pulled high outside).
- `op2-s2-fix74.img` (frame kick, WLED driver off): owner sees the bands and
  **the green LED follows the finger**. Phone log: 47 touches with
  coordinates (x=509 y=472, x=586 y=1179, ...), 262 IRQs on GPIO 96.
  → **Touchscreen works on mainline 7.3.**
- Earlier conclusions about the dark screen under DRM / after panel re-init
  are confounded by this bug and must be re-tested.
- Phone A (display broken) on USB in fastboot: serial <phone-A>, bootloader
  **unlocked**. Scripts now pin phone B (`OP2_SERIAL`, default <phone-B>).

## 2026-10-25 ~18:05–18:20 — the panel power recipe (screen + touch)

On the frame-kick image (WLED driver on: still fine, so WLED is innocent):
- `op2-dcs seq` (downstream on-sequence) **without** a panel reset: screen
  stays on. **With** the GPIO 78 reset: screen goes dark (and the in-cell
  touch with it), also when the touch is reset afterwards.
- LK's own command table found in aboot.img (`tools/lk-panel-cmds.py`,
  file offset 0x7d88c): same commands as the kernel DTS, no 2a/2b, waits
  11→120 ms, 29→64 ms.
- OnePlus power path (`vendor_lcd_power_on`, `mdss_dsi_panel_reset`):
  TPS65132 ±5 V enabled by PMI8994 GPIO 7 (+5 V, "en") then GPIO 3 (−5 V,
  "en_n") 2 ms later; off: en_n low, 5 ms, en low, 5 ms; reset after power.
- `tools/op2-gpio` (GPIO uAPI v1): PMI8994 GPIOs are gpiochip3
  "pmic@2:gpio@c000" (GPIO n = line n-1).
- Full OnePlus cycle — off commands (ff 10, 53 00, 28, 10), reset low,
  GPIO 3 low, 5 ms, GPIO 7 low, 100 ms, GPIO 7 high, 2 ms, GPIO 3 high,
  reset 1/11 0/2 1/12 ms, on-sequence, touch reset pulse (GPIO 31) and
  rmi4 re-bind → **screen on and touch working** (owner; 33 touches logged).

## 2026-10-25 ~18:20–18:40 — real driver: panel + touch OK, pixels black

- Panel driver now does the OnePlus power path in prepare (off commands,
  TPS65132 -5 V/+5 V off/on via PMI8994 GPIO 3/7, reset, on-sequence, touch
  reset on GPIO 31); GPIOs requested in their bootloader state.
- `op2-s5-drm.img` (msm.identity_iova=1): power mode 0x9c, ID aa 04 10,
  **touch works** (owner); screen "black with a barely visible glow"
  (backlight on, LCD black), also with a white framebuffer at brightness 4095.
- DSI pixel stream registers identical to the bootloader's (STREAM0
  0x0CA90039 / 0x07800438, CMD_DMA_CTRL, CLKOUT 0x203E, EOT); TRIG_CTRL TE
  bit and MDP_CTRL2 burst set back by hand → no change. DSI CMD_MDP_DONE
  interrupts follow frame updates (+11 for 20 updates): frames are sent.
- LM2 border colour forced white with the pipe unstaged (CTL0 layer2 = 0,
  flush LM2, start) → still black.
Open: MDP5 path of the mainline driver (CTL0 → LM2 → PP2, DMA0 pipe) vs the
bootloader's (VIG0, CTL_TOP 0x21F20); next step is to dump the bootloader's
CTL/LM/PP setup and compare.

## 2026-10-25 ~18:45–21:25 — real DRM display works

- `tools/op2-peek` + `scripts/dump-mdp.sh`: dump of all MDP5 blocks
  (msm8994 offsets from mdp5_cfg.c, base 0xfd901000) in the bootloader/kick
  state (`logs/mdp/bl.txt`) and under DRM (`logs/mdp/drm.txt`).
  Bootloader: VIG0 → LM0 → PP0, no tear check, CTL_TOP 0x21F20.
  DRM: DMA0 → LM2 → PP2, tear check on.
- On the kick image, moving the bootloader picture to LM2 and turning on
  PP2's tear check with DRM's values: picture still updates (flashes only
  from the unsynchronised 30 Hz kick). The MDP path is fine.
- Pitfall: under DRM the fbcon cursor blink commits ~5×/s and rewrites
  CTL/LM, undoing hand pokes within 200 ms. Earlier "LM border white" test
  was void. `echo 0 > /sys/class/graphics/fbcon/cursor_blink` first.
- Display clocks equal except mdp_clk_src: bootloader GPLL0/2 (300 MHz),
  DRM MMPLL0/2 (400 MHz); MMPLL0 lock bit set in only 3 of 12 reads. Moving
  MDP to GPLL0 did not change the picture (still open as a stability item).
- Panel accepts DCS in HS (display off/on in HS changes power mode), and
  20 white lines written straight into panel RAM (2C/3C via `op2-dcs`) did
  not show either → the panel itself was not showing its RAM.
- Re-sending `/etc/jd35695-on.seq` by hand made the picture appear, and the
  DRM framebuffer then updated live (noise band → white band). Bisecting
  the sequence: display on alone no; first half (TE, 2A/2B, 44) no;
  **`51 ff` alone yes**.
- Cause: the generated driver used `mipi_dsi_dcs_set_display_brightness(0x00ff)`,
  which sends `51 ff 00`; this panel takes it as brightness 0 (backlight on,
  picture black: the "faint glow"). Fixed with a one-byte `51 ff`.
- `op2-s8-drm.img`, clean boot, no manual step: console + noise band
  visible, touch works (owner). Touch reset now happens right after the
  panel reset, before the init sequence.

## 2026-10-25 ~21:25–21:40 — alert slider, keys below the screen, op2-keyled

- Alert slider: OnePlus "tri-state key" on TLMM GPIO 34 and 77, switches to
  ground, no external pull-up (both read 0 until the internal pull-up is on).
  Measured: top = 77 low, middle = both high, bottom = 34 low. DTS:
  `alert-slider` gpio-keys, KEY_F13 (top) / KEY_F15 (bottom), pull-ups.
  The helper's proposal (PMIC GPIO 4/5, GPIO 75) used commented-out camera
  keys and the hall sensor.
- Keys below the screen are not on the S3320 touch chip (its F1A raises no
  interrupt): they are a second Synaptics chip, S1302, RMI4 at 0x20 on
  BLSP1 QUP6 (0xf9928000), IRQ GPIO 67. F1A buttons: bit 0 back, bit 1
  recents → left key = KEY_APPSELECT, right key = KEY_BACK (owner-tested).
  Home (fingerprint sensor surface) gives nothing on the S1302: it is the
  FPC1020, SPI owned by TrustZone. Open.
- `tools/op2-keyled` (helper's code, slider codes adapted, touch events
  ignored) starts from init: LED colour per key / slider position.

## 2026-10-25 ~21:40–22:05 — phone A backup; towards ztOS on B

- Phone A (<phone-A>, TWRP 3.2.1 in RAM): partition backup done
  (`scripts/backup-partitions.sh A-broken`), all images match the phone's
  own hashes; userdata skipped (media already copied: 51,026 files).
- ztOS has no published release images: building its generic (QEMU target)
  root filesystem here (`installer/ztos_installer` run_stage only, no QEMU
  disk, so no mtools). Arch Linux ARM tarball from dk.mirror.archlinuxarm.org
  (md5 as published; the geo redirector gave ~170 kB/s), packages from the
  same mirror. The SDK apps (Welcome, WhatsApp, Music) are skipped: they
  need a prebuilt aarch64 GLES renderer the repository lacks.
- Owner OK'd erasing B's userdata (ext4, 55 GB, mmcblk1p43) for ztOS.
- initramfs: `op2.root=<dev>` mounts the ext4 root, stops every helper and
  `switch_root`s to systemd; USB gadget stays, IMEM still says fastboot.
  Kernel: CONFIG_CGROUP_BPF=y. Image `op2-s12-ztos`.
- `rootfs-overlay/` + `scripts/ztos-op2-overlay.sh`: fstab on mmcblk1p43
  (the QEMU fstab wants an EFI partition), NetworkManager usb0 172.16.42.1,
  ssh key, ZTMETRO_SCALE=3 with software OpenGL.

## 2026-10-25 ~22:15–22:50 — ztOS boots on B, ztMETRO up

- `root.img` (10 GiB ext4, sha256 ac294b8f…) streamed with gzip over the
  USB link into B's userdata (mmcblk1p43): 16 min at 10.8 MB/s (gunzip on
  one core). On-phone sha256 of the first 10 GiB matches.
- `scripts/ztos-op2-overlay.sh` applied (fstab, usb0, ssh key, scale 3).
- `op2-s12-ztos.img`: initramfs → switch_root → systemd → greetd →
  ztMETRO. ssh as root on 172.16.42.1 works (NetworkManager usb0).
  ztMETRO log: DSI-1 1080x1920@60, 360x640 points at scale 3, renderer
  llvmpipe (no GPU node in the DTS yet), 8 tiles, app list 21 rows; owner
  unlocked it by touch. Frames 700–950 ms (software GL on one core,
  maxcpus=1). Sensor hub warning screen (no sensors).
- Screenshots: no /dev/mem for RAM (STRICT_DEVMEM); `grim` 1.5.0 from the
  ALARM mirror installed by hand → `shots/ztos-1.png`.
- No RTC time: clock set from the computer by hand.

## 2026-10-25 ~22:50–23:45 — Adreno 430: probes and powers up, GUI use resets

- `kernel/dts/op2-gpu.dtsi` (DTS_DEFINES=OP2_GPU): gpu@fdb00000
  "qcom,adreno-430.2", SPI 33, clocks oxili_gfx3d/oxilicx_ahb/rbbmtimer/
  ocmemcx_ocmemnoc, GX GDSC, GMEM = OCMEM gmu_sram (CONFIG_QCOM_OCMEM=y:
  "8 ports, 3 regions, 32 macros"); GPU SMMU iommu@fdb18000 (msm-iommu-v1,
  secure id 18, banks gfx3d_user/priv, SPI 241) on the GX GDSC (with CX
  only, oxili_gfx3d_clk "stuck at off").
- VDD_GFX: pmi8994 S2 is an RPM corner rail; SPMI writes are undone (VSET
  0x84/0x85 = 0.74 V). mmcc now hangs off rpmpd MSM8994_VDDGFX with
  required-opps = nom → VSET 0xa1 (~0.885 V), genpd "gfx on 4".
- TrustZone answers -EINVAL to qcom_scm_restore_sec_cfg(18, …) both on
  resume and per context bank: patch 0005 treats -EINVAL as "nothing to
  restore".
- Firmware a420_pm4.fw / a420_pfp.fw from B's own system partition
  (LineageOS, /system/etc/firmware; sha256 cca23b69… / 1ceae8d1…), in
  `firmware/qcom/` (git-ignored) and ztOS /usr/lib/firmware/qcom/.
- Opening /dev/dri/renderD128 by hand (initramfs and ztOS without greetd):
  firmware loaded, OPP 180 MHz set, phone fine.
- Starting the ztMETRO session (even with LIBGL_ALWAYS_SOFTWARE=1, even
  after the GPU was initialised by hand) resets the phone silently back to
  fastboot: pstore console ends right after the firmware load / journald,
  no oops. Looks like a TrustZone/XPU reset from a bad bus access (GPU or
  its SMMU), not a Linux crash. Open.
- B back on `op2-s12-ztos` (no GPU) for the UI.
- With drm.debug: when the GPU firmware is in place the msm bind (and its
  first modeset) happens with the GPU loaded; the reset comes ~0.4 s after
  the panel's "after init". Display first, GPU later (hand-opened render
  node) survives. So: display (re)start while the GPU is loaded → reset.

## 2026-10-26 ~00:05–00:30 — ztOS kernel in B's boot partition; USB PHY

- A GPU-test reset came back as a cold boot: IMEM fastboot magic lost, LK
  booted the boot partition (LineageOS) → "Encryption unsuccessful" (its
  userdata is ztOS now). Owner: power, then power + volume up → fastboot.
- With the owner's OK ("se hai fatto i backup vai pure"; B boot.img backup
  checked against SHA256SUMS): `fastboot flash boot out/op2-s12-ztos.img`.
  ztOS now starts from flash.
- From flash the USB gadget binds (journal: "gadget on f9200000.usb") but
  the computer sees no device: mainline msm8994.dtsi has no USB PHY
  (QUSB2); LK only sets it up in fastboot. Workaround: `fastboot continue`
  from the fastboot screen. Proper fix: QUSB2 PHY node (helper task 19).
- The journal is persistent on userdata: `journalctl -b -1 -k` reads the
  previous boot from a later one.

## 2026-10-26 ~00:25–00:40 — GPU: the reset needs freedreno

- GPU and its SMMU pinned on (power/control=on) before the GUI: still
  resets. So not a power-collapse/lost-SMMU-state problem.
- GUI with MESA_LOADER_DRIVER_OVERRIDE=kms_swrast (Mesa never touches
  freedreno) and the GPU loaded in the kernel: survives. The reset needs
  freedreno, i.e. the GPU running commands (wlroots' GBM allocator uses
  freedreno even with LIBGL_ALWAYS_SOFTWARE=1).
- kgsl source added to research/lineage-kernel (sparse: drivers/gpu/msm).
  OnePlus describes the A430 as qcom,chipid 0x04030000 (patch 0); kgsl and
  mainline both turn top-level HW clock gating off for A430 patch < 2
  ("register read/writes dropped"). Patch 0006 adds 0x04030000 to the
  mainline catalog; DT now "qcom,adreno-430.0". Still resets with freedreno.
- Do NOT read IMEM above the restart reason: dumping 0xfe87f720 (tz-log)
  through /dev/mem reset the phone.
- B back on its flashed boot (op2-s12-ztos) via `fastboot continue`.
- OCMEM: mainline ocmem.c locks the graphics range through
  qcom_scm_ocmem_lock() when TZ offers it (as kgsl's ocmem_core.c does);
  no "could not lock" on GPU start. Probably not the cause.
- Open leads: GPU SMMU global registers (0xfdb10000, TZ restore refused, so
  SMR/S2CR may be unprogrammed or routing to a secure bank); A4XX secure
  video / trust registers; kgsl's per-A430 settings vs a4xx_hw_init
  (RBBM_WAIT_IDLE_CLOCKS_CTL2, SP regfile sleep, CP_DEBUG bit 14).

## 2026-10-26 ~00:45–00:55 — computer: btrfs metadata full, build moved

- git could not write its index: /home btrfs had metadata at 92% and no
  unallocated space. Owner ran `sudo btrfs balance start -dusage=20 /home`.
- ztOS build outputs moved to /run/media/matt/Games/Various/Development/
  oneplus2-ztos-build/ (NTFS): root.img (sha256 ac294b8f…, checked after
  copy) and root-staging.tar.zst (staged rootfs, numeric owners, made and
  checked inside `unshare --map-auto --map-root-user`; 4 gpg sockets
  skipped). Originals removed; README-moved.txt left in their place.

## 2026-10-26 ~01:00–01:15 — GPU: OCMEM GX clock missing; QUSB2 PHY data

- clk-smd-rpm's msm8994_clks has no RPM_SMD_OCMEMGX_CLK, although
  msm8994.dtsi gives it to the OCMEM node; ocmem.c takes the core clock as
  optional, so it was never voted. The OnePlus kernel drives
  clk_ocmemgx_core_clk from RPM. Patch 0007 adds OCMEMGX (MEM clock 2, as
  msm8974). Fits the reset pattern: GPU init works (no GMEM use), the first
  real render (GMEM in OCMEM) locks the bus. Test pending (`op2-s16-gpu*`).
- USB PHY (helper task 19 only found the board override; the node is in
  msm8994.dtsi:1992): qusb@f9b39000 "qcom,qusb2phy", vdd pm8994_s2_corner,
  vdda18 pm8994_l6, vdda33 pm8994_l24, qcom,qusb-tune = 0xa08391d5, clocks
  ln_bb_clk (ref), gcc_usb_phy_cfg_ahb2phy_clk, gcc_qusb2_phy_reset.
  Mainline phy-qcom-qusb2 (msm8996 config) is the candidate driver.
- `fastboot continue` does not always bring USB back (lost B once).
- 01:10 test, `op2-s16-gpu-nogui` + greetd with freedreno: still resets.
  clk_summary right before: only `ocmemgx_a_clk` listed (enabled count 0),
  no consumer shown for the OCMEM node on ocmemgx: check next whether the
  OCMEM driver actually gets and enables the new clock (and at what rate:
  ocmem.c sets 1000).
- Still open, in order: OCMEM clock really on; GPU SMMU global config
  (TZ restore refused); CP_DEBUG bit 14 for non-A420 (kgsl) missing in
  mainline.

### State at 01:15
- B: boot partition = op2-s12-ztos (ztOS, display, touch, keys, no GPU).
  USB from a cold boot needs the QUSB2 PHY (not done); `fastboot continue`
  works most times.
- GPU kernel images: out/op2-s16-gpu{,-nogui}.img (OP2_GPU, patches
  0005-0007) — RAM only.

## 2026-10-26 ~17:40 — helper agents driven from here

- `claude` with an OpenAI-compatible LLM gateway models hangs ("unrecognized_model"), so
  `claudefree` cannot work. an OpenAI-compatible LLM gateway (https://<private LLM gateway>) speaks the
  OpenAI API at /v1 with tool calling (288 models, router "auto").
- `tools/helper-agent/agent.py`: one task file → tool-using agent
  (list_dir, read_file, grep, write_file only under gemini/, run inside
  bubblewrap: read-only filesystem, no network). On finish it appends
  "FATTO <n>" to gemini/STATO.md; transcript in gemini/logs/<task>.jsonl.
- `tools/helper-agent/queue.sh [PAR] [MODEL]`: runs every gemini/tasks/*.md
  not yet FATTO, PAR at a time, exits when done (so this session is told).
- First queue: 20 Wi-Fi hardware, 21 Wi-Fi mainline, 22 Bluetooth,
  23 ADSP DTS proposal.

## 2026-10-26 ~17:50–18:15 — phone A for the agents; QUSB2 attempt; power key

- QUSB2 PHY (op2-usbphy.dtsi, CONFIG_PHY_QCOM_QUSB2=y, op2-s17-usb): B
  vanished from USB; the journal only has a 1 s, 631-line boot cut off in
  the middle of probing, i.e. a reset early in boot. Parked (OP2_USBPHY off).
- initramfs: network by serial — A (SECOND_PHONE_SERIAL) 172.16.44.1, MAC
  02:00:00:0a:02:xx; B 172.16.42.1 as before. Host profile op2a-usb
  (MAC 02:00:00:0A:02:02, 172.16.44.2) added with nmcli. ssh host `op2a`.
- helper agents: tools a_state / a_boot (only out/op2a-*.img, RAM) /
  a_shell (eMMC writes refused) / a_to_fastboot for tasks marked
  "telefono: A". Runner now nudges a model that writes a tool call as text
  or stops before writing its report (task 21 ended that way).
- op2a-s19-i2c: A image with BLSP2 QUP5 I2C (0xf9967000, TFA9890) on.
- ztOS power key: logind HandlePowerKey=ignore (as ztOS's S9 overlay;
  ztMETRO handles the short press), long press powers off. In
  rootfs-overlay and written to B.

## 2026-10-26 ~18:10–18:30 — GPU bisect with gpu-steps; TFA9890 found

- tools/gpu-steps (EGL surfaceless + GLES2, built on the phone): steps 1-2
  fine (eglInitialize; context: GL_RENDERER FD430, OpenGL ES 3.0 Mesa
  26.2.5). Step 3 (clear a 256x256 texture FBO + glFinish) resets the phone,
  also with FD_MESA_DEBUG=sysmem (no GMEM). So: the first GPU job that
  writes memory resets the phone; OCMEM is not the cause.
- All RAM is below 4 GiB (/proc/iomem up to 0xf7ffffff): no 32-bit IOVA
  truncation with identity IOVA.
- Third GPU SMMU bank (gfx3d_spare, SID 2) in the domain: B hangs at boot
  (no network). Reverted.
- Helper agents (task 24, on A): TFA9890 answers on i2c-2 (BLSP2 QUP5,
  0xf9967000) at 0x36 only with GPIO 106 low (reset active high); register
  0x03 = 0x80 (TFA9890 revision expected by tfa989x.c).
- Agents run "caveman": short prompt, tool output capped, old results
  compacted (Groq models have 2-8k tokens/min limits).

## 2026-10-26 ~18:45–19:05 — four CPU cores (no PSCI)

- The firmware has no PSCI; OnePlus's kernel uses enable-method
  "qcom,8994-arm-cortex-acc" (drivers/soc/qcom/cpu_ops.c, cpu_pwr_ctl.c).
- Patch 0010: arm64 cpu_ops "qcom,8994-arm-cortex-acc"
  (arch/arm64/kernel/smp_qcom_acc.c): SCM cold boot address at cpu_boot
  (at smp_prepare time SCM is not up: -12), then the ACC sequence of
  msm8994_unclamp_secondary_arm_cpu (GATE_CTL 1→3, PWR_CTL 0x79→0x7d→
  0x3d→0x3c→0x0c→0x8c), a wakeup SGI, minimal hotplug (park in WFI) so
  cpuN/online is writable. DTS OP2_SMP: ACC nodes for cpu1-3
  (0xf909b000 + 0x10000·n).
- Cores powered but never reached the kernel ("failed in unknown state
  0x0") until patch 0009: qcom_scm_set_cold_boot_addr() leaves out
  QCOM_SCM_BOOT_MC_FLAG_AARCH64 (OnePlus adds SCM_FLAG_HLOS), so TZ started
  them in AArch32. qcom_scm_set_cold_boot_addr_aarch64() fixes it.
- CPUs 0-3 (A53) online; ztMETRO llvmpipe "finish" 237 ms per frame
  (was ~1000 ms). The bootloader appends maxcpus=8 itself. initramfs onlines
  cpu1..N before switch_root.
- CONFIG_DEBUG_DRIVER off, LOG_BUF_SHIFT=19: early boot messages were being
  pushed out of the log buffer.
- A57 cluster (cpu4-7) needs its L2 powered first (power_on_l2_msm8994,
  SPM rail): not yet.

## 2026-10-26 ~19:05–19:20 — A57 cluster, temperatures, 4-core image

- A57 bring-up: L2 power-up (power_on_l2_msm8994: SPM Q2S 0x2, VCTL 0xb8 then
  0x30080 at 0xf9013000+0x1c, L2_PWR_CTL sequence at 0xf900f000, scm_io bit
  at 0xf911210c) + ACC: CPU4 boots ("0x100, 0x411fd071"), but (1) mainline
  refuses it late: Spectre-v2 and A57 errata 832075/1319367/1742098 were not
  enabled by the A53-only boot — patch 0011 adds
  arm64.late_cpu_conflicts=warn; (2) its PLL is not programmed: a shell loop
  that takes 10 s on CPU0 does not finish in 100 s on CPU4 (~19.2 MHz).
  A57 parked behind OP2_SMP_A57 until a cluster clock/cpufreq driver exists
  (helper task 34).
- Temperatures: no TSENS in mainline msm8994.dtsi. tools/op2-tsens.py reads
  TSENS (0xfc4a8000, status +0x1030+4n) with the 8994 fuse calibration of
  the OnePlus kernel (fuses 0xfc4bc000: two-point, base0 532, base1 839).
  Idle 38-45 °C; 4 A53 at 100 % for 60 s: max 54 °C, back to 46 °C in 10 s.
  Kernel TSENS driver proposal: helper task 35.
- op2-s31-ztos (OP2_DISPLAY OP2_SMP, no maxcpus): cpus 0-3 online at boot
  (initramfs), ztMETRO 73 frames in 11.1 s (154 ms each), 50 °C.
- Owner OK: `fastboot flash boot out/op2-s31-ztos.img` on B (sha256
  checked). Boots ztOS from flash with CPUs 0-3, 45 °C idle.
- Helper tasks 34 (A57 clock) and 35 (TSENS kernel patch) came back
  unusable (no addresses; an invented tsens_read_fuses()). Agents keep to
  look-up tasks; kernel code stays here.

## 2026-10-26 ~19:25–19:40 — GPU hang caught alive

- The phone resets on msm's hang *recovery*, not on the render: with
  debugfs dri/1/hangcheck_period_ms = 4000000000 it stays up with a hung GPU.
- tools/gpu-steps/gpu-regs.py (A4xx status regs via /dev/mem, GPU powered):
  hung on gpu-steps 3 (clear): RBBM_STATUS 0x800000b1 (GPU_BUSY, HI_BUSY,
  bits 4/5/7; CP ME/PFP idle), CP_RB_RPTR = WPTR = 0x20, IB1 at GPU address
  0x01059000 (IOMMU address, not identity) size 0x8d, no CP_HW_FAULT/PROTECT,
  GPU SMMU banks 0/1: SCTLR 0x10e7 (stall on fault) and FSR 0, no fault IRQ.
- Reading debugfs dri/1/gpu while hung resets the phone; reading the third
  GPU SMMU bank (0xfdb1a000, gfx3d_spare) resets it too (secure bank; that is
  also why putting it in our domain hung the boot).
- debugfs dri/1/rd captured the submit (logs/gpu/rd-step3.bin);
  tools/gpu-steps/rddec.py decodes rd + PM4 (a4xx.xml.h / adreno_pm4.xml.h
  names): a normal Mesa GMEM-binning stream (CP_SET_BIN, VSC, nested IB).
- Reading: the CP fetches fine (ring, IB1), the other GPU clients never
  complete memory traffic. Suspect the GPU SMMU global stream mapping
  (TZ refuses restore_sec_cfg for id 18). Helper task 37 on kgsl's flow.
- OnePlus msm8994-iommu.dtsi for the GPU SMMU: bank 0 (0xfdb18000) takes
  SIDs <0 1> (user and priv), bank 1 none, bank 2 (0xfdb1a000) secure with
  SID 2; plus 27 "qcom,iommu-bfb-regs/-data" writes at 0xfdb12000+ that
  msm_iommu_sec.c does from Linux even for TZ-owned SMMUs ("bfb settings are
  always programmed by HLOS"), right after msm_iommu_sec_program_iommu().
  tools/gpu-steps/gpu-bfb.py writes them: many differed (e.g. 0x2600 0→7),
  but done by hand on an initialised GPU the next job wedged the bus
  (gpu-steps zombie, GPU register reads hanging). They belong in qcom_iommu's
  probe/resume, before the secure-config call and with the GPU idle.
- Helper model quality (owner disabled codestral, dots-3-note, gemini
  flash-lite): good gemini-3.6-flash (task 20), ministral-3b on A (24).
- Patch 0012 (qcom_iommu writes the BFB list from DT on resume, before the
  secure-config call) + GPU on bank 0 only (op2-s32-gpu-nogui): B hangs at
  boot (no USB network). To look at: write the BFB set only once the SMMU is
  clocked and powered, or leave it out.

## 2026-10-26 ~19:55–20:10 — battery first; stricter helper rules

- Owner: battery is the priority, done by the helpers on phone A; stronger
  rules against invented data; no disk access on A (not wiped yet).
- Runner (tools/helper-agent/agent.py): on A, any command naming block
  devices (/dev/mmcblk*, /dev/block, by-name, /sys/block), dd, partition
  tools, mount other than debugfs/sysfs/proc/configfs/tmpfs, reboot/sysrq is
  refused; register writes (devmem with a value, i2cset, writes into /sys)
  only when the task says "permessi: scrittura-registri". Provenance check:
  every hex value and file:line in a written report must appear in this
  task's tool outputs; otherwise the model is sent back (up to 6 times) and
  what is left is listed at the end of the report as NOT verified.
- B back on its boot partition (op2-s31-ztos) after the 0012 hang.
- Queued: 40 (A, read-only PMI8994 charger/FG register dump), 41 (meaning
  of those registers from qpnp-smbcharger.c / qpnp-fg.c).
- Battery (helpers on A, tasks 40-42, checked here): PMI8994 SID 2 blocks
  0x1000 CHGR, 0x1100 OTG, 0x1200 BAT_IF, 0x1300 USBIN, 0x1400 DC (type
  0x02); FG 0x4000/0x4100/0x4400 (type 0x0d). A on our kernel: CHGR_STS
  (0x100e) 0x80 = not charging with USB present (0x1310 0x04), SOC_MONOTONIC
  (0x4009) 0x3b → 0x3a in 60 s (23.1 % → 22.7 %). B (fastboot continue):
  0x100e 0x05 charging, 0x1310 0x24, SOC 0xb4 = 70.6 %. A sent back to
  fastboot. Task 43: how the OnePlus driver enables charging.

## 2026-10-26 ~22:45 — battery driver (patch 0013)

- drivers/power/supply/op2-battery.c (patch 0013, CONFIG_BATTERY_OP2=y,
  kernel/dts/op2-battery.dtsi, always included): writes the charger set-up
  LK leaves on a charging B (FCC_CFG 0x04, CHGR_CFG2 0xd2, IL_CFG 0x07 with
  SEC_ACCESS, CMD_IL 0x07, CMD_CHG_REG 0x02→0x00) and registers
  /sys/class/power_supply/battery (status from CHGR_STS, present from
  BAT_IF 0x1208 bit 7, capacity = FG SOC_MONOTONIC 0x4009 ·100/255).
- On A: registers already held B's values; CHGR_STS 0x80 = CHG_EN (bit 0)
  off, FG SOC 0, no BAT_IF faults. Owner: A's battery may be disconnected.
  Not chased further; back to the GPU.

## 2026-10-26 ~23:00 — GPU: where it stops

- VBIF (gpu-regs.py now reads it): VERSION 0x20020000, GATE_OFF_WRREQ_EN 1,
  RD/WR limits 0x18181818 (the A430 values), XIN_HALT_CTRL0 0,
  XIN_HALT_CTRL1 0x001f0000 before and during the hang (kgsl waits for the
  low bits 0x1f as halt ack; the high bits are not explained).
- CP_IB1_BUFSZ falls from 333 to 0x8d: the CP consumed 192 dwords of the
  user IB (so SMMU translation of non-identity addresses works for the CP).
  Dword 192 is the CP_WAIT_FOR_IDLE right after the CP_INDIRECT_BUFFER at
  178 (IB2 0x1069000, 0xd7 dwords: shader set-up and the clear draw). The
  draw never completes: the 3D pipe (SP/VFD/UCHE, not the CP) stalls.
- Helper task 44: A420/A430 differences in Mesa (sources in
  research/other/mesa, sparse) and kernels.

## 2026-10-26 ~22:55–23:15 — GPU: A430 CP_DEBUG bit; s35 hung at boot (BFB)

- kgsl a4xx_start sets CP_DEBUG bit 14 on every non-A420 ("disable the speed
  up of bootstrap on A430"); mainline only sets the A420 bit 29. Patch 0014
  adds it. VBIF limits, SP regfile sleep, GMEM size (1.5 MiB) and hwcg for
  patch < 2 already match kgsl.
- op2-s35-gpu-nogui (0014) hung at boot: op2-gpu.dtsi still carried the BFB
  properties, so patch 0012 wrote them at probe (same as s32). They are now
  under `OP2_GPU_BFB` (off). op2-s36-gpu-nogui = 0014 without BFB, not tested
  yet (B needs a button reset to reach fastboot).
- gpu-regs.py also reads RBBM_CLOCK_CTL, RBBM_POWER_CNTL_IP,
  SP_REGFILE_SLEEP_CNTL_0, RBBM_POWER_STATUS (SP/TP power, bit 20), CP_DEBUG.
- Next suspect after 0014: OCMEM grant to the GPU (mainline ocmem.c locks
  the graphics region by SCM or writes GFX_MPU_START/END; 8994 TZ may refuse).
- Helpers: task 44 report is shallow and partly wrong ("mainline has no
  adreno_is_a430"); the report was written by ministral-3b-2512 and
  ministral-3b-latest. Tasks 45 (OCMEM 8994), 46 (CP start / ME_INIT dwords),
  47 (PCIe0 controller) queued. The A battery toggle test (s34) was stopped:
  A did not return to fastboot.

## 2026-10-26 ~23:15–23:45 — GPU: the draw needs both SMMU banks; not OCMEM

- s36 (0014, 4 cores): hard LOCKUP on CPU1 at 48 s while msm_open waited
  ~60 s for the firmware fallback (driver asks for "a420_pm4.fw" first, then
  "qcom/…"): an SMP problem during the wait, not the GPU. Tests below on one
  core (op2.smp=0).
- GPU on SMMU bank 0 only (since 3d89e1c): the first draw resets the phone
  silently, with or without 0014. Back to banks 0+1 (op2-gpu.dtsi): the draw
  hangs with the phone alive, as at 19:25.
- During the hang (s39, 0014): RBBM_POWER_STATUS 0x00140003 (SP/TP on),
  CP_DEBUG 0x02004000 (0014 active), RBBM_CLOCK_CTL 0, RBBM_STATUS 0x800000b1
  (only GPU_BUSY, HI_BUSY and unnamed bits 4/5/7: no pipeline block busy).
  0014 alone does not fix the hang.
- FD_MESA_DEBUG=sysmem (no GMEM/OCMEM): still hangs, and the CP has
  consumed the whole IB1 (BUFSZ 0). OCMEM ruled out; memory writes from the
  GPU through the SMMU never complete.
- CAF calls IOMMU_SECURE_PTBL_SIZE/INIT before IOMMU_SECURE_CFG; mainline
  only for a secure context. Patch 0015 (always for a secure-id SMMU):
  op2-s40 resets the phone during boot (retried 23:58: B came back in the
  flashed ztOS, so a reset, not a hang; the first time I had read the lost
  USB link as a hang). Parked in kernel/patches-off/. The crash log should
  be in B's /var/lib/systemd/pstore (archived by the flashed ztOS boot).
- Helpers: 45 empty ("non trovato" everywhere, codestral-2508), 46 partial
  (mistral-code-latest, misses the kgsl ME_INIT dwords), 47 usable
  (ministral-14b: apq8084 cfg_1_0_0 closest for PCIe). Task 48 queued: ztOS
  diagnostics / Settings > System hard-coded for the S9 (owner's request).

## 2026-10-26 ~23:50–00:00 — A for the helpers; ztOS tasks to the helpers

- A booted with op2a-s41 (latest kernel: display, 4 cores, 0014, no GPU),
  initramfs shell for the helpers (A is not wiped: no ztOS on A).
- Owner: ztOS tasks go to the helpers. 48 (S9 diagnostics) by
  ministral-3b-2512 missed every hard-coded line and invented a "max8998";
  verified by hand: ztmetro/settings/ztsettings.c 855, 861, 866, 1951, 2034,
  2143 (S9 / Exynos 9810 / Mali-G72 strings), 1247-1248 (s9p-panel
  backlight). Redone as task 50; task 49: does ztOS have a power-off menu.

## 2026-10-27 ~00:00–00:15 — s40 crash log; ztOS power key

- s40 console (from B's /var/lib/systemd/pstore, read from the initramfs
  with op2a-s41): "iommu sec: pgtable size: 151552" on the *display* SMMU
  (fd9d4000, probes first), log ends at 0.90 s: handing TZ the secure page
  table memory resets the phone. 0015 stays parked.
- postmarketOS msm8994 (6.16) ships no GPU node: no prior art to copy.
- Helpers 49/50 (ztOS): no power-off menu; ztmetro.c:9067 the power key only
  toggles the screen; reboot in ztmetro.c:7703, poweroff in csf/ztoscsf.c:461.
  Long press = logind HandlePowerKeyLongPress=poweroff (ours), no
  confirmation. Settings reads max170xx_battery, devfreq 17500000.gpu
  (Exynos paths) and shows fixed S9 strings (ui-50-settings-fissi.md).

## 2026-10-27 ~00:05–00:30 — GPU write test; ztOS power-off menu proposal

- tools/gpu-steps/gpu-memwrite.c: the smallest GPU job straight through the
  msm uapi (no Mesa): "nop" (only the kernel's fence write), "write" (two
  CP_MEM_WRITE into a buffer), "idle" (CP_WAIT_FOR_IDLE first). Built on B
  (s39, one core); run by memwrite-test.sh (log /root/memwrite.log). The
  USB link went at ~20 s: result unknown (B neither in fastboot nor on the
  network); asking the owner what the screen shows.
- Helper task 51 (power-off menu): the idea is fine, the patch is not (an
  invented server->power_key_timer, corrupt hunks, git apply refuses);
  mostly gemini-3.1-flash-lite-preview. Rewritten by hand:
  gemini/ui-51-menu-spegnimento-claude.patch (applies to the ztOS tree;
  not applied, not built, not tried): short press toggles the screen on
  release, holding 0.8 s opens dialog_show "power off / restart" (tap
  outside to cancel), actions run systemctl poweroff/reboot. Needs
  HandlePowerKeyLongPress=ignore in our logind drop-in when used.
- gpu-memwrite, mode "nop" (s39, one core): GPU id 430, cmd iova 0x1000000,
  dst 0x1001000, IB `c0001000 00000000`; the phone resets right after the
  submit (twice). The IB itself does nothing: what follows it is the
  kernel's fence write (CACHE_FLUSH_TS into memptrs). Mesa's clear hangs on
  its first memory write; the bare job resets on the kernel's. Reading:
  GPU reads go through, GPU writes do not — fits TZ refusing the GPU SMMU's
  secure config (sec id 18), which may also gate the GPU master's write
  access.
- CAF msm_iommu_sec_program_iommu: optional SMMU_INTR_SEL_NS write (needs
  "smmu_local_base", which the OnePlus GPU SMMU node does not have), then
  scm_restore_sec_cfg(sec_id, ctx number) per context at attach — same call
  as mainline's. RAM on B is all below 4 GiB (iomem up to 0xf7ffffff), so
  the s40 reset is not a >32-bit table address.

## 2026-10-27 ~00:20–00:45 — reboot into fastboot from Linux; power menu pages

- kernel/dts/op2-reboot.dtsi (always in): syscon-reboot-mode on the 4 bytes
  at IMEM 0xfe87f65c (OnePlus msm-poweroff.c restart_reason): bootloader
  0x77665500, recovery 0x77665502; no mode-normal, so a plain reboot keeps a
  magic written by hand. op2-s42-ztos (OP2_DISPLAY OP2_SMP, ztOS, 4 cores):
  `systemctl reboot --reboot-argument=bootloader` -> fastboot in 10 s.
  `--reboot-argument=recovery` also ended in fastboot: B's recovery
  partition still has the stock OnePlus recovery; the owner suggests TWRP
  there (backup/B-target/recovery.img is the current one) — waiting for OK.
- Power menu patch (gemini/ui-51-menu-spegnimento-claude.patch) now has
  pages, since dialog_show has two buttons: power off | restart >,
  restart | more >, fastboot | recovery; the next page is shown 220 ms later
  because the dialog closes right after its action. Compiled on B (patched
  copy in /root/ztm, wlroots 0.20.2): builds, strings present; not
  installed.
- Owner OK: `fastboot flash recovery build/twrp/twrp-3.2.1-0-oneplus2.img`
  on B (<phone-B>). Old recovery kept in backup/B-target/recovery.img
  (sha256 fec78226…). From ztOS (s42) `systemctl reboot
  --reboot-argument=recovery` -> TWRP 3.2.1-0 on adb in 16 s; `adb reboot
  bootloader` -> fastboot. Both reboot modes work.
- Owner OK: power menu installed on B. /usr/local/bin/ztmetro = the patched
  build (sha256 284d3066…), original kept as /usr/local/bin/ztmetro.orig-s9;
  logind drop-in (rootfs-overlay and B) now HandlePowerKeyLongPress=ignore.
  B running op2-s42-ztos (fastboot boot): ztMETRO up with the new binary.
  Waiting for the owner's hands-on test.
- Owner test of the menu: "restart" went to fastboot, "fastboot" did
  nothing. Causes: (1) our initramfs writes the fastboot magic at the top of
  every boot (so a crash lands in fastboot) and nothing cleared it, so any
  plain reboot went to fastboot; (2) ztMETRO runs as zerone and
  `systemctl reboot --reboot-argument=…` needs root; ztOS's 99-ztos-shell
  (recovery only) is not even in this rootfs, so recovery would have failed
  too. Fixes: initramfs writes 0x77665501 (normal) right before
  switch_root unless op2.crash=fastboot (test images); sudoers
  rootfs-overlay/etc/sudoers.d/99-op2-reboot allows exactly the bootloader
  and recovery reboots for zerone; the menu's fastboot/recovery buttons call
  `sudo -n /usr/bin/systemctl reboot --reboot-argument=…` (new action
  reboot_recovery_only, no racing plain reboot as in ztOS's reboot_recovery).
  op2-s43-ztos = s42 kernel + this initramfs, booted on B; ztmetro rebuilt
  (sha256 e3c65363…) and running. To test again by the owner.
- A: display broken, the owner cannot see it; helpers drive A over the
  network only. Helper tasks 52 (GPU SMMU in CAF), 53 (PCIe PHY), 54
  (TFA989x), 55 (ADSP PAS) queued.
- Future test images get op2.crash=fastboot on the command line.
- Normal reboot tests (owner asleep, then awake): (1) plain `systemctl
  reboot` from s43 landed in TWRP: the PMIC also keeps a reboot reason
  (PON_SOFT_RB_SPARE; s44 dmesg: "reboot reason 0x1 cleared" = recovery,
  left by the recovery test). Patch 0016 (qcom-pon, DT
  qcom,clear-reboot-reason) clears it at probe. (2) still TWRP: the OnePlus LK
  boots recovery on IMEM 0x77665501 too, so the initramfs now writes 0 before
  switch_root. op2-s45-ztos (s44 kernel + that initramfs) flashed to B's boot
  (fix of my s43 bug).
- USB network after a normal boot from flash: ztOS boots fine but the UDC
  stays "not attached" (journal of that boot); rebinding the gadget does not
  help: the QUSB2 PHY is only set up when LK itself used USB (fastboot boot).
  Needs the QUSB2 PHY driver (op2-usbphy.dtsi, parked). op2-usb-watch
  (rootfs-overlay, service enabled on B) logs and repairs what it can; its
  fastboot fallback flag /etc/op2-usb-fallback is removed (it would send
  every cable-less boot to fastboot after 3 min).

## 2026-10-27 ~00:55–01:15 — GPU SMMU global space is TZ-only; CAF-style secure tables

- Helper 52 (good): in the secure case CAF leaves SMR/S2CR/CBAR to TZ
  (msm_iommu-v1.c:840, 718-737). tools/gpu-steps/smmu-glob.sh reads the GPU
  SMMU global registers one at a time: the very first (IDR0 at 0xfdb10020)
  resets the phone (log stops at "reading IDR0"). The whole global space is
  XPU-protected; only TZ can set up the GPU streams.
- CAF msm_iommu_sec_ptbl_init: IOMMU_SET_CP_POOL_SIZE (300 MiB, MP feature
  >= 1.1.1) first, then PTBL_SIZE/INIT with NO_KERNEL_MAPPING memory (CAF
  arm64 really unmaps it). Patch 0015 v2 (replaces the parked one): when the
  SMMU node has memory-region, of_reserved_mem_device_init + set_cp_pool_size
  + ptbl init; kernel/dts/op2-iommu-sec.dtsi (OP2_SECURE_PTBL): 256 KiB
  no-map shared-dma-pool below 2 GiB on both SMMUs.
- op2-s46-gpu-ptbl (one core, op2.crash=fastboot): after fastboot boot, B
  shows nothing on USB for 3 min (no network, no fastboot; the 18d1:d001 on
  the PC was A). Asking the owner what the screen shows.
- 0015 v2 step by step (op2-s47-ptbl1/2/3, kernel with qcom_iommu.ptbl_step,
  test images arm "reboot reason = bootloader" at PON probe via 0016 v2):
  step 1 (no-map reserved memory) ok; step 2 IOMMU_SET_CP_POOL_SIZE(300 MiB)
  returns 0 on both SMMUs; GPU secure config still refused after step 2.
  Step 3 (PTBL_SIZE/INIT): B shows neither network nor fastboot for 3 min
  although any reset should now land in fastboot: probably a hang in the TZ
  call; asking the owner what the screen shows.

## 2026-10-27 ~01:40 — helpers: token cap, new tasks, 15-minute check

- agent.py: all agents together at most 7000 tokens/min (OP2_TPM_LIMIT;
  shared ledger gemini/logs/tpm.ledger) — owner's cap.
- 53 thin (gemini-3.1-flash-lite-preview); 54 and 55 ran 80 steps without a
  report (closed, 54 redone short as 59). New: 56 QUSB2 "good" register
  values read on A (read only), 57 ath10k QCA6174 firmware files, 58
  Bluetooth QCA6174 pins/UART on the OnePlus 2 (mainline hci_qca has
  qcom,qca6174-bt; BT is on UART, separate from Wi-Fi's PCIe), 59 TFA9890 in
  tfa989x.c.
- Recurring check every 15 min (session cron): review reports, queue next
  tasks (Wi-Fi to see <home Wi-Fi>, audio with a quiet speaker->mic test, USB PHY,
  then GPU help).
- 01:55 check: no new reports; the cap leaked (17.6k tokens in a minute: two ~9k requests passed together on an empty ledger). agent.py now books its estimate atomically before each request (one over-cap request only on an empty minute), OUT_CAP 3500, compact keep=3. 56/57 (old code, 25 steps each, Qwen3.8-Flash-Next) stopped, to rerun; 58/59 running on the new code.
- 02:10 check: no new reports; 58/59 at 8-9 model calls each (Qwen3.8-Flash-Next), cap holding (4.2k tokens in the last minute). 56/57 queued to restart when this queue ends (gemini/logs/queue-56b.log).
- 02:25 check: 59 (Qwen3.8-Flash-Next) answer right — mainline tfa989x.c supports nxp,tfa9890 rev 0x80 (lines 50, 407) — but its compatible-table lines/text (286-289) are invented. 58 running; task 60 (TFA9890 DT node) added; 56/57/60 start when 58 ends.
- 02:38 check: no new FATTO; 58 (25 calls) and 59 (18, being sent back by the provenance check to fix line numbers) still working. Cap overshoot (10.8k/min): estimate now chars/3 + 1500 for the answer.
- 02:53 check: overshoot explained — 58/59 started 01:53, before the atomic booking (running processes keep the old code). Stopped; chained queue now runs 56, 57, 58, 59, 60 on the current agent.py (2 at a time).
- 03:08 check: no new reports; 56/57 running (17-18 calls), cap holding (~7.5k in the last minute).
- 03:23 check: no new reports; 56/57 at 28/23 calls. Requests grew to ~12k tokens each, so one alone exceeded the 7k cap: bookings now block 60 s x size/cap (12k -> ~103 s), OUT_CAP 2500, compact keep=2. Applies to the next tasks; 56/57 left to finish.
- 03:38 check: no new reports; 56 (34 calls, now reading lk2nd qusb2_phy.c) and 57 (31, ath10k firmware names) progressing; requests ~13.7k tokens on the old runner until they end.
- 03:53 check: no reports yet; 56 at 43 calls, 57 at 37. 57 copied gemini/wifi57/board-2-hw3.0.bin = the PC's linux-firmware ath10k/QCA6174/hw3.0/board-2.bin (sha256 66e83dde…, verified): generic QCA6174 hw3.0 firmware (firmware-4/6, board-2) is on the PC; OnePlus-specific board data still to find.
- 04:08 check: no reports; 56 at 48 calls, 57 at 47, still running.
- 04:23 check: no reports; 56 at step 44/80, 57 at 45/80 (about one step every 2 min under the cap).
- 04:38 check: no reports; 56 step 52/80, 57 step 51/80, neither has written its report yet (risk of hitting 80 steps; next tasks will be smaller).
- 04:53 check: no reports; 56 step 58/80 (has not used A yet, only file searches), 57 step 60/80.
- 05:08 check: no reports; 56 step 63/80, 57 step 68/80.
- 05:23 check: no reports; 56/57 near the 80-step end.
- 05:38 check: 56 and 57 hit 80 steps with no report (2.5 h lost; 56 never used A). Runner: max 25 steps, at 5 left it is told to write the report with what it has. New mechanical tasks: 61 (read 17 listed QUSB2 registers on A, read only), 62 (PCIe0 clocks OnePlus vs mainline 1_0_0). 58/59 running; 60, 61, 62 next.
- 05:53 check: no new reports; 58/59 (started 05:29 on the 80-step runner) stopped to rerun with 25 steps + forced report; 60 running now; 58, 59, 61, 62 follow (queue-61).
- 06:08 check: no reports; 60 running alone, 61 started beside it (queue-61 will skip it once FATTO).
- 06:23 check: 60 (qwen3.8-flash) — DT node usable and binding lines right; driver part partly invented (no 3.7 V set_voltage, vddd uses devm_regulator_get at 339 not _optional, gpiod at 345). Real point: no reset GPIO in driver/binding, so GPIO106 must be held low elsewhere (my job in the audio image). 61 running; task 63 (mainline LPASS direct DAI for 8994?) added; 58, 59, 62, 63 next.
- 06:38 check: 60 had written its report but ended '25 passi senza fine' -> marked done; runner now marks a task done when all its reports exist at the step limit. Found why 56/61 never touched A: A tools need a line starting 'telefono: A' (I had it in the title). 61 fixed and restarted. 58/59 running; 62, 63 next.
- 06:53 check: no new reports; 61 was reading A one register per step: the write filter took 'devmem A 32; devmem B' for a write (\S+ crossed ';'). Filter now stops at ; & |, tested (reads pass, 'devmem A 32 V' still refused); 61 restarted. 58/59 running.
- 07:08 check: no new reports; 61 reading QUSB2 registers on A (bytes repeated across 32-bit reads, e.g. 0x19191919: 8-bit registers), 58/59 still running; 62/63 queued.
- 07:23 check: no new reports; 58, 59, 61 running (shared cap: about one model call a minute in total).
- 07:38 check: 58 (qwen3.8-flash/Qwen3.8-Flash-Next) good — BT_EN = PM8994 GPIO 19, supplies S4/L30 1.8 V, BLSP2 UART2 at 0xf995e000, board 14049 includes msm8994-mtp.dtsi; errors: compatible is qca,qca6174, wake-gpio line wrong, btqca.c does name nvm files. Task 64 (ROME firmware names, PC copies, mainline UART node) added.
- B after the step-3 test (s47-ptbl3, ~01:38): not hung. pstore (read with
  the light image) shows a ztOS boot of 22205 s ending in the owner's menu
  reboot to bootloader; op2boot.log: flashed s45 cmdline,
  androidboot.startupmode=pwrkey. So step 3 (TZ PTBL_SIZE/INIT) shut the
  phone down or reset it past the test-image fastboot arming, then a power-key
  start ran the system on flash for ~6 h without USB network. The secure
  table hand-over is fatal on this TZ as done by mainline.
- 0015 v3: table memory handed to TZ by physical address only (rmem lookup,
  never mapped; ptbl_step 1 find, 2 pool, 3 size, 4 init). op2-s48-ptbl3:
  steps 1-3 ok on both SMMUs (151552 bytes asked, 256 KiB at 0x7ffc0000).
  op2-s48-ptbl4: B gone again (no network, no fastboot for 3 min) — so the
  linear/WC mapping was not the cause. Next variant op2-s49-ptbl4-gpuonly:
  only the GPU SMMU hands the tables over (the display SMMU, first to probe,
  is live with the boot splash; OP2_SECURE_PTBL_MDP to put it back).
- 08:02 check: queue-61 had made its list at 06:26, so it reran 60 (done) and a second 61 beside mine: both duplicates stopped; 58/59 (reports present, old runner) marked done. queue.sh now re-checks FATTO and running agents before starting each task. Running: 61 (A), 62 (Wi-Fi PCIe clocks), 63 (LPASS direct).
- 08:17 check: no new reports; 61/62/63 running; 64 (Bluetooth firmware) chained after the current queue (queue-64.log).
- 08:32 check: A was in fastboot — task 61 had left its task and read random MMIO (0x80000000, 0xf9000004, 0xf9021000...): an off block read resets the phone. 61 stopped; its 17 QUSB2 reads (all done before that) written up by me in gemini/usb-61-qusb2-a.md: LK's MSM8994 values differ from mainline msm8996 in almost every register (PORT_TUNE1-4 24/c5/01/10, PLL_USER_CTL1 f9, AUTOPGM 95, TEST2 08). agent.py: devmem on A only inside 'indirizzi: 0xA-0xB' ranges the task lists (none = no devmem). A booted again with op2a-s41. 62/63 running.
- 08:40 owner: after the s48 step-4 test B again came up in the system on flash (ztOS fine) — the TZ crash resets the phone fully, past the PON fastboot arming. OnePlus DT: secure_mem = 300 MiB CMA (= the cp pool size) used by the GPU secure context (fdb1a000, SID 2) and the ION CP_MM heap; the CAF ptbl memory itself comes from a dummy device (default CMA). Next: s49 (tables handed over by the GPU SMMU only).
- 08:47 check: no new reports; 62/63 running; 64 queued.
- op2-s49-ptbl4-gpuonly (tables handed over by the GPU SMMU only): same, B
  gone — not the live display SMMU. Mainline ptbl_init call matches CAF
  (args addr/size/spare, RW/VAL/VAL; SMCCC 32 here, legacy path has a 12-byte
  response buffer). Next: op2-s50-ptbl4-1m, region 1 MiB aligned to 1 MiB.
- op2-s50-ptbl4-1m (1 MiB aligned region): B gone again right after boot (owner confirms) — alignment/size is not it either. The TZ PTBL_INIT call as mainline makes it is fatal on this phone whatever memory it gets.
  (a 'fastboot devices' right after showed <phone-B> for a moment, then nothing: LK passing through, not a stop in fastboot)
- TZ diagnostic log: OnePlus DT qcom_tzlog at 0xfe87f720 (0x2000) — the very
  address whose read reset the phone in an earlier session, so TZ's own reason
  for killing the ptbl init cannot be read from Linux as things stand.
- GPU status: TZ refuses the GPU SMMU secure config (id 18) without the
  secure page table pool; handing the pool over (PTBL_INIT) resets the phone
  in every variant tried (mapped/unmapped, 256 KiB/1 MiB aligned, display+GPU
  or GPU SMMU only). Without TZ's config, GPU writes never complete (or reset).
- 09:08 check: 62 (gemini-3.6-flash etc.) honest but cut short by OUT_CAP; mainline 1_0_0 lines verified, OnePlus pcie0 clocks read by me: pipe, ln_bb ref, aux, cfg_ahb (iface), mstr_axi (master_bus), slv_axi (slave_bus), phy_ldo, phy_reset; gdsc_pcie_0, L12 1.8 V, L28 0.9 V. 63 (gemini-3.5-flash) correct: mainline direct LPASS DAI only for apq8016/ipq806x/sc7180/sc7280; audio needs the ADSP. New: 65 (PCIe PHY init seq), 66 (ADSP firmware files), 67 (QUSB2 tune via DT); 64 running.

## 2026-10-27 ~09:00–09:40 — Bluetooth bring-up (not answering yet); tasks

- Owner: pause the GPU; implement BT/Wi-Fi/USB/audio; helpers on GPU
  analysis, alert slider, home key + fingerprint (FPC1020, irq GPIO 90, reset
  89), all S9-specific code in ztOS (the BT switch in Settings does nothing),
  camera (an A camera watching B's screen).
- op2-bt.dtsi (OP2_BT): blsp2_uart2 on (no BAM), bluetooth { qcom,qca6174-bt,
  enable-gpios PM8994 GPIO 19 }, L30 1.8 V always on, bt_pa regulator-fixed on
  PM8994 GPIO 9 (OnePlus bt_vreg, also vdd-wlan) always on; CONFIG_BT,
  BT_HCIUART(_QCA), BT_QCA, RFKILL built in; firmware qca/rampatch_00440302.bin
  + nvm_00440302.bin from linux-firmware (rootfs-overlay, git-ignored).
- op2-s52-bt on B: hci0 appears, "setting up ROME/QCA6390", then "command
  0xfc00 tx timeout" / version read -110. /proc/tty/driver/msm_serial: tx:50
  rx:0, RTS|CTS. BT_EN high during the attempt, GPIO 9 high, S4/L30 on, pins
  45-48 blsp_uart8, WL_EN (GPIO 113) high: no change. OnePlus bluetooth-power.c
  does the same sequence (io, xtal, pa, reset 0/50 ms/1/50 ms).
- My mistake: a first GPIO 113 write used a 4 KiB stride (MSM8994 TLMM is
  0x1000 + 0x10*n) and hit another block: B reset (landed in TWRP).

## 2026-10-27 ~09:40–10:00 — USB PHY for MSM8994 works from reset

- Patch 0017 (phy-qcom-qusb2): qcom,msm8994-qusb2-phy = msm8996 layout, init
  table = the values LK leaves on a working phone (A, task 61: TUNE1-5
  24/c5/01/10/00, PLL_TUNE 00, USER_CTL1 f9, USER_CTL2 20, TEST2 08, AUTOPGM
  95, PWR_CTRL 10), differential ref clock (PLL_TEST reads 0), no lock bit
  (PLL_STATUS reads 0 on a working PHY: mask 0 skips the check).
- op2-usbphy.dtsi now without the L6/L24 regulator overrides (the s17 try that
  reset the phone set them). op2-s53-usbphy (fastboot boot): boots, USB network
  up in 8 s; ln_bb and cfg_ahb clocks enabled once each = qusb2_phy_init ran
  (PHY reset via QUSB2_PHY_RESET and reprogrammed) and USB still works.
- op2-s54-ztos-usb = s53 kernel (display, SMP, USB PHY) for daily use, to
  flash and test a normal boot (owner OK needed).
- 09:38 check: no new reports; 7 agents running at once (three queues): 64-70; a leftover copy of 63 (already done) stopped. 71-73 waiting in queue-71. Throughput is set by the shared 7k/min cap either way.
- Owner OK: s54 (display, SMP, USB PHY 0017) flashed to B's boot (sha256
  45caf2bb…). Normal boot from flash (fastboot reboot): after ~2 min B is not
  on USB at all (the 18d1:d001 on the PC is A, interface ...0a...). Asking
  the owner what B's screen shows.
- Model ranking from the verified reports (main model per task from the jsonl):
  gemini-3.5-flash (63 correct) > Qwen3.8-Flash-Next / qwen3.8-flash (52, 58,
  59, 60: substance right, line numbers often invented) ~ gemini-3.6-flash (62
  honest about what it did not see) > gpt-oss-120b/20b (47, 50 usable) >
  ministral-14b (47) > mistral-code-latest (46 partial) > ministral-8b >
  ministral-3b, gemini-3.1-flash-lite-preview (51 invented), codestral-2508 (45 empty).
- 10:05 check: no new reports; 64-70 still running (7 at once under the cap); 71-73 queued. B still off USB after the s54 normal boot (waiting for the owner).
- Owner: after the s54 normal boot ztOS runs fine on B, but no USB network: the QUSB2 driver alone is not enough from a normal boot. Next: read that boot's journal (qusb2/dwc3/udc, op2-usb-watch).
- s54 normal boot journal (read from s53 in RAM): PHY probes, gadget binds,
  op2-usb-watch: UDC "not attached" for 3 min despite rebinds. On a working
  (fastboot) boot QSCRATCH_HS_PHY_CTRL = 0x1d3279b2: UTMI_OTG_VBUS_VALID and
  SW_SESSVLD_SEL set (by LK). dwc3-qcom sets them only when the glue node is
  dr_mode peripheral (ours had it on the dwc3 child only): op2-usbphy.dtsi
  &usb3 dr_mode = "peripheral". op2-s55-ztos-usb flashed (fix of the same
  test): normal boot still not on USB after 150 s. Need that boot's journal.
- s55 normal boot dump vs fastboot boot: QSCRATCH HS_PHY_CTRL 0x1f3259b2 vs
  0x1d3279b2 (VBUS_VALID + SW_SESSVLD_SEL now set; bits 13/25 differ),
  SS_PHY_CTRL 0x71210002 vs 0x71210102 (bit 8), QUSB2 values identical, DCTL
  run in both, DSTS 0x008e0001 (link suspended) vs 0x00026020. PC journal: no
  connect at all on port 1-3 during the normal boot. CAF writes no other
  QSCRATCH bits (dwc3-msm.c, phy-msm-qusb.c only VBUS_VALID/SESSVLD).
- Suspect: PHY supplies off after a normal boot (LK turns L6/L24 on only in
  fastboot). op2-usbphy.dtsi: L6 1.8 V and L24 3.075-3.15 V (OnePlus
  msm8994-regulator.dtsi) as vdda-pll / vdda-phy-dpdm. op2-s56-usb-test from
  RAM: boots, PHY holds L6/L24 (so the s17 reset was not the supplies).
  op2-s56-ztos-usb flashed, normal boot: not on USB after 150 s; the owner saw
  B "stuck" and by mistake chose reboot to recovery (TWRP); back to fastboot
  with adb.
- op2-usb-watch now logs, 15 s after start, QSCRATCH HS/SS_PHY_CTRL, QUSB2
  PLL_TEST/TUNE1-4/POWERDOWN and dwc3 DCTL/DSTS. Fastboot (working) boot:
  QSCRATCH 0x1d3279b2/0x71210102, QUSB2 00/24/c5/01/10/22, DCTL 0x8cf00a00
  (run), DSTS 0x00026020. Normal boot of s55 started to compare.
- 10:35 check: report 66 (agnes-2.5-flash) good — ADSP firmware adsp.mdt/b00-b15 already in gemini/fw-A/image/ (copied from A earlier), OnePlus pas-id 1 / firmware-name adsp = mainline msm8996 adsp.mdt; line refs off by a few. 64-70 still running; 71-73 queued. USB: patch 0018 (HS PHY VBUSVLDEXT0) in s57, flash waiting for the owner's OK (auto-mode classifier refused it as irreversible).
- Owner OK: s57 (patch 0018, PHY VBUSVLDEXT0) flashed to B's boot. Normal boot: ztOS runs (owner), but still no USB interface on the PC. Need the op2-usb-watch register dump of this boot to see whether bit 13 got set.
- s57 dump: HS_PHY_CTRL still 0x1f3259b2 (bit 13 not set): MSM8994 binds dwc3-qcom-legacy (qcom,dwc3 with a dwc3 child), not dwc3-qcom; 0018 had patched the wrong file (bits 20/28 come from legacy's own override, mode read from the child). 0018 moved to dwc3-qcom-legacy.c; op2-s58-ztos-usb built; flash waits for the owner's OK (classifier).
- 10:50 check: 70 (agnes-2.5-flash) partly wrong (claims mainline has no PTBL_INIT wrapper; qcom_scm_iommu_secure_ptbl_init exists); causes are generic guesses. Idea to keep for the GPU: zero the no-map table region before PTBL_INIT (CAF's dma_alloc memory is zeroed, ours is not). 64-69 still running; 71-73 queued.
- s58 flashed (owner OK) and booted normally: still no USB network / no B interface after 120 s. Need its register dump (B in fastboot).
- s58 dump: HS_PHY_CTRL 0x1f3279b2 (bit 13 now set by 0018) — still 'not attached'. Left: HS bit 25 (set here, clear on fastboot boots; unnamed in CAF), SS_PHY_CTRL bit 8 = REF_SS_PHY_EN (CAF phy-msm-ssusb.c). Experiment via op2-usb-watch (/etc/op2-usb-qs25: clear bit 25 at boot), normal boot: still no USB after 120 s. Task 74 (one-screen power menu with icons, red Power off, capitalised labels) queued.
- 11:05 check: no new reports; 64-71 running (8 at once), 72-74 queued.
- 11:20 check: 64 (Qwen3.8-Flash-Next) file names right (btqca.c:831 qca/rampatch_%08x.bin, :925 qca/nvm_%08x.bin) but its quoted 'case QCA_ROME' block does not exist (invented). 65 (agnes-2.5-flash) DISCARDED: function right (pci-msm.c:967 pcie_phy_init, 20nm QMP) but values invented (POWER_DOWN_CONTROL 0x03 not 0x00, SYSCLK_EN_SEL_TXBAND 0x08 not 0x1C, ...). agnes-2.5-flash: 66 good, 65 invented. 66-71 running; 72-74 queued.
- 11:35 check: 69 (agnes-2.5-flash/Qwen3.8-Flash-Next) useful: OnePlus 2 home = the FPC1020 fingerprint sensor (SPI f9968000, irq GPIO 90, reset 89, vendor 91); fpc1020_tee.c sends KEY_HOME only when the Android fingerprint HAL writes sysfs report_home (lines 296-323); the irq handler (954) reports no key. Errors: an invented GPIO 41 1V8_EN, GPIO 91 missed. Next: check on A whether GPIO 90 moves when the home key is touched (owner's finger needed).
- 11:50 check: 68 (agnes-2.5-flash) GPIOs right (OnePlus msm8994-mtp.dtsi:585-587: key1 GPIO 34, key2 GPIO 77, pinctrl bias-disable) but logic and key codes invented. Real tri_state_key.c:104-118: GPIO77 low -> bottom (normal); else GPIO34 high -> middle (do not disturb); else top (mute). To do myself: gpio-keys switches on GPIOs 34/77. 66, 67, 69-71 running; 72-74 queued.

## 2026-10-27 ~11:55–12:15 — slider already in the kernel; Wi-Fi PCIe plan

- Slider: our DT already has gpio-keys "Alert slider" (dts:153-172): GPIO 77
  active low -> KEY_F13, GPIO 34 active low -> KEY_F15; by OnePlus
  tri_state_key.c:104-118 that is F13 = bottom (normal), F15 = top (mute),
  none = middle (do not disturb); the node's labels are reversed. Kernel side
  works (input3 "Alert slider"); ztOS ignores F13/F15: helper task 75.
- Wi-Fi: OnePlus pcie_phy_init (pci-msm.c:967-1039, 20nm QMP, 19.2 MHz),
  offsets flat in the PHY region (QSERDES_COM 0x000-0x168, TX 0x2xx, RX
  0x4xx-0x5xx, PCS 0x600-0x73c): POWER_DOWN_CONTROL 03, SYSCLK_EN_SEL_TXBAND 08,
  DEC_START1/2 82/03, DIV_FRAC_START1-3 D5/AA/4D, PLLLOCK_CMP_EN 03, CMP1/2
  06/1A, PLL_CRCTRL 7C, CP_SETI 1F, IP_SETP 12, CP_SETP 0F, IP_SETI 01,
  IE_TRIM 0F, IP_TRIM 0F (no vbg-opt), PLL_CNTRL 46, CDR_CONTROL1 F4,
  CDR_CONTROL_HALF 2C, VCOTAIL_EN E1, RESETSM_CNTRL/2 91/07, RES_CODE_START_SEG1
  20, RES_CODE_CAL_CSR 77, RES_TRIM_CONTROL 15, TX RCV_DETECT_LVL 03, UCDR
  FO/SO GAIN 09/04, SO_SAT 49, EQ_GAIN1 LSB/MSB FF/1F, EQ_GAIN2 FF/00,
  EQU_ADAPTOR_CNTRL2 1E, EQ_OFFSET_ADAPTOR_CNTRL1 67, OFFSET_ADAPTOR_CNTRL2 80,
  SIGDET_ENABLES 40, SIGDET_CNTRL B0, DEGLITCH 06, RXTXEPCLK_EN 10, ENDPOINT
  REFCLK_DRIVE 10, POWER_STATE_CONFIG1/2 A3/4B, RX_IDLE_DTCT_CNTRL 4D, then
  SW_RESET 00, START 03; ready when PCS_STATUS (0x728) bit 6 is 0.
- OnePlus msm_pcie_enable (pci-msm.c:3242+): PERST low, vregs, clocks, TZ
  restore_sec_config, PARF_PHY_CTRL bit0 = 0, DBI_BASE 0, SYS_CTRL 0x365E,
  SLV_ADDR_SPACE_SIZE, AXI halt bit, phy init, pipe clk, wait ready, PERST
  high, LTSSM bit 8, link up via ELBI_SYS_STTS.
- Mainline: no PHY driver for this 20nm QMP PCIe PHY; pcie-qcom cfg_1_0_0
  (apq8084) matches the controller but wants a "core" reset that gcc-msm8994
  does not have (only PCIE_PHY_0_RESET). Plan: patch 0019 PHY driver, 0020
  pcie-qcom msm8994 (optional core reset), DT node + WL_EN GPIO 113, ath10k +
  linux-firmware QCA6174 hw3.0. Tests from RAM only after the owner's go.
- Wi-Fi code written (not tested on a phone yet): patch 0019 new driver
  phy-qcom-pcie-msm8994.c (CONFIG_PHY_QCOM_PCIE_MSM8994; the CAF table in
  order, pipe clock after it, PCS_STATUS bit 6 poll); patch 0020 pcie-qcom
  "qcom,pcie-msm8994" (1.0.0 resources with optional core reset,
  PARF_PHY_CTRL power-up, PARF_SYS_CTRL 0x365e, TZ restore_sec_cfg(11) logged,
  PARF_LTSSM training); kernel/dts/op2-wifi.dtsi (OP2_WIFI): PHY + controller
  nodes, WL_EN GPIO 113 hog, GPIO 9 chip power, L30; CFG80211, MAC80211,
  ATH10K(_PCI) built in; ath10k QCA6174 hw3.0 board-2.bin/firmware-6.bin from
  linux-firmware (rootfs-overlay, git-ignored). op2-s59-wifi-test built
  (display, SMP, USB PHY, Wi-Fi; op2.crash=fastboot; RAM only).
- 12:20 check: 67 (agnes-2.5-flash) correct: read the tree with 0017 applied, msm8994_init_tbl (phy-qcom-qusb2.c:227-231) already holds A's TUNE values, DT tune properties (qcom,hstx-trim-value...) not needed. 66, 69-71 still running; 72-75 queued.
- op2-s59-wifi-test from RAM (owner OK): boots fine; TZ restore_sec_cfg(11) = 0
  (accepted, unlike the GPU's); PHY not ready: PCS_STATUS 0x68 (bit 6 still
  set), qcom-pcie probe -ETIMEDOUT. Order is right (PARF_PHY_CTRL before PHY
  power-on), L12 1.8 V / L28 1.0 V as OnePlus. Lead: CAF clock-gcc-8994.c:499
  pcie_0_pipe_clk_src is F_EXT(125 MHz, pcie_pipe) = the PHY's own pipe
  output, mainline gcc-msm8994.c:875-892 models it as XO (src 0) -> needs a
  "pcie_0_pipe" parent (from the PHY) in gcc-msm8994. Next step there.
- 13:55 check (after the usage pause): 73 (BT, qwen/qwen3.8-omni-flash:free) generic, no new evidence (suggests start-up timing). 72 camera partly wrong: says CAMSS has only msm8916 (camss.c:5743-5750 also msm8939/8953/8996...), no msm8994 indeed; sensors ov13860 rear, ov5648 front (OnePlus DT). 73/74 running, 75 queued.
- Wi-Fi iterations (all from RAM, owner OK; B stays up each time):
  s60 = patch 0021 (gcc-msm8994: pcie_0_pipe_clk_src parent "pcie_0_pipe"
  from the PHY, source 2 as CAF F_EXT(125 MHz, pcie_pipe)) + PHY registers a
  125 MHz fixed clock and sets the pipe rate: still "PHY not ready" 0x68.
  s61/s62 diagnostics: PCS_STATUS 0x68, PCS_STATUS2 0, RESET_SM 0x0 (reset
  state machine never started), CORE_VCO_TUNE 0x3f, START 3, POWER_DOWN 3;
  readback of the table (SYSCLK_EN_SEL 08, DEC_START1 82, PLL_CNTRL 46, CDR1 f4,
  EQ_GAIN1_MSB 1f, POWER_STATE_CONFIG1 a3) all as written: the PHY takes the
  writes but its PLL never starts -> suspect the 19.2 MHz reference does not
  reach it (ln_bb_clk voted as CAF: RPM XO buffer id 8) or a missing enable.
  TZ restore_sec_cfg(11) = 0 every time. Report 72: ov5648 (front) has a
  mainline driver (the report said no).
- 14:00 check: 71 (agnes-2.5-flash) correct: Settings BT switch = bluetoothctl power on (ztsettings.c:2377-2382, generic; works once hci0 answers); S9 service zrn-bluetooth (modprobe zrn-bt, ttySAC0, BCM4361) fails on OP2 -> to disable; also lists max77705-charger/max170xx paths (zrn-charge). 73 done (generic). New Wi-Fi tasks 76 (CAF ref clock / PARF_PHY_REFCLK / TCSR) and 77 (CAF vs mainline PCIe0 GCC registers); 74/75 running.
- 14:20 owner: image "Cyclone Zone.png" (2560x3200 PNG, 7 MB) copied to B
  /home/zerone/Pictures/Wallpapers (picker: "Your photos"), not set by me.
- Runner (tools/helper-agent/agent.py): per-model budgets. an OpenAI-compatible LLM gateway does
  not publish per-model limits (/v1/models has execution_status ready /
  exhausted / needsKey and supported_parameters only; x-ratelimit headers are
  the gateway key's 12000/120). So: model-limits.json (prefer order + tpm/rpm
  estimates, default 7000/10), --model auto now picks the first preferred
  model that is ready, supports tools and has room (ledger now "time tokens
  model"), falls back to the router "auto"; a model's 4xx rests it (until the
  429's retryAtMs, else 90 s / 15 min) and moves on; a short 429 lowers its
  tpm (gemini/logs/model-limits.learned.json). The owner's total cap
  OP2_TPM_LIMIT=7000 still applies and is the real bottleneck (~1 request a
  minute across all agents).
- S9 paths: on B the S9 BT/charge services are not installed (nothing to
  disable). Settings and ztoscsf read max170xx_battery / s9p-panel only:
  now they find the battery (S9 name, "battery", or type Battery) and the
  first backlight (ztOS commit). Installed on B (old binaries *.orig-s9),
  ztoscoresensorframework restarted. Battery on B: 94 %, Charging.
- New GPU analysis tasks: 78 (SCM convention: does the OnePlus arm64 kernel
  call PTBL_INIT as SMC64 while mainline uses SMC32?), 79 (CAF ptbl memory:
  device, zeroing, flush, order), 80 (GPU without the secure context).
  Queue queue-78.log started (it began with 76).
- 14:25 owner: total cap raised to 30000 tokens/min (OP2_TPM_LIMIT default),
  per-model limits stay. Test: qwen3.8-flash-next resting (429, quota),
  runner picked agnes-2.5-flash, answer in 1 s. 74/75 still run the old code
  (7000) until they end; new agents use 30000.
- 14:24 check: no new reports. 74 (step 19), 75 (step 15) running on the old runner (qwen3.8-omni-flash, some 502s). 76 starved since 14:17 (started with the 7000 cap while the old runners kept the ledger full): stopped by PID and restarted (queue-76b.log, PAR 2) with 78; queue-78 went on to 77. 79/80 pending. Cap 30000 per the owner's 14:25 decision (the check prompt still says 7000).
- 14:40 check: 77 (agnes-2.5-flash + mistral-code/devstral) DISCARDED: 4 of 7
  OnePlus registers wrong (pipe 0x1AD8 not 0x1AB8, aux 0x1AD4, cfg_ahb
  0x1AD0, PHY BCR 0x1B18 not 0x1A80). Checked myself: mainline gcc-msm8994
  matches CAF for all PCIe0 clocks and PCIE_PHY_0_BCR 0x1b18, BUT CAF has a
  second reset, PCIE_PHY_0_PHY_BCR 0x1B14 (bcr_reg of gcc_pcie_0_pipe_clk),
  deasserted by msm_pcie_pipe_clk_init (pci-msm.c:2666) right before the
  pipe clock; mainline has no such reset. On B (s62, after the failed PHY
  init): GCC 0x1b14 = 1 (asserted), 0x1b18 = 1, LDO 0x1e00 = 0. Lead for
  "PHY not ready": patch 0022 adds PCIE_PHY_0/1_PHY_RESET (0x1b14/0x1b94)
  and the PHY driver deasserts the optional "pipe" reset before the pipe
  clock; op2-wifi.dtsi passes it. Test image s63.
  78 (qwen3.8-27b, agnes, mistral-code) DISCARDED: quoted lines exist, the
  table and the conclusion ("OnePlus calls PTBL_INIT as SMC64") are made up:
  CAF scm_init tries SMC64 then SMC32 at runtime (scm.c:545-558), as
  mainline (qcom_scm.c:255+), and on B mainline gets "smc arm 32", so the
  SMC64 idea is ruled out. Running: 74, 75, 76, 79, 80.
- 14:45 s63 (patch 0022 + DT "pipe" reset = GCC 0x1B14 deasserted before the
  pipe clock): B reset into fastboot but did not show on USB (owner saw the
  fastboot screen). s62 booted fine after, pstore empty (hard reset, not a
  panic). s64 = s63 + initcall_blacklist=ath10k_pci_init: same (no network,
  not on USB after 3 min) -> not ath10k; the reset comes from deasserting
  0x1B14 / powering the PHY after it, or the controller once the link is up.
  DT "pipe" reset taken out again (patch 0022 kept, the reset is optional).
- 14:54 check: 74 (qwen3.8-omni-flash, agnes) and 75 (qwen3.8-omni-flash)
  DISCARDED: both patches corrupt (git apply: corrupt patch); 74 puts an enum
  inside struct zt_server, 75 never goes back to DND on release and forces
  ring_volume 21. 79 (agnes, mistral-code, qwen3.8-27b) DISCARDED: memset +
  dmac_flush_range at msm_iommu_sec.c:432-433 do not exist. 80 (agnes,
  devstral) shallow: lines 262/682 right, "probe fails at 675" wrong, no new
  facts. New tasks 81 (CAF msm_pcie_enable order), 82 (CAF branch BCR reset
  bits), 83 (ADSP pas node for msm8994), 84 (QSCRATCH HS_PHY_CTRL bit 25 in
  CAF); queue-81.log (PAR 2). 76 still running. B: not visible (s64).
- 15:10 slider direction: measured + OnePlus tri_state_key.c:104-118 agree:
  top = GPIO 77 low = KEY_F13 = MUTE, bottom = GPIO 34 low = KEY_F15 =
  NORMAL, middle = DND (task 75's brief had it backwards). ztmetro (ztOS,
  not committed yet: needs a build on the phone, wlroots-0.20 is not on the
  PC): one-screen power menu (hold power 800 ms: rows Power off in red,
  Restart, Fastboot, Recovery, drawn icons) and the alert slider (device
  "Alert slider": bottom ringer back to its level, top silent = ring 0 /
  vibrate, middle do not disturb = ring 0 and no buzz; start position read
  with EVIOCGKEY). 82 (devstral) CORRECT: CAF and mainline both toggle BCR
  bit 0 (clock-local2.c:67, reset.c:34-36), so s63's reset is not a wrong
  bit. 76, 81, 83, 84 done, not checked yet.
- 15:30 GPU analysis: our PTBL_INIT args match CAF (size, spare 0, pool
  300 MiB as args[0]=size, args[1]=spare). The difference is WHEN: CAF calls
  it once from a subsys_initcall (msm_iommu_sec.c:981-995), before any SMMU
  is probed or makes a secure call; we called it in an SMMU probe (display
  SMMU in s48, GPU SMMU in s49/s50 after the display's restore_sec_cfg).
  0015 v4: qcom_iommu.ptbl_early=1 does it at the start of qcom_iommu_init
  (before the SMMU drivers register; SCM is up at 0.10 s). Test image
  out/op2-s65-ptbl-early.img (OP2_DISPLAY OP2_GPU OP2_SECURE_PTBL,
  ptbl_step=4 ptbl_early=1, greetd masked), not run yet: B not visible.
- Patch layering: a later patch must not change lines of an earlier one
  (build-kernel.sh checks each patch reverses cleanly). 0022's PHY driver
  part folded into 0019; the early ptbl into 0015 (0023 dropped).
- 15:17 check: 76 DISCARDED (wrong REFCLK_STABILIZATION_DELAY_US_MAX: 1005,
  not 100; only lists defines; the REFCLK_CTRL2/3 PHY code it missed is
  FSM9010-only, pci-msm.c:667; ENDPOINT_REFCLK_DRIVE 0x10 is already in our
  table). 81 (devstral) DISCARDED: line numbers made up (PARF_PHY_CTRL is
  3290, phy init 3308, pipe 3314, ready 3323). 83 (mistral-code) mostly
  RIGHT: OnePlus lpass node values match (2099-2131), but it missed mainline
  qcom,msm8996-adsp-pil (pas.c:1838, msm8996_adsp_resource 1099-1111 with
  proxy pd "cx") and its draft is CAF-style. 84 (devstral) DISCARDED: says
  not found, HS_PHY_CTRL bits are at phy-msm-hsusb.c:52-79; bit 25 has no
  name there; bits 22/23 (USB2_SUSPEND_N / _SEL) are 0 in both dumps, so no
  forced suspend. New tasks 85 (exact CAF enable lines), 86 (mainline ADSP
  node from the msm8996 example), 87 (REF_SS_PHY_EN), 88 (SMMU secure ids);
  queue-85.log. B still not visible.
- 15:22 owner: menu and slider work on B (slider read as silent at start;
  zerone is in group input). ztOS commit aae4e8f.
- s65 (0015 v4, ptbl_early=1: PTBL_INIT when qcom_iommu registers, before
  any SMMU probe): B back in fastboot ~3 min after boot, pstore empty (hard
  reset). So the timing is not it either: PTBL_INIT is fatal on this TZ even
  done early, as CAF does it.
- Owner: power menu glitches. Two drawing faults fixed: no cairo_new_path
  before each icon (a stray line from where the last text ended to the
  circle) and labels top-aligned in the row (draw_text centres only with
  centre=true); now measured and centred on the icon. Rebuilt/installed on B.
- 15:30 check: 85 (agnes, mistral-code, devstral) DISCARDED: invented code
  and line numbers (steps every 5 lines, msm_pcie_phy_write(PARF_PHY_CTRL,
  0x365e) does not exist). 86 DISCARDED: its "msm8996 example" is the OnePlus
  node copied; the real one (msm8996.dtsi:3583) has reg 0x09300000,
  interrupts-extended with smp2p, power-domains cx. 87 (devstral) DISCARDED:
  "not found", REF_SS_PHY_EN is at phy-msm-ssusb.c:46, used 224-236. 88: no
  report. Cause: since the model picker most turns went to devstral-2 and
  mistral-code (learned tpm limits from 429s had pushed the good models
  down, e.g. qwen3.8-flash-next 2149). Fix: those two (and mistral-medium,
  ministral) out of the prefer list, learned tpm floor 4000, learned tpm
  cleared; 85-88 rerun (queue-85b.log), bad reports kept as *.scartato.
- Owner: power menu now OK (ztOS commit for the drawing fix).
- 15:35 old kernel for the GPU: Linux 6.12 from kernel.org (sha256 OK) in
  build/old/linux-6.12; it still has msm's allow_vram_carveout for a4xx
  (a4xx_gpu.c:705, adreno_device.c:19-21) — 7.3 only creates the GPU VM
  through the IOMMU (adreno_gpu.c:195). Agent tasks 89 (our patches on
  6.12, dry-run), 90 (config symbols), 91 (carveout), 92 (DT labels).
- Strada 2: patch 0023 adds qcom_scm_get_feat_version; 0015 v5 logs TZ's
  MP version and sets the pool size only from 1.1.1 (ptbl_pool=-1/0/1).
  s66 (ptbl_step=2): "MP version 1.1.1", pool size 0 -> same as CAF, no
  difference there. s67 = table at 1 GiB (OP2_PTBL_LOW, alloc-ranges
  0x40000000+256M) with step 4, not run yet: reboot to bootloader from s66
  went to ztOS on flash instead (owner), now in fastboot.
- 15:44 check: 85 rerun (agnes mostly) CAF part RIGHT (3278 clk_init, 3290
  PARF_PHY_CTRL, 3293 DBI_BASE_ADDR 0, 3295 SYS_CTRL 0x365e, 3298
  SLV_ADDR_SPACE_SIZE 16M, 3303 AXI_MSTR_WR_ADDR_HALT, 3308 phy init, 3314
  pipe clk); "our 0020 has none" WRONG (7 matches). Lead: we never write
  SLV_ADDR_SPACE_SIZE and write DBI base / AXI halt in post_init, after the
  PHY. 86 rerun (agnes, qwen3.8-max, qwen3.8-27b) RIGHT: msm8996 ADSP
  example (msm8996.dtsi:3583-3622) and adsp.yaml required (84-86) match;
  its smp2p label in the draft is to check. Running 87, 88, 89; 90-92 queued.
- 15:49 s67 (table at 1 GiB, early, step 4): B not back on the network nor
  visible in fastboot after 4 min -> same as s48-s50/s65. Strada 2 (TZ
  PTBL_INIT) closed: args, MP version, timing and address all as CAF, still
  fatal.
- s68 (owner: everything the agents finished, USB included; flash it if it
  behaves): OP2_DISPLAY OP2_SMP OP2_USBPHY OP2_WIFI, s58 cmdline. New:
  0018 v2 also sets SS_PHY_CTRL REF_SS_PHY_EN (bit 8: 0x71210102 on fastboot
  boots where USB works, 0x71210002 after a normal boot; CAF
  phy-msm-ssusb.c:245); 0020 v2 writes PARF DBI_BASE_ADDR 0 and
  SLV_ADDR_SPACE_SIZE 16M before the PHY (CAF pci-msm.c:3293-3299, report
  85). out/op2-s68-ztos.img, waiting for B in fastboot.
- 15:57 check: 87 rerun DISCARDED: CAF phy-msm-ssusb.c lines right (46,
  245, 354-355, 400-402) but dwc3-msm.c:124/129 "setbits REF_SS_PHY_EN" made
  up (no REF_SS_PHY_EN in dwc3-msm.c) and "legacy has no SS_PHY_CTRL" wrong;
  its conclusion matches what s68's 0018 v2 does. 88 RIGHT, nothing new:
  secure ids 1 (MDP) and 18 (GPU) as ours; CAF MDP SMMU 0xfd9cc000 (64 KiB)
  contains our 0xfd9d4000. Running 87, 89, 90; 91, 92 queued. B not visible
  (after s67).
- 15:58 s68 from RAM: ztOS fine, 4 cpus, UDC configured, no failed units,
  QSCRATCH HS 0x1d3279b2 SS 0x71210102; Wi-Fi still "PHY not ready" 0x68.
  Owner's condition met -> boot partition (mmcblk1p35) backed up to
  backups/boot-before-s68.img (== s58 image) and s68 flashed to boot only.
  Normal boot from flash: PC saw only the fastboot disconnect (15:58:45),
  no USB device after 3+ min -> REF_SS_PHY_EN alone does not fix USB after a
  normal boot. Need that boot's op2-usb-watch register dump (journal).
- 16:01 previous (normal, s68 from flash) boot's op2-usb-watch dump: HS
  0x1f3279b2, SS 0x71210102 (bit 8 now set), QUSB2 identical, DCTL
  0x80f00000, DSTS 0x008e0001 (USBLNKST 3 = suspended); fastboot boot: HS
  0x1d3279b2, same SS/QUSB2, DSTS 0x00825910. Only HS bit 25 left: enabled
  /etc/op2-usb-qs25 (clears it 15 s after start) and normal-booted: still
  no USB after 4 min. So bits 8 + 25 together are not it.
- op2-usb-watch now also writes a full dump per boot to
  /var/log/op2-usb-regs.<boot_id>.txt: QSCRATCH 0x8800-0x88ff, QUSB2
  0x9000-0x91ff, GCC 0x03c0-0x04ff and 0x1400-0x141f, to diff a normal
  boot against a fastboot one. Not on B yet (B normal-booted, not visible).
- 16:10 check: 89 DISCARDED: wrong on 5 of 22 patches (0013, 0016, 0017,
  0018, 0021) and made-up reasons ("4.14", "file removed"). My own dry-run
  of each patch alone on clean 6.12: FAIL 0001 (no ubwc_config.c), 0004,
  0010, 0012, 0013, 0018 (no dwc3-qcom-legacy.c in 6.12: USB glue must go
  to the old dwc3-qcom there); the rest apply (several with offsets; 0016,
  0021 clean). 87 still running (report rewritten 16:02, checked next time).
  Running 87, 90, 91; 92 queued.
- 16:24 check: 90 DISCARDED ("all 81 symbols exist"): on clean 6.12,
  BATTERY_OP2, DRM_PANEL_ONEPLUS2_JD35695, PHY_QCOM_PCIE_MSM8994 (ours, come
  with patches) and RMI4_F1A (touch keys; really absent in 6.12) do not
  exist. 87 final mostly RIGHT (CAF lines verified; dwc3-msm.c never touches
  bit 8; one error: legacy glue does have SS_PHY_CTRL). 91, 92 running; new
  93 (CAF msm8994 PHY table, pci-msm.c:967, vs ours), 94 (APR/Q6 services
  for ADSP audio, msm8996.dtsi:3606-3680); queue-93.log.
- USB dumps: good one (fastboot boot, s68 RAM) in logs/usbdump/good-fastboot.txt;
  B normal-booted 16:19 to write the bad one.
- 16:35 owner: live web dashboard of the agents -> task 95 (gemini/dashboard/op2-dash.py, port 8765); agent.py now logs t and usage per step. s69 (USB3 PHY resets + aux clock in op2-usbphy.dtsi, from the good/bad GCC dump diff: 0x1400/0x1404 asserted, 0x1408 off after a normal boot) built, not tested.
- 18:53 check (one for the checks missed while the owner's usage limit was
  hit): 95 dashboard WORKS (76 jobs, retroactive; old jobs show 0 tokens /
  0 duration, no t/usage in their logs): installed as
  tools/helper-agent/dashboard.py, queue.sh starts it on 127.0.0.1:8765 if
  not up; running now. My own diff of CAF pcie_phy_init (pci-msm.c:967) vs
  our PHY table: all CAF writes present with the same values (IE/IP_TRIM
  0x0f is the non-vbg-opt branch; only msm8992.dtsi sets qcom,vbg-opt), we
  add 0x41c and 0x4f0 (not in that function) and the order differs -> the
  table is not why the PLL does not start. 93 (agnes) shallow (4 regs).
  92 DISCARDED (blsp1_i2c2, blsp2_uart2 "missing" but in 6.12 msm8994.dtsi).
  91: key fact right (a4xx_gpu.c:696-708: allow_vram_carveout lets a4xx run
  without aspace), rest unchecked. 94 RIGHT (msm8996 APR example, 3623).
  New 96 (6.12 GPU without IOMMU: params, DT), 97 (PHY table in CAF order);
  95 rerun stopped and marked done.
- 18:54 check: no new reports (previous check 1 min ago); 96, 97 running.
- 18:58 s69 from RAM (fastboot boot, where USB always worked): B not on the network after 90 s, not in fastboot -> the legacy glue asserts then deasserts the listed resets: resetting the USB3 PHY that LK had set up breaks USB even here. Not flashed. Next: deassert-only (no assert) of USB3_PHY/USB3PHY_PHY resets + aux clock (s70).
- s70: 0018 v3 adds qcom,deassert-only-resets (glue releases the listed resets without asserting them); op2-usbphy.dtsi uses it with the USB3 PHY resets + aux clock. out/op2-s70-ztos.img, not tested (B not visible after s69).
- 19:10 owner: dashboard v2 (written by me): chat-app layout on one page
  (tasks list with search/filters, task "conversation" with model turns,
  tool cards, nudges and review steps, fixed right panel with details,
  reports, review verdict, .out log), "+ Nuovo compito" (POST /api/new
  writes gemini/tasks/NN-slug.md) and corrections (POST /api/correct appends
  "Correzione del proprietario" to the task, drops its FATTO line, starts
  queue.sh if none runs). All 78 tasks (20-97) listed; 95 shows done.
- agent.py review pass: when a task ends, the model with most steps is
  reviewed by a model ranked above it in model-limits.json "prefer" (ready,
  not resting), which writes gemini/review/<task>.md ("VERDETTO: OK /
  CORRETTO / SCARTATO" + errors) and may rewrite the report; if nobody ranks
  above (the worker was the best) or the reviewer fails, it writes
  gemini/review/<task>.claude.md for Claude's checks. --no-review skips it.
- 19:09 s70 (deassert-only resets + aux clock at 1.2 MHz): reset back to
  fastboot during boot. s71 (deassert-only resets, no aux clock): boots,
  USB fine from RAM, GCC 0x1400/0x1404 = 0 -> the aux clock (or its 1.2 MHz
  rate) caused the reset. s71 flashed (owner: flash when RAM test is fine),
  normal boot 19:12: still no USB after 3 min -> releasing the resets is not
  enough. s72 = resets + GCC_USB3_PHY_AUX_CLK on without assigned rate
  (OP2_USB3_RESETS OP2_USB3_AUX; the rate only with OP2_USB3_AUX_RATE).
  Flash now: s71 (backups/boot-before-s68.img = s58).
- 19:20 s72 (resets + aux clock, no rate) fine from RAM; flashed; normal
  boot: no USB. Diff vs good: GCC 0x1418 (aux RCG cfg 0 vs 0x1f = 19.2 vs
  1.2 MHz). The s70 reset was a mainline bug: usb3_phy_aux_clk_src has no
  parent_map, set_rate dereferences NULL -> patch 0024 (parent_map =
  gcc_xo_gpll0_map). s73 (0024 + OP2_USB3_AUX_RATE): fine from RAM, aux 1.2
  MHz like LK; flashed; normal boot: no USB. Now every dumped USB register
  (QSCRATCH, QUSB2, GCC USB) matches the fastboot boot after clearing HS
  bit 25 and writing PARAMETER_OVERRIDE_X 0x00d190e4 (new /etc/op2-usb-poke
  experiment in op2-usb-watch, QSCRATCH only) — still DSTS link suspended,
  PC sees nothing. The difference is outside those blocks: suspect the
  SMB1357 charger's D+/D- source detection (task 101) or Type-C.
- Owner: /etc/op2-usb-fallback now ON on B (no USB 180 s after boot ->
  reboot to fastboot); worked at 19:35. Flash now: s73.
- 19:40 check: review pass works: 100 reviewed by agnes (OK, I agree: vl6180.c:745-747, st,vl6180.yaml:29-31),
  98 and 101 handed to Claude. My reviews in gemini/review/: 98 OK (DRV2605 node is commented out in OnePlus,
  "we do not use it any more", mtp:492 -> vibration is likely PMI8994 haptics); 101 CORRETTO (SMB1357
  status="disabled" is active, mtp:1089, and it is only a parallel charger -> the main charger, and the
  D+/D- source detection suspect for USB, is PMI8994 smbcharger). 96 RIGHT (6.12: no iommus -> aspace NULL,
  msm_gpu.c:939-942; msm.vram default 16m, msm_drv.c:50-52). 97 values right, line numbers off by one.
  New 102 (PMI8994 APSD/HVDCP and D+/D-), 103 (PMI8994 haptics); 99 running.
- 19:38 check: nothing new since 19:37; 99, 102, 103 running; no reviews pending for Claude.
- 20:00-21:00 GPU on Linux 6.12 (VRAM carveout, no GPU IOMMU): 6.12 builds for OP2
  (scripts KSRC/KCONFIG_FRAG/DTB_OUT/SKIP_PATCHES/EXTRA_PATCHES, kernel/oneplus2-612.config,
  kernel/patches-612/, OP2_K612/OP2_GPU_NOIOMMU/OP2_MDP_NOIOMMU/OP2_GPU_HEADLESS/OP2_GPU_NOSRAM DT
  options, CPU refs by path, panel driver 6.12 compat, 0016 via reboot_mode.write). Mainline bugs
  fixed: 0024 gcc usb3_phy_aux_clk_src parent_map (USB), 0025 ocmem PSGSC stride 1->4 (alignment
  oops), 0026 ocmem: go on when TZ refuses the lock (-EIO; GFX MPU regs are secure, writing them
  resets), 0102 a4xx looks up OCMEM on the GPU node; 0101 VRAM for every object / carveout
  allocated via MDSS parent; 0103 op2_trace (msm.op2_trace=1). Headless GPU (amd,imageon compat,
  msm as module): "Initialized msm 1.12.0", /dev/dri/renderD128, firmware loaded; first use resets
  the phone: a4xx_hw_init reads RBBM_HW_VERSION 0x00010011 fine, reading VBIF_VERSION resets
  (MMCC: GX/CX on, gfx3d/ahb/rbbm/ocmemnoc/axi clocks on). On 7.3 VBIF was readable (GPU never
  used OCMEM there): testing s85 = no sram (no OCMEM). tools/gpu-test/gles-clear.py = Mesa EGL test.
  msm+display on 6.12 resets after mdp_clk_src "rcg didn't update" (display path, s80).
- 21:02 check: 102 (USB/PMI8994 APSD) reviewed by Claude: OK (5510-5511, 5653-5655, 1730 verified; no PMI8994 charger in mainline). Pending Claude reviews: 99, 103, 104, 106, 107; 105, 108 running. Nothing pushed to GitHub yet.
