{ config, pkgs, lib, ... }:
{
  # Enable Wayland and required services
  services.xserver.enable = false;  # Explicitly disable X11
  programs.dconf.enable = true;
  security.polkit.enable = true;

  # Display manager (SDDM with Wayland support)
  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
      package = lib.mkForce pkgs.kdePackages.sddm;
    };
    defaultSession = "plasma";
  };

  # Desktop manager (Plasma 6)
  services.desktopManager.plasma6.enable = true;

  # Environment options
  environment = {
    plasma6.excludePackages = with pkgs.kdePackages; [
      plasma-browser-integration
      elisa
      okular
      kate
      khelpcenter
      krdp
    ];

        # System packages
    systemPackages = with pkgs.kdePackages; [
    ];


    # Plasma 6 session variables
    sessionVariables = {
      QT_QPA_PLATFORM = "wayland";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      SDL_VIDEODRIVER = "wayland";
      XDG_SESSION_TYPE = "wayland";
      MOZ_ENABLE_WAYLAND = "1";
      CLUTTER_BACKEND = "wayland";
      GDK_BACKEND = "wayland";
      NIXOS_OZONE_WL = "1";  # For Chromium/Electron apps
    };
  };

  # XDG Portal configuration
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];
    wlr.enable = true;
    config.common.default = "*";
  };

  # Qt theming
  qt = {
    enable = true;
    platformTheme = "kde";
    style = "breeze";
  };

}