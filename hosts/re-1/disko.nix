# Disk layout for re-1:
#   nvme0n1 → system (EFI + btrfs root)
#   nvme1n1 → /data/fast (games, music, projects)
#   sda     → /data/slow (games overflow)
{ ... }:
{
  disko.devices.disk = {
    system = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-NE-256_2280_0028111040168";
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
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "nixos"
                "-f"
              ];
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@snapshots" = {
                  mountpoint = "/.snapshots";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@home_snapshots" = {
                  mountpoint = "/home/.snapshots";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };

    fast = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-Netac_NVMe_SSD_512GB_AA20241129512G455837";

      content = {
        type = "gpt";

        partitions = {
          secrets = {
            size = "8G";
            label = "secrets";

            content = {
              type = "luks";
              name = "secrets";
              initrdUnlock = false;

              settings = {
                allowDiscards = true;
              };

              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/data/secrets";

                mountOptions = [
                  "noauto"
                  "noatime"
                  "nodev"
                  "nosuid"
                  "noexec"
                ];
              };
            };
          };

          data = {
            size = "100%";

            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "fast"
                "-f"
              ];

              subvolumes = {
                "@fast" = {
                  mountpoint = "/data/fast";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };

                "@fast_snapshots" = {
                  mountpoint = "/data/fast/.snapshots";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };

    slow = {
      type = "disk";
      device = "/dev/disk/by-id/ata-Apacer_AS350_512GB_50F20752164B00077066";
      content = {
        type = "gpt";
        partitions.data = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [
              "-L"
              "slow"
              "-f"
            ];
            subvolumes = {
              "@slow" = {
                mountpoint = "/data/slow";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
              "@slow_snapshots" = {
                mountpoint = "/data/slow/.snapshots";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
            };
          };
        };
      };
    };
  };
}
