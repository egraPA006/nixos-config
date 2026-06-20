{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gcc
    clang-tools
    meson
    ninja
    pkg-config
    gdb
    cmake
  ];
}
