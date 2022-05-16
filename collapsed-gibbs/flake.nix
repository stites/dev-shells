{
  nixConfig.extra-substituters = "https://nix-community.cachix.org";
  nixConfig.extra-trusted-public-keys = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";

  inputs = {
    cargo2nix.url = "github:cargo2nix/cargo2nix/master";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.inputs.flake-utils.follows = "flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs?ref=release-21.11";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    devshell.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, cargo2nix, flake-utils, rust-overlay, devshell, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [cargo2nix.overlay rust-overlay.overlay devshell.overlay];
        };

        rustPkgs = pkgs.rustBuilder.makePackageSet {
	        rustChannel = "nightly";

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
            (pkgs.rustBuilder.rustLib.makeOverride {
              name = "minisat";
              overrideAttrs = old: {
                nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.llvmPackages.libclang ];
                LIBCLANG_PATH = pkgs.lib.makeLibraryPath [ pkgs.llvmPackages.libclang.lib ];
              };
            })
          ];
        };

        # The workspace defines a development shell with all of the dependencies
        # and environment settings necessary for a regular `cargo build`
        workspaceShell = rustPkgs.workspaceShell {};

      in rec {
        # nix develop
        devShell = pkgs.devshell.mkShell {
          devshell.packages = workspaceShell.nativeBuildInputs ++ workspaceShell.buildInputs;
          env = [{
            name = "LIBCLANG_PATH";
            value = pkgs.lib.makeLibraryPath [ pkgs.llvmPackages.libclang.lib ];
          } {
            name = "RUST_SRC_PATH";
            value = workspaceShell.RUST_SRC_PATH;
          }];
          commands = [
            {category = "development"; package = pkgs.watchexec;}
            {category = "development"; package = pkgs.cargo-watch;}
            {category = "formatting"; package = pkgs.rustfmt;}
            {category = "formatting"; package = pkgs.nixpkgs-fmt;}
          ];
        };


        packages = {
          collapsed-gibbs = (rustPkgs.workspace.collapsed-gibbs {}).bin;
        };
        defaultPackage = packages.collapsed-gibbs;
      }
    );
}
