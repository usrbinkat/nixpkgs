{
  lib,
  python3Packages,
  fetchPypi,
  fetchpatch,
  versionCheckHook,
}:

python3Packages.buildPythonPackage rec {
  pname = "lesscpy";
  version = "0.15.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-T2t/NMIsXOE35+4oDcsZhK3g1QC22rWR1KTYQlLRjek=";
  };

  patches = [
    # remove use of pkg_resources (drop on next release)
    (fetchpatch {
      url = "https://github.com/lesscpy/lesscpy/commit/bd8949579713c9d4ff9e15799a26fcecdf73530e.patch";
      hash = "sha256-U1VDqZqHYaUmND5qCkARyU/eDv2QRhGcCDzuN4+XTbo=";
    })
  ];

  build-system = with python3Packages; [ setuptools ];

  postPatch = ''
    substituteInPlace lesscpy/scripts/compiler.py \
      --replace-fail 'from lesscpy.lessc import' 'from lesscpy import __version__
    from lesscpy.lessc import' \
      --replace-fail 'VERSION_STR = "Lesscpy compiler 0.9h"' \
        'VERSION_STR = "Lesscpy compiler " + __version__'
  '';

  dependencies = with python3Packages; [
    ply
  ];

  nativeCheckInputs = with python3Packages; [ pytestCheckHook ];

  pythonImportsCheck = [ "lesscpy" ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/lesscpy";
  doInstallCheck = true;

  meta = {
    description = "Python LESS Compiler";
    mainProgram = "lesscpy";
    homepage = "https://github.com/lesscpy/lesscpy";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ s1341 ];
  };
}
