{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  bun2nix,
  bun,
  nodejs,
  sysctl,
  darwin,
  makeWrapper,
  models-dev,
  ripgrep,
  wayland,
  installShellFiles,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "opencode";
  version = "2.0.15";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "usrbinkat";
    repo = "opencode";
    rev = "9362c8bdbf42b1d08a479039bf85cc217dc443c1";
    hash = "sha256-vmylnPQQI4aVXG279kVknxl7NAVjE4LvasYZiOlZNSA=";
  };

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = finalAttrs.src + "/nix/bun.nix";
  };

  nativeBuildInputs = [
    bun2nix.hook
    bun
    nodejs
    installShellFiles
    makeWrapper
    writableTmpDirAsHomeHook
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isDarwin [
    darwin.sigtool
  ];

  bunInstallFlags = [
    "--frozen-lockfile"
    "--no-progress"
  ];

  env.MODELS_DEV_API_JSON = "${models-dev}/dist/_api.json";
  env.OPENCODE_DISABLE_MODELS_FETCH = true;
  env.OPENCODE_VERSION = finalAttrs.version;
  env.OPENCODE_CHANNEL = "latest";
  env.NODE_OPTIONS = "--max-old-space-size=4096";

  buildPhase = ''
    runHook preBuild

    cd ./packages/cli
    bun --bun ./script/build.ts --single --skip-install

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 dist/cli-*/bin/opencode $out/bin/opencode

    # OpenTUI dlopens Wayland for clipboard images.
    wrapProgram $out/bin/opencode \
      --set OPENCODE_DISABLE_AUTOUPDATE true \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            ripgrep
          ]
          ++ lib.optional stdenvNoCC.hostPlatform.isDarwin sysctl
        )
      } ${lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ wayland ]}
      ''}

    ln -s opencode $out/bin/opencode2

    runHook postInstall
  '';

  dontStrip = true;

  postInstall =
    lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
      codesign --force --sign - $out/bin/.opencode-wrapped
    ''
    + lib.optionalString (stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform) ''
      installShellCompletion --cmd opencode \
        --bash <($out/bin/opencode completion) \
        --zsh <(SHELL=/bin/zsh $out/bin/opencode completion)

      installShellCompletion --cmd opencode2 \
        --bash <($out/bin/opencode2 completion) \
        --zsh <(SHELL=/bin/zsh $out/bin/opencode2 completion)
    '';

  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  doInstallCheck = true;
  versionCheckKeepEnvironment = [
    "HOME"
    "OPENCODE_DISABLE_MODELS_FETCH"
  ];
  versionCheckProgramArg = "--version";

  passthru = {
    inherit (finalAttrs) bunDeps;
    updateScript = nix-update-script { };
  };

  meta = {
    description = "AI coding agent built for the terminal";
    homepage = "https://opencode.ai";
    changelog = "https://github.com/anomalyco/opencode/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      delafthi
      DuskyElf
      graham33
      usrbinkat
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "opencode";
  };
})
