{ ... }:
{
  # Refused by scripts/server-stage.sh until replaced with the explicitly
  # confirmed installation disk.
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/disk/by-id/PINO_SERVER_DISK_NOT_SELECTED";
    content = {
      type = "gpt";
      partitions = {
        BIOS = {
          size = "1M";
          type = "EF02";
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
