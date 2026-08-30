{ ... }:
{
  boot.loader.grub.devices = [ "/dev/vda" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/pino-root";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  fileSystems."/data" = {
    device = "/dev/disk/by-label/pino-data";
    fsType = "ext4";
    options = [ "noatime" "nofail" ];
  };

  swapDevices = [ ];
}
