{
  description = "pleamar-shell — Island/Frame, glass panels, cava water";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      packages = forAll (pkgs: let
        # swaybg hard-codes the layer-shell namespace "wallpaper".  Prefix it
        # so `niri msg layers` shows which shell owns the background.
        swaybg-pleamar = pkgs.swaybg.overrideAttrs (old: {
          pname = "swaybg-pleamar";
          postPatch = (old.postPatch or "") + ''
            substituteInPlace main.c --replace-fail '"wallpaper"' '"pleamar-shell-wallpaper"'
          '';
        });
      in {
        inherit swaybg-pleamar;
        default = pkgs.callPackage ./nix/package.nix { swaybg = swaybg-pleamar; };
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [ bash coreutils findutils gnused gnugrep gawk jq imagemagick python3 swaybg swayidle procps util-linux ];
        };
      });
    };
}
