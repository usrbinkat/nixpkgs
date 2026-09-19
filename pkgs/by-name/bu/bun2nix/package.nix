{
  lib,
  fetchFromGitHub,
  callPackage,
}:

let
  src = fetchFromGitHub {
    owner = "usrbinkat";
    repo = "bun2nix";
    rev = "a4bedb247cabd86e2ed760d17d6b1dfb650e4316";
    hash = "sha256-XwypaTE32xhbuMdiJyqTc1Okj+EQ8MaScmPg2V5bSFI=";
  };
in
callPackage (src + "/package.nix") { }
