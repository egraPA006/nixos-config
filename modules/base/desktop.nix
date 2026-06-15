{ pkgs, ... }:
{
  xdg.portal = {
    enable = true;
    config.common.default = "gnome";
  };

  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "us,ru";
    options = "grp:alt_shift_toggle";
  };
  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm = {
    enable = true;
    settings = {
      greeter.MultiMonitor = "mirror";
    };
  };

  environment.systemPackages = with pkgs.gnomeExtensions; [
    clipboard-history
    tiling-assistant
  ];

  environment.gnome.excludePackages = with pkgs; [
    gnome-photos
    gnome-tour
    gnome-music
    epiphany
    geary
    totem
  ];
}
