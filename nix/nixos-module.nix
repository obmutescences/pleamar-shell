{ config, lib, pkgs, ... }:

let
  cfg = config.services.pleamar-shell;
in
{
  options.services.pleamar-shell = {
    enable = lib.mkEnableOption "Pleamar shell";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { swaybg = pkgs.swaybg; };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { swaybg = pkgs.swaybg; }";
      description = "Pleamar shell package (includes pleamar-shell and pleamar-ipc).";
    };

    layout = lib.mkOption {
      type = lib.types.enum [ "island" "frame" ];
      default = "island";
      description = "Pleamar layout to start.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Keep IPC helpers on PATH for keybindings and the lock helper.
    environment.systemPackages = [ cfg.package ];

    systemd.user.services.pleamar-shell = {
      description = "Pleamar shell (${cfg.layout})";
      after = [ "graphical-session.target" ];
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
      };
    };
  };
}
