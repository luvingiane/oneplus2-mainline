# OnePlus 2 su Linux mainline (per ztOS)

[English](README.md)

Porting del **OnePlus 2** (ONE A2003, Qualcomm MSM8994 / Snapdragon 810) su Linux
mainline, per usare [ztOS](https://github.com/luvingiane/ztOS) (Arch Linux ARM +
ztMETRO) come dispositivo di casa. Patch del kernel, device tree, strumenti per le
immagini di avvio, piccoli programmi per il telefono e il diario completo del lavoro.

> Sperimentale. Tutto è stato provato su due telefoni dello stesso modello. Le
> immagini si avviano di solito dalla RAM (`fastboot boot`): sul telefono non viene
> scritto niente finché non lo flashi tu. Prima fai il backup delle partizioni (vedi
> [docs/BACKUP.md](docs/BACKUP.md)) e non toccare mai le partizioni modem/EFS.

## Stato (in breve)

| Parte | Linux 7.3 | Note |
|-------|-----------|------|
| CPU, RAM, eMMC, PMIC, RPM | funziona | 4 core con l'avvio stile CAF `qcom,8994-arm-cortex-acc` (patch 0010) |
| Display (JDI JD35695, DSI command mode) | funziona | framebuffer del bootloader + driver del pannello (`kernel/panel/`) |
| Touchscreen, tasti, slider | funziona | slider = `gpio-keys` F13/F15 |
| USB (dispositivo, rete NCM + seriale) | funziona se avviato da fastboot | dopo un avvio normale il PC non vede ancora il telefono (vedi LOG.md) |
| Batteria | funziona | `kernel/patches/0013` |
| Wi-Fi (QCA6174 su PCIe) | non ancora | PHY PCIe: clock aux e reset del PHY sistemati (0028, 0020), il PLL non si aggancia ancora |
| Bluetooth | non ancora | il chip non risponde |
| Audio | altoparlante funziona | ADSP avviato (`op2-adsp.dtsi`), MI2S quaternario q6 -> amplificatore TFA9890 (`op2-audio.dtsi`, patch 0029); il codec WCD9330 (microfoni, capsula, jack) non ha driver mainline |
| GPU (Adreno 430) | funziona su 6.12 | SMMU della GPU collegata + indirizzi fisici (`patches-612/0104`, `msm.op2_gpu_phys=1`), Mesa freedreno FD430; la GMEM (OCMEM) è ancora rifiutata da TrustZone: usare `FD_MESA_DEBUG=sysmem` |

Stato completo per componente: [STATUS.md](STATUS.md). Il lavoro giorno per giorno,
con comandi, dump dei registri e risultati: [LOG.md](LOG.md) (in inglese).

## Struttura

| Percorso | Cosa |
|----------|------|
| `kernel/patches/` | patch per Linux 7.3 (quasi tutte valgono anche per 6.12), applicate in ordine |
| `kernel/patches-612/` | patch solo per 6.12 (GPU con carveout VRAM, tracce di debug) |
| `kernel/dts/` | `msm8994-oneplus-oneplus2.dts` e `op2-*.dtsi`, attivati con `DTS_DEFINES` (`OP2_DISPLAY`, `OP2_SMP`, `OP2_USBPHY`, `OP2_WIFI`, `OP2_GPU`, ...) |
| `kernel/panel/` | il driver del pannello |
| `kernel/oneplus2*.config` | frammenti di config sopra la config msm8994 di postmarketOS |
| `scripts/` | `build-kernel.sh`, `build-boot.sh` (immagine per `fastboot boot`), backup e test |
| `initramfs/` | l'`init` dell'initramfs (gadget USB, rete, passaggio al root) |
| `rootfs-overlay/` | file aggiunti al file system di ztOS (servizio di controllo USB, regola sudoers per il menu di spegnimento) |
| `tools/` | piccoli strumenti C/Python usati sul telefono (lettura registri, comandi al pannello, test GPU) |
| `docs/` | strategia, hardware, backup |

## Compilazione

Servono una toolchain aarch64 (`build/toolchain/`, ARM GNU 14.2), i sorgenti del
kernel in `build/linux-7.3` (o 6.12 con `KSRC=`) e la config
`linux-postmarketos-qcom-msm8994` di postmarketOS in `research/pmaports/` (vedi gli script).

```bash
DTS_DEFINES="OP2_DISPLAY OP2_SMP OP2_USBPHY" bash scripts/build-kernel.sh
bash scripts/build-boot.sh mia-immagine --cmdline "op2.root=/dev/mmcblk1p43"
fastboot boot out/mia-immagine.img     # solo RAM
```

Gli script che parlano con un telefono vogliono `OP2_SERIAL` impostato. Il secondo
telefono della configurazione a due telefoni si riconosce dal seriale in
`initramfs/init` e in `rootfs-overlay/usr/local/bin/op2-usb-watch`
(`SECOND_PHONE_SERIAL`): metti lì il tuo.

## Correzioni per mainline trovate strada facendo

Alcune patch correggono bug di mainline non specifici del OnePlus 2, per esempio
`0024` (gcc-msm8994: `usb3_phy_aux_clk_src` senza parent map, puntatore nullo con
`clk_set_rate`), `0025` (ocmem: passo dei registri PSGSC di 1 byte invece di 4) e
`patches-612/0102` (a4xx cerca OCMEM sul dispositivo DRM invece che sul nodo GPU).

## Licenza

Patch del kernel, device tree e driver del pannello: GPL-2.0-only, come il kernel Linux.
Script e strumenti: GPL-2.0-only salvo diversa indicazione nel file.
