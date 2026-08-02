{ ... }:
{
  imports = [
    ./networking.nix
    ../boot/systemd-boot.nix
  ];

  users.users.egrapa.extraGroups = [ "networkmanager" "audio" "video" ];
}
