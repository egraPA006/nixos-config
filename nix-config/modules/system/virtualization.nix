{ config, pkgs, lib, ... }:
let
  # CPU Detection Logic
  cpuInfo = builtins.readFile "/proc/cpuinfo";
  isIntel = lib.hasInfix "GenuineIntel" cpuInfo;
  isAMD = lib.hasInfix "AuthenticAMD" cpuInfo;
in
{
  virtualisation = {
    # Docker Configuration
    docker = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
      daemon.settings = {
        iptables = true;
        experimental = false;
      };
    };

    # QEMU/KVM Configuration
    qemu = {
      package = pkgs.qemu_kvm;
    };
  };

  # Automatic KVM Module Loading
  boot.kernelModules = 
    if isIntel then [ "kvm-intel" ]
    else if isAMD then [ "kvm-amd" ]
    else [];

  # Essential Packages
  environment.systemPackages = with pkgs; [
    docker-compose
    qemu
    virt-viewer  # Lightweight alternative to virt-manager
  ] ++ lib.optionals isAMD [
    rocmPackages.clr  # AMD GPU passthrough support
  ];

  # Performance Tuning
  boot.extraModprobeConfig = lib.optionalString (isIntel || isAMD) ''
    options kvm ignore_msrs=1
    options kvm_intel nested=1
  '';
}