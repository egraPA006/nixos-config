{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/base
    ../../modules/hardware/nvidia.nix
    ../../modules/profiles
  ];

  networking.hostName = "re-1";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  zramSwap.enable = true;

  services.hardware.openrgb.enable = true;

  users.users.egrapa = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
    ];
    shell = pkgs.fish;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      hostname = "re-1";
    };
    users.egrapa = {
      imports = [ ../../home ];
      systemd.user.services.openrgb-init = {
        Unit.Description = "Set OpenRGB default colors";
        Unit.After = [ "graphical-session.target" ];
        Install.WantedBy = [ "graphical-session.target" ];
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.openrgb}/bin/openrgb --color FF70AB";
          RemainAfterExit = false;
        };
      };
    };
  };

  systemd.paths.gdm-monitor-config = {
    description = "Watch for GDM greeter home creation";
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathCreated = "/run/gdm/home/gdm-greeter";
  };

  systemd.services.gdm-monitor-config = {
    description = "Set GDM monitor configuration";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gdm-monitor-config" ''
        mkdir -p /run/gdm/home/gdm-greeter/.config
        cat > /run/gdm/home/gdm-greeter/.config/monitors.xml << 'EOF'
<monitors version="2">
  <configuration>
    <layoutmode>logical</layoutmode>
    <logicalmonitor>
      <x>0</x>
      <y>0</y>
      <scale>1</scale>
      <primary>yes</primary>
      <monitor>
        <monitorspec>
          <connector>DP-3</connector>
          <vendor>HPN</vendor>
          <product>HP X27q</product>
          <serial>6CM14208Y0</serial>
        </monitorspec>
        <mode>
          <width>2560</width>
          <height>1440</height>
          <rate>59.951</rate>
        </mode>
      </monitor>
    </logicalmonitor>
    <logicalmonitor>
      <x>2560</x>
      <y>234</y>
      <scale>1</scale>
      <monitor>
        <monitorspec>
          <connector>HDMI-1</connector>
          <vendor>SAM</vendor>
          <product>SAMSUNG</product>
          <serial>0x01000e00</serial>
        </monitorspec>
        <mode>
          <width>1920</width>
          <height>1080</height>
          <rate>60.000</rate>
        </mode>
      </monitor>
    </logicalmonitor>
  </configuration>
</monitors>
EOF
        chown -R 60578:132 /run/gdm/home/gdm-greeter/.config
      '';
    };
  };

  system.stateVersion = "25.05";
}
