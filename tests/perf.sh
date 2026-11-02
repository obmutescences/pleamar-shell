#!/usr/bin/env bash
# Measures one scene while the workspaces are switched every 300 ms.
# Uses whatever the system sink is playing; it does not generate audio.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-island}"
case "$mode" in island|frame) ;; *) echo "usage: $0 island|frame" >&2; exit 2 ;; esac
command -v niri >/dev/null || { echo "niri is required" >&2; exit 1; }

p="$("$root/bin/pleamar-shell" --path)"
export PLEAMAR_SHELL_ROOT="$root"
out="$root/out/perf-$mode.md"
mkdir -p "$root/out"
orig="$(niri msg workspaces | awk '/\*/ {gsub(/"/,"",$3); print $2; exit}')"
[[ -n "$orig" ]] || orig=1

"$p" --scene "$root/scenes/$mode.plm" --no-hud --seconds 15 --mouse "1280,700@0" \
    >"$root/out/perf-$mode.log" 2>&1 &
scene=$!
sleep 2
music="$("$p" --say "$mode" "get music_on" 2>/dev/null || true)"
echo "$mode · music_on=$music · switching workspaces every 300 ms"

( for i in $(seq 1 28); do
      niri msg action focus-workspace $(( i % 4 + 1 )) >/dev/null 2>&1 || true
      sleep 0.3
  done
  niri msg action focus-workspace "$orig" >/dev/null 2>&1 || true
) &
sw=$!

"$p" --report "$mode" --seconds 8 --out "$out" 2>&1 | tail -8
wait "$sw" 2>/dev/null || true
niri msg action focus-workspace "$orig" >/dev/null 2>&1 || true
sleep 6

echo "--- $out"
grep -E 'Frame time|Late frames|Measured|Surface:' "$out" || true
echo "--- timing lines"
grep -E 'timing · [0-9]+ rounds|^cycle' "$root/out/perf-$mode.log" | tail -6 || true
