{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    ### Core System Utilities
    btop               # System monitor
    udiskie           # Auto-mount disks
    tlp               # Power management (if not in power-save.nix)
    bluetuith         # Bluetooth TUI
    polkit            # Privilege elevation
    xdg-utils         # Open URLs/file associations
    wl-clipboard      # Clipboard (wl-copy/wl-paste)
    cliphist          # Clipboard history

    ### Shell & Terminal
    kitty             # Terminal emulator
    zsh               # Shell
    zsh-syntax-highlighting
    zsh-autosuggestions
    fzf               # Fuzzy finder
    direnv            # Environment switcher
    fastfetch         # System info

    ### File Management
    ranger            # File browser
    ueberzugpp        # Image previews in ranger
    unzip             # Archive extraction

    ### Networking
    curl              # HTTP client
    speedtest-cli     # Network speed test
    openssh           # SSH client/server
    openssl           # Cryptography tools

    ### Development (CLI-only)
    git               # Version control
    gcc               # Compiler
    cmake
    gdb               # Debugger
    strace            # System call tracer
    bat               # Better `cat`
    rust-analyzer     # Rust LSP
    python3
    rustc
    cargo

    ### Media (CLI-only)
    ffmpeg            # Video/audio processing
    mpd               # Music server
    ncmpcpp           # Music client (TUI)
  ];
}