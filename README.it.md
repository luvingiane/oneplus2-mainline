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

Ultima tappa (2026-11-03): la GPU hardware disegna l'interfaccia di ztOS su mainline 7.3, vedi
[docs/MILESTONE-2026-11-03.md](docs/MILESTONE-2026-11-03.md) (in inglese).

| Parte | Linux 7.3 | Note |
|-------|-----------|------|
| CPU, RAM, eMMC, PMIC, RPM | funziona | 4 core con l'avvio stile CAF `qcom,8994-arm-cortex-acc` (patch 0010); ancora senza cpufreq (i core restano al clock del bootloader, circa 600 MHz) e il cluster A57 non viene acceso |
| Display (JDI JD35695, DSI command mode) | funziona | framebuffer del bootloader + driver del pannello (`kernel/panel/`) |
| Touchscreen, tasti, slider | funziona | slider = `gpio-keys` F13/F15 |
| USB (dispositivo, rete NCM + seriale) | funziona se avviato da fastboot | dopo un avvio normale il PC non vede ancora il telefono (vedi LOG.md) |
| Batteria | funziona | `kernel/patches/0013` |
| Wi-Fi (QCA6174 su PCIe) | non ancora | PHY PCIe: clock aux e reset del PHY sistemati (0028, 0020), il PLL non si aggancia ancora |
| Bluetooth | non ancora | il chip non risponde |
| Audio | altoparlante funziona | ADSP avviato (`op2-adsp.dtsi`), MI2S quaternario q6 -> amplificatore TFA9890 (`op2-audio.dtsi`, patch 0029); il codec WCD9330 (microfoni, capsula, jack) non ha driver mainline |
| GPU (Adreno 430) | funziona su 7.3 e 6.12 | **7.3: la GL hardware disegna tutta l'interfaccia ztMETRO dalla eMMC, senza blocchi né invii falliti** (patch `0130` + `0144`: una VM con MMU "vuoto", IOVA == fisico; cmdline `msm.identity_iova=1 msm.op2_gpu_phys=1 cma=768M`; Mesa freedreno FD430 con `FD_MESA_DEBUG=sysmem`, la strada OCMEM/GMEM è ancora rifiutata da TrustZone), vedi [docs/MILESTONE-2026-11-03.md](docs/MILESTONE-2026-11-03.md). 6.12: SMMU collegata + indirizzi fisici (`patches-612/0104`). Il clock della GPU è fisso a 300 MHz |

Stato completo per componente: [STATUS.md](STATUS.md). Il lavoro giorno per giorno,
con comandi, dump dei registri e risultati: [LOG.md](LOG.md) (in inglese).

## Struttura

| Percorso | Cosa |
|----------|------|
| `kernel/patches/` | patch per Linux 7.3 (quasi tutte valgono anche per 6.12), applicate in ordine |
| `kernel/patches-73/` | patch solo per 7.3 (GPU su indirizzi fisici, camss, lavoro su PCIe/DSI); si passano con `EXTRA_PATCHES=$PWD/kernel/patches-73` |
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

Con la GPU hardware (7.3):

```bash
EXTRA_PATCHES=$PWD/kernel/patches-73 \
DTS_DEFINES="OP2_DISPLAY OP2_SMP OP2_USBPHY OP2_GPU OP2_GPU_RPMCLK" bash scripts/build-kernel.sh
bash scripts/build-boot.sh gpu --cmdline "msm.identity_iova=1 msm.op2_gpu_phys=1 arm64.late_cpu_conflicts=warn op2.gpuhw=1 cma=768M op2.root=/dev/mmcblk1p43"
```

Se l'albero del kernel è stato compilato su un'altra macchina, controlla che `scripts/dtc/dtc` e `scripts/mod/modpost`
siano eseguibili: altrimenti `make` fallisce e i DTB restano vecchi (`build-kernel.sh` ora si ferma se `make` fallisce).

Gli script che parlano con un telefono vogliono `OP2_SERIAL` impostato. Un secondo
telefono sullo stesso computer si avvia con `op2.net=44` nella cmdline (`initramfs/init`) e si riconosce dal seriale in
`rootfs-overlay/usr/local/bin/op2-usb-watch` (`SECOND_PHONE_SERIAL`): metti lì il tuo.

## Correzioni per mainline trovate strada facendo

Alcune patch correggono bug di mainline non specifici del OnePlus 2, per esempio
`0024` (gcc-msm8994: `usb3_phy_aux_clk_src` senza parent map, puntatore nullo con
`clk_set_rate`), `0025` (ocmem: passo dei registri PSGSC di 1 byte invece di 4) e
`patches-612/0102` (a4xx cerca OCMEM sul dispositivo DRM invece che sul nodo GPU).

## Licenza

Patch del kernel, device tree e driver del pannello: GPL-2.0-only, come il kernel Linux.
Script e strumenti: GPL-2.0-only salvo diversa indicazione nel file.
