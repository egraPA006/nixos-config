# Shared low-latency audio base: imported by music-lite and music-full.
{ ... }:
{
  services.pipewire.extraConfig.pipewire."10-realtime" = {
    "context.properties" = {
      "default.clock.rate"        = 48000;
      "default.clock.quantum"     = 64;
      "default.clock.min-quantum" = 32;
    };
  };

  security.pam.loginLimits = [
    { domain = "@audio"; item = "rtprio";  type = "-"; value = "99"; }
    { domain = "@audio"; item = "memlock"; type = "-"; value = "unlimited"; }
  ];

  users.users.egrapa.extraGroups = [ "audio" ];
}
