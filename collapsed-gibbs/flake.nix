{
  nixConfig.extra-substituters = "https://nix-community.cachix.org";
  nixConfig.extra-trusted-public-keys = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";

  inputs = {
    cargo2nix.url        = "github:cargo2nix/cargo2nix";
    cargo2nix.inputs.nixpkgs.follows = "nixpkgs";
    cargo2nix.inputs.rust-overlay.follows = "rust-overlay";

    #nixpkgs.url = "github:nixos/nixpkgs?ref=release-22.05";
    nixpkgs.url = "github:nixos/nixpkgs?ref=bc41b01dd7a9fdffd32d9b03806798797532a5fe";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    flake-utils.follows  = "cargo2nix/flake-utils";
    # flake-utils.url = "github:numtide/flake-utils";
    # #rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    # #rust-overlay.inputs.flake-utils.follows = "flake-utils";
    # #nixpkgs.url = "github:nixos/nixpkgs?ref=release-21.11";
    # #nixpkgs.follows = "github:nixos/nixpkgs?ref=release-21.11";
    mach-nix.url = "mach-nix/3.5.0";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    devshell.inputs.flake-utils.follows = "flake-utils";
    mach-nix.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, cargo2nix, flake-utils, rust-overlay, devshell, mach-nix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [cargo2nix.overlays.default rust-overlay.overlays.default devshell.overlay];
        };

        rustPkgs = pkgs.rustBuilder.makePackageSet {
          rustVersion = "1.63.0";
          #rustChannel = "nightly";

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
            rust-bin.stable.latest.default # rust stable
            rust-analyzer                  # IDE for emacs
            rustracer                      # backup IDE for emacs
            rustfmt                        # format rust
            nixpkgs-fmt                    # format nix (maybe not so important)


            # experimental
           #cargo-ui # A GUI for Cargo
            ograc

            # development (#* meas recommended via rust for rustaceans)
            cargo-watch         # A Cargo subcommand for watching over Cargo project's source
            cargo-nextest       # Next-generation test runner for Rust projects
            cargo-limit         # Cargo subcommand "limit": reduces the noise of compiler messages
           #cargo-rr            # Cargo subcommand "rr": a light wrapper around rr, the time-travelling debugger
            cargo-expand     #* # Expands macros in a given crate and lets you inspect the output, which makes it
                                # much easier to spot mistakes deep down in macro transcribers or procedural
                                # macros. cargo-expand is an invaluable tool when you’re writing your own macros.
            cargo-llvm-lines #* # Count the number of lines of LLVM IR across all instantiations of a generic function
                                # Analyzes the mapping from Rust code to the
                                # intermediate representation (IR) that’s passed to the part of the
                                # Rust compiler that actually generates machine code (LLVM), and tells
                                # you which bits of Rust code produce the largest IR. This is useful
                                # because a larger IR means longer compile times, so identifying what
                                # Rust code generates a bigger IR (due to, for example, monomorphization)
                                # can highlight opportunities for reducing compile times.
            cargo-inspect       # See what Rust is doing behind the curtains
            cargo-download      # A utility for managing cargo dependencies from the command line
            cargo-criterion     # Cargo extension for running Criterion.rs benchmarks
            lldb                # debugging

            # setup and file structure
            cargo-generate   # cargo, make me a project
           #cargo-hack    #* # Helps you check that your crate works with any
                             # combination of features enabled. The tool
                             # presents an interface similar to that of Cargo
                             # itself (like cargo check, build, and test) but
                             # gives you the ability to run a given command with
                             # all possible combinations (the powerset) of the
                             # crate’s features.
            cargo-sweep      # A Cargo subcommand for cleaning up unused build files generated by Cargo
            cargo-cache      # Manage cargo cache (${CARGO_HOME}, ~/.cargo/), print sizes of dirs and remove dirs selectively

            # dependency management
            cargo-outdated  #* # Checks whether any of your dependencies, either
                               # direct or transitive, have newer versions
                               # available. Crucially, unlike cargo update, it
                               # even tells you about new major versions, so
                               # it’s an essential tool for checking if you’re
                               # missing out on newer versions due to an
                               # outdated major version specifier. Just keep in
                               # mind that bumping the major version of a
                               # dependency may be a breaking change for your
                               # crate if you expose that dependency’s types in
                               # your interface!
            cargo-udeps     #* # Identifies any dependencies listed in your Cargo.toml that are never actually used.
                               # Maybe you used them in the past but they’ve since become redundant, or maybe they
                               # should be moved to dev-dependencies; whatever the case, this tool helps you trim
                               # down bloat in your dependency closure.
            cargo-sort         # A tool to check that your Cargo.toml dependencies are sorted alphabetically
            cargo-fund         # Discover funding links for your project's dependencies
            cargo-msrv         # Cargo subcommand "msrv": assists with finding your minimum supported Rust version (MSRV)
            cargo-supply-chain # Gather author, contributor and publisher data on crates in your dependency graph
            cargo-depgraph     # Create dependency graphs for cargo projects using `cargo metadata` and graphviz

            # documentation
            cargo-readme      # Generate README.md from docstrings
            cargo-deadlinks   # Cargo subcommand to check rust documentation for broken links
            cargo-spellcheck  # Checks rust documentation for spelling and grammar mistakes
            cargo-sync-readme # A cargo plugin that generates a Markdown section in your README based on your Rust documentation

            # release optimization
            cargo-bloat # subcommand to help find what takes up space in your executable
            cargo-diet  # Help computing optimal include directives for your Cargo.toml manifest
            cargo-udeps # Find unused dependencies in Cargo.toml

            # auditing and security
            cargo-deny #* # Provides a way to lint your dependency graph: only
                          # allow certain licenses, deny-list crates or specific crate versions,
                          # detect dependencies with known vulnerabilities or that use Git
                          # sources, and detect crates that appear multiple times with different
                          # versions in the dependency graph. By the time you’re reading this,
                          # there may be even more handy lints in place. cargo-about # Cargo
                          # plugin to generate list of all licenses for a crate
            cargo-audit   # Audit Cargo.lock files for crates with security vulnerabilities
            cargo-geiger  # Detects usage of unsafe Rust in a Rust crate and its dependencies

            # Profiling tools
           #cargo-profiler   # Cargo subcommand for profiling Rust binaries
            cargo-flamegraph # Easy flamegraphs for Rust projects and everything else, without Perl or pipes <3
            cargo-valgrind   # Cargo subcommand "valgrind": runs valgrind and collects its output in a helpful manner
            perf-tools
            linuxPackages.perf
            linuxPackages.bcc
            linuxPackages.bpftrace
            heaptrack
            valgrind

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
            (mach-nix.lib."${system}".mkPython {
              requirements = ''
                matplotlib
                numpy
                pandas
              '';
            })
          ];

          LIBCLANG_PATH = pkgs.lib.makeLibraryPath [ pkgs.llvmPackages.libclang.lib ];
          RUST_SRC_PATH = workspaceShell.RUST_SRC_PATH;
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
