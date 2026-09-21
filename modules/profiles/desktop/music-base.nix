# Shared low-latency audio base: imported by music-lite and music-full.

{ config, ... }:
{
  imports = [ ./audio.nix ];

  services.pipewire.extraConfig.pipewire."10-realtime" = {
    "context.properties" = {
      "default.clock.rate"        = 48000;
      "default.clock.quantum"     = 256;
      "default.clock.min-quantum" = 64;
    };
  };

  security.pam.loginLimits = [
    { domain = "@audio"; item = "rtprio";  type = "-"; value = "99"; }
    { domain = "@audio"; item = "memlock"; type = "-"; value = "unlimited"; }
  ];

  users.users.${config.pino.user.name}.extraGroups = [ "audio" ];
}
