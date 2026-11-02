{ lib, stdenvNoCC, makeWrapper, bash, coreutils, findutils, imagemagick, python3, swaybg, procps, util-linux, libnotify, pipewire, xdg-utils, cliphist, wl-clipboard, cava, fontconfig, jq, niri, swayidle, curl }:

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
    makeWrapper ${bash}/bin/bash $out/bin/pleamar-shell \
      --add-flags "$out/share/pleamar-shell/bin/pleamar-shell" \
      --suffix PATH : ${lib.makeBinPath [ bash coreutils findutils imagemagick python3 swaybg procps util-linux libnotify pipewire xdg-utils cliphist wl-clipboard cava fontconfig jq niri swayidle curl ]}
    makeWrapper ${bash}/bin/bash $out/bin/pleamar-ipc \
      --add-flags "$out/share/pleamar-shell/bin/pleamar-ipc" \
      --suffix PATH : ${lib.makeBinPath [ bash coreutils procps jq util-linux ]}
    runHook postInstall
  '';

  meta = {
    description = "Pleamar Island/Frame shell with glass panels and cava water";
    license = lib.licenses.mit;
    mainProgram = "pleamar-shell";
    platforms = lib.platforms.linux;
  };
}
