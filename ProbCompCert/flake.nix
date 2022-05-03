{
  inputs.utils.url = "github:numtide/flake-utils";
  inputs.devshell.url = "github:numtide/devshell";
  outputs = {nixpkgs, utils, devshell, ... }:
    utils.lib.eachSystem ["x86_64-linux"] (system:
      let
        pkgs = import "${nixpkgs}" {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            devshell.overlay
            (final: prev: {
              python3 = prev.python3.override {
                self = prev.python3;
                packageOverrides = finalpy: prevpy: {
                  pystan = prevpy.buildPythonPackage rec {
                    pname = "pystan";
                    version = "2.19.1.1";
                    name = "${pname}-${version}";
                    src = prevpy.fetchPypi {
                      inherit pname version;
                      sha256 = "0f5hbv9dhsx3b5yn5kpq5pwi1kxzmg4mdbrndyz2p8hdpj6sv2zs";
                    };
                    propagatedBuildInputs = with prevpy; [ cython numpy matplotlib ];
                    doCheck = false; # long, slow tests
                  };
                };
              };
            })
          ];

        };
      in
      rec {
       devShell = pkgs.devshell.mkShell {
          packages = with pkgs; [
            watchexec
            cmdstan
            gcc
          ];
          commands = let
            watchexec = "${pkgs.watchexec}/bin/watchexec";
            cd-root = ''
              current_dir=$PWD
              root_dir=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
              stan_dir=$root_dir/stanfrontend
            '';
            cd-root-with-prog = ''
              ${cd-root}
              prog=''${1##*/}
              name=''${prog%.*}
              parent_dir="$(dirname -- "$(readlink -f -- "$1")")"
              cd $root_dir
            '';
            run = {build ? null, cmd, debug ? null, finally ? null}:
              let
                err-str = if debug == null then cmd else "${cmd}, attempting ${debug}...";
                debug-cmd = if debug == null then "" else "&& ${debug}";
                final-cmd = if finally == null then "" else "&& (${finally})";
                runnable = "${cmd} && echo '>>> done: ${cmd}.' || ( echo '>>> error! ${err-str}' ${debug-cmd})";
              in if build == null then runnable else "${build} && (${runnable}) ${final-cmd}";

            watch = {at-root ? true, exts ? "v,ml,stan,c,Makefile", build ? null, cmd, finally ? null}: ''
              ${if at-root then cd-root-with-prog else ""}
              if [ -z "$1" ]; then
                  ignore=""
              else
                  ignore="--ignore $name.v --ignore $name.light.c"
              fi
              ${watchexec} -e ${exts} $ignore "${run {inherit build cmd finally; }}"
             '';
            mk-watcher = name: all@{ ... }: all // { inherit name; category = "watchers"; };

          in [
            (mk-watcher "watch-stan" {
              command = watch {
                build = "make -j && make install && rm ccomp clightgen";
                cmd = "./out/bin/ccomp -c $current_dir/$1";
              };
            })
            (mk-watcher "watch-stan-debug" {
              command = watch {
                build = "make -j && make install && rm ccomp clightgen";
                cmd = "./out/bin/ccomp -c $current_dir/$1";
                #finally = "./out/bin/clightgen $current_dir/$1";
                finally ="./out/bin/clightgen $current_dir/$1 && ./out/bin/ccomp -dclight -dcminor -c $current_dir/$1";
              };
            })
            (mk-watcher "watch-clightgen" {
              command = watch {
                build = "make -j && make install && rm ccomp clightgen";
                cmd = "./out/bin/clightgen $current_dir/$1";
              };
            })
            {
              category = "configure";
              name = "cconf64+clightgen";
              command = ''
                ${cd-root}
                ./configure -prefix ./out -clightgen x86_64-linux
              '';
            }
            {
              category = "configure";
              name = "cconf64";
              command = ''
                ${cd-root}
                ./configure -prefix ./out x86_64-linux
              '';
            }
            {
              category = "test";
              name = "test-stan";
              command = ''
                ${cd-root-with-prog}
                ./out/bin/ccomp -c $current_dir/$1
              '';
            }
            {
              category = "build";
              name = "ccompstan";
              command = pkgs.lib.strings.concatStringsSep "\n" [
                # boilerplate for some env variables used below
                cd-root-with-prog

                # working directory is stan dir
                "cd stanfrontend"

                # ccomp doesn't compile down to object files, just asm
                ''ccomp -g3 -O0 -c $current_dir/$1 && ccomp -c ''${name}.s''

                # build libstan.so
                ''ccomp -O0 -g3 -c stanlib.c''
                ''ccomp -O0 -g3 -c staninput.c''
                ''ld -shared stanlib.o staninput.o -o libstan.so''

                # runtime is dependent on libstan, temporarily.
                ''ccomp -g3 -O0 -I''${stan_dir} -c Runtime.c''

                # compile the final binary
                ''ccomp -g3 -O0 -L''${stan_dir} -Wl,-rpath=''${stan_dir} -L../out/lib/compcert -lm -lstan ''${name}.o Runtime.o -o runit''

                # tell the user what to do next
                ''echo "compiled! ./stanfrontend/runit INT [DATA_FIELD...]"''
              ];
            }
            {
              category = "build";
              name = "build";
              command = ''
                ${cd-root}
                make -j && make install && rm ccomp clightgen
              '';
            }
            {
              category = "build";
              name = "clean";
              command = ''
                ${cd-root}
                rm -f *.s clightgen ccomp *.so *.o
                rm -f compcert.ini compcert.config .depend .lia.cache

                cd ./stanfrontend
                rm -f *.s *.so runit *.vo *.vok *.glob *.vos *.s *.o
              '';
            }
            {
              category = "test";
              name = "test-c1";
              command = let
                compiler = "../out/bin/ccomp";
              in ''
                ${cd-root}
                cd stanfrontend
                ${compiler} -c Runtime.c
                ${compiler} -c Program.c
                ${compiler} -L../out/lib/compcert -lm Program.o Runtime.o -o runit
                ./runit $1
              '';
            }
            {
              category = "test";
              name = "test-c2";
              command = let
                compiler = "../out/bin/ccomp";
                program = "Program2";
              in ''
                ${cd-root}
                cd stanfrontend
                ${compiler} -c Runtime.c
                ${compiler} -c ${program}.c
                ${compiler} -c stanlib.c
                ld -shared stanlib.o -o libstan.so
                ${compiler} -L''${stan_dir} -Wl,-rpath=''${stan_dir} -L../out/lib/compcert -lm -lstan ${program}.o Runtime.o -o runit
                ./runit $1
              '';
            }
            {
              category = "test";
              name = "test-stan2";
              command = ''
                ${cd-root}
                ./out/bin/ccomp -c $current_dir/$1
                ./out/bin/ccomp -c $current_dir/$1.s
              '';
            }
            {
              category = "test";
              name = "test-stan2-full";
              command = ''
                ${cd-root}
                ./out/bin/ccomp -c $current_dir/$1
                ./out/bin/ccomp -c $current_dir/$name.s
                ./out/bin/ccomp -c $stan_dir/Runtime.c
                ./out/bin/ccomp -c $stan_dir/stanlib.c
                ld -shared $current_dir/stanlib.o -o $current_dir/libstan.so
                ./out/bin/ccomp -L''${stan_dir} -Wl,-rpath=''${stan_dir} -L./out/lib/compcert -lm -lstan $name.o Runtime.o -o runit
                ./runit $2
              '';
            }
          ];
        };
      });
}
