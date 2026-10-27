#!/usr/bin/env bash
# Build the mainline kernel + DTBs for the OnePlus 2.
#   base config: pmOS config-postmarketos-qcom-msm8994.aarch64
#   + kernel/oneplus2.config
#   + kernel/dts/msm8994-oneplus-oneplus2.dts, one DTB per board revision
# Output: build/linux-7.3/arch/arm64/boot/Image.gz and
#         build/dtbs/msm8994-oneplus-oneplus2-hwNN.dtb (NN = 11..14)
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# KSRC: kernel tree (default build/linux-7.3); FRAG: config fragment; DTB_OUT:
# where the DTBs go; SKIP_PATCHES: patch numbers not applied (e.g. on 6.12)
SRC=${KSRC:-$ROOT/build/linux-7.3}
FRAG=${KCONFIG_FRAG:-$ROOT/kernel/oneplus2.config}
DTBS=${DTB_OUT:-$ROOT/build/dtbs}
TC=$ROOT/build/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin
BASECFG=$ROOT/research/pmaports/device/testing/linux-postmarketos-qcom-msm8994/config-postmarketos-qcom-msm8994.aarch64
export PATH=$TC:$PATH ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- LC_ALL=C
J=$(nproc)

cd "$SRC"
# our kernel patches (idempotent)
# EXTRA_PATCHES: a second folder applied after kernel/patches (e.g. kernel/patches-612)
for pt in "$ROOT"/kernel/patches/*.patch ${EXTRA_PATCHES:+"$EXTRA_PATCHES"/*.patch}; do
	[ -e "$pt" ] || continue
	n=$(basename "$pt"); case " ${SKIP_PATCHES:-} " in *" ${n%%-*} "*) echo "skipped $n"; continue ;; esac
	patch -p1 --forward --silent --dry-run < "$pt" >/dev/null 2>&1 && patch -p1 --forward --silent < "$pt" && echo "applied $(basename "$pt")"
	patch -p1 -R --dry-run --silent < "$pt" >/dev/null 2>&1 || { echo "patch $(basename "$pt") neither applies nor is applied"; exit 1; }
done
# our panel driver into the tree
P=drivers/gpu/drm/panel
cp "$ROOT/kernel/panel/panel-oneplus2-jd35695.c" $P/
grep -q PANEL_ONEPLUS2_JD35695 $P/Kconfig || cat >> $P/Kconfig <<'KEOF'

config DRM_PANEL_ONEPLUS2_JD35695
	tristate "OnePlus 2 JDI JD35695 command mode panel"
	depends on OF && DRM_MIPI_DSI && BACKLIGHT_CLASS_DEVICE
	help
	  The OnePlus 2's 1080x1920 command-mode DSI panel.
KEOF
grep -q panel-oneplus2-jd35695 $P/Makefile || echo 'obj-$(CONFIG_DRM_PANEL_ONEPLUS2_JD35695) += panel-oneplus2-jd35695.o' >> $P/Makefile
if [ ! -f .config ] || [ "$FRAG" -nt .config ] || [ "${FRESH:-}" = 1 ]; then
	cp "$BASECFG" .config
	./scripts/kconfig/merge_config.sh -m .config "$FRAG" >/dev/null
	make olddefconfig >/dev/null
fi
# every option of the fragment must have survived olddefconfig
miss=0
while IFS= read -r l; do
	case "$l" in CONFIG_*=*) grep -qxF "$l" .config || { echo "config: not applied: $l"; miss=1; } ;; esac
done < "$FRAG"
[ $miss = 0 ] || exit 1

D=arch/arm64/boot/dts/qcom
cp "$ROOT"/kernel/dts/*.dtsi $D/
# one DTB per (SoC revision, board revision), like the stock kernel's 12
VARIANTS=
for soc in 10000 20000 20001; do
	for rev in 11 12 13 14; do
		v=msm8994-oneplus-oneplus2-v$soc-hw$rev
		{ for d in ${DTS_DEFINES:-}; do echo "#define $d"; done
		  sed -e "s/^#define OP2_HW_REV 14$/#define OP2_HW_REV $rev/" \
		      -e "s/^#define OP2_SOC_REV 0x20001$/#define OP2_SOC_REV 0x$soc/" \
			"$ROOT/kernel/dts/msm8994-oneplus-oneplus2.dts"; } > "$D/$v.dts"
		grep -q "$v.dtb" $D/Makefile || echo "dtb-\$(CONFIG_ARCH_QCOM) += $v.dtb" >> $D/Makefile
		VARIANTS="$VARIANTS qcom/$v.dtb"
	done
done
make -j"$J" Image.gz $VARIANTS 2>&1 | grep -E 'error|Error|warning: .*oneplus2' || true
mkdir -p "$DTBS"; rm -f "$DTBS"/*.dtb
for v in $VARIANTS; do cp "$D/${v#qcom/}" "$DTBS/"; done
ls -l arch/arm64/boot/Image.gz "$DTBS"/
echo "kernel: $(cat include/config/kernel.release)"
