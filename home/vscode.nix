{ pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;

    extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      ms-vscode.cpptools
      rust-lang.rust-analyzer
      ms-python.python
      ms-python.vscode-pylance
      tamasfe.even-better-toml
      eamodio.gitlens
    ];

    userSettings = {
      "editor.fontSize" = 14;
      "editor.tabSize" = 2;
      "editor.formatOnSave" = true;
      "editor.minimap.enabled" = false;
      "workbench.colorTheme" = "Default Dark+";
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "nil";
    };
  };

  home.packages = with pkgs; [ nil ];
}
