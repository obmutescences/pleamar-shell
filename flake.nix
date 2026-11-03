{
  description = "pleamar-shell — Island/Frame, glass panels, cava water";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #  The engine, built from its Git source instead of whichever pleamar
    #  happens to be in /nix/store.  The input follows upstream main; the
    #  lockfile pins the latest fetched revision until `nix flake update pleamar`.
    pleamar = {
      url = "github:k4ditano/pleamar";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    #  The released skwd-wall v2 binaries.  Its daemon owns the background
    #  layer and the shader transitions; Pleamar keeps the picker and colours.
    skwdWall = {
      url = "github:liixini/skwd-wall/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, pleamar, skwdWall }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      #  The release channel ships x86_64 binaries only.  Keep the aarch64
      #  package evaluable with the swaybg-only fallback.
      skwdFor = pkgs: if pkgs.stdenv.hostPlatform.system == "x86_64-linux"
        then skwdWall.packages.x86_64-linux.default
        else null;
    in {
      nixosModules.default = { config, lib, pkgs, ... }: import ./nix/nixos-module.nix {
        inherit config lib pkgs;
        pleamar = pleamar.packages.${pkgs.stdenv.hostPlatform.system}.default;
        skwdWall = skwdFor pkgs;
      };

      packages = forAll (pkgs: let
        swaybg-pleamar = import ./nix/swaybg-pleamar.nix { inherit pkgs; };
      in {
        inherit swaybg-pleamar;
        default = pkgs.callPackage ./nix/package.nix {
          swaybg = swaybg-pleamar;
          pleamar = pleamar.packages.${pkgs.stdenv.hostPlatform.system}.default;
          skwdWall = skwdFor pkgs;
        };
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [ bash coreutils findutils gnused gnugrep gawk jq imagemagick python3 wireplumber swayidle procps util-linux ]
            ++ [ (import ./nix/swaybg-pleamar.nix { inherit pkgs; }) ]
            ++ [ pleamar.packages.${pkgs.stdenv.hostPlatform.system}.default ];
        };
      });
    };
}
