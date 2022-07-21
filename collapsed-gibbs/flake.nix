{
  nixConfig.extra-substituters = "https://nix-community.cachix.org";
  nixConfig.extra-trusted-public-keys = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";

  inputs = {
    cargo2nix.url        = "github:cargo2nix/cargo2nix";
    flake-utils.follows  = "cargo2nix/flake-utils";
    rust-overlay.follows = "cargo2nix/rust-overlay";
    nixpkgs.follows      = "cargo2nix/nixpkgs";

    # flake-utils.url = "github:numtide/flake-utils";
    # #rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    # #rust-overlay.inputs.flake-utils.follows = "flake-utils";
    # #nixpkgs.url = "github:nixos/nixpkgs?ref=release-21.11";
    # #nixpkgs.follows = "github:nixos/nixpkgs?ref=release-21.11";

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
          # rustVersion = "1.60.0";
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
          ];
        };

        # The workspace defines a development shell with all of the dependencies
        # and environment settings necessary for a regular `cargo build`
        workspaceShell = rustPkgs.workspaceShell {
          buildInputs = with pkgs; let
            tensorboard = pkgs.writeScriptBin "tensorboard" ''
              ${python39Packages.tensorboard}/bin/tensorboard $@
            '';
          in [
            watchexec
            cargo
            cargo-watch
            rustfmt
            nixpkgs-fmt
            lldb

            # required for influxdb dependency
            openssl.dev
            pkg-config

            # tensorboard tooling
            tensorboard
            (pkgs.writeScriptBin "serve" ''
              rootdir=$(git rev-parse --show-toplevel)
              logdir=''${rootdir}/logs
              clear=0
              while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
                -l | --logdir )
                  shift; logdir=$1
                  ;;
                -c | --clear )
                  clear=1
                  ;;
              esac; shift; done
              if [[ "$1" == '--' ]]; then shift; fi
              if [[ $clear -eq 1 ]]; then
                echo "deleting all files in ''${logdir}"
                rm -rf ''${logdir}
              else
                logsize=$(${coreutils}/bin/du -bs ''${logdir} 2>/dev/null | cut -f1)
                if [[ "$logsize" -ge 1073741824 ]]; then
                  echo "[WARNING] $logdir over 1GiB"
                fi
              fi
              echo "tensorboard serve --bind_all --logdir ''${logdir}"
              tensorboard serve --bind_all --logdir ''${logdir}
            '')
          ];

          LIBCLANG_PATH = pkgs.lib.makeLibraryPath [ pkgs.llvmPackages.libclang.lib ];
          RUST_SRC_PATH = workspaceShell.RUST_SRC_PATH;
          RUSTFLAGS = "-Awarnings";
          RUST_BACKTRACE = "1";
        };

      in rec {
        # nix develop
        devShell = workspaceShell;

        packages = {
          collapsed-gibbs = (rustPkgs.workspace.collapsed-gibbs {}).bin;
        };
        defaultPackage = packages.collapsed-gibbs;
      }
    );
}
