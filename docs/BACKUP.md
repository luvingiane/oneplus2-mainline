# Backups and media recovery

`backup/` is **never committed** (`.gitignore`): it holds IMEI, MAC addresses,
calibration (`persist`, `modemst1/2`, `fsg`) and personal photos.

## Two phones

| | Phone A ("A-broken") | Phone B ("B-target") |
|---|---|---|
| State | display dead, no interaction possible | fully working; the ztOS target |
| Role | first test bench (more destructive tests allowed, **with consent**), *after* its media are safe | the device we ship on |
| Before anything | recover all media, full partition backup | full partition backup |

## Order, for each phone

1. `scripts/recon.sh <label>` — read-only (adb or fastboot).
2. Root shell available? (rooted Android, or a recovery)
   → `scripts/backup-partitions.sh <label>` (all partitions except
   system/userdata/cache; each image hash-checked against the phone)
   → `scripts/pull-media.sh <label>` (internal storage).
3. Only then: anything that writes.

## Phone A: how the media can come off, from least to most invasive

The screen does not work, so nothing that needs a tap on the phone is possible
(USB debugging prompt, "OEM unlocking" toggle, PIN entry).

| # | Condition (found by recon) | Route | Writes to phone? |
|---|---|---|---|
| 1 | Android boots and adb is already authorised for this PC | `adb pull /sdcard` | no |
| 2 | Android boots, MTP is on, phone has no lock (or MTP doesn't need unlock) | copy over MTP (`gio`/`jmtpfs`) | no |
| 3 | Bootloader **unlocked** | `fastboot boot` a RAM-only image (our own mainline initramfs, or the official TWRP for oneplus2) → adb root → pull `/data/media/0` + partitions | no (RAM boot) |
| 4 | Bootloader locked, a custom recovery is already installed | boot to recovery with the keys (Volume Down + Power) → adb | no |
| 5 | Bootloader locked, stock recovery, adb not authorised | Qualcomm EDL (9008) with OnePlus's signed firehose programmer → read `userdata` raw (works only if storage is not encrypted) | no (reads only), but needs a OnePlus programmer file: I will ask first |
| 6 | none of the above | `fastboot oem unlock` **wipes userdata** → media lost | **yes — never without explicit consent, and only after 1–5 are ruled out** |

Encryption: OxygenOS on the OP2 does not force encryption by default; recon
reads `ro.crypto.state` (route 1) or the userdata superblock (route 3/5).
