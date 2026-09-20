{
  callPackage,
  opencode,
}:

callPackage (opencode.src + "/nix/desktop.nix") {
  inherit opencode;
}
