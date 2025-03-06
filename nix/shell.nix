{
  lib,
  pkgs,
  pythonSet,
  self,
  uv-workspace,
  ...
}:

let
  inherit (self.checks.${pkgs.system}) pre-commit;

  editablePythonSet = pythonSet.overrideScope (
    lib.composeManyExtensions [
      (uv-workspace.mkEditablePyprojectOverlay { root = "$REPO_ROOT"; })
      (final: prev: {
        yubigen = prev.yubigen.overrideAttrs (o: {
          src = lib.fileset.toSource {
            root = o.src;
            fileset = lib.fileset.unions [
              (o.src + "/src/yubigen/__main__.py")
              (o.src + "/README.md")
              (o.src + "/pyproject.toml")
            ];
          };

          nativeBuildInputs = o.nativeBuildInputs ++ final.resolveBuildSystem { editables = [ ]; };
        });
      })
    ]
  );
  virtualenv = editablePythonSet.mkVirtualEnv "yubigen-virtualenv" uv-workspace.deps.all;
in
pkgs.mkShellNoCC {
  nativeBuildInputs = pre-commit.enabledPackages ++ (with pkgs; [ uv ]);
  buildInputs = [ virtualenv ];

  env = {
    UV_NO_SYNC = "1";
    UV_PYTHON = lib.getExe' virtualenv "python";
    UV_PYTHON_DOWNLOADS = "never";
  };

  shellHook =
    pre-commit.shellHook
    + ''
      unset PYTHONPATH
      export REPO_ROOT="$(git rev-parse --show-toplevel)"
    '';
}
