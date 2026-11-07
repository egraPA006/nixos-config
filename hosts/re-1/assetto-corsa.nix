{ lib, activeProfiles, ... }:
let
  assists = tc: builtins.toJSON {
    AutoClutch = true;
    AutoBlip = true;
    AutoShifter = false;
    StabilityControl = 0;
    TractionControl = tc; # 1 = factory; 0 only for explicit car-control exercises
    Abs = 1;
    SlipSteam = 1;
    FuelConsumption = 0;
    TyreWear = 0;
    Damage = 0;
  };
  practice = car: track: {
    Mode = "/Pages/Drive/QuickDrive_Practice.xaml";
    CarId = car;
    TrackId = track;
    WeatherId = "4_mid_clear";
    RealConditions = false;
    asc = true;
    AssistsData = assists 1;
    tpc = true;
    TrackPropertiesData = builtins.toJSON {
      s = 0.98; t = 1; r = 0; g = 0; w = false;
      d = "Repeatable 98% base grip; CSP handles rain separately";
    };
    Temperature = 23;
    Time = 57600; # 16:00
    TimeMultipler = 1; # CM's serialized field spelling
    wsf = 2; wst = 2; wd = 30;
  };
  wet = preset: preset // {
    WeatherId = "sol_34_light_rain";
    Temperature = 18;
  };
  control = (practice "bmw_z4" "acs_nola_v1.5") // { AssistsData = assists 0; };
  roadCars = {
    "Giulietta TCT - FWD" = "alfa_romeo_giulietta_qv_le";
    "Z4 DCT - RWD" = "bmw_z4";
    "4C TCT - mid-engine RWD" = "ks_alfa_romeo_4c";
    "Macan PDK - AWD SUV" = "ks_porsche_macan";
  };
in {
  # Keep paid archives outside the repository and Nix store, just like music installers.
  config = lib.optionalAttrs (builtins.elem "assetto-corsa" activeProfiles) {
    pino.profiles.assettoCorsa = {
      stateDir = "/data/fast/assetto-corsa";
      csp = {
        source = "/data/fast/assetto-corsa/installs/lights-patch-v0.3.2-preview2-full.zip";
        sha256 = "1a9884c0c2a72e545a4c85c022b9e826ac0ca18d8f19bf5aa79874a8bbfd0af4";
      };
      mods = [ {
        source = "/data/fast/assetto-corsa/installs/Pure 3.59 Highres.zip";
        sha256 = "0fa5cee01e13f566d38a16eac6c03b61c3a0ffa8602d0265cbcde35fbe2fe784";
        stripPrefix = "Pure 3.59";
      } {
        # Hakone's required additional emissive shaders, supplied by CSP authors.
        source = "https://github.com/ac-custom-shaders-patch/sdk-shaders/releases/download/v5.0/ac-new.zip";
        sha256 = "029ea85ec006a5fafd7df60bd1457ace276c3bcf0b2936913ec89d26c9d747c2";
        stripPrefix = "MODS/CSP Original AC Patch";
      } {
        source = "/data/fast/assetto-corsa/installs/hakone-v3.zip";
        sha256 = "3f0fee780a3457be1510fdf05f8fc4db3b02c26a474d195426e3326fd43b4573";
        stripPrefix = "90SGDSP_Hakone_Ohiradai_v3/assettocorsa";
      } {
        # Public SMP Esports release; only the unrelated root README was omitted.
        source = "/data/fast/assetto-corsa/installs/moscow-raceway-smp-1.0.5.zip";
        sha256 = "93dd48a808bc375b67e0bc9c6eb87afc910b738b610d09997db29804940522b9";
      } {
        # Public ACS/Geronimo skidpad; original 7z and provenance retained.
        source = "/data/fast/assetto-corsa/installs/acs-nola-skidpad-1.5.zip";
        sha256 = "4243eb36727ac97f3b072cf89ca4320d1382f463d91595b22c828bc0f3494304";
        destination = "content/tracks";
      } ];
      videoSettings.POST_PROCESS.FILTER = "pureLinear";
      # Keep the old preset filename usable, without the rejected drift build.
      quickDrivePreset = control;
      extendedPhysicsCars = builtins.attrValues roadCars ++ [ "ks_bmw_m235i_racing" ];
      roadTyreCompounds = {
        # Kunos defaults these two cars to semislicks; train on their road tyres.
        bmw_z4 = 0;
        ks_alfa_romeo_4c = 1;
      };
      quickDrivePresets = (lib.mapAttrs' (name: car:
        lib.nameValuePair "Pino/02 Moscow Raceway/${name}" (practice car "moscow_raceway/layout_race")
      ) roadCars) // {
        "Pino/01 Car control/Z4 - dry - TC off" = control;
        "Pino/01 Car control/Z4 - light rain - TC off" = wet control;
        "Pino/01 Car control/Giulietta - dry" = practice "alfa_romeo_giulietta_qv_le" "acs_nola_v1.5";
        "Pino/01 Car control/Macan - dry" = practice "ks_porsche_macan" "acs_nola_v1.5";
        "Pino/02 Moscow Raceway/Giulietta - light rain" = wet (practice "alfa_romeo_giulietta_qv_le" "moscow_raceway/layout_race");
        "Pino/03 Learn a circuit/Giulietta - Magione" = practice "alfa_romeo_giulietta_qv_le" "magione";
        "Pino/03 Learn a circuit/M235i Racing - Imola" = practice "ks_bmw_m235i_racing" "imola";
        "Pino/04 Roads/Z4 - Highlands Long" = practice "bmw_z4" "ks_highlands/layout_long";
        "Pino/04 Roads/4C - Trento Bondone" = practice "ks_alfa_romeo_4c" "trento-bondone";
        "Pino/04 Roads/Giulietta - Highlands Short town" = practice "alfa_romeo_giulietta_qv_le" "ks_highlands/layout_short";
      };
      settings = {
        "assists.ini".ASSISTS = {
          AUTO_CLUTCH = "1";
          AUTO_BLIP = "1";
          AUTO_SHIFTER = "0";
          TRACTION_CONTROL = "1";
          ABS = "1";
          STABILITY_CONTROL = "0";
        };
        "controls.ini".SHIFTER.ACTIVE = "0";
        "extension/neck.ini" = {
          BASIC.ENABLED = "1";
          SCRIPT.ENABLED = "0";
          LOOKAHEAD.GAIN = "0.25";
          ALIGNMENT_BASE = {
            ALIGN_WITH_VELOCITY = "0.5";
            ALIGN_WITH_STEERING = "0.05";
            HORIZON_LOCK = "0.5";
            G_TILT_X = "0.1";
            G_TILT_Z = "0.2";
          };
        };
        "extension/rain_fx.ini".BASIC = {
          ENABLED = "1";
          AUTOSELECT_RAIN_TYRES = "0"; # Keep road tyres for dry/wet comparisons.
        };
        "extension/grass_fx.ini".BASIC = { ENABLED = "1"; QUALITY = "2"; };
        "extension/particles_fx.ini" = { BASIC.ENABLED = "1"; SMOKE.ENABLED = "1"; };
        "extension/extra_fx.ini" = {
          BASIC.ENABLED = "1";
          MOTION_BLUR.ENABLED = "0";
          TAA.ENABLED = "0";
          SSLR = { ENABLED = "1"; TRACING_QUALITY3 = "3"; STEPS_SIMPLE = "24"; SCALE = "0.5"; };
          ASSAO = { ENABLED = "1"; QUALITY = "1"; };
          HBAO.ENABLED = "0";
          SSAO.ENABLED2 = "0";
        };
      };
      weatherSettings.BASIC = {
        ENABLED = "1";
        IMPLEMENTATION = "Pure LCS";
        CONTROLLER = "pureCtrl static";
      };
    };
  };
}
