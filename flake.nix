{
  description = "Pino NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-openrgb.url = "github:NixOS/nixpkgs/148bab9c1c3c53136ecb44a6ea356a0ed5b39b06";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-images.url = "github:nix-community/nixos-images";
  };

  outputs = { self, nixpkgs, nixpkgs-openrgb, home-manager, nixos-images, ... }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    overlays = {
      neural-amp-modeler-lv2-0_2_0 = final: prev: {
        neural-amp-modeler-lv2 = prev.neural-amp-modeler-lv2.overrideAttrs (_: {
          version = "0.2.0";
          src = prev.fetchFromGitHub {
            owner = "mikeoliphant";
            repo  = "neural-amp-modeler-lv2";
            tag   = "v0.2.0";
            fetchSubmodules = true;
            hash  = "sha256-rwh4OGAIw/cLP8Q3kx8mqxUBM2FzLNf9blMgmkwnWpI=";
          };
        });
      };
    };

    mkHost = name: extraModules: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs.activeProfiles = import (./hosts + "/${name}/active-profiles.nix");
      modules = [
        home-manager.nixosModules.home-manager
      ] ++ extraModules ++ [ (./hosts + "/${name}") ];
    };
    re1 = mkHost "re-1" [
      { nixpkgs.overlays = [ overlays.neural-amp-modeler-lv2-0_2_0 ]; }
      { services.hardware.openrgb.package = nixpkgs-openrgb.legacyPackages.x86_64-linux.openrgb; }
    ];
  in {
    packages.x86_64-linux.server-secrets = pkgs.writeShellApplication {
      name = "pino-server-secrets";
      runtimeInputs = [ pkgs.amneziawg-tools pkgs.git pkgs.bitwarden-cli ];
      text = ''
        export PINO_PROXY_SETTINGS=${./resources/mosk-proxies.json}
        export PINO_HALOS_PROXY_SETTINGS=${./resources/halos-proxies.json}
        exec ${pkgs.python3.withPackages (p: [ p.bcrypt ])}/bin/python3 ${./scripts/server-secrets.py} "$@"
      '';
    };
    packages.x86_64-linux.kexec-installer =
      nixos-images.packages.x86_64-linux.kexec-installer-nixos-unstable-noninteractive;
    # The kernel limits kexec segments to half of RAM. Keep an ext4 installer
    # for 1 GiB VPS hosts instead of loading the universal filesystem toolset.
    packages.x86_64-linux.kexec-installer-small =
      (nixos-images.inputs.nixos-unstable.legacyPackages.x86_64-linux.nixos [
        nixos-images.nixosModules.kexec-installer
        nixos-images.nixosModules.noninteractive
        ({ config, lib, pkgs, ... }:
        let
          modules = [
            "virtio_pci" "virtio_net" "virtio_blk" "virtio_scsi"
            "virtio_console" "virtio_balloon" "virtio_gpu"
            "af_packet"
            "ata_piix" "ahci" "sd_mod" "sr_mod"
            "ext4" "vfat" "squashfs" "overlay" "loop" "erofs" "autofs4"
            "nls_cp437" "nls_iso8859-1" "nls_utf8"
            "usbhid" "hid_generic" "atkbd" "psmouse"
            "dm_mod" "xhci_pci" "uhci_hcd" "ehci_pci" "i8042"
          ];
          kernelModules = lib.getOutput "modules" config.boot.kernelPackages.kernel;
          minimalModules = pkgs.makeModulesClosure {
            kernel = kernelModules;
            firmware = pkgs.emptyDirectory;
            rootModules = modules;
            allowMissing = false;
          };
          moduleTree = pkgs.runCommand "halos-installer-modules" { } ''
            cp -a ${minimalModules} "$out"
            for directory in "$out"/lib/modules/*; do
              chmod u+w "$directory"
              version="''${directory##*/}"
              # Stage 1 derives another closure and needs the ordering hints
              # that makeModulesClosure normally removes from its output.
              cp ${kernelModules}/lib/modules/"$version"/modules.{order,builtin,builtin.modinfo} "$directory/"
            done
          '';
        in {
          system.kexec-installer.name = "nixos-kexec-installer-noninteractive";
          system.tools.nixos-rebuild.enable = false;
          # This installer targets the checked QEMU/KVM hardware, not arbitrary
          # machines. A full kernel module tree otherwise dominates its RAM use.
          system.modulesTree = lib.mkForce [ moduleTree ];
          boot.initrd.availableKernelModules = lib.mkForce modules;
          boot.kernelModules = lib.mkForce [ "virtio_pci" "virtio_net" "virtio_blk" ];
          boot.supportedFilesystems = lib.mkForce [ "ext4" "vfat" ];
          boot.initrd.supportedFilesystems = lib.mkForce [ "ext4" "vfat" "squashfs" "overlay" ];
          netboot.squashfsCompression = "xz -Xdict-size 100%";
        })
      ]).config.system.build.kexecInstallerTarball;

    devShells.x86_64-linux.cpp = pkgs.mkShell {
      packages = with pkgs; [
        gcc
        clang
        clang-tools
        meson
        ninja
        pkg-config
        gdb
        cmake
      ];
    };

    nixosConfigurations = {
      re-1 = re1;
      la1n = mkHost "la1n" [
        { nixpkgs.overlays = [ overlays.neural-amp-modeler-lv2-0_2_0 ]; }
      ];
      mosk = mkHost "mosk" [ ];
      halos = mkHost "halos" [ ];
    };

    checks.x86_64-linux = {
      re-1 = re1.config.system.build.toplevel;
      la1n = self.nixosConfigurations.la1n.config.system.build.toplevel;
      mosk = self.nixosConfigurations.mosk.config.system.build.toplevel;
      halos = self.nixosConfigurations.halos.config.system.build.toplevel;
    };
  };
}
