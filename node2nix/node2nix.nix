with import <nixpkgs> {};
stdenv.mkDerivation rec {
        name = "node2nix";
        buildInputs = [ nodePackages.node2nix ];
}
