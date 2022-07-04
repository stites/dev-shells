{
  nixConfig.extra-substituters = "https://nix-community.cachix.org";
  nixConfig.extra-trusted-public-keys = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";

  inputs = {
    cargo2nix.url = "github:cargo2nix/cargo2nix/release-0.11.0";

    rust-overlay.follows = "cargo2nix/rust-overlay";
    nixpkgs.follows = "cargo2nix/nixpkgs";
    flake-utils.follows = "cargo2nix/flake-utils";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    devshell.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, cargo2nix, flake-utils, rust-overlay, devshell, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [cargo2nix.overlays.default rust-overlay.overlay devshell.overlay];
        };

        rustPkgs = pkgs.rustBuilder.makePackageSet {
          rustVersion = "1.60.0";

          packageFun = import ./Cargo.nix;

          # Provide the gperfools lib for linking the final rust-analyzer binary
          packageOverrides = pkgs: pkgs.rustBuilder.overrides.all ++ [
            (pkgs.rustBuilder.rustLib.makeOverride {
              name = "rust-analyzer";
              overrideAttrs = drv: {
                propagatedNativeBuildInputs = drv.propagatedNativeBuildInputs or [ ] ++ [
                  pkgs.gperftools
                ];
              };
            })
          ] ++ (let
            mk-sys-package = name: _pkg: pkgs.rustBuilder.rustLib.makeOverride {
              inherit name;
              overrideAttrs = drv: {
                propagatedBuildInputs = drv.propagatedBuildInputs ++ (with pkgs; [
                  cmake pkg-config _pkg
                ]);
                propagatedNativeBuildInputs = (if builtins.hasAttr drv "propagatedNativeBuildInputs" then drv.propagatedNativeBuildInputs else []) ++ (with pkgs; [
                  cmake pkg-config _pkg
                ]);
              };
            };
          in [
            (mk-sys-package "expat-sys" pkgs.expat)
            (mk-sys-package "freetype-sys" pkgs.freetype)
            (mk-sys-package "fontconfig-sys" pkgs.fontconfig)
          ]);
        };

        # The workspace defines a development shell with all of the dependencies
        # and environment settings necessary for a regular `cargo build`
        workspaceShell = rustPkgs.workspaceShell {
          buildInputs = (with pkgs; [
            watchexec
            cargo-watch
            rustfmt
            nixpkgs-fmt
            cargo2nix.packages.${system}.cargo2nix
          ]);
          nativeBuildInputs = (with pkgs; [
            # for plotters / servo-fontconfig-sys. Helps to symlink /etc/profiles/per-user/$USER/bin/file to /usr/bin/file
            cmake pkg-config freetype expat fontconfig
          ]);

          LIBCLANG_PATH = pkgs.lib.makeLibraryPath [ pkgs.llvmPackages.libclang.lib ];
          RUST_SRC_PATH = workspaceShell.RUST_SRC_PATH;
        };

        oldshell = pkgs.devshell.mkShell {
          devshell.packages = workspaceShell.nativeBuildInputs ++ workspaceShell.buildInputs;
          env = [
            {
            name = "LIBCLANG_PATH";
            value = pkgs.lib.makeLibraryPath [ pkgs.llvmPackages.libclang.lib ];
            }
            {
            name = "RUST_SRC_PATH";
            value = workspaceShell.RUST_SRC_PATH;
            }
          ];
          commands = [
            {category = "development"; package = pkgs.watchexec;}
            {category = "development"; package = pkgs.cargo-watch;}
            {category = "formatting"; package = pkgs.rustfmt;}
            {category = "formatting"; package = pkgs.nixpkgs-fmt;}
          ];
        };

      in rec {
        # nix develop is currently the only output
        devShell = workspaceShell;
        packages =  {
          main = (rustPkgs.workspace.monte-carlo-strategies-in-scientific-computing {}).bin;
        };
        defaultPackage = packages.main;
      }
    );
}
