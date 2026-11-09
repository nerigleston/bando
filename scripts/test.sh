#!/bin/bash
# Roda os testes. Com só as Command Line Tools (sem Xcode), o framework
# Testing fica fora do caminho padrão; este script aponta para ele.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
if [ -d "$DEV/Library/Developer/Frameworks/Testing.framework" ]; then
  F="$DEV/Library/Developer/Frameworks"
  L="$DEV/Library/Developer/usr/lib"
  exec swift test \
    -Xswiftc -F -Xswiftc "$F" \
    -Xlinker -F -Xlinker "$F" \
    -Xlinker -rpath -Xlinker "$F" \
    -Xlinker -rpath -Xlinker "$L" "$@"
fi
exec swift test "$@"
