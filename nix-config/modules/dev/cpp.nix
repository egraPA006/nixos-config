{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gcc
    g++
    cmake
    gdb
  ];
}