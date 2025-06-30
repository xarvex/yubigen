{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  uv-workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ../.; };
  pythonSet =
    (pkgs.callPackage inputs.pyproject-nix.build.packages { python = pkgs.python3; }).overrideScope
      (
        lib.composeManyExtensions [
          inputs.pyproject-build-systems.overlays.default
          (uv-workspace.mkPyprojectOverlay { sourcePreference = "wheel"; })
          (final: prev: {
            gpg = pkgs.python3Packages.gpgme;

            # INFO: https://github.com/NixOS/nixpkgs/blob/66576dcd9e7858544b293b0600ad8bd1b73cb770/pkgs/development/python-modules/pyscard/default.nix
            pyscard = prev.pyscard.overrideAttrs (
              o:
              let
                inherit (pkgs)
                  pcsclite
                  pkg-config
                  stdenv
                  swig
                  ;
              in
              {
                nativeBuildInputs =
                  (o.nativeBuildInputs or [ ])
                  ++ [ swig ]
                  ++ lib.optional (!stdenv.hostPlatform.isDarwin) pkg-config
                  ++ final.resolveBuildSystem { setuptools = [ ]; };

                buildInputs = (o.buildInputs or [ ]) ++ lib.optional (!stdenv.hostPlatform.isDarwin) pcsclite;

                postPatch =
                  (o.postPatch or "")
                  + ''
                    substituteInPlace pyproject.toml \
                      --replace-fail 'requires = ["setuptools","swig"]' 'requires = ["setuptools"]'
                  ''
                  + lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
                    substituteInPlace setup.py --replace-fail "pkg-config" "$PKG_CONFIG"
                    substituteInPlace src/smartcard/scard/winscarddll.c \
                      --replace-fail "libpcsclite.so.1" \
                                "${lib.getLib pcsclite}/lib/libpcsclite${stdenv.hostPlatform.extensions.sharedLibrary}"
                  '';
              }
            );

            yubigen = prev.yubigen.overrideAttrs (
              o:
              let
                inherit (pkgs) pam_u2f;
              in
              {
                propagatedBuildInputs = (o.propagatedBuildInputs or [ ]) ++ [ pam_u2f ];

                passthru = lib.recursiveUpdate o.passthru { dependencies.gpg = [ ]; };
              }
            );
          })
        ]
      );
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
  nativeBuildInputs = with pkgs; [
    uv

    basedpyright
    deadnix
    flake-checker
    nixfmt-rfc-style
    pre-commit
    ruff
    statix
  ];
  buildInputs = [ virtualenv ];

  env = {
    UV_NO_SYNC = "1";
    UV_PYTHON = lib.getExe' virtualenv "python";
    UV_PYTHON_DOWNLOADS = "never";
  };

  shellHook = ''
    PYTHONPATH="$(${lib.getExe' virtualenv "python"} -c 'import sys; print(":".join(sys.path));')"
    export PYTHONPATH
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    export REPO_ROOT

    PATH="${virtualenv}/bin:''${PATH}"

    pre-commit install
  '';
}
