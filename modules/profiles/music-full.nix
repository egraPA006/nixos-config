# Full music production: Reaper DAW + yabridge for Windows VST plugins
# Guitar Pro and drum plugins: install via Wine after enabling this profile.
{ pkgs, ... }:
{
  imports = [ ./music-lite.nix ];

  environment.systemPackages = with pkgs; [
    reaper
    yabridge
    yabridgectl
    wineWowPackages.stable
    winetricks
  ];
}
