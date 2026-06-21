{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gcc
    clang-tools
    meson
    ninja
    pkg-config
    gdb
    cmake
  ];

  home-manager.users.egrapa = {
    programs.vscode.profiles.default.extensions = with pkgs.vscode-extensions; [
      llvm-vs-code-extensions.vscode-clangd
      mesonbuild.mesonbuild
    ];

    programs.vscode.profiles.default.userSettings = {
      "clangd.path" = "${pkgs.clang-tools}/bin/clangd";
      "clangd.arguments" = [ "--header-insertion=never" "--clang-tidy" ];
    };
  };
}
