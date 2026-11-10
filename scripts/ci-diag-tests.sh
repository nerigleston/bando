#!/bin/bash
# Diagnóstico temporário: roda cada teste sozinho, com limite de tempo, e
# mostra os processos quando um trava.
set -uo pipefail
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
F="$DEV/Library/Developer/Frameworks"; L="$DEV/Library/Developer/usr/lib"
X=(-Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L")
swift build --build-tests "${X[@]}" 2>&1 | tail -3
swift test list "${X[@]}" --skip-build 2>/dev/null | sed 's/^BandoCoreTests\.//' > /tmp/testes.txt
echo "== $(wc -l < /tmp/testes.txt) testes"; cat /tmp/testes.txt
travou=0
while read -r t; do
  [ -z "$t" ] && continue
  echo "::group::$t"
  swift test "${X[@]}" --skip-build --filter "$t" > /tmp/saida.txt 2>&1 &
  pid=$!
  for i in $(seq 1 60); do kill -0 $pid 2>/dev/null || break; sleep 1; done
  if kill -0 $pid 2>/dev/null; then
    echo "TRAVOU: $t"
    travou=1
    ps -Ao pid,ppid,etime,stat,command | grep -vE "grep|Runner\.|actions-runner" | tail -40
    for p in $(pgrep -f "BandoPackageTests|swiftpm-testing"); do echo "--- sample $p"; sample "$p" 3 2>/dev/null | grep -E "Shell|Executables|Git|FileBrowser|Session|readData|wait|Thread_" | head -40; done
    for p in $(pgrep -P $(pgrep -f swiftpm-testing | head -1) 2>/dev/null); do echo "--- filho $p: $(ps -o command= -p $p)"; lsof -p $p 2>/dev/null | grep -E "PIPE|FIFO" | head; done
    pkill -9 -f "BandoPackageTests|swiftpm-testing"; kill -9 $pid 2>/dev/null
  fi
  tail -4 /tmp/saida.txt
  echo "::endgroup::"
done < /tmp/testes.txt
echo "git: $(git --version) em $(command -v git)"; git config --global --list 2>/dev/null | head -20
exit $travou
