# FPGA/JTAG via Distrobox container to avoid FHS issues with Quartus etc.
{ pkgs, ... }:
{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  environment.systemPackages = with pkgs; [
    distrobox
    podman-compose
  ];
}
