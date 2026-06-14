{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    qemu
    nasm
    gdb
    binutils
    grub2
    xorriso
    # Cross-compile toolchains — add per-project via nix-shell or devShell:
    # pkgsCross.aarch64-multiplatform.buildPackages.gcc
    # pkgsCross.riscv64.buildPackages.gcc
  ];
}
