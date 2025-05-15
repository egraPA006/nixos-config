{ config, pkgs, ... }:
{
  ##### Display Manager (SDDM) #####
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  ##### Core Sway/Wayland #####
  programs.sway = {
    enable = true;
    wrapperFeatures = {
      gtk = true;  # GTK3 integration
      base = true;  # Base Sway functionality
    };
  };

  ##### Essential WM Packages #####
  environment.systemPackages = with pkgs; [
    # Sway Essentials
    swayidle
    swaylock
    swaybg
    wlr-randr
    wofi

    # Wayland Utilities
    wl-clipboard
    cliphist
    grim
    slurp
    mako
    wlsunset
    wayland-utils
    waybar

    # Display Control
    brightnessctl  # Only included because it's often bound to WM keybindings
  ];

  ##### Required Services #####
  services.xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
  };
}