#!/bin/bash
# Gera assets/AppIcon.icns a partir de assets/logo/bando-icone.svg.
# Rode depois de mudar o ícone e commite o .icns.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sips -s format png assets/logo/bando-icone.svg --out "$TMP/1024.png" >/dev/null
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$TMP/1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o assets/AppIcon.icns
echo "gerado assets/AppIcon.icns ($(du -h assets/AppIcon.icns | cut -f1))"
