# Experiments

`wrap.plm` is the single-full-screen water ring: perfect rounded corners and a
seamless perimeter, but one 2560×1440 layer. Measured on the RX 6500 XT / niri:
median 8.3 ms (~120 fps) alone, ~11.1 ms (~90 fps) while switching workspaces.
The default shell uses the four 120 px strips + four corner shaders instead.

`probe.plm` is a 1×1 overlay that only requests frame callbacks. It is the
no-shell baseline: `tests/baseline.sh` switches workspaces every 300 ms and
reports niri itself at median 11.0 ms (~91 fps). A background-layer four-edge
variant was also tried: it reserved the border, measured 11.7 ms (~79 fps),
and was removed; the four-edge overlay is faster and keeps the corners on the
actual screen corners.

Run them with:

```sh
pleamar --scene experiments/wrap.plm --no-hud
./tests/baseline.sh
```
