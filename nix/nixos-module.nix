{ config, lib, pkgs, pleamar, skwdWall ? null, ... }:

let
  cfg = config.services.pleamar-shell;
  swaybg-pleamar = import ./swaybg-pleamar.nix { inherit pkgs; };
  skwdEnabled = cfg.skwdWall && skwdWall != null;
in
{
  options.services.pleamar-shell = {
    enable = lib.mkEnableOption "Pleamar shell";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix {
        swaybg = swaybg-pleamar;
        inherit pleamar;
        skwdWall = if cfg.skwdWall then skwdWall else null;
      };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { swaybg = ...; pleamar = ...; skwdWall = ...; }";
      description = "Pleamar shell package (includes pleamar-shell and pleamar-ipc).";
    };

    layout = lib.mkOption {
      type = lib.types.enum [ "island" "frame" ];
      default = "island";
      description = "Pleamar layout to start.";
    };

    skwdWall = lib.mkOption {
      type = lib.types.bool;
      default = skwdWall != null;
      description = ''
        Use skwd-wall v2's daemon as the wallpaper backend.  It owns the
        background layer and provides the shader transitions; Pleamar keeps
        the picker, config and palette.  Falls back to the old flow only when
        this is disabled or the release has no binary for this system.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = !cfg.skwdWall || skwdWall != null;
      message = "services.pleamar-shell.skwdWall needs the skwd-wall flake input (x86_64-linux release binaries).";
    }];

    # Keep IPC helpers on PATH for keybindings and the lock helper.
    environment.systemPackages = [ cfg.package ]
      ++ lib.optional skwdEnabled skwdWall;

    systemd.user.services.skwd-walld = lib.mkIf skwdEnabled {
      description = "skwd-wall v2 wallpaper daemon";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${skwdWall}/bin/skwd-walld";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    systemd.user.services.pleamar-shell = {
      description = "Pleamar shell (${cfg.layout})";
      after = [ "graphical-session.target" ] ++ lib.optional skwdEnabled "skwd-walld.service";
      wants = lib.optional skwdEnabled "skwd-walld.service";
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      # A failed start should be retried, not left in failed state.
      startLimitIntervalSec = 0;

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/pleamar-shell ${cfg.layout}";
        Restart = "on-failure";
        RestartSec = 2;
        # The wrapper starts one scene per session; a quick restart can race
        # the old process during shutdown, so let the retry succeed once it is gone.
        RestartSteps = 5;
        RestartMaxDelaySec = 30;
        #  ccal is installed in the NixOS profile, not nixpkgs (upstream
        #  removed it), and systemd user services do not inherit the login
        #  PATH.  Expose the system profile so the calendar helper can find it;
        #  the package wrapper prepends its own runtime tools after this.
        Environment = lib.optional skwdEnabled "PLEAMAR_WALL_BACKEND=skwd"
          ++ [ "PATH=${config.system.path}/sw/bin" ];
      };
    };
  };
}
