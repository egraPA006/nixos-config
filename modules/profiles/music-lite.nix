# Guitar amp sim via NAM (Neural Amp Modeler) + Carla as plugin host
# Requires PipeWire (already in base).
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    neural-amp-modeler-lv2
  ];

  # Low-latency PipeWire config for real-time audio
  services.pipewire.extraConfig.pipewire."10-realtime" = {
    "context.properties" = {
      "default.clock.rate" = 48000;
      "default.clock.quantum" = 64;
      "default.clock.min-quantum" = 32;
    };
  };

  security.pam.loginLimits = [
    { domain = "@audio"; item = "rtprio";   type = "-"; value = "99"; }
    { domain = "@audio"; item = "memlock";  type = "-"; value = "unlimited"; }
  ];

  users.users.egrapa.extraGroups = [ "audio" ];
}
