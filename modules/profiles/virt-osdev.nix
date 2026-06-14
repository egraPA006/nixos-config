# Full QEMU with cross-arch support (aarch64, riscv64, etc.)
# Extends virt-general — enable both if you want virt-manager too.
{ pkgs, ... }:
{
  imports = [ ./virt-general.nix ];

  virtualisation.libvirtd.qemu.package = pkgs.qemu;

  environment.systemPackages = with pkgs; [
    qemu
  ];
}
