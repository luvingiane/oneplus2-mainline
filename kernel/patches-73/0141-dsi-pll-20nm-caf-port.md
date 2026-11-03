# 0141 — Port del driver CAF 20nm DSI PLL (WORK IN PROGRESS, non cablato)

File pronto: `kernel/patches-73/dsi_pll_20nm_hw.c.parked` (platform driver
"qcom,dsi-pll-20nm" che al probe rilegge il PLL a VCO 883.2 MHz con la
sequenza CAF completa: common blocks, loop bw, vco rate calc, resetsm,
vco start, poll lock, trim). Kconfig/Makefile/DT node: vedi commit.

## Stato test (1/11 sera)
- s187 (driver attivo, nodo DT sotto `/`): BOOT-OK una volta, poi HANG —
  il probe legge i registri PLL mentre il GDSC MDSS e' spento -> bus hang.
- s188 (PHY full re-init + PLL): HANG — reinizializzare il PHY al boot
  butta giu' il byte clock (motivo originale della patch 0003).
- s183/s185/s186 (relock manuale in phy, patch 0140, anche con trim e
  deferred a 20 s): HANG — a 883 Mbps il timing del PHY del bootloader
  (clk_pre/post 0x3e/0x20) non e' valido.

## Per sbloccare (serve seriale o pazienza)
1. Non toccare i registri PLL prima che il GDSC MDSS sia on: programmare
   il PLL dentro un clk_hw la cui enable() viene chiamata dall'host DSI
   dopo clk_enable, oppure via late work dopo che il display e' up.
2. A 883 Mbps ricalcolare anche il timing del PHY (non tenere 0x3e/0x20).
3. Misurare il PLL attuale del bootloader: il driver stampa
   "bootloader PLL: VCO ..." al probe (senza dsipll=1 non rilegge).

## Misura del collo (frametrace, s136)
11 fps in animazione continua: ogni frame cmd-mode = full transfer
~91 ms -> il PLL del bootloader e' ~115 Mbps/lane (byte ~14 MHz), non
110 MHz come dice il DT fixed-clock.
