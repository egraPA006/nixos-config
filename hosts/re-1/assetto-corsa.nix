{ lib, activeProfiles, ... }:
{
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
      } {
        # Free release: https://www.patreon.com/posts/162054947
        source = "/data/fast/assetto-corsa/installs/nijusei-touge-1.0.zip";
        sha256 = "283171ec3846de914b448654327433d2be9a692a3711fc0c1468a90310e05603";
        destination = "content/tracks";
      } {
        # Free VOSAN release with TreeFX; original 7z and source record retained.
        # https://vosan.co/tracks/gsot
        source = "/data/fast/assetto-corsa/installs/great-state-of-touge-1.06.zip";
        sha256 = "7e5c7ab233d0f7ae6ec6a22587af18aa5cd2e7f32fbb95b366c18159d713c9d9";
        destination = "content/tracks";
      } {
        # Arch physics 2026-10-29_A, Girellu commit 1fea64cb98b5686f28859f8a7c2464f3f354595b.
        # Local package uses owned Kunos donor assets; originals remain untouched.
        source = "/data/fast/assetto-corsa/installs/arch-road-selection.zip";
        sha256 = "0ee57120a56d047cb8b1fd9484c0ec1fafe871f342c32d831b776d5cfa2c9b20";
        destination = "content/cars";
      } {
        # 101creative public release: https://www.patreon.com/posts/145941062
        source = "/data/fast/assetto-corsa/installs/audi-tts-2009.zip";
        sha256 = "97d1d82f2fc2f8492bb69f4496526f76cd3a985913545df560344121f12150f6";
        destination = "content/cars";
      } {
        # Official stable release, repacked from 7z without changing content.
        # https://shutokorevivalproject.com/
        source = "/data/fast/assetto-corsa/installs/srp-0.9.3.zip";
        sha256 = "57b65abaad721b8134ff0d4e29a417fdc54afe83c1efe21a0616b5c9c9d31705";
      } {
        # Local Pure LCS driving filter override: no sensor noise or amplified glare.
        source = "/data/fast/assetto-corsa/installs/pino-pure-candy-stable.zip";
        sha256 = "75b35efc27c2ff6dd1dc7bee4668c295db015dd8d493caea07f357026bab33da";
      } {
        # Ciba1991 public release, downloaded from OverTake by the user.
        source = "/data/fast/assetto-corsa/installs/c13-aegis-3.0-directors-cut.zip";
        sha256 = "fa32f02c95b0f4251fc25d12119de63634f507d04e1f07da2b8c427100cb0a1d";
      } {
        # Preserve SRP's stronger cast lighting; bloom and car lights stay unchanged.
        source = "/data/fast/assetto-corsa/installs/srp-night-lighting.zip";
        sha256 = "c8331654fcb300e0a6015bdcaf14bb5580e34c36046918c710a450ca9b2bea22";
      } ];
      # Samsung NU7100: UHD Color enabled, 3840x2160 at 60 Hz over HDMI.
      # DLSS Performance K with lighter reflections for wet SRP scenes.
      videoSettings = {
        VIDEO = {
          WIDTH = "3840"; HEIGHT = "2160"; FULLSCREEN = "0";
          AASAMPLES = "1"; ANISOTROPIC = "16"; SHADOW_MAP_SIZE = "2048";
          VSYNC = "1"; FPS_CAP_MS = "16.666667";
          # Let CSP rebuild its placement cache from CM's Show on screen setting.
          _EXT_PLACEMENT = "";
        };
        ASSETTOCORSA.WORLD_DETAIL = "5";
        CUBEMAP = { SIZE = "512"; FACES_PER_FRAME = "1"; FARPLANE = "1000"; };
        MIRROR = { SIZE = "512"; HQ = "1"; };
        EFFECTS = { MOTION_BLUR = "0"; FXAA = "0"; SMOKE = "3"; RENDER_SMOKE_IN_MIRROR = "0"; };
        POST_PROCESS = {
          FILTER = "C13AEGIS 3.0 Directors Cut"; ENABLED = "1"; QUALITY = "4";
          GLARE = "3"; DOF = "0"; FXAA = "0"; HEAT_SHIMMER = "0";
          RAYS_OF_GOD = "1";
        };
      };
      # Drive sessions are selected manually in Content Manager.
      extendedPhysicsCars = [
        "alfa_romeo_giulietta_qv_le" "bmw_z4" "ks_alfa_romeo_4c"
        "ks_porsche_macan" "ks_bmw_m235i_racing"
      ];
      roadTyreCompounds = {
        # Kunos defaults these two cars to semislicks; train on their road tyres.
        bmw_z4 = 0;
        ks_alfa_romeo_4c = 1;
      };
      settings = {
        # XWayland uses 2x coordinates with the TV at 200% in the dual profile.
        # CM's native Show on screen setting; DP-3 remains the primary display.
        "extension/window_position.ini".AC_WINDOW_POSITION = {
          REAL_X = "5120"; REAL_Y = "468";
          X = "5128"; Y = "499";
        };
        "assists.ini".ASSISTS = {
          AUTO_CLUTCH = "1";
          AUTO_BLIP = "1";
          AUTO_SHIFTER = "0";
          TRACTION_CONTROL = "1";
          ABS = "1";
          STABILITY_CONTROL = "0";
        };
        "controls.ini" = {
          SHIFTER.ACTIVE = "0";
          # Stock MOZA ES, zero-based DirectInput buttons. Keep FL and CAM as configured.
          __EXT_WIPERS_MORE = { JOY = "0"; BUTTON = "19"; }; # WIP
          __EXT_WIPERS_LESS = { JOY = "0"; BUTTON = "18"; }; # N
          __EXT_LOW_BEAM = { JOY = "0"; BUTTON = "2"; HOLD_MODE = "0"; }; # X
          ACTION_HEADLIGHTS_FLASH = { JOY = "0"; BUTTON = "3"; }; # Y
          ACTION_HORN = { JOY = "0"; BUTTON = "0"; }; # A
          HANDBRAKE = { JOY = "0"; BUTTON = "1"; }; # B
          __EXT_TURNSIGNAL_LEFT = { JOY = "0"; BUTTON = "23"; HOLD_MODE = "0"; }; # S1
          __EXT_TURNSIGNAL_RIGHT = { JOY = "0"; BUTTON = "36"; HOLD_MODE = "0"; }; # S2
          __EXT_HAZARDS = { JOY = "0"; BUTTON = "22"; HOLD_MODE = "0"; }; # RADIO
        };
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
        "extension/graphics_adjustments.ini" = {
          RENDER_SCALE = { SCALE = "1"; FOLLOW_DESKTOP_SCALE = "0"; };
          FSR = {
            ACTIVE = "1"; OLD_IMPLEMENTATION = "3";
            QUALITY_DLSS = "0.5"; DLSS_PRESET = "11";
            # Bias mask caused distant windows and lamps to shimmer on SRP.
            DLSS_BIAS_MASK = "0";
            SHARPEN_DLSS = "0"; CAS_SHARPEN = "0";
            ADJUST_GLARE = "1"; FOVEATED = "0";
          };
          # Negative texture bias makes distant roads and markings shimmer.
          TWEAKS.TILT_MIP_BIAS = "0";
        };
        "extension/dxgi_tweaks.ini" = {
          BASIC.ALLOW_VRR = "0";
          # Keep the declared resolution instead of persisting Wine window resizes.
          BASIC.SAVE_WINDOW = "0";
          WINDOW_TWEAKS.BORDERLESS_WINDOWED = "2";
        };
        "extension/lighting_fx.ini".SHADOWS = {
          ENABLED = "1"; FULL_RESOLUTION = "0";
          CARS_SHADOWS = "2"; HIGH_QUALITY_HEADLIGHT_SHADOWS = "0";
        };
        "extension/smart_shadows.ini" = {
          BASIC.ENABLED = "1";
          SMOOTH_CASCADES.ENABLED = "1";
        };
        "extension/track_adjustments.ini".MISCELLANEOUS = {
          TREES_RECEIVE_SHADOWS = "1";
          TREES_A2C_DITHERING = "0";
        };
        "extension/extra_fx.ini" = {
          BASIC.ENABLED = "1";
          MOTION_BLUR.ENABLED = "0";
          TAA.ENABLED = "0";
          SSLR = { ENABLED = "1"; TRACING_QUALITY3 = "3"; STEPS_SIMPLE = "24"; SCALE = "0.5"; EXTRA_SPECULARS = "1"; };
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
