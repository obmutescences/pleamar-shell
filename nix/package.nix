{ lib, stdenvNoCC, makeWrapper, pleamar, bash, coreutils, findutils, imagemagick, python3, swaybg, procps, util-linux, libnotify, pipewire, xdg-utils, cliphist, wl-clipboard, cava, fontconfig, jq, niri, swayidle, curl, skwdWall ? null }:

let
  runtimePackages = [
    bash coreutils findutils imagemagick python3 swaybg procps util-linux
    libnotify pipewire xdg-utils cliphist wl-clipboard cava fontconfig jq niri
    swayidle curl
  ] ++ lib.optional (skwdWall != null) skwdWall;
  ipcPackages = [ bash coreutils procps jq util-linux ]
    ++ lib.optional (skwdWall != null) skwdWall;
in
stdenvNoCC.mkDerivation {
  pname = "pleamar-shell";
  version = "0.1.0";

  src = ../.;
  dontBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/pleamar-shell $out/bin
    cp -r scenes modules lockscreen bin assets tests experiments README.md $out/share/pleamar-shell/
    #  Force the engine built from the flake's Git source.  Without this the
    #  launcher's discovery falls back to whichever pleamar is in the system
    #  store (0.4.31 here) and the shell silently runs the old one.
    makeWrapper ${bash}/bin/bash $out/bin/pleamar-shell \
      --add-flags "$out/share/pleamar-shell/bin/pleamar-shell" \
      --set PLEAMAR ${pleamar}/bin/pleamar \
      --set SWAYBG ${swaybg}/bin/swaybg \
      --prefix PATH : ${pleamar}/bin \
      --suffix PATH : ${lib.makeBinPath runtimePackages}
    makeWrapper ${bash}/bin/bash $out/bin/pleamar-ipc \
      --add-flags "$out/share/pleamar-shell/bin/pleamar-ipc" \
      --set PLEAMAR ${pleamar}/bin/pleamar \
      --prefix PATH : ${pleamar}/bin \
      --suffix PATH : ${lib.makeBinPath ipcPackages}
    runHook postInstall
  '';

  meta = {
    description = "Pleamar Island/Frame shell with glass panels and cava water";
    license = lib.licenses.mit;
    mainProgram = "pleamar-shell";
    platforms = lib.platforms.linux;
  };
}
