{ ... }:
{
  boot.initrd.luks.devices.cryptroot.device =
    "/dev/disk/by-partlabel/pino-cryptroot";

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/PINO_BOOT";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  swapDevices = [ ];
}
