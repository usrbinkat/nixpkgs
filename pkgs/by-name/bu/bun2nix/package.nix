{
  lib,
  fetchFromGitHub,
  callPackage,
}:

let
  src = fetchFromGitHub {
    owner = "usrbinkat";
    repo = "bun2nix";
    rev = "714af6d3f54fab402a3ee8ac016506c477b52384";
    hash = "sha256-1crWPaBfpNxtqPxfg01ryTeTLJIKkmYIzo49e74+baQ=";
  };
in
callPackage (src + "/package.nix") { }
