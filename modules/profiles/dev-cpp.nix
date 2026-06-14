{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gcc
    clang
    cmake
    ninja
    meson
    pkg-config
    gdb
    lldb
    valgrind
    binutils
  ];
}
