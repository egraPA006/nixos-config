{ ... }:
{
  boot.loader = {
    grub.enable = true;
    efi.canTouchEfiVariables = false;
  };
}
