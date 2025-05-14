{ config, pkgs, lib, ... }:
let
  # Battery threshold (stop charging at 80% to preserve battery health)
  chargeThreshold = 100;
in
{
  ####################
  ### CPU Power Management
  ####################
  powerManagement = {
    enable = true;
    cpuFreqGovernor = lib.mkDefault "powersave";
    powertop.enable = true;
  };

  services = {
    ####################
    ### Adaptive Power Daemons
    ####################
    tlp = {
      enable = true;
      settings = {
        # Battery settings
        START_CHARGE_THRESH_BAT0 = chargeThreshold;
        STOP_CHARGE_THRESH_BAT0 = chargeThreshold;
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
        PCIE_ASPM_ON_BAT = "powersupersave";

        # AC settings
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
        PCIE_ASPM_ON_AC = "powersave";
      };
    };

    auto-cpufreq = {
      enable = true;
      settings = {
        battery = {
          governor = "powersave";
          turbo = "never";
        };
        charger = {
          governor = "performance";
          turbo = "auto";
        };
      };
    };
  };

  ####################
  ### Hardware Tweaks
  ####################
  hardware = {
    # Enable battery health options
    acpilight.enable = true;

    # SSD power saving
    enableAllFirmware = true;  # For NVMe power states
  };

  ####################
  ### Kernel Parameters
  ####################
  boot.kernelParams = [
    # Power saving
    "mem_sleep_default=deep"
    "pcie_aspm=force"
    
    # Disable wake-on-LAN
    "libata.noacpi=1"
  ];

  ####################
  ### User-Space Tools
  ####################
  environment.systemPackages = with pkgs; [
    powertop          # Power usage monitoring
    cpupower          # CPU frequency control
    acpi              # Battery status
    auto-cpufreq      # Dynamic scaling
  ];

  ####################
  ### Power Alerts
  ####################
  services.upower.enable = true;
  services.batsignal.enable = true;  # Battery level notifications
}