{ config, ... }:
{
  imports = [
    ./networking.nix
    ../boot/systemd-boot.nix
  ];

  users.users.${config.pino.user.name}.extraGroups = [ "networkmanager" "audio" "video" ];
}
