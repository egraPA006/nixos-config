{ pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    mutableExtensionsDir = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      anthropic.claude-code
      llvm-vs-code-extensions.vscode-clangd
      mesonbuild.mesonbuild
    ];

    profiles.default.userSettings = {
      "editor.fontSize" = 14;
      "editor.tabSize" = 2;
      "editor.formatOnSave" = true;
      "editor.minimap.enabled" = false;
      "workbench.colorTheme" = "Default Dark+";
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "nil";
      "claude-code.executablePath" = "/etc/profiles/per-user/egrapa/bin/claude";
      "clangd.path" = "${pkgs.clang-tools}/bin/clangd";
      "clangd.arguments" = [ "--header-insertion=never" "--clang-tidy" ];
    };
  };

  home.packages = with pkgs; [
    nil
    claude-code
  ];
}
