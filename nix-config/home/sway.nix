{ config, pkgs, ... }:

{
  # Sway Configuration
  wayland.windowManager.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraSessionCommands = ''
      export SDL_VIDEODRIVER=wayland
      export QT_QPA_PLATFORM=wayland
      export QT_WAYLAND_DISABLE_WINDOWDECORATION="1"
      export _JAVA_AWT_WM_NONREPARENTING=1
      export MOZ_ENABLE_WAYLAND=1
    '';
    
    config = rec {
      # Defaults
      modifier = "Mod4";
      terminal = "kitty";
      menu = "wofi --show drun --prompt 'Launch:'";
      
      # Keybindings
      keybindings = let
        modifier = config.wayland.windowManager.sway.config.modifier;
      in {
        "${modifier}+Return" = "exec ${terminal}";
        "${modifier}+d" = "exec ${menu}";
        "${modifier}+Shift+q" = "kill";
        "${modifier}+h" = "focus left";
        "${modifier}+j" = "focus down";
        "${modifier}+k" = "focus up";
        "${modifier}+l" = "focus right";
        "${modifier}+Left" = "focus left";
        "${modifier}+Down" = "focus down";
        "${modifier}+Up" = "focus up";
        "${modifier}+Right" = "focus right";
        "${modifier}+Shift+h" = "move left";
        "${modifier}+Shift+j" = "move down";
        "${modifier}+Shift+k" = "move up";
        "${modifier}+Shift+l" = "move right";
        "${modifier}+Shift+Left" = "move left";
        "${modifier}+Shift+Down" = "move down";
        "${modifier}+Shift+Up" = "move up";
        "${modifier}+Shift+Right" = "move right";
        
        "${modifier}+1" = "workspace number 1";
        "${modifier}+2" = "workspace number 2";
        "${modifier}+3" = "workspace number 3";
        "${modifier}+4" = "workspace number 4";
        "${modifier}+5" = "workspace number 5";
        "${modifier}+6" = "workspace number 6";
        "${modifier}+7" = "workspace number 7";
        "${modifier}+8" = "workspace number 8";
        "${modifier}+9" = "workspace number 9";
        "${modifier}+0" = "workspace number 10";
        
        "${modifier}+Shift+1" = "move container to workspace number 1";
        "${modifier}+Shift+2" = "move container to workspace number 2";
        "${modifier}+Shift+3" = "move container to workspace number 3";
        "${modifier}+Shift+4" = "move container to workspace number 4";
        "${modifier}+Shift+5" = "move container to workspace number 5";
        "${modifier}+Shift+6" = "move container to workspace number 6";
        "${modifier}+Shift+7" = "move container to workspace number 7";
        "${modifier}+Shift+8" = "move container to workspace number 8";
        "${modifier}+Shift+9" = "move container to workspace number 9";
        "${modifier}+Shift+0" = "move container to workspace number 10";
        
        "${modifier}+b" = "splith";
        "${modifier}+v" = "splitv";
        "${modifier}+f" = "fullscreen toggle";
        "${modifier}+s" = "layout stacking";
        "${modifier}+w" = "layout tabbed";
        "${modifier}+e" = "layout toggle split";
        
        "${modifier}+Shift+space" = "floating toggle";
        "${modifier}+space" = "focus mode_toggle";
        
        "${modifier}+a" = "focus parent";
        
        # Media controls
        "XF86AudioRaiseVolume" = "exec pactl set-sink-volume @DEFAULT_SINK@ +5%";
        "XF86AudioLowerVolume" = "exec pactl set-sink-volume @DEFAULT_SINK@ -5%";
        "XF86AudioMute" = "exec pactl set-sink-mute @DEFAULT_SINK@ toggle";
        "XF86AudioPlay" = "exec playerctl play-pause";
        "XF86AudioNext" = "exec playerctl next";
        "XF86AudioPrev" = "exec playerctl previous";
        
        # Screen brightness
        "XF86MonBrightnessUp" = "exec brightnessctl set +5%";
        "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
        
        # Screenshots
        "Print" = "exec grim -g \"$(slurp)\" - | wl-copy";
        "${modifier}+Print" = "exec grim - | wl-copy";
        
        # Lock screen
        "${modifier}+Escape" = "exec swaylock -f -c 000000";
        
        # Exit Sway
        "${modifier}+Shift+e" = "exec swaynag -t warning -m 'Exit Sway?' -b 'Yes' 'swaymsg exit'";
      };
      
      # Window rules
      window = {
        commands = [
          {
            command = "floating enable";
            criteria = { app_id = "pavucontrol"; };
          }
          {
            command = "floating enable";
            criteria = { title = "File Operation Progress"; };
          }
        ];
      };
      
      # Colors and theming
      colors = {
        focused = {
          border = "#4c7899";
          background = "#285577";
          text = "#ffffff";
          indicator = "#2e9ef4";
          childBorder = "#285577";
        };
        unfocused = {
          border = "#333333";
          background = "#222222";
          text = "#888888";
          indicator = "#292d2e";
          childBorder = "#222222";
        };
      };
      
      # Bar configuration
      bars = [
        {
          position = "bottom";
          statusCommand = "${pkgs.i3status}/bin/i3status";
          colors = {
            background = "#000000";
            statusline = "#ffffff";
            separator = "#666666";
            focusedWorkspace = {
              background = "#0088CC";
              border = "#0088CC";
              text = "#ffffff";
            };
            activeWorkspace = {
              background = "#333333";
              border = "#333333";
              text = "#ffffff";
            };
            inactiveWorkspace = {
              background = "#222222";
              border = "#222222";
              text = "#888888";
            };
          };
        }
      ];
      
      # Input configuration
      input = {
        "*" = {
          xkb_layout = "us";
          xkb_options = "caps:escape";
        };
      };
      
      # Output configuration
      output = {
        "*" = {
          bg = "~/.background fill";
        };
      };
      
      # Startup applications
      startup = [
        { command = "swaybg -i ~/.background"; }
        { command = "mako"; }
        { command = "wl-paste --watch cliphist store"; }
      ];
    };
    
    extraConfig = ''
      # Enable gaps
      gaps inner 5
      gaps outer 5
      
      # Titlebar
      default_border pixel 2
      default_floating_border pixel 2
      
      # Mouse binding
      bindsym --to-code {
        --locked button2 kill
      }
    '';
  };
  
  # Additional packages
  home.packages = with pkgs; [
    # Utilities
    wofi # Application launcher
    cliphist # Clipboard manager
    swaylock # Screen locker
    swayidle # Idle management
    grim # Screenshot tool
    slurp # Region selection
    mako # Notification daemon
    wl-clipboard # Clipboard utilities
    
    # Media control
    playerctl
    pavucontrol
    
    # Theming
    qt5.qtwayland
    libsForQt5.qtstyleplugin-kvantum
  ];
  
  # Enable necessary services
  services.swayidle = {
    enable = true;
    events = [
      { event = "before-sleep"; command = "swaylock -f"; }
      { event = "lock"; command = "swaylock -f"; }
    ];
    timeouts = [
      { timeout = 300; command = "swaylock -f"; }
      { timeout = 600; command = "swaymsg 'output * dpms off'"; resumeCommand = "swaymsg 'output * dpms on'"; }
    ];
  };
  
  # Configure Kitty terminal
  programs.kitty = {
    enable = true;
    settings = {
      scrollback_lines = 10000;
      enable_audio_bell = false;
      update_check_interval = 0;
      background_opacity = "0.9";
    };
  };
  
  # Configure Mako notifications
  services.mako = {
    enable = true;
    backgroundColor = "#1e1e2e";
    borderColor = "#cba6f7";
    borderRadius = 5;
    borderSize = 2;
    textColor = "#cdd6f4";
    extraConfig = ''
      [urgency=high]
      border-color=#f38ba8
    '';
  };
  
  # Configure environment variables
  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    _JAVA_AWT_WM_NONREPARENTING = "1";
  };

  # Configure Wofi
  programs.wofi = {
    enable = true;
    settings = {
      width = 600;
      height = 400;
      location = "center";
      show = "drun";
      prompt = "Launch...";
      filter_rate = 100;
      allow_markup = true;
      no_actions = true;
      halign = "fill";
      orientation = "vertical";
      content_halign = "fill";
      insensitive = true;
      allow_images = true;
      image_size = 24;
      gtk_dark = true;
    };
    style = ''
      * {
        font: "Fira Code 12";
      }
      
      window {
        background-color: #1e1e2e;
        border-radius: 10px;
        border: 2px solid #cba6f7;
      }
      
      #input {
        background-color: #1e1e2e;
        color: #cdd6f4;
        border: none;
        margin: 5px;
      }
      
      #inner-box {
        background-color: #1e1e2e;
        margin: 5px;
      }
      
      #outer-box {
        background-color: #1e1e2e;
        margin: 5px;
      }
      
      #scroll {
        background-color: #1e1e2e;
        margin: 5px;
      }
      
      #text {
        color: #cdd6f4;
        margin: 5px;
      }
      
      #entry:selected {
        background-color: #585b70;
        border-radius: 5px;
      }
    '';
  };

}