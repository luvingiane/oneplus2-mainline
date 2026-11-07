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
| CPU, RAM, eMMC, PMIC, RPM | funziona | 4 core con l'avvio stile CAF `qcom,8994-arm-cortex-acc` (patch 0010); ancora senza cpufreq (i 4 core A53 girano a un clock fisso di circa 1,5 GHz) e il cluster A57 non viene acceso |
| Display (JDI JD35695, DSI command mode) | funziona | framebuffer del bootloader + driver del pannello (`kernel/panel/`) |
| Touchscreen, tasti, slider | funziona | slider = `gpio-keys` F13/F15 |
| USB (dispositivo, rete NCM + seriale) | funziona se avviato da fastboot | dopo un avvio normale il PC non vede ancora il telefono (vedi LOG.md) |
| Batteria | funziona | `kernel/patches/0013` |
| Wi-Fi (QCA6174 su PCIe) | funziona | il chip è su **PCIe1**, non su PCIe0 (patch 0149-0158, 0162, 0164, 0165; DT `op2-wifi.dtsi` con `OP2_WIFI_PCIE1 OP2_WIFI_BOOT`); ath10k scansiona e si associa, vedi [docs/MILESTONE-2026-11-05-wifi.md](docs/MILESTONE-2026-11-05-wifi.md) (in inglese). Il firmware va nell'initramfs e `CONFIG_FW_LOADER_USER_HELPER` spento. Parte con rfkill bloccato |
| Bluetooth | funziona | QCA6174 su UART (`op2-bt.dtsi`, patch 0161): serve il GPIO WL_EN alto, la lettura della versione a 115200 baud e rampatch/nvm QCA nell'initramfs. L'indirizzo BD di fabbrica non è valido: ne va impostato uno |
| Temperatura SoC | funziona | 16 zone TSENS tarate dai fusibili (patch 0159, `op2-tsens.dtsi`); il cluster A57 si riavvia vicino a 118 °C, `rootfs-overlay/usr/local/bin/op2-thermal.py` rallenta i post-divisori del PLL |
| Vibrazione, sensore hall | presenti | haptic PMI8994 come dispositivo input FF_RUMBLE (patch 0163); hall sul GPIO 75 come `SW_MACHINE_COVER` (cover StyleSwap). Non ancora provati a mano |
| Audio | altoparlante funziona | ADSP avviato (`op2-adsp.dtsi`), MI2S quaternario q6 -> amplificatore TFA9890 (`op2-audio.dtsi`, patch 0029); il codec WCD9330 (microfoni, capsula, jack) non ha driver mainline |
| GPU (Adreno 430) | funziona su 7.3 e 6.12 | **7.3: la GL hardware disegna tutta l'interfaccia ztMETRO dalla eMMC, senza blocchi né invii falliti** (patch `0130` + `0144`: una VM con MMU "vuoto", IOVA == fisico; cmdline `msm.identity_iova=1 msm.op2_gpu_phys=1 cma=768M`; Mesa freedreno FD430 con `FD_MESA_DEBUG=sysmem`, la strada OCMEM/GMEM è ancora rifiutata da TrustZone), vedi [docs/MILESTONE-2026-11-03.md](docs/MILESTONE-2026-11-03.md). 6.12: SMMU collegata + indirizzi fisici (`patches-612/0104`). Il clock della GPU è fisso a 300 MHz |
| Modem, SIM, chiamate, SMS | funziona (audio delle chiamate no) | remoteproc MSS + ADSP, `rmtfs` sulle partizioni grezze del modem, poi una richiesta QMI DPM apre `DATA5_CNTL` (`/dev/wwan0qmi0`, servono `CONFIG_WWAN` + `RPMSG_WWAN_CTRL`) e l'AT risponde su `/dev/wwan0at0`. Registrazione LTE, SMS (memoria SIM), squillo e risposta. Serve un client QMI VOICE registrato, altrimenti la rete non viene mai avvisata. `scripts/op2-modem-up.sh`, `op2-modem-watch.sh`, `tools/qmux`. Manca il percorso voce modem-codec (SLIMbus) |
| Dati mobili | non funzionano | manca il percorso dei pacchetti: l'IPA v2 dell'MSM8994 non ha un driver mainline (ricerca in LOG.md) |
| Modalità aereo | funziona | `AT+CFUN=4` (e una deregistrazione) fanno crashare il firmware del modem su questo telefono mentre è registrato: `scripts/op2-airplane.sh` ferma il remoteproc del modem e lo riavvia nell'ordine che evita il ciclo "stalled initialization" |
| Sensori di luce e prossimità | parziale | gestore sensori dell'ADSP con `tools/op2-sensord`; la luce funziona, la prossimità dà un valore costante (non ancora capito) |
| Fotocamere | non funzionano | frontale OV5648: CAMSS/CSID/ISPIF/VFE allineati al driver originale, ancora nessun pacchetto MIPI (PHY status 0); posteriore OV13860: bozza di driver in `kernel/patches-73` (0189, 0190), non provata |
| Logo di avvio | funziona | logo Arch Linux nella partizione `LOGO` (`tools/boot-logo/build_arch_logo.py`, scritto con `fastboot flash LOGO`, maiuscolo) |

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

## Avviare qualcosa che non sia ztOS

Kernel, device tree e initramfs non dipendono da ztOS: `scripts/build-boot.sh` produce un'immagine di avvio il cui
initramfs monta la radice indicata in `op2.root=` (una partizione ext4 della eMMC) e avvia l'init di quel sistema.
Dovrebbe andar bene qualunque filesystem radice aarch64 con systemd e un userland recente; i pezzi specifici del
telefono (servizi del modem, sensori, helper dell'aereo, controllo USB) sono file semplici in `rootfs-overlay/` e si
possono togliere o tenere. Non ancora provato con un altro sistema: è l'obiettivo quando l'elenco dell'hardware sarà
completo. Prima si avvia sempre dalla RAM (`fastboot boot`), si scrive in flash solo dopo che funziona.

## Correzioni per mainline trovate strada facendo

Alcune patch correggono bug di mainline non specifici del OnePlus 2, per esempio
`0024` (gcc-msm8994: `usb3_phy_aux_clk_src` senza parent map, puntatore nullo con
`clk_set_rate`), `0025` (ocmem: passo dei registri PSGSC di 1 byte invece di 4) e
`patches-612/0102` (a4xx cerca OCMEM sul dispositivo DRM invece che sul nodo GPU).

## Licenza

Patch del kernel, device tree e driver del pannello: GPL-2.0-only, come il kernel Linux.
Script e strumenti: GPL-2.0-only salvo diversa indicazione nel file.
