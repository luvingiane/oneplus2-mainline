#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SRC=$ROOT/build/linux-7.3; S=$(mktemp -d); D=drivers/gpu/drm/msm; FILES="msm_gem.c msm_gem.h"
cd "$SRC"; mkdir -p "$S/a/$D" "$S/b/$D"
for f in $FILES; do /bin/cp -f "$D/$f" "$S/a/$D/$f"; done
python3 "$ROOT/tools/patchgen/mkpatch-0004.py" "$SRC"
for f in $FILES; do /bin/cp -f "$D/$f" "$S/b/$D/$f"; done
cd "$S"
{ printf 'From: Matt\nSubject: [PATCH] drm/msm: identity IOVA for GEM objects (msm.identity_iova)\n\nBring-up hack, not for upstream as is. On MSM8994 the MDP and the DSI\ncommand DMA bypass the SMMU, whose stream routing TrustZone owns, and treat\nIOVAs as physical addresses: the screen shows black and panel commands are\ngarbage. With msm.identity_iova=1 every GEM object is backed by contiguous\nCMA memory and mapped at IOVA == physical address.\n\n---\n'
  for f in $FILES; do diff -u "a/$D/$f" "b/$D/$f" || true; done; } > "$ROOT/kernel/patches/0004-drm-msm-identity-iova.patch"
echo "lines added: $(grep -c '^+[^+]' "$ROOT/kernel/patches/0004-drm-msm-identity-iova.patch")"
