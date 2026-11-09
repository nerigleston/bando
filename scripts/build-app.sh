#!/bin/bash
# Monta build/Bando.app a partir do SwiftPM, sem projeto Xcode.
#
# Variáveis opcionais:
#   BANDO_VERSION          versão exibida (padrão: a de Version.swift)
#   BANDO_BUILD            CFBundleVersion, número que só cresce (padrão: commits no HEAD)
#   BANDO_FEED_URL         URL do appcast do Sparkle (sem ela, atualização fica desligada)
#   BANDO_ED_PUBLIC_KEY    chave pública EdDSA do Sparkle
#   BANDO_SIGN_IDENTITY    identidade de assinatura (padrão: ad hoc "-"). Com "Developer ID"
#                          no nome, liga hardened runtime e carimbo de tempo (notarização);
#                          com certificado próprio, assina sem eles (a validação de
#                          bibliotecas recusaria o Sparkle sem Team ID).
#   BANDO_CONFIGURATION    debug | release (padrão: release)
#   BANDO_UNIVERSAL=1      binário universal arm64 + x86_64 (precisa do Xcode completo)
set -euo pipefail
cd "$(dirname "$0")/.."

CONF="${BANDO_CONFIGURATION:-release}"
VERSION="${BANDO_VERSION:-$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/BandoCore/Version.swift)}"
BUILD="${BANDO_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${BANDO_SIGN_IDENTITY:--}"
BUNDLE_ID="io.github.nerigleston.bando"

# Universal: compila cada arquitetura separada e junta com lipo. Pedir as duas
# de uma vez (--arch arm64 --arch x86_64) usa o build do Xcode, que não resolve
# o plugin de build do SwiftTerm.
build_arch() {  # $1 = triple vazio (nativo) ou arm64/x86_64
  local T=()
  [ -n "$1" ] && T=(--triple "$1-apple-macosx14.0")
  swift build -c "$CONF" ${T[@]+"${T[@]}"} --product BandoApp >&2
  swift build -c "$CONF" ${T[@]+"${T[@]}"} --product bando >&2
  swift build -c "$CONF" ${T[@]+"${T[@]}"} --show-bin-path
}

if [ "${BANDO_UNIVERSAL:-0}" = "1" ]; then
  echo "==> compilando ($CONF, arm64 + x86_64)"
  BIN_ARM="$(build_arch arm64)"
  BIN_X86="$(build_arch x86_64)"
  BIN="build/universal"
  rm -rf "$BIN" && mkdir -p "$BIN"
  for exe in BandoApp bando; do
    lipo -create "$BIN_ARM/$exe" "$BIN_X86/$exe" -output "$BIN/$exe"
  done
  for b in "$BIN_ARM"/*.bundle; do [ -e "$b" ] && ditto "$b" "$BIN/$(basename "$b")"; done
else
  echo "==> compilando ($CONF)"
  BIN="$(build_arch "")"
fi

APP="build/Bando.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"

cp "$BIN/BandoApp" "$APP/Contents/MacOS/Bando"
cp "$BIN/bando" "$APP/Contents/MacOS/bando-cli"

# Sparkle vem como binário (xcframework) pelo SwiftPM.
SPARKLE="$(find .build/artifacts -path '*macos*' -name Sparkle.framework -type d | head -1)"
[ -z "$SPARKLE" ] && SPARKLE="$(find "$BIN" -maxdepth 2 -name Sparkle.framework -type d | head -1)"
if [ -z "$SPARKLE" ]; then echo "Sparkle.framework não encontrado" >&2; exit 1; fi
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"

cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Logo para a tela "Sobre" e para o app escolher a cor conforme o tema.
cp assets/logo/bando-completo-preto.svg assets/logo/bando-completo-branco.svg "$APP/Contents/Resources/"

# Recursos de pacotes (bundles do SwiftPM), se houver.
for b in "$BIN"/*.bundle; do [ -e "$b" ] && ditto "$b" "$APP/Contents/Resources/$(basename "$b")"; done

FEED_KEYS=""
if [ -n "${BANDO_FEED_URL:-}" ]; then
  FEED_KEYS="  <key>SUFeedURL</key><string>${BANDO_FEED_URL}</string>
  <key>SUPublicEDKey</key><string>${BANDO_ED_PUBLIC_KEY:?defina BANDO_ED_PUBLIC_KEY junto com BANDO_FEED_URL}</string>
  <key>SURequireSignedFeed</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>3600</integer>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bando</string>
  <key>CFBundleDisplayName</key><string>Bando</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>Bando</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
${FEED_KEYS}
</dict>
</plist>
PLIST

echo "==> assinando (${IDENTITY})"
SIGN_OPTS=(--force --sign "$IDENTITY")
case "$IDENTITY" in *"Developer ID"*) SIGN_OPTS+=(--options runtime --timestamp);; esac
# De dentro para fora: componentes do Sparkle, framework, executáveis, app.
for x in "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/"*.xpc \
         "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
         "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"; do
  [ -e "$x" ] && codesign "${SIGN_OPTS[@]}" "$x"
done
codesign "${SIGN_OPTS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_OPTS[@]}" "$APP/Contents/MacOS/bando-cli"
codesign "${SIGN_OPTS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

du -sh "$APP" | awk '{print "==> pronto: build/Bando.app (" $1 ")"}'
