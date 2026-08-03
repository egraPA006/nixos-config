{ config, pkgs, ... }:

let
  python3WithGi = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  monitorTool   = pkgs.writeScriptBin "monitor" ''
    #!${python3WithGi}/bin/python3
    ${builtins.readFile ../../../../scripts/monitor.py}
  '';
in
{
  home-manager.users.${config.pino.user.name}.imports = [ ./home.nix ];

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

  pino.subcommands.desktop.commands.monitor = {
    description = "Manage display profiles";
    commands = {
      list.description = "List saved display profiles";
      status.description = "Show the current display layout";
      switch = { description = "Apply a saved display profile"; usage = "<name>"; };
      save = { description = "Save the current display layout"; usage = "<name>"; };
      rm = { description = "Delete a saved display profile"; usage = "<name>"; };
    };
    helpText = ''
      pino desktop monitor — manage GNOME display profiles
        pino desktop monitor list               List saved profiles
        pino desktop monitor status             Show current display layout
        pino desktop monitor switch <name>      Apply a saved profile
        pino desktop monitor save   <name>      Save current GNOME layout as a profile
        pino desktop monitor rm     <name>      Delete a saved profile

        Profiles stored in ~/.config/monitor-profiles/
      Set a layout in GNOME Settings → Displays, then: pino desktop monitor save <name>
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
