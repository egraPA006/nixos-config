{ pkgs, ... }:

{
  imports = [ ./gaming-lite.nix ];

  services.udev.extraRules = ''
    # Moza (Gudsen) ttyACM devices — uaccess so any logged-in user can reach them
    SUBSYSTEM=="tty", KERNEL=="ttyACM*", ATTRS{idVendor}=="346e", ACTION=="add", TAG+="uaccess"
    # uinput — needed to create virtual joysticks
    SUBSYSTEM=="misc", KERNEL=="uinput", OPTIONS+="static_node=uinput", TAG+="uaccess"
  '';
  programs.gamescope = {
    capSysNice = true;
  };

  programs.steam = {
    remotePlay.openFirewall = true;
    gamescopeSession = {
      args = [
        "--force-grab-cursor"
      ];
    };
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
    package = pkgs.steam.override {
      extraProfile = ''
        export PROTON_ENABLE_WAYLAND=1
      '';
    };
  };

  programs.gamemode = {
    enableRenice = true;
  };

  environment.systemPackages = with pkgs; [
    gamescope-wsi
    lutris
    r2modman
    # wineWowPackages.stable
    # winetricks
    boxflat
  ];
}
