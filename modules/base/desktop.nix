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
    helpText = ''
      pino monitor — manage GNOME display profiles
        pino monitor list               List saved profiles
        pino monitor status             Show current display layout
        pino monitor switch <name>      Apply a saved profile
        pino monitor save   <name>      Save current GNOME layout as a profile
        pino monitor rm     <name>      Delete a saved profile

        Profiles stored in ~/.config/monitor-profiles/
        Set a layout in GNOME Settings → Displays, then: pino monitor save <name>
    '';
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
