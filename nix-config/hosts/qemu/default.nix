{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    # Core system modules
    ../../modules/core/hardware.nix
    ../../modules/core/network.nix
    ../../modules/core/utilities.nix
    
    # Hardware configuration (QEMU-specific)
    ./hardware.nix
    
    # Development tools
    ../../modules/dev
    
    # Apps (if any are needed for the VM)
    ../../modules/apps
  ];

  # Enable flakes support in the VM
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Security
  security.sudo.wheelNeedsPassword = false;  # Convenience for VM testing
}