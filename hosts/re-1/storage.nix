{ ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/pino-root";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/PINO_BOOT";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  fileSystems."/data/fast" = {
    device = "/dev/disk/by-label/pino-fast";
    fsType = "ext4";
    options = [ "noatime" "nofail" "x-systemd.device-timeout=5s" ];
  };

  fileSystems."/data/slow" = {
    device = "/dev/disk/by-label/pino-slow";
    fsType = "ext4";
    options = [ "noatime" "nofail" "x-systemd.device-timeout=5s" ];
  };

  swapDevices = [ ];
}
