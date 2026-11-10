#!/bin/bash
# Instala ou atualiza o Bando a partir da última versão publicada.
#
#   curl -fsSL https://bando.nerifilho.com.br/install.sh | bash
#
# Baixa com o curl (sem a marca de quarentena dos navegadores), então o macOS
# abre o app sem o aviso de desenvolvedor não identificado. Depois disso, o
# próprio app se atualiza.
set -euo pipefail

BASE="${BANDO_RELEASES_URL:-https://bando-releases.s3.amazonaws.com}"
DEST="${BANDO_APP_DIR:-/Applications}"
APP="$DEST/Bando.app"

[ "$(uname -s)" = "Darwin" ] || { echo "O Bando roda só no macOS." >&2; exit 1; }
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || { echo "O Bando precisa do macOS 14 ou mais recente." >&2; exit 1; }

version="$(curl -fsSL "$BASE/latest/VERSION")"
echo "==> Bando $version"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar -o "$tmp/Bando.zip" "$BASE/latest/Bando.zip"
ditto -x -k "$tmp/Bando.zip" "$tmp"
codesign --verify --deep --strict "$tmp/Bando.app"

if pgrep -xq Bando; then
  echo "==> fechando o Bando aberto (as sessões continuam no tmux)"
  osascript -e 'quit app "Bando"' >/dev/null 2>&1 || true
  sleep 2
fi

if [ -w "$DEST" ]; then
  rm -rf "$APP" && ditto "$tmp/Bando.app" "$APP"
else
  echo "==> $DEST pede senha de administrador"
  sudo rm -rf "$APP" && sudo ditto "$tmp/Bando.app" "$APP"
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# CLI no PATH do usuário, sem sudo.
mkdir -p "$HOME/.local/bin"
ln -sf "$APP/Contents/MacOS/bando-cli" "$HOME/.local/bin/bando"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "==> adicione ~/.local/bin ao PATH para usar o comando bando" ;;
esac

command -v tmux >/dev/null || echo "==> falta o tmux: brew install tmux"
echo "==> instalado em $APP"
open "$APP"
