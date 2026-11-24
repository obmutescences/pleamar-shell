#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
p="${PLEAMAR:-}"
if [[ -z "$p" || ! -x "$p" ]]; then
    p="$("$root/bin/pleamar-shell" --path 2>/dev/null || true)"
fi
if [[ -z "$p" || ! -x "$p" ]]; then
    p="$(ls -d /nix/store/*-pleamar-*/bin/pleamar 2>/dev/null | sort -V | tail -1)"
fi
[[ -n "$p" && -x "$p" ]] || { echo "pleamar not found; set PLEAMAR" >&2; exit 1; }
"$p" --check "$root/scenes/notches.plm"
"$p" --check "$root/lockscreen/lockscreen.plm"
"$p" --check "$root/scenes/centerkeys.plm"
"$p" --check "$root/scenes/settingskeys.plm"
"$p" --check "$root/experiments/wrap.plm"
"$p" --check "$root/experiments/probe.plm"

#  Headless layout QA check (introduced in pleamar 0.8-exp).
"$p" --layout "$root/scenes/notches.plm" | tail -n 1 | python3 -c '
import json, sys
report = json.load(sys.stdin)
assert isinstance(report, dict), report
'

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

#  Frame-pacing chatter belongs to tuning, not the journal.  The wrapper
#  drops it by default and PLEAMAR_RENDER_LOG=1 brings it back.
cat >"$tmp/fake-pleamar" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" --version "* ]]; then echo "fake 1.0"; exit 0; fi
echo 'render · slow frame: 34 ms at 90.55 s'
echo 'render · this scene does not keep up: 12.1 ms a frame'
echo 'render · captures of a glass go straight onto the card (480×560), the processor never reads them'
echo 'render · the compositor is not showing this surface: painting once a second until it shows it again'
echo 'render · the compositor is showing it again'
echo 'render · failed to import capture'
echo 'kept line'
echo 'fatal kept on stderr' >&2
EOF
chmod +x "$tmp/fake-pleamar"
PLEAMAR="$tmp/fake-pleamar" "$root/bin/pleamar-shell" notches >"$tmp/filtered" 2>&1
grep -q '^kept line$' "$tmp/filtered" || { echo "render filter ate ordinary output" >&2; exit 1; }
grep -q 'fatal kept on stderr' "$tmp/filtered" || { echo "render filter ate stderr" >&2; exit 1; }
! grep -q '^render · slow frame' "$tmp/filtered" || { echo "render filter left slow frames" >&2; exit 1; }
PLEAMAR="$tmp/fake-pleamar" PLEAMAR_RENDER_LOG=1 "$root/bin/pleamar-shell" notches >"$tmp/unfiltered" 2>&1
grep -q '^render · slow frame' "$tmp/unfiltered" || { echo "PLEAMAR_RENDER_LOG did not restore logs" >&2; exit 1; }
! grep -q '^render · captures of a glass' "$tmp/filtered" || { echo "render filter left capture notices" >&2; exit 1; }
! grep -q '^render · the compositor is' "$tmp/filtered" || { echo "render filter left compositor pacing notices" >&2; exit 1; }
grep -q '^render · failed to import capture' "$tmp/filtered" || { echo "render filter ate a failure" >&2; exit 1; }
grep -q '^render · captures of a glass' "$tmp/unfiltered" || { echo "PLEAMAR_RENDER_LOG did not restore capture notices" >&2; exit 1; }
grep -q '^render · the compositor is not showing this surface' "$tmp/unfiltered" || { echo "PLEAMAR_RENDER_LOG did not restore compositor notices" >&2; exit 1; }
bash -n "$root/bin/pleamar-shell" "$root/bin/pleamar-lock" "$root/bin/pleamar-lock-keeper" "$root/bin/pleamar-settingskeys"

#  lockscreen.plm must declare `screens: all` unquoted (quoted `"all"` matches a
#  literal monitor name and breaks ext-session-lock on DPMS wake).
grep -qE '^[[:space:]]*screens:[[:space:]]*all([[:space:]]|$)' "$root/lockscreen/lockscreen.plm"

#  The centre panel's System page is fed by this helper; a broken JSON line
#  would silently blank the whole monitor.
"$root/bin/pleamar-sysmon" --once | python3 -B -c '
import json, sys
row = json.load(sys.stdin)
assert "cpu" in row and "mem" in row and "net" in row and "disk" in row
'

#  Bar widgets use --lite mode: ensure its first JSON line arrives promptly.
python3 -B - "$root/bin/pleamar-sysmon" <<'PY'
import json, subprocess, sys
proc = subprocess.Popen([sys.argv[1], "--lite"], stdout=subprocess.PIPE, text=True)
try:
    line = proc.stdout.readline()
finally:
    proc.terminate()
    proc.wait(timeout=4)
row = json.loads(line)
assert row.get("lite") is True, row
assert "cpu" in row and "total" in row["cpu"], row
assert "mem" in row and "total" in row["mem"] and "used" in row["mem"], row
assert "net" in row and "rx" in row["net"] and "tx" in row["net"], row
PY

#  The calendar's countdown follows the month on screen, not the month of
#  today, and keeps an anniversary that has just passed (marked 已过).  The
#  grid also carries the full lunar date used by hover.
python3 - "$root" "$tmp/calendar" <<'PY'
import json, os, shutil, subprocess, sys
from datetime import date
from pathlib import Path

root, work = Path(sys.argv[1]), Path(sys.argv[2])
today = date.today()
if today.month == 12:
    next_year, next_month = today.year + 1, 1
else:
    next_year, next_month = today.year, today.month + 1
conf = work / "conf" / "pleamar-shell"
cache = work / "cache" / "pleamar-shell" / "holidays"
conf.mkdir(parents=True)
cache.mkdir(parents=True)
(conf / "anniversaries.json").write_text(json.dumps([
    {"name": "PastTest", "calendar": "solar", "month": today.month, "day": 1},
    {"name": "NextTest", "calendar": "solar", "month": next_month, "day": 1},
]), encoding="utf-8")
for year in {today.year, next_year}:
    (cache / f"{year}.json").write_text('{"days":[]}', encoding="utf-8")
env = dict(os.environ, XDG_CONFIG_HOME=str(work / "conf"),
           XDG_CACHE_HOME=str(work / "cache"))

def build(year, month):
    out = subprocess.run(
        [sys.executable, str(root / "bin" / "pleamar-calendar"),
         "--year", str(year), "--month", str(month)],
        env=env, check=True, capture_output=True, text=True, timeout=30,
    ).stdout
    return json.loads(out)

cur = build(today.year, today.month)
assert cur["countdown_title"] == "本月倒计时", cur["countdown_title"]
past = next(c for c in cur["countdowns"] if c["title"] == "PastTest")
assert past["days"] <= 0
assert past["when"] == "今天" or past["when"].startswith("已过"), past
nxt = build(next_year, next_month)
assert nxt["countdown_title"] == f"{next_month}月倒计时", nxt["countdown_title"]
nxt_item = next(c for c in nxt["countdowns"] if c["title"] == "NextTest")
assert nxt_item["days"] > 0
ncd = cur.get("next_countdown")
assert ncd is not None, cur
expected_title = "PastTest" if today.day == 1 else "NextTest"
assert ncd["title"] == expected_title, ncd
assert ncd["days"] >= 0 and ncd["days_txt"] and ncd["label"].startswith(expected_title), ncd
assert len(nxt["days"]) == 42
assert all(c["hover"] for c in nxt["days"])
if shutil.which("ccal"):
    assert any("农历" in c["hover"] for c in nxt["days"])
PY
