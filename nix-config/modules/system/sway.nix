{ config, pkgs, lib, ... }:
{
  ####################
  ### Pure Wayland Core
  ####################
  programs.sway = {
    enable = true;
    extraPackages = with pkgs; [
      # Required components
      swaylock
      swayidle
      wlroots
      xdg-desktop-portal-wlr
      
      # Basic utilities
      wlr-randr
      grim
      slurp
      wl-clipboard
    ];
  };

  ####################
  ### Essential Services
  ####################
  services = {
    # Screen locking
    swayidle = {
      enable = true;
      timeouts = [
        { timeout = 300; command = "${pkgs.swaylock}/bin/swaylock -f"; }
      ];
    };

    # Screensharing portal
    xdg.portal = {
      enable = true;
      wlr.enable = true;
      extraPortals = [ ]; # Explicitly no X11 fallbacks
    };
  };

  ####################
  ### Hardware Integration
  ####################
  hardware.opengl.enable = true;

  ####################
  ### Environment
  ####################
  environment.variables = {
    NIXOS_OZONE_WL = "1"; # Enable Wayland for Chromium
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    _JAVA_AWT_WM_NONREPARENTING = "1";
  };

  ####################
  ### Security
  ####################
  security.polkit.enable = true;
  security.pam.services.swaylock = {};
}