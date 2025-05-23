## Installation Guide

### VirtualBox:
```bash
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart primary 512MiB 100%
parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
parted /dev/sda -- set 2 esp on
mkfs.ext4 -L nixos /dev/sda1
mkfs.vfat -n boot /dev/sda2
mount /dev/sda1 /mnt
mkdir -p /mnt/boot
mount /dev/sda2 /mnt/boot
```

### Laptop (UEFI + Swap):
```bash
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart primary 512MiB -8GiB
parted /dev/nvme0n1 -- mkpart swap linux-swap -8GiB 100%
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 512MiB
parted /dev/nvme0n1 -- set 3 esp on
mkfs.ext4 -L nixos /dev/nvme0n1p1
mkswap -L swap /dev/nvme0n1p2
mkfs.vfat -n boot /dev/nvme0n1p3
mount /dev/nvme0n1p1 /mnt
swapon /dev/nvme0n1p2
mkdir -p /mnt/boot
mount /dev/nvme0n1p3 /mnt/boot
```

### After Partitioning (Both Cases):
```bash
nixos-generate-config --root /mnt
cd /mnt/etc/nixos
git clone https://github.com/egraPA006/nixos-config.git
nixos-install --flake .#hostname  # Replace with your target (laptop/virtualbox)
reboot
```

Note: Replace `/dev/sda`/`/dev/nvme0n1` with your actual disk device.