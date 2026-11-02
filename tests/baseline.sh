#!/usr/bin/env bash
# Baseline: niri alone, no shell.  A 1x1 overlay only requests frame callbacks;
# the same 300 ms workspace-switch loop as tests/perf.sh.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
command -v niri >/dev/null || { echo "niri is required" >&2; exit 1; }
p="$("$root/bin/pleamar-shell" --path)"
out="$root/out/baseline.md"
mkdir -p "$root/out"
orig="$(niri msg workspaces | awk '/\*/ {gsub(/"/,"",$3); print $2; exit}')"
[[ -n "$orig" ]] || orig=1

"$p" --scene "$root/experiments/probe.plm" --no-hud --seconds 15 \
    >"$root/out/baseline.log" 2>&1 &
scene=$!
sleep 2
echo "niri only · 1x1 frame-callback probe · switching workspaces every 300 ms"
( for i in $(seq 1 28); do
      niri msg action focus-workspace $(( i % 4 + 1 )) >/dev/null 2>&1 || true
      sleep 0.3
  done
  niri msg action focus-workspace "$orig" >/dev/null 2>&1 || true
) &
sw=$!
"$p" --report probe --seconds 8 --out "$out" 2>&1 | tail -8
wait "$sw" 2>/dev/null || true
niri msg action focus-workspace "$orig" >/dev/null 2>&1 || true
sleep 6
echo "--- $out"
grep -E 'Measured|Frame time|Late frames' "$out" || true
