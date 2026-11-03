{ pkgs }:

#  swaybg hard-codes the layer-shell namespace "wallpaper".  Prefix it so
#  `niri msg layers` shows which shell owns the background.
pkgs.swaybg.overrideAttrs (old: {
  pname = "swaybg-pleamar";
  postPatch = (old.postPatch or "") + ''
    substituteInPlace main.c --replace-fail '"wallpaper"' '"pleamar-shell-wallpaper"'
  '';
})
