{ ... }:
{
  services.power-profiles-daemon.enable = true;
  powerManagement.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # i915 modesetting is the default; no videoDrivers override needed

  # Better battery life
  services.thermald.enable = true;
}
