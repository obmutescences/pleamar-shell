# pleamar-shell

[![pleamar-shell showcase](showcase-preview.gif)](showcase.mp4)

A small, animated Wayland shell for [niri](https://github.com/YaLTeR/niri), built on the [Pleamar](https://github.com/k4ditano/pleamar) engine. Its main layout is **Notches**: one continuous glass frame, a clock at the top centre, and music-reactive glass bands around the edges.

## Features

- **Notches** — a continuous four-sided glass frame with a top-centre clock and a music band on the top edge or all four edges.
- **Notch drawers** — Settings and the centre panel grow out of the top edge with a liquid throat and water rings.
- **Launcher** — search apps, files, commands, emoji, clipboard history, wallpapers, windows, the web, and calculations.
- **Notifications** — desktop toasts and a notification center.
- **Settings** — appearance, layout, font, motion, notifications, lock screen, idle, weather, and wallpapers.
- **Lock screen** — a separate PAM-backed session-lock scene.
- **Wallpaper and palette** — shader transitions with colors sampled from the current wallpaper.

## Requirements

- Linux with Wayland
- [niri](https://github.com/YaLTeR/niri)
- Nix with flakes (recommended)

## Quick start

```sh
nix build .#default
./result/bin/pleamar-shell notches
```

For local development, the repository launcher works too:

```sh
./bin/pleamar-shell notches
```

## NixOS

Add the flake input and the NixOS module:

```nix
# flake.nix
{
  inputs.pleamar-shell.url = "github:obmutescences/pleamar-shell";

  outputs = { self, nixpkgs, pleamar-shell, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        pleamar-shell.nixosModules.default
      ];
    };
  };
}
```

```nix
# configuration.nix
services.pleamar-shell = {
  enable = true;
  layout = "notches";
};
```

The module installs `pleamar-shell` and `pleamar-ipc` and runs the shell as a systemd user service. Remove any old niri `spawn-at-startup` entry for the shell when switching to the service.

## IPC

`pleamar-ipc` opens the shell's panels without clicking the bar:

```sh
pleamar-ipc search
pleamar-ipc settings        # optionally: settings 0..11
pleamar-ipc notifications
pleamar-ipc windows         # windows toggle for toggle
pleamar-ipc lock
pleamar-ipc wallpaper /path/to/image
```

## Configuration

Settings are stored in:

```text
~/.config/pleamar-shell/config.json
```

Use the settings panel for normal changes. Its **Frame music** page chooses **Top edge** or **Four sides**. Window previews, notification sounds, and wallpaper transitions are handled by helpers installed with the package.

## Credits

Thanks to these projects, which this shell builds on and takes reference from:

- [Vitreus](https://github.com/natepayn3/Vitreus) — glass UI and shell behavior reference.
- [Pleamar](https://github.com/k4ditano/pleamar) — the rendering engine behind this shell.
