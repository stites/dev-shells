{
  nixConfig.extra-substituters = "https://stites.cachix.org";
  nixConfig.extra-trusted-public-keys = "stites.cachix.org-1:JN1rOOglf6VA+2aFsZnpkGUFfutdBIP1LbANgiJ940s=";

  description = "Pyro dev shell";
  inputs = rec {
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell";

    mach-nix.url = "github:DavHau/mach-nix";
    mach-nix.inputs.flake-utils.follows = "flake-utils";
    pypi-deps-db = {
      url = "github:DavHau/pypi-deps-db";
      flake = false;
    };
    mach-nix.inputs.pypi-deps-db.follows = "pypi-deps-db";
  };

  outputs = { self, nixpkgs, flake-utils, mach-nix, devshell, ... }:
    flake-utils.lib.eachSystem ["x86_64-linux"] (system:
      let
        inherit (mach-nix.lib.${system}) mkPython buildPythonPackage;
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ devshell.overlay ];
        };
        inherit (pkgs) lib mkShell;
        providers = rec {
          _default = "wheel,nixpkgs,sdist";
          torch = "wheel";
          tqdm = "wheel";
          torchvision = "wheel";
          protobuf = "wheel"; # ...otherwise infinite recursion.
          setuptools = "nixpkgs";
          wheel = "nixpkgs,sdist";
          numpy = "wheel";
          jupyter = "nixpkgs";
          jupyter-core = jupyter;
          jupyter-client = jupyter;
          jupyterlab-widgets = jupyter;
          jupyter_packaging = jupyter;
          matplotlib = "wheel";
          pandas = "wheel";
          jedi = "wheel";
          kiwisolver = "wheel";
          dateutil = "wheel";

          argon2-cffi = "nixpkgs";
          scikit-learn = "nixpkgs";
          scipy = "nixpkgs";
          pybind11 = scipy;
        };

        pyro-pkg = buildPythonPackage {
          src = ./pyro;
          inherit providers;
        };
        pyro-py = mkPython {
          packagesExtra = [
            # pyro-pkg
            # "https://github.com/gatagat/lap/tarball/master"
          ];
          inherit providers;
          requirements = lib.strings.concatStringsSep "\n" [
            "numpy>=1.7"
            "opt_einsum>=2.3.2"
            "pyro-api>=0.1.1"
            "torch>=1.9.0"
            "tensorboard" # just for tensorboard visualizations
            "tqdm>=4.36"
            "parso<0.9.0" # loose transitive dep of jedi, which is also a loose transitive dep

            "jupyter>=1.0.0" "jupyter_packaging"
            "graphviz>=0.8"
            "matplotlib>=1.3"
            "torchvision>=0.10.0"
            "visdom>=0.1.4"
            "pandas"
            "pillow==8.2.0"
            "scikit-learn" "Cython>=0.28.5"
            "seaborn"
            "wget"
            #"lap"

            "pybind11"
            "sphinx"
            "pytest-xdist"
            ##"pytest-cov" # borked
            "scipy>=1.1"
            "black>=21.4b0"
            "flake8" ######### new change
            "isort>=5.0" ######### new change
            #"mypy>=0.812"
            #"nbformat"
            #"nbsphinx>=0.3.2"
            #"nbstripout"
            #"nbval"
            #"ninja"
            #"pypandoc"
            "pytest>=5.0"
            #"pytest-xdist"
            #"sphinx"
            #"sphinx_rtd_theme"
            #"yapf"
            "funsor"

            "ipython" # for me
          ];
        };

      in {
        # FIXME: make this buildPythonApplication and move this to devShell only
        packages.pyro-ppl = pyro-pkg;
        defaultPackage = pyro-pkg;
        devShell = pkgs.devshell.mkShell {
          packages = with pkgs; [
            pyro-py
            gnused
            watchexec
            rsync
            git
            oil
          ];

          # applying patch: https://github.com/microsoft/pyright/issues/565
          bash.extra = ''
            export PYTHONPATH="$(${pkgs.git}/bin/git rev-parse --show-toplevel):$PYTHONPATH"
            export PYTHONBREAKPOINT='IPython.core.debugger.set_trace'
          '';
          bash.interactive = ''
            VENV_NAME="$(echo ${pyro-py} | ${pkgs.gnused}/bin/sed -E 's/\/nix\/store\/(.*)-env/\1/')-env"

            if [ -f pyrightconfig.json ]; then
              DETECTED=$(\grep -oP "[^\"]\w+-python3-[23].[0-9].[0-9](-env)?" pyrightconfig.json)
              if [ "$DETECTED" != "$VENV_NAME" ]; then
                cp pyrightconfig.json{,.bk}
                echo "detected venv $DETECTED in pyrightconfig.json, patching venv with $VENV_NAME"
                ${pkgs.gnused}/bin/sed -E -i "s/(\"venv\": \")\w+-python3-[23].[0-9].[0-9](-env)?/\1$VENV_NAME/" pyrightconfig.json
              else
                echo "detected matching venv $DETECTED in pyrightconfig.json"
              fi
            else
              echo "did not detect pyrightconfig.json, generating new venv with $VENV_NAME"
              cat > pyrightconfig.json << EOF
            {
              "pythonVersion": "3.8",
              "pythonPlatform": "Linux",
              "venv": "$VENV_NAME",
              "venvPath": "/nix/store"
            }
            EOF
            fi
          '' + (lib.optionalString true ''
            temp_dir=$(mktemp -d)
            cat <<'EOF' >"$temp_dir/.zshrc"
            if [ -e ~/.zshrc ]; then . ~/.zshrc; fi
            if [ -e ~/.config/zsh/.zshrc ]; then . ~/.config/zsh/.zshrc; fi
            menu
            EOF
            ZDOTDIR=$temp_dir zsh -i
          '');
        };
      });
}
