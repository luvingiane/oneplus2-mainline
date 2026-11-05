# Wi-Fi and Bluetooth on mainline 7.3 (2026-11-05)

The QCA6174 of the OnePlus 2 is on **PCIe1** (PARF `0xfc528000`, PHY `0xfc52e000`,
DBI `0xf8800000`, PERST GPIO 35, WAKE 37, CLKREQ 36, scm-dev-id 12). Days of work went
into PCIe0, where the PHY PLL never locks because nothing is connected to it. The stock
device tree leaves the first controller disabled; the second one worked at once.

## What it took

1. DT for PCIe1 (`kernel/dts/op2-wifi.dtsi`, `OP2_WIFI_PCIE1`).
2. `gcc-msm8994`: wrong registers for `gcc_pcie_1_mstr_axi_clk` (0x1b50 -> 0x1b4c) and
   `gcc_pcie_1_cfg_ahb_clk` (0x1b54 -> 0x1b50), plus the pipe clock parent (patches 0162, 0164).
3. `pcie-qcom`: the 1.0.0 post-init wrote the DBI base and a 2 GiB slave window, which on
   PCIe1 covers the GIC at `0xf9000000` and hangs the machine on the first access. New
   `qcom_pcie_post_init_msm8994` without that window (patch 0165).
4. The stock `wlan-bootstrap-gpio` (TLMM 112) must be high before WL_EN (113), or the
   device is not found (`OP2_WIFI_BOOT`).
5. Firmware (`firmware-6.bin`, `board.bin`, `board-2.bin`, and for Bluetooth `rampatch_tlv_3.2.tlv`,
   `nvm_tlv_3.2.bin`) in the initramfs (`scripts/build-boot.sh` picks it up from `firmware/`, which is not
   published) and `CONFIG_FW_LOADER_USER_HELPER` off; otherwise every optional firmware costs a 60 s wait.

Result on the phone, about 9 s after boot: `wlP1p1s0` (ath10k, firmware 4.4.1), a scan finds the
neighbouring networks on 2.4 and 5 GHz, and the connection works through NetworkManager.
`rfkill unblock wifi` is needed at start.

Bluetooth: `hci0` comes up (QCA setup completed). The controller has an invalid factory BD address.

## Also in this round

- SoC temperature: 16 calibrated TSENS zones (patch 0159) and a throttling daemon. The A57 cluster
  reset seen on the second phone was a thermal trip at about 118 C.
- Haptic motor (patch 0163) and hall sensor (GPIO 75).
- A TrustZone application probe (`0160`, `scripts/fpc-tz-start.sh`) that brings the fingerprint
  trustlet up on a phone whose firmware images were extracted from its own backup. The firmware
  images are not published.

## Build

```
EXTRA_PATCHES=$PWD/kernel/patches-73 \
DTS_DEFINES="OP2_DISPLAY OP2_SMP OP2_USBPHY OP2_GPU OP2_GPU_RPMCLK OP2_CPUFREQ OP2_WIFI OP2_WIFI_PIPE_RESET OP2_WIFI_REFPIN OP2_WIFI_PCIE1 OP2_WIFI_BOOT OP2_BT OP2_TSENS OP2_HAPTIC OP2_SENSORS_HALL OP2_QSEE" \
SKIP_PATCHES="0150 0154 0158 0165" bash scripts/build-kernel.sh
```

`SKIP_PATCHES` is a trap fix: 0150, 0154, 0158 and 0165 touch the same place of `pcie-qcom.c`
and apply twice on a pre-patched tree, duplicating module parameters. Patches 0149-0158 are
the experiments that led to the PCIe1 finding and are kept for the record.
