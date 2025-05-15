{ config, pkgs, lib, ... }:
{
  # Enable TLP (advanced power management)
  services.tlp = {
    enable = true;
    settings = {
      # CPU scaling (Intel/AMD)
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      
      # PCIe power savings
      PCIE_ASPM_ON_AC = "performance";
      PCIE_ASPM_ON_BAT = "powersupersave";
      
      # Disk power management
      DISK_DEVICES = "nvme0n1 sda";  # Replace with your disks
      DISK_APM_LEVEL_ON_AC = "254";  # Max performance
      DISK_APM_LEVEL_ON_BAT = "128";  # Balanced power saving
      SATA_LINKPWR_ON_BAT = "med_power_with_dipm";
      
      # WiFi power saving
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";
      
      # Runtime power management
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";
    };
  };

  # Additional kernel tweaks
  boot.kernelParams = [
    # Intel CPU-specific
    "intel_pstate=passive"  # Better battery life for Intel CPUs
    "mem_sleep_default=deep"  # Deeper sleep states
  ];

  # Laptop-specific services
  services.thermald.enable = true;  # Prevent overheating
  services.auto-cpufreq.enable = lib.mkDefault false;  # Disable if using TLP

  # Power-aware scheduling
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  # Suspend/hibernate settings
  powerManagement.powertop.enable = true;  # Auto-tune power savings
  systemd.targets.hibernate.enable = config.services.logind.lidSwitch == "hibernate";

  # Userspace power saving
  environment.systemPackages = with pkgs; [
    powertop       # Diagnose power usage
    cpupower       # CPU frequency control
    acpi           # Battery status
  ];
}