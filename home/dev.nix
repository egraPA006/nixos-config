{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # C/C++ toolchain
    gcc
    cmake
    make

    # Rust toolchain (use rustup from shell instead if you prefer)
    rustc
    cargo
    rust-analyzer
    rustfmt
    clippy

    # Python toolchain
    python3
  ];

  # Minimal language-specific configurations
  home.file.".config/nix/nix.conf".text = ''
    experimental-features = nix-command flakes
  '';

  # Rust environment variables
  home.sessionVariables = {
    RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";
  };
}