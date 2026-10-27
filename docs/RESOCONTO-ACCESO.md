# OnePlus 2 Mainline Port — Stato Attuale e Resoconto

Questo documento riassume lo stato attuale del porting del kernel mainline Linux (7.x) sul **OnePlus 2** (`oneplus2`, project `14049`, SoC MSM8994 v2.1), redatto in base alla documentazione di progetto, ai log di compilazione/boot e ai test eseguiti sul dispositivo (attualmente acceso e testato via boot RAM-only con `fastboot boot`).

---

## 1. Decisione Strategica: Mainline 7.x vs Downstream 3.10
- **Problema di Userspace:** ztOS utilizza Arch Linux ARM e **systemd**. systemd 258 richiede Linux ≥ 5.4, e systemd 259 richiede ≥ 5.10 (rimozione cgroup v1, pidfd, nuove API di mount).
- **Kernel Downstream (3.10.108):** EOL nel 2017, impossibile da usare con ztOS, toolchain obsoleta (GCC 6).
- **Scelta:** Utilizzare un kernel **Mainline 7.x** (basato su `linux-postmarketos-qcom-msm8994`, 6.16+ rebasato su mainline) con un Device Tree dedicato (`msm8994-oneplus-oneplus2.dts`).

---

## 2. Stato dei Componenti Hardware (Mainline 7.3)

| Componente | Stato / Dettagli |
|---|---|
| **SoC / CPU** | MSM8994 v2.1 (4×A53 + 4×A57), SMEM, GCC, MMCC, RPM, pinctrl, SPMI, eMMC, USB funzionanti. |
| **Boot & Memoria** | Avvio tramite `fastboot boot` (RAM-only, nessuna scrittura su eMMC in questa fase). L'immagine include `Image.gz` con 4 DTB accodati per le varie revisioni hardware, con limiti di dimensione tassativi per evitare il conflitto con la DTB a `0x01e00000`. Ramoops configurato per preservare i log in `/sys/fs/pstore`. |
| **Display (Schermo)** | **Funzionante in modalità Stage 1**: utilizza il framebuffer continuo del bootloader (`simple-framebuffer` su `0x03400000`). La retroilluminazione e i LED funzionano. Sotto DRM puro lo schermo risulta nero perché l'MDP/DSI DMA bypassa la SMMU di TrustZone; implementati comandi manuali (`op2-dcs`) e kick continui (`op2-kick`). |
| **Touchscreen** | Synaptics **S3320** (I²C BLSP1 QUP2): si collega ma non esegue lo scan sotto mainline (funziona sotto TWRP). Bloccato, richiede ulteriore analisi. |
| **USB / Rete** | Funzionante con gadget USB (NCM + ACM): assegna IP `172.16.42.1` al telefono e offre accesso SSH (`dropbear` con chiave ED25519) e console seriale virtuale (`/dev/ttyACM0`). |
| **Audio** | WCD9330 / TFA9890: da implementare / verificare tramite LPASS MI2S. |
| **Wi-Fi / BT** | QCA6174: Bluetooth (`hci_qca`) teoricamente fattibile su UART BLSP; Wi-Fi richiede il controller PCIe (non ancora upstream su msm8994). |

---

## 3. Strumenti di Diagnostica e Diagnostica PMIC
- **Script di boot:** `scripts/build-boot.sh` compila il kernel, genera l'initramfs con BusyBox, Dropbear, script di test pattern (`/pattern24.raw.gz`, `/pattern32.raw.gz`) e tool di utilità (`op2-kick`, `op2-touchled`, `op2-dcs`).
- **Analisi PMIC:** Utilizzo di `tools/pmic-diff.py` per confrontare i registri SPMI dei PMIC (PMI8994 / PM8994) tra mainline e TWRP (`logs/pmic/`), utile per diagnosticare discrepanze di alimentazione e configurazione hardware.

---

*Documento aggiornato al 2026-10-25.*
