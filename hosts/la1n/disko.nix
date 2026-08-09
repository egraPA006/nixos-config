# Single internal NVMe: EFI, an on-demand encrypted vault, and ext4 system data.
# Verify the device name with lsblk before running scripts/disko.sh.
{ ... }:
{
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        secrets = {
          size = "8G";
          label = "secrets";
          content = {
            type = "luks";
            name = "secrets";
            initrdUnlock = false;
            settings.allowDiscards = true;
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/data/secrets";
              mountOptions = [ "noauto" "noatime" "nodev" "nosuid" "noexec" ];
            };
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [ "-L" "nixos" "-F" ];
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
