{ config, pkgs, ... }:
{
  # Enable sound (PipeWire for modern Wayland support)
  sound.enable = true;
  hardware.pulseaudio.enable = false;  # Disable PulseAudio (conflicts with PipeWire)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;  # PulseAudio replacement
    jack.enable = true;   # For professional audio
  };

  # Network (NetworkManager for simplicity)
  networking.networkmanager.enable = true;
  networking.wireless.enable = false;  # Disable wpa_supplicant if using NM

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
  services.blueman.enable = false;  # Disable GUI (configured later in Home Manager)

  # Wayland essentials (no DM/WM here!)
  programs.sway.enable = true;  # Required for Wayland compatibility
  xdg.portal = {
    enable = true;
    wlr.enable = true;          # Screen sharing for Wayland
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Hardware (GPU, input, etc.)
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;     # For 32-bit apps (e.g., Steam)
  };

  i18n = {
    defaultLocale = "en_US.UTF-8";
    supportedLocales = [ "en_US.UTF-8/UTF-8"];
  };

  # Set the time zone
  time.timeZone = "Europe/Moscow";

  # Console keymap
  console.keyMap = "us";

  # Kernel tweaks for Wayland
  boot.kernelParams = [ "quiet" "udev.log_priority=3" ];

  # Security (needed for swaylock, etc.)
  security.pam.services.swaylock = {};
  security.rtkit.enable = true;  # Realtime priority for PipeWire

  # Users (minimal setup)
  users.users.egrapa = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

  # System-wide packages (no GUI apps!)
  environment.systemPackages = with pkgs; [
    git
    wget
    seatd               # For seat management (required by Sway)
    dbus                # D-Bus integration
    glib                # GTK/Wayland utils
  ];

  # Virtualization (disabled here, enabled in `virtualisation.nix`)
  virtualisation.docker.enable = false;
  virtualisation.libvirtd.enable = false;

  # System state version (required)
  system.stateVersion = "23.11";
}