{ lib, ... }:
{
  options.pino.vault = {
    sync = {
      serverName = lib.mkOption {
        type = lib.types.str;
        default = "mosk";
        description = "Syncthing device name of the KeePass synchronization server";
      };
      serverId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Syncthing device ID of the KeePass synchronization server";
      };
      serverAddress = lib.mkOption {
        type = lib.types.str;
        default = "tcp://10.77.0.1:22000";
        description = "Direct Syncthing address reachable through the private VPN";
      };
      mirrors = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            id = lib.mkOption {
              type = lib.types.str;
              description = "Public Syncthing device ID of the storage mirror";
            };
            address = lib.mkOption {
              type = lib.types.str;
              description = "Direct Syncthing address, normally reachable through VPN";
            };
          };
        });
        description = "Additional Syncthing mirrors for identity and Cryptomator ciphertext";
      };
    };
  };
}
