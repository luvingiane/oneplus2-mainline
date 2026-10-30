# ztOS on the OnePlus 2 — status

OnePlus 2 (`oneplus2`, project 14049), Qualcomm MSM8994 (Snapdragon 810).
Target: ztOS (Arch Linux ARM + mainline Linux + ztMETRO), as on the Galaxy S9.
Strategy: mainline kernel, downstream 3.10 as reference only — see
[docs/STRATEGY.md](docs/STRATEGY.md). Hardware map: [docs/HARDWARE.md](docs/HARDWARE.md).
Backups and media recovery: [docs/BACKUP.md](docs/BACKUP.md).

**Works**: tried on the phone, does what it should. **Partial**: some of it
works; notes say what. **Blocked**: tried, stuck; notes say where.
**Not started**: nothing yet.

## Phones

| Phone | State | Bootloader | Backup | Media |
|---|---|---|---|---|
| **B (target)** `51c1ec64` | ONE A2003, H2OS 2.5.1 (Android 6.0.1, kernel 3.10.84), unencrypted, adb authorised, no root; worn battery (charges at ~1.5 A max); airplane mode + Doze to save power | **unlocked** 2026-10-25 (`fastboot oem unlock`, userdata wiped) | **done**: 40 partitions + system, hashes match the phone (TWRP in RAM) | **done**: 627 files, 342 MB, counts match, `backup/B-target/media-SHA256SUMS` |
| A (display broken) | serial 7485b821, TWRP 3.2.1 (RAM) | **unlocked** | **done** (all partitions but userdata, checked) | **recovered** (51,026 files, `backup/A-broken/media`) |

## Hardware (phone B, mainline)

| # | Category | Feature | Status | Notes |
|---|---|---|---|---|
| 1 | Boot | `fastboot boot` of a mainline image | **Works** (RAM boot) | 7.3.0, CPU0 only, 3.6 GB; kernel must end below 0x01e00000. Not yet flashed; SMP not tried |
| 1 | Display | Panel **jd35695 1080p command mode** (from the phone) | **Works (real DRM driver)** | MDP5 + DSI 6G + 20nm PHY + `panel-oneplus2-jd35695` (`op2-s8-drm`, `DTS_DEFINES=OP2_DISPLAY`, `msm.identity_iova=1`). Console and framebuffer updates visible, touch works alongside. Fix: panel brightness 0x51 sent as one byte. Open: MMPLL0 (MDP clock) loses lock, keep an eye on it |
| – | GPU | Adreno A430 (`card1`/`renderD128`, mainline msm) | **Works (7.3)** | SMMU attached unlocks VBIF + `msm.op2_gpu_phys=1` (physical iova, TZ refuses SMMU secure cfg); hw_init ret=0, gles-demo 2-3 ms/frame FD430, ztOS+ztmetro on card1 (s128). GMEM/OCMEM still locked by TZ -> FD_MESA_DEBUG=sysmem; devfreq off (0113) |
| 2 | Input | Touchscreen (Synaptics S3320, in-cell) | **Works** | RMI4 F12, multi-touch coordinates read. Needs GPIO 74 (1.8 V shared with the panel) never switched off. Probe at boot sometimes needs a re-bind |
| 2 | Input | Capacitive keys (Synaptics S1302), power/volume | Partial | Power + volume keys registered (pm8941_pwrkey, gpio-keys); S1302 not yet |
| 3 | Audio | Speaker (TFA9890) | **Works** | ADSP/q6 QUAT MI2S -> TFA9890, heard by the owner (s95) |
| 3 | Audio | Earpiece, headphones, mic (WCD9330) | Not started | No mainline codec driver |
| 4 | Network | Wi-Fi (QCA6174 on PCIe) | Not started | Needs msm8994 PCIe controller support |
| 5 | Network | Bluetooth (QCA6174 on UART) | Not started | `hci_qca` |
| 6 | Location | GPS (in the modem) | Not started | Needs MSS remoteproc + QMI LOC |
| – | Network | USB networking / ssh | **Works** | NCM 172.16.42.1 + DHCP + telnet; host profile `op2-usb` |
| – | Power | Battery, charging | **Works** | op2-battery (patch 0013) + APSD re-run (0x1341, op2-battery.dtsi): status=Charging con USB, 73% su B (s132) |
| – | LED | Notification LED (PMI8994 LPG) | **Works** | red/green/blue, heartbeat trigger |

## Software

| Feature | Status | Notes |
|---|---|---|
| Arch Linux ARM rootfs | Not started | Reuse `ztOS/scripts/build-arch-root.sh` |
| ztMETRO shell | Not started | After display + touch |
