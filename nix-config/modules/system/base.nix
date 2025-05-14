{ config, pkgs, lib, ... }:
{
  ####################
  ### Core System Settings
  ####################
  time.timeZone = "Europe/Moscow";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_TIME = "ru_RU.UTF-8";
      LC_MONETARY = "ru_RU.UTF-8";
    };
  };
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  ####################
  ### Graphics & Input
  ####################
  hardware = {
    # GPU/Acceleration
    opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
      extraPackages = with pkgs; [ 
        vaapiVulkanDriver
        libvdpau-va-gl
      ];
    };

    # Touchpad/Mouse
    libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
        disableWhileTyping = true;
      };
    };

    # Bluetooth
    bluetooth = {
      enable = true;
      powerOnBoot = false;
      settings = {
        General = {
          Enable = "Source,Sink,Media,Socket";
          FastConnectable = true;
        };
      };
    };
  };

  ####################
  ### Audio
  ####################
  sound.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = false;
    wireplumber.enable = true;
  };

  ####################
  ### Networking
  ####################
  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];
    };
    nameservers = [ "1.1.1.1" "8.8.8.8" ]; # Cloudflare + Google DNS
  };

  services = {
    # SSH Server
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # DNS Resolution
    resolved.enable = true;
  };

  ####################
  ### Security
  ####################
  security = {
    polkit.enable = true;
    sudo = {
      enable = true;
    };
  };

  # Disk Management
  services.udisks2.enable = true;

  ####################
  ### Essential Packages
  ####################
  environment.systemPackages = with pkgs; [
    # Network Utilities
    curl wget openssh openssl nmap tcpdump

    # Wayland Core
    wayland-utils wlr-randr brightnessctl glxinfo

    # System Tools
    file strace lsof pciutils usbutils
  ];

  ####################
  ### Wayland Environment
  ####################
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ ]; # Explicitly empty to prevent X11 fallbacks
  };
}