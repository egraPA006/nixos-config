{ config, lib, pkgs, ... }:
let
  cfg = config.pino.server.xray;
  domain = if cfg.domain == null then "invalid.local" else cfg.domain;
in {
  imports = [ (import ./proxy-service.nix {
    inherit config lib pkgs;
    name = "xray";
    package = pkgs.xray;
    arguments = "run -config";
    settings = { inherit (cfg) port path; };
  }) ];
  assertions = [
    { assertion = cfg.domain != null; message = "server-xray requires a public domain"; }
    { assertion = cfg.port > 1024 && cfg.port != 8443; message = "Xray requires a non-privileged backend port distinct from Galene"; }
  ];
  services.caddy = {
    enable = true;
    virtualHosts.${domain}.extraConfig = ''
      @pinoXhttp path ${cfg.path} ${cfg.path}/*
      log_skip @pinoXhttp
      handle @pinoXhttp {
        @privateSource remote_ip private_ranges
        respond @privateSource 403
        reverse_proxy 127.0.0.1:${toString cfg.port} {
          flush_interval -1
        }
      }
    '';
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
