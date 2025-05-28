{ pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode.fhsWithPackages (ps: with ps; [
      # Additional packages to include in the FHS environment
      zlib
    ]);
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        # Core functionality
        vscodevim.vim
        eamodio.gitlens
        editorconfig.editorconfig

        # C/C++
        ms-vscode.cpptools
        ms-vscode.cmake-tools
        twxs.cmake

        # Rust
        rust-lang.rust-analyzer
        tamasfe.even-better-toml
        # serayuzgur.crates

        # Python
        ms-python.python
        ms-python.vscode-pylance
        ms-toolsai.jupyter
        ms-toolsai.jupyter-keymap
        ms-toolsai.jupyter-renderers

        # Nix
        jnoortheen.nix-ide
        arrterian.nix-env-selector
        bbenoist.nix

        # Other useful extensions
        usernamehw.errorlens
        # mkhl.direnv
        yzhang.markdown-all-in-one
        gruntfuggly.todo-tree
      ];

      userSettings = {
        # Core settings
        "editor.fontSize" = 14;
        "editor.fontFamily" = "'FiraCode Nerd Font', 'Droid Sans Mono', 'monospace', monospace";
        "editor.tabSize" = 2;
        "editor.renderWhitespace" = "selection";
        "files.autoSave" = "afterDelay";
        "workbench.colorTheme" = "Default Dark Modern";

        # Language specific settings
        "[nix]".editor.tabSize = 2;
        "[python]".editor.tabSize = 4;
        "python.linting.enabled" = true;
        "python.linting.pylintEnabled" = true;
        "python.formatting.provider" = "black";
        "python.analysis.typeCheckingMode" = "basic";

        # Rust settings
        "rust-analyzer.checkOnSave.command" = "clippy";
        "rust-analyzer.lens.enable" = false;
        "rust-analyzer.updates.askBeforeDownload" = false;

        # C/C++ settings
        "C_Cpp.default.cppStandard" = "c++20";
        "C_Cpp.default.cStandard" = "c17";
        "cmake.configureOnOpen" = true;

        # Nix settings
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nil";
        "nix.serverSettings".nil.formatting.command = [ "nixpkgs-fmt" ];

        # Jupyter settings
        "jupyter.askForKernelRestart" = false;
        "jupyter.alwaysTrustNotebooks" = true;
      };

      keybindings = [
        {
          key = "ctrl+shift+r";
          command = "workbench.action.terminal.runRecentCommand";
          when = "terminalFocus";
        }
        {
          key = "ctrl+shift+e";
          command = "workbench.view.explorer";
        }
      ];
    };
  };

  home.packages = with pkgs; [
    # Language servers and tools
    nil
    nixpkgs-fmt
    rust-analyzer
    python311Packages.python-lsp-server
    cmake-language-server
    ccls
    clang-tools
    jupyter
  ];
  programs.git.extraConfig.core.editor = "code";
}