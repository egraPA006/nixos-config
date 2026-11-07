{ config, lib, pkgs, ... }:
let cfg = config.pino.server.telemt;
in {
  imports = [ (import ./proxy-service.nix {
    inherit config lib pkgs;
    name = "telemt";
    package = pkgs.telemt;
    arguments = "";
    settings = { inherit (cfg) port tlsDomain; };
  }) ];
  assertions = [{
    assertion = cfg.port > 1024 && !builtins.elem cfg.port
      [ 8443 config.pino.server.xray.port config.pino.server.galene.turnPort ];
    message = "telemt requires its own non-privileged TCP port";
  }];
  networking.firewall.allowedTCPPorts = [ cfg.port ];
}
