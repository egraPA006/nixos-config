{ config, pkgs, ... }:
{
  sound.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  networking.networkmanager.enable = true;
  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Hardware (GPU, input, etc.)
  # hardware.opengl = {
  #   enable = true;
  #   driSupport = true;
  #   driSupport32Bit = true;     # For 32-bit apps (e.g., Steam)
  # };

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ru_RU.UTF-8";
    LC_IDENTIFICATION = "ru_RU.UTF-8";
    LC_MEASUREMENT = "ru_RU.UTF-8";
    LC_MONETARY = "ru_RU.UTF-8";
    LC_NAME = "ru_RU.UTF-8";
    LC_NUMERIC = "ru_RU.UTF-8";
    LC_PAPER = "ru_RU.UTF-8";
    LC_TELEPHONE = "ru_RU.UTF-8";
    LC_TIME = "ru_RU.UTF-8";
  };
  time.timeZone = "Europe/Moscow";
  console.keyMap = "us";

  # Kernel tweaks for Wayland
  boot.kernelParams = [ "quiet" "udev.log_priority=3" ];

  # Security (needed for swaylock, etc.)
  security.pam.services.swaylock = {};
  security.rtkit.enable = true;  # Realtime priority for PipeWire

  # System-wide packages (no GUI apps!)
  environment.systemPackages = with pkgs; [
  ];
  nixpkgs.config.allowUnfree = true;

  services.openssh.enable = true;

  system.stateVersion = "24.11";
}