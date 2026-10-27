# OnePlus 2 (oneplus2, "14049") — hardware

Sources: LineageOS `android_device_oneplus_oneplus2` (lineage-17.1) and
`android_kernel_oneplus_msm8994` (3.10.108), board DTS
`arch/arm/boot/dts/qcom/msm8994-mtp.dtsi` + `msm8994-v2.1-mtp_14049_HW_1x.dts`.
Everything below is to be **confirmed on the phone itself** (Phase 0 recon).

| Block | Part | Bus / where | Downstream 3.10 driver | Mainline 7.3 |
|---|---|---|---|---|
| SoC | MSM8994 v2.1 (Snapdragon 810), 4×A53 + 4×A57 | qcom,msm-id 207 | — | `msm8994.dtsi`: CPUs, GCC, MMCC, RPM, pinctrl, SPMI, eMMC (sdhci), USB (dwc3), BLSP i2c/spi/uart, SMEM. **No** MDSS, GPU, PCIe, remoteproc, audio nodes |
| Display | JDI 1080p video panel (`dsi_jdi_1080_vid`); a 2nd variant `dsi_jd35695_1080_cmd` exists in DTS | DSI0 | mdss fb | drivers exist (MDP5 `msm8x94`, DSI 6g `msm8994`, DSI PHY 20nm) but **no DT nodes**; panel driver to generate. First step: `simple-framebuffer` on the bootloader splash (like xiaomi-libra) |
| GPU | Adreno 430 (chip id 0x04030002) | — | kgsl | a4xx driver supports it; needs DT node + IOMMU + `a420_pm4.fw`/`a420_pfp.fw` (on the phone) |
| Touch | Synaptics **S3320** @0x20, i2c BLSP1 QUP2 (`f9924000`), irq GPIO 96, reset GPIO 31, 1v8-en GPIO 74 | I²C | synaptics s3320 rmi | RMI4 (`syna,rmi4-i2c`) — same as Sony Kitakami in mainline |
| Touch keys | Synaptics **S1302** @0x20, i2c `f9928000`, irq GPIO 67 | I²C | s1302 rmi | RMI4 |
| Speaker amp | NXP **TFA9890** @0x36, i2c `f9967000` | I²C + I²S (MI2S) | tfa98xx (+ `tfa98xx.cnt` container) | `tfa989x` driver exists (TFA9895/9897; 9890 to check) |
| Audio codec | Qualcomm **WCD9330 (TomTom)** | SLIMbus, Q6 ADSP | wcd9330 + qdsp6v2 | **none** (wcd9335/934x only); msm8994 ADSP remoteproc absent |
| Wi-Fi | Qualcomm **QCA6174** (Rome) | **PCIe0** | CNSS + qcacld-2.0 | ath10k supports QCA6174 PCI, but **msm8994 PCIe controller is not upstream** |
| Bluetooth | QCA6174 (`vendor.qcom.bluetooth.soc=rome`) | UART (BLSP) | hci_uart + userspace patch | `hci_qca` (`qcom,qca6174-bt`) |
| GPS | GNSS inside the modem (MPSS), loc via QMI | SMD/IPC router | PIL mss + QMI (Android loc HAL) | msm8994 MSS remoteproc **absent**; then QMI LOC over qrtr |
| Modem | MSM8994 MPSS | — | PIL mss | absent |
| Battery/charger | PMI8994 SMBCHARGER + FG; battery ATL/SDI 3300 mAh | SPMI | qpnp-smbcharger, qpnp-fg | PMI8994 partial |
| Storage | eMMC (sdhci `f9824900`) | — | ✔ | ✔ |
| USB | dwc3 `f9200000` (USB 2.0 Type-C) | — | ✔ | ✔ (gadget → USB networking/ssh) |
| Vibrator | PMI8994 haptics | SPMI | qpnp-haptic | to check |
| Fingerprint | FPC1020 | SPI | — | out of scope |

Firmware to extract **from the phone** (never downloaded):
`a420_pm4.fw a420_pfp.fw` (GPU), `venus.*` (video), `adsp.*`/`modem.*`/`mba.*`
(from the `modem`/NON-HLOS partition), `tfa98xx.cnt` (amp), BT `rampatch_tlv_3.2.tlv nvm_tlv_3.2.bin`,
Wi-Fi QCA6174 `qwlan30.bin bdwlan30.bin otp30.bin utf30.bin` (location to confirm: `/system/etc/firmware`, `/firmware`, or `/persist`),
`WCNSS_qcom_cfg.ini`, and the MAC addresses / calibration in `persist`.
