{
  lib,
  fetchFromGitHub,
  callPackage,
}:

let
  src = fetchFromGitHub {
    owner = "usrbinkat";
    repo = "bun2nix";
    rev = "e249d1b211d0a6b8189d0c51e929efae6e929f00";
    hash = "sha256-RZPDkkNVrGpU7sQrUdmoKN6QCarR3toooObMmvFczC4=";
  };
in
callPackage (src + "/package.nix") { }
