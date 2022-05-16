{
  inputs = {
    cargo2nix.url = "github:cargo2nix/cargo2nix/master";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.inputs.flake-utils.follows = "flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs?ref=release-21.11";
  };

  outputs = { self, nixpkgs, cargo2nix, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [cargo2nix.overlay rust-overlay.overlay];
        };

        rustPkgs = pkgs.rustBuilder.makePackageSet {
	        rustChannel = "nightly";

          packageFun = import ./Cargo.nix;
        };
	
        # The workspace defines a development shell with all of the dependencies
        # and environment settings necessary for a regular `cargo build`
        workspaceShell = rustPkgs.workspaceShell {};

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
