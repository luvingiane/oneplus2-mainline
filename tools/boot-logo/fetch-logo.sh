#!/bin/sh
# Scarica il logo ufficiale Arch Linux (one-color, nero) dagli artwork ufficiali
# https://archlinux.org/art/ -> sources.archlinux.org/other/artwork/
set -eu
cd "$(dirname "$0")"
BASE="https://sources.archlinux.org/other/artwork"
curl -fsSL -o archlinux-logo-black-90dpi.png   "$BASE/archlinux-logo-black-90dpi.png"
curl -fsSL -o archlinux-logo-black-1200dpi.png "$BASE/archlinux-logo-black-1200dpi.png"
echo "c9f3a7ac8ced191608f5aaaebe9e698122a68bdcd7220064fc99f72d18003c84  archlinux-logo-black-90dpi.png"   | sha256sum -c -
echo "0c646b9d6ea78042fe5606f0f96948e415206770196fbb4ceb9863f3db722a8c  archlinux-logo-black-1200dpi.png" | sha256sum -c -
echo "logo ufficiali Arch Linux (artwork) scaricati e verificati."
