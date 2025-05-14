{ config, pkgs, ... }:
{
  # Required: Bootloader (GRUB for BIOS-style QEMU)
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";  # QEMU's default virtio disk
  };

  # Required: Filesystem (assumes single ext4 partition)
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  # Optional: QEMU guest agent (for clipboard/shared folders)
  virtualisation.qemu.guestAgent.enable = true;
}