{ config, lib, pkgs, ... }:

let
  cfg = config.pino.server.gitMirror;
  storageUser = config.pino.user.name;
  postUpdate = pkgs.writeShellScript "pino-git-post-update" ''
    exec ${pkgs.git}/bin/git update-server-info
  '';
in
{
  options.pino.server.gitMirror = {
    enable = lib.mkEnableOption "read-only public NixOS configuration mirror" // { default = true; };
    root = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pino/git";
    };
    repository = lib.mkOption {
      type = lib.types.str;
      default = "nixos-config.git";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.git ];

    systemd.tmpfiles.rules = [
      "d ${cfg.root} 0755 ${storageUser} users -"
    ];

    systemd.services.pino-git-mirror-init = {
      description = "Initialize the Pino bare Git mirror";
      wantedBy = [ "multi-user.target" ];
      before = [ "caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = storageUser;
        Group = "users";
      };
      script = ''
        repository=${lib.escapeShellArg "${cfg.root}/${cfg.repository}"}
        if [ ! -d "$repository" ]; then
          ${pkgs.git}/bin/git init --bare "$repository"
        fi
        ${pkgs.coreutils}/bin/ln -sfn ${postUpdate} "$repository/hooks/post-update"
        ${pkgs.git}/bin/git --git-dir="$repository" update-server-info
      '';
    };

    services.caddy.virtualHosts."git.${config.pino.server.domain}".extraConfig = ''
      root * ${cfg.root}
      file_server browse
    '';
  };
}
