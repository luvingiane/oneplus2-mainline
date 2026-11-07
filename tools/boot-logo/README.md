# boot-logo — OnePlus 2: logo di Arch Linux al posto di "Powered by Android"

Task 362. NON eseguire nulla sul telefono da qui: il flash lo fa Claude solo con
OK esplicito del proprietario, dopo il backup. Vedi report.md per FATTO/IPOTESI.

## Dove vive l'immagine (FATTO da sorgenti pubblici + log del repo)

- La partizione e' **LOGO** (in fastboot: `logo`), **16777216 byte (16 MiB)** su
  A e B: `logs/backup-A.log:4` e `logs/backup-B-target.log:4`
  (`LOGO ok 16777216 bytes`, `all images match the phone`).
  Nessuna partizione `splash` nella lista di backup (stesso file).
- Dentro la partizione c'e' **logo.bin** (nessun filesystem): container con
  piu' immagini,ognuna con header di 512 byte che inizia con `SPLASH!!`.
  Formato "old OnePlus/OPPO" documentato dal tool pubblico LogoInjector v1.52
  (makers_mark @ XDA, `IMAGEHEAD`, `OFFSETSTART 48`, `Decode`/`Encode`):
  - header 512B: `0x00` magic `SPLASH!!` (8B), `0x20` width u32le, `0x24`
    height u32le, `0x28` lengthOfData u32le, `0x2C` special u32le,
    `0x30` offsets[28] u32le (offset assoluti degli header; `offsets[0]==0`;
    la tabella finisce al primo 0), `0xA0` name[64], `0xE0` meta[288].
  - payload a `offsets[i]+512`, lunghezza `lengthOfData`, padding a 512.
  - payload = RLE orientato ai byte su pixel **BGR888**: coppie
    (valore, count), count 1..255; decodificato deve essere width*height*3.
- La stessa famiglia `SPLASH!!` e' usata da LK/CAF per la partizione `splash`
  (qui assente sull'OP2): `research/lk2nd/include/dev/fbcon.h:35-38`
  (`LOGO_IMG_MAGIC "SPLASH!!"`, `LOGO_IMG_HEADER_SIZE 512`) e
  `research/lk2nd/app/aboot/aboot.c:4986-4998` (`splash_screen_check_header`),
  `:5000-5025` (`splash_screen_flash` cerca la partizione `"splash"`),
  `:5086-5132` (`splash_screen_mmc`, header a `ptn + PLL_CODES_OFFSET`,
  `PLL_CODES_OFFSET 4096` a `:150`). Il ramo RLE24 di quel codice
  (`dev/fbcon/fbcon.c:514-572`, run byte con flag 0x80, 3 byte BGR, centrato)
  e' il formato della partizione `splash` Qualcomm, NON del logo.bin OP2.
- Pannello: 1080x1920, `logs/recon-<phone-B>-20261025-110444/fb.txt:2`
  (`U:1080x1920p-360`), `:14` (`panel_name=jd35695 1080p cmd mode dsi panel`).
- Quale immagine e' "Powered by Android": IPOTESI — e' l'immagine a schermo
  intero 1080x1920 mostrata per prima (di solito #0, nome tipo `bootlogo.png`).
  Da confermare sul dump reale con `boot_logo.py list backups/logo-A.img`;
  lo script la choisitrice con `--name` o `--index`.

## Uso

```sh
# logo ufficiale Arch ( nero ) — vedi fetch-logo.sh per URL e sha256
./fetch-logo.sh

# elenco immagini nel dump originale (quando backups/logo-A.img esiste)
python3 boot_logo.py list  backups/logo-A.img

# genera la nuova partizione (mai sovrascrive l'input)
python3 boot_logo.py build --input backups/logo-A.img \
    --logo archlinux-logo-black-90dpi.png --output out/logo-arch.img --name bootlogo

# controlli pre-flash
python3 boot_logo.py verify out/logo-arch.img          # magic, offset, RLE, size
sha256sum backups/logo-A.img out/logo-arch.img
stat -c %s out/logo-arch.img                            # deve essere <= 16777216
```

## Procedura di flash e ripristino (DA NON ESEGUIRE QUI — solo con OK del proprietario)

1. Backup (gia' fatto dal flusso esistente: `logs/backup-A.log:4` mostra LOGO
   salvato e hash verificato; il file atteso e' `backups/logo-A.img`).
   Se serve rileggerlo dal telefono:
   `adb shell "dd if=/dev/block/bootdevice/by-name/LOGO of=/sdcard/logo-A.img bs=1M"`
   poi `adb pull /sdcard/logo-A.img backups/logo-A.img` e confrontare sha256.
2. Build + verify come sopra.
3. `fastboot devices` ; telefono in fastboot con bootloader sbloccato.
4. Flash (solo con OK esplicito, eseguito da Claude):
   `fastboot flash logo out/logo-arch.img`
   (nome partizione in fastboot: `logo`; in `/dev/block/bootdevice/by-name`: `LOGO`).
5. Ripristino: `fastboot flash logo backups/logo-A.img`.
6. Se il file fosse sbagliato: la partizione LOGO non fa parte della catena
   firmata (sbl1/aboot/tz/modem sì, LOGO no) — IPOTESI: il telefono parte lo
   stesso e LK mostra schermo nero o logo di fallback; si risolve riflashando
   il backup. Nel codice CAF per la partizione `splash` un header invalido fa
   fallback al logo di default e il boot prosegue
   (`aboot.c:5024-5027` ritorna -1 senza bloccare).

## Il dump REALE (7/11, backups/logo-A.img = partizione LOGO di A, `mmcblk1p24`, 16 MiB) e `build_arch_logo.py`
`boot_logo.py` (scritto sul file sintetico) non legge il contenitore vero: ha 28 offset di cui 14 vuoti (blocchi da 512 B a zero) e due serie di immagini (1080x1920 `fhd_*` e 1440x2559 `wqxga_*`); due header `SPLASH!!` in coda (`0x17ca00`, `0x17e800`) non sono nella tabella, quindi NON si spostano le immagini. L'immagine 0 è `fhd_oppo_1080_1920_result.raw` = marchio OnePlus + "POWERED BY android", **su nero** (non bianco), 60570 byte di payload nello spazio di `0xf000-0x200`.
`build_arch_logo.py DUMP OUT_DIR [--variant a|b|both] [--width N] [--levels L] [--logo PNG]` sostituisce SOLO il payload dell'immagine 0 sul posto (e il campo lunghezza a `0x28`), con asserzioni: nessun altro byte cambia, dimensione 16 MiB, round-trip RLE. Vincolo: l'RLE è per BYTE (coppie valore,conteggio ≤255), il nero di sfondo costa già ~49 KB e restano ~11 KB: logo bianco ufficiale (`archlinux-logo-white-1200dpi.png`, https://sources.archlinux.org/other/artwork/), bordi con pochi livelli di grigio (`--levels 3`), mai a colori (i pixel non grigi costano il triplo). Varianti: `a` = marchio OnePlus + logo Arch al posto di "powered by android" (payload 55740 B), `b` = solo il logo Arch al centro (56710 B). Il flash resta `fastboot flash LOGO out/logo/logo-arch-X.img` (nome MAIUSCOLO: con `logo` questo bootloader risponde "partition table doesn't exist" e non scrive nulla), solo con OK del proprietario e dopo aver tenuto `backups/logo-A.img`.
