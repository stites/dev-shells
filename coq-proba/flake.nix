{

  description = "coq-proba";

  inputs.utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, utils, ... }@inputs:
    utils.lib.eachSystem ["x86_64-linux"] (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in
      rec {
        packages = utils.lib.flattenTree {
          coq-proba = let
            coq-version = "8_12";
            coqc = pkgs."coq_${coq-version}";
            coqPackages = pkgs."coqPackages_${coq-version}";
            inherit (pkgs) stdenv;
          in
            stdenv.mkDerivation {
              name = "coq-proba";
              src = ./.;
              #buildFlags = [ "COQLIB=$(out)/lib/coq/${coqc.coq-version}/" ];
              propagatedBuildInputs = [ coqc ];
              enableParallelBuilding = true;
              buildInputs = (with pkgs; [
                ocaml
                dune_2
              ]) ++ (with coqPackages; [
                bignums
                mathcomp-ssreflect
                stdpp
                coquelicot
                flocq
                interval
              ]) ++ (with pkgs.ocamlPackages; [
                menhir
              ]);
            };
          };
        defaultPackage = packages.coq-proba;
        devShell = with pkgs; mkShell {
          buildInputs = packages.coq-proba.buildInputs ++ [git];
        };
      }
    );
}
