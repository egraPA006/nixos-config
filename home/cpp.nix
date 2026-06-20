{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gcc
    clang
    clang-tools
    meson
    ninja
    pkg-config
    gdb
    cmake
  ];
}
