{
  callPackages,
  installShellFiles,
  lib,
  stdenvNoCC,
  symlinkJoin,
  systemdMinimal,

  pyproject-nix,
  pythonSet,
  uv-workspace,
}:

let
  application = (callPackages pyproject-nix.build.util { }).mkApplication {
    venv = pythonSet.mkVirtualEnv "yubigen-virtualenv" uv-workspace.deps.default;
    package = pythonSet.yubigen.overrideAttrs (o: {
      meta = (o.meta or { }) // {
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ xarvex ];
        platforms = lib.platforms.linux;
      };
    });
  };
  extras = stdenvNoCC.mkDerivation {
    pname = "${application.pname}-extras";
    inherit (application) version;

    inherit (pythonSet.yubigen) src;

    nativeBuildInputs = [ installShellFiles ];

    patchPhase = ''
      runHook prePatch

      substituteInPlace lib/udev/rules.d/69-yubigen.rules \
          --replace-fail '/usr/bin/env systemd-escape' '${lib.getExe' systemdMinimal "systemd-escape"}'

      runHook postPatch
    '';

    installPhase = ''
      runHook preInstall

      mkdir $out
      cp -r --parents lib $out

      installShellCompletion --cmd yubigen \
          --bash <(_YUBIGEN_COMPLETE=bash_source ${application}/bin/yubigen) \
          --fish <(_YUBIGEN_COMPLETE=fish_source ${application}/bin/yubigen) \
          --zsh  <(_YUBIGEN_COMPLETE=zsh_source  ${application}/bin/yubigen)

      runHook postInstall
    '';
  };
in
symlinkJoin {
  inherit (application)
    name
    pname
    version
    meta
    ;

  paths = [
    application
    extras
  ];
}
