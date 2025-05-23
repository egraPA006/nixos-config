{ config, pkgs, ... }:

{
  # Enable Plasma Wayland without X11
  wayland.windowManager.plasma5 = {
    enable = true;
    # Optional: Enable Wayland-specific features
    wayland.enable = true;
  };

  # Minimal KDE Plasma packages for Wayland
  home.packages = with pkgs; [
    # Core Plasma Wayland components
    plasma5Packages.plasma-desktop
    plasma5Packages.plasma-workspace
    plasma5Packages.kwin
    plasma5Packages.kscreen

    # Wayland specific components
    plasma5Packages.kwayland-integration
    plasma5Packages.plasma-wayland-session
    qt5.qtwayland

    # Basic utilities
    plasma5Packages.dolphin
    plasma5Packages.konsole
    plasma5Packages.kate

    # SDDM for login manager (Wayland version)
    (sddm.override {
      waylandSupport = true;
    })
  ];

  # Configure Qt for Wayland
  qt = {
    enable = true;
    platformTheme = "kde";
    style = "breeze";
  };

  # Environment variables for Wayland
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    SDL_VIDEODRIVER = "wayland";
    XDG_SESSION_TYPE = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    CLUTTER_BACKEND = "wayland";
    GDK_BACKEND = "wayland";
  };

  # Enable D-Bus and XDG portals for proper Wayland integration
  services.dbus.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-kde ];
    wlr.enable = true;
  };
}