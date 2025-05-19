{ config, pkgs, lib, ... }:

{
  imports = [
    ../modules/apps.nix
    ../modules/sway.nix
    ../modules/system.nix
    ../modules/utillities.nix
    ./hardware-configuration.nix
  ];

  # Basic system configuration
  boot.loader.grub = {
    enable = true;
    version = 2;
    device = "/dev/vda"; # QEMU virtual disk
  };

  # # QEMU-specific hardware settings
  # boot.initrd.availableKernelModules = [
  #   "ahci"
  #   "sd_mod"
  #   "sr_mod"
  #   "virtio_pci"
  #   "virtio_blk"
  #   "virtio_net"
  #   "virtio_scsi"
  # ];

  # # Use virtio drivers for better performance
  # boot.kernelModules = [ "virtio" "virtio_pci" "virtio_blk" "virtio_net" ];

  # # Filesystem configuration
  # fileSystems."/" = {
  #   device = "/dev/vda1";
  #   fsType = "ext4";
  # };

  # Enable QEMU guest agent
  services.virtualbox.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "23.11"; # Make sure to set this to your actual NixOS version
}