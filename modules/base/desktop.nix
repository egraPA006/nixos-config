{ pkgs, ... }:
let
  python3WithGi = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  monitorTool   = pkgs.writeScriptBin "monitor" ''
    #!${python3WithGi}/bin/python3
    ${builtins.readFile ../../scripts/monitor.py}
  '';
in
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
  };

  environment.systemPackages = (with pkgs.gnomeExtensions; [
    clipboard-history
    tiling-assistant
  ]) ++ [ monitorTool ];

  pino.subcommands.monitor = {
    description = "Manage display profiles";
    script = ''monitor "$@"'';
  };

  environment.gnome.excludePackages = with pkgs; [
    gnome-photos
    gnome-tour
    gnome-music
    epiphany
    geary
    totem
  ];
}
