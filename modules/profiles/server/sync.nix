{ activeProfiles, config, lib, pkgs, ... }:

let
  cfg = config.pino.server.sync;
  gitRepository = "${config.pino.server.gitMirror.root}/${config.pino.server.gitMirror.repository}";
  deviceNames = builtins.attrNames cfg.devices;
  syncthingDevices = lib.mapAttrs (_: device: removeAttrs device [ "secretScopes" ]) cfg.devices;
  folderId = scope: "pino-secret-${lib.replaceStrings [ "/" ] [ "-" ] scope}";
  scopeDevices = scope: builtins.attrNames (lib.filterAttrs
    (_: device: device.secretScopes == null || builtins.elem scope device.secretScopes)
    cfg.devices);
  secretFolders = lib.listToAttrs (map (scope: {
    name = folderId scope;
    value = {
      label = "Pino encrypted ${scope}";
      path = "${cfg.encryptedRoot}/${scope}";
      devices = scopeDevices scope;
      versioning = {
        type = "simple";
        params.keep = "2";
      };
    };
  }) cfg.secretScopes);
in
{
  services.syncthing = {
    enable = true;
    user = "syncthing";
    group = "syncthing";
    dataDir = "/var/lib/syncthing";
    configDir = "/var/lib/syncthing/config";
    guiAddress = "127.0.0.1:8384";
    openDefaultPorts = false;
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      devices = syncthingDevices;
      folders = {
        keepass = {
          label = "KeePass identity database";
          path = cfg.folder;
          devices = deviceNames;
          versioning = {
            type = "simple";
            params.keep = "2";
          };
        };
        share = {
          label = "Pino temporary encrypted share";
          path = "/var/lib/syncthing/share";
          devices = deviceNames;
        };
      } // secretFolders;
      options = {
        listenAddresses = [ "tcp://0.0.0.0:22000" ];
        localAnnounceEnabled = false;
        globalAnnounceEnabled = false;
        relaysEnabled = false;
        natEnabled = false;
        urAccepted = -1;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${cfg.folder} 0700 syncthing syncthing -"
    "d /var/lib/syncthing/share 0700 syncthing syncthing -"
    "d ${cfg.encryptedRoot} 0700 syncthing syncthing -"
  ] ++ map (scope: "d ${cfg.encryptedRoot}/${scope} 0700 syncthing syncthing -") cfg.secretScopes;

  assertions = [
    {
      assertion = builtins.elem "server-vpn" activeProfiles;
      message = "server-sync requires server-vpn";
    }
    {
      assertion = deviceNames != [ ];
      message = "server-sync requires at least one pino.server.sync.devices entry";
    }
    {
      assertion = lib.all (scope:
        builtins.match "[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*" scope != null
        && !(lib.hasInfix ".." scope)) cfg.secretScopes;
      message = "pino.server.sync.secretScopes contains an unsafe relative path";
    }
    {
      assertion = lib.all (device: device.secretScopes == null
        || lib.all (scope: builtins.elem scope cfg.secretScopes) device.secretScopes)
        (lib.attrValues cfg.devices);
      message = "A sync device references an unknown secret scope";
    }
  ];

  pino.subcommands.server.commands.sync = {
    description = "Inspect encrypted data and configuration mirrors";
    commands = {
      status.description = "Show Syncthing service status";
      id.description = "Print the server Syncthing device ID";
      files.description = "Summarize synchronized encrypted data";
      config.description = "Show the mirrored NixOS configuration refs";
      logs.description = "Show recent synchronization logs";
    };
    helpText = ''
      KeePass databases and Cryptomator ciphertext synchronize automatically.
      Vault passwords and plaintext never reach this server. NixOS configuration
      uses the separate bare Git mirror and is updated explicitly by `pino repo
      sync` on a trusted client, preserving commits and preventing file races.
    '';
    script = ''
      case "''${1:-}" in
        status)
          systemctl status syncthing --no-pager
          echo
          systemctl status pino-git-mirror-init --no-pager
          ;;
        id)
          sudo -u syncthing ${pkgs.syncthing}/bin/syncthing \
            cli --home=/var/lib/syncthing/config show system | jq -r .myID
          ;;
        files)
          sudo -u syncthing ${pkgs.coreutils}/bin/du -sh \
            ${lib.escapeShellArg cfg.folder} \
            ${lib.escapeShellArg cfg.encryptedRoot} \
            /var/lib/syncthing/share
          ;;
        config)
          [ -d ${lib.escapeShellArg gitRepository} ] || {
            echo "Git mirror is not initialized: ${gitRepository}" >&2
            exit 1
          }
          ${pkgs.git}/bin/git --git-dir=${lib.escapeShellArg gitRepository} \
            for-each-ref --format='%(refname:short) %(objectname:short) %(committerdate:iso8601)' \
            refs/heads refs/tags
          ;;
        logs) journalctl -u syncthing -n 100 --no-pager ;;
        *) echo "Run 'pino server sync help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
}
