{ config, pkgs, lib, ... }:

let
  # Use the latest KDE packages (replace with unstable or your preferred channel if needed)
  kdePackages = pkgs.kdePackages;
in {
  options = {
    plasma6.enable = lib.mkEnableOption "KDE Plasma 6 desktop environment";
  };

  config = lib.mkIf config.plasma6.enable {
    # Enable Wayland and required services
    services.xserver.enable = false;  # Explicitly disable X11
    programs.dconf.enable = true;
    security.polkit.enable = true;

    # Display manager (SDDM with Wayland support)
    services.displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
        package = pkgs.sddm.override { waylandSupport = true; };
      };
      defaultSession = "plasma";
    };

    # Desktop manager (Plasma 6)
    services.desktopManager.plasma6.enable = true;

    # Environment options
    environment = {
      # System packages
      systemPackages = with kdePackages; [
        # Core Plasma
        plasma-desktop
        plasma-workspace
        kwin
        kscreen
        systemsettings

        # Wayland components
        kwayland-integration
        plasma-wayland-session
        xdg-desktop-portal-kde

        # Basic applications
        dolphin
        konsole
        kate
        ark

        # Qt6 Wayland support
        qt6.qtwayland
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
        kdePackages.xdg-desktop-portal-kde
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

    # Hardware acceleration
    hardware.opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
    };

    # Optional: PipeWire for audio
    sound.enable = true;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };
}