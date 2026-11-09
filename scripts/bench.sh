#!/bin/bash
# Mede memória e CPU do Bando.app aberto e anota em doc/medicoes.md.
#
# Footprint (vmmap) é o número do Monitor de Atividade e o que vale para a
# meta. RSS aparece só como referência (conta páginas compartilhadas dos
# frameworks do sistema).
#
# Uso: scripts/bench.sh [segundos ociosos para medir CPU, padrão 30] [nota]
set -euo pipefail
cd "$(dirname "$0")/.."
IDLE="${1:-30}"
NOTE="${2:-}"
APP="build/Bando.app"
[ -d "$APP" ] || { echo "rode scripts/build-app.sh antes" >&2; exit 1; }

osascript -e 'quit app "Bando"' 2>/dev/null || true
open "$APP"
PID=""
for _ in $(seq 1 80); do
  PID="$(pgrep -f "$APP/Contents/MacOS/Bando" || true)"
  [ -n "$PID" ] && break
  python3 -c 'import time; time.sleep(0.25)'
done
[ -n "$PID" ] || { echo "app não abriu" >&2; exit 1; }
python3 -c 'import time; time.sleep(5)'

FOOT="$(vmmap --summary "$PID" 2>/dev/null | awk '/^Physical footprint:/{print $3}')"
PEAK="$(vmmap --summary "$PID" 2>/dev/null | awk '/^Physical footprint \(peak\):/{print $4}')"
RSS="$(ps -o rss= -p "$PID" | awk '{printf "%.0fM", $1/1024}')"
CPU0="$(ps -o time= -p "$PID")"
python3 -c "import time; time.sleep($IDLE)"
CPU1="$(ps -o time= -p "$PID")"
TMUX_RSS="$(ps -axo rss=,comm= | awk '$2 ~ /tmux/ {s+=$1} END {printf "%.0fM", s/1024}')"
SIZE="$(du -sh "$APP" | awk '{print $1}')"
VERSION="$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)"

LINE="| $(date '+%Y-%m-%d %H:%M') | $VERSION | $FOOT | $PEAK | $RSS | $CPU0 → $CPU1 em ${IDLE}s | $TMUX_RSS | $SIZE | $NOTE |"
if [ ! -f doc/medicoes.md ]; then
  cat > doc/medicoes.md <<'HDR'
# Medições

Geradas por `scripts/bench.sh`. Meta (PLANO.md, seção 2): footprint até 80 MB com grade 2×2 e 5 sessões, CPU parada com agentes ociosos, .app até 25 MB.

| Data | Versão | Footprint | Pico | RSS | CPU (tempo acumulado) | tmux | .app | Nota |
|---|---|---|---|---|---|---|---|---|
HDR
fi
echo "$LINE" >> doc/medicoes.md
echo "$LINE"
