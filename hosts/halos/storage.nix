{ ... }:
{
  boot.loader.grub.devices = [ "/dev/vda" ];
  fileSystems."/" = {
    device = "/dev/disk/by-label/pino-root";
    fsType = "ext4";
    options = [ "noatime" ];
  };
  swapDevices = [ ];
}
