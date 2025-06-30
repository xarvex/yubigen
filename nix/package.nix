{
  installShellFiles,
  lib,
  python3Packages,
  systemdMinimal,
  yubikey-manager,
}:

let
  pyproject = (lib.importTOML ../pyproject.toml).project;
in
python3Packages.buildPythonPackage {
  pname = pyproject.name;
  inherit (pyproject) version;
  pyproject = true;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../lib
      ../README.md
      ../pyproject.toml
      (lib.fileset.fileFilter (file: lib.strings.hasSuffix ".py" file.name) ../.)
    ];
  };

  nativeBuildInputs = [ installShellFiles ];

  patchPhase = ''
    runHook prePatch

    substituteInPlace lib/udev/rules.d/69-yubigen.rules \
        --replace-fail '/usr/bin/env systemd-escape' '${lib.getExe' systemdMinimal "systemd-escape"}'

    runHook postPatch
  '';

  postInstall = ''
    cp -r --parents lib $out

    installShellCompletion --cmd yubigen \
        --bash <(_YUBIGEN_COMPLETE=bash_source $out/bin/yubigen) \
        --fish <(_YUBIGEN_COMPLETE=fish_source $out/bin/yubigen) \
        --zsh  <(_YUBIGEN_COMPLETE=zsh_source  $out/bin/yubigen)
  '';

  pythonImportsCheck = [ pyproject.name ];

  build-system = with python3Packages; [ hatchling ];
  dependencies = with python3Packages; [
    click
    gpgme
    platformdirs
    pydantic
    yubikey-manager
  ];

  meta = {
    inherit (pyproject) description;
    homepage = pyproject.urls.Repository;
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ xarvex ];
    mainProgram = pyproject.name;
    platforms = lib.platforms.linux;
  };
}
