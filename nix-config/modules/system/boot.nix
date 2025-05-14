{ config, pkgs, lib, ... }:
let
  # Minecraft GRUB theme (updated for modern NixOS)
  minecraftGrubTheme = pkgs.stdenv.mkDerivation {
    name = "minecraft-grub-theme";
    src = pkgs.fetchFromGitHub {
      owner = "Lxtharia";
      repo = "minecraft-grub-theme";
      rev = "v2.1";
      sha256 = "sha256-7UANZ9p9QHQ2XebB9Nl1ZUGQqFqMYOueQnXQD8j6WzY=";
    };
    installPhase = ''
      mkdir -p $out/grub/themes/minecraft
      cp -r $src/* $out/grub/themes/minecraft
    '';
  };
in
{
  ####################
  ### Bootloader (GRUB)
  ####################
  boot = {
    loader = {
      grub = {
        enable = true;
        efiSupport = true;
        theme = "${minecraftGrubTheme}/grub/themes/minecraft";
        splashImage = null; # Let theme handle background
        gfxmodeEfi = "1920x1080";
        configurationLimit = 10; # Keep last 10 generations
        extraConfig = ''
          set timeout_style=hidden
          set timeout=1
        '';
      };
      efi.canTouchEfiVariables = true;
      timeout = 1;
    };

    # Faster boot
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "loglevel=3"
      "systemd.show_status=auto"
      "udev.log_level=3"
    ];
  };

  ####################
  ### Wayland Display Manager (SDDM)
  ####################
  services = {
    xserver.enable = lib.mkForce false; # Explicitly disable X11

    displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
        theme = "${pkgs.sddm-sugar-candy}";
        settings = {
          Theme = {
            CursorTheme = "Adwaita";
            Font = "Fira Code";
            Background = "${pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/master/wallpapers/nix-wallpaper-mosaic-blue.png";
              sha256 = "sha256-7UANZ9p9QHQ2XebB9Nl1ZUGQqFqMYOueQnXQD8j6WzY=";
            }}";
          };
        };
      };
      defaultSession = "sway"; # Or "sway" if using Sway
    };
  };

  ####################
  ### Additional Optimizations
  ####################
  systemd.services = {
    # Faster startup for critical services
    systemd-udev-settle.enable = false;
    NetworkManager-wait-online.enable = false;
  };

  environment.systemPackages = with pkgs; [
    # Boot analysis tools
    bootanalyze
    systemd-boot-manager

    # Theme utilities
    grub-customizer
    sddm-theme-switcher
  ];
}