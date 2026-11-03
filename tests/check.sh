#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
p="${PLEAMAR:-}"
if [[ -z "$p" || ! -x "$p" ]]; then
    p="$(ls -d /nix/store/*-pleamar-*/bin/pleamar 2>/dev/null | sort -V | tail -1)"
fi
[[ -n "$p" && -x "$p" ]] || { echo "pleamar not found; set PLEAMAR" >&2; exit 1; }
for scene in island frame; do
    "$p" --check "$root/scenes/$scene.plm"
done
"$p" --check "$root/lockscreen/lockscreen.plm"
"$p" --check "$root/scenes/centerkeys.plm"
"$p" --check "$root/scenes/settingskeys.plm"
"$p" --check "$root/experiments/wrap.plm"
"$p" --check "$root/experiments/probe.plm"

#  The lock and keyboard helpers run this discovery from a systemd unit whose
#  PATH has no nix-store.  It used to exit 127 there, which made every button
#  that starts a helper do nothing; it must still print a usable binary.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for c in bash dirname sed sort tail; do
    src="$(type -P "$c")"
    [[ -n "$src" ]] || { echo "$c is required" >&2; exit 1; }
    ln -s "$src" "$tmp/$c"
done
helper_bin="$(env -i HOME="${HOME:-/tmp}" PATH="$tmp" "$root/bin/pleamar-shell" --path)"
[[ -x "$helper_bin" ]] || {
    echo "pleamar-shell --path failed with a minimal PATH" >&2
    exit 1
}

#  The centre panel's System page is fed by this helper; a broken JSON line
#  would silently blank the whole monitor.
"$root/bin/pleamar-sysmon" --once | python3 -c '
import json, sys
row = json.load(sys.stdin)
assert "cpu" in row and "mem" in row and "net" in row and "disk" in row
'
