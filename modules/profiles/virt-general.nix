{ pkgs, lib, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = lib.mkDefault pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
      ovmf.enable = true;
    };
  };

  programs.virt-manager.enable = true;

  users.users.egrapa.extraGroups = [ "libvirtd" ];
}
