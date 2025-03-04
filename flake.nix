{
  description = "yubigen";

  inputs = {
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
      };
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      self,
      ...
    }:
    let
      inherit (nixpkgs) lib;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      perSystem =
        { pkgs, system, ... }:
        let
          python = pkgs.python312;

          uv-workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

          pythonSet =
            (pkgs.callPackage inputs.pyproject-nix.build.packages { inherit python; }).overrideScope
              (
                lib.composeManyExtensions [
                  inputs.pyproject-build-systems.overlays.default
                  (uv-workspace.mkPyprojectOverlay { sourcePreference = "wheel"; })
                  (final: prev: {
                    gpg = pkgs.python312Packages.gpgme;

                    # INFO: https://github.com/NixOS/nixpkgs/blob/6313551cd05425cd5b3e63fe47dbc324eabb15e4/pkgs/development/python-modules/pyscard/default.nix
                    pyscard = prev.pyscard.overrideAttrs (o: {
                      nativeBuildInputs =
                        (o.nativeBuildInputs or [ ])
                        ++ (with pkgs; [ swig ])
                        ++ (lib.optional (!pkgs.stdenv.isDarwin) pkgs.pkg-config)
                        ++ final.resolveBuildSystem { setuptools = [ ]; };
                      buildInputs =
                        (o.buildInputs or [ ]) ++ (with pkgs; if stdenv.isDarwin then [ PCSC ] else [ pcsclite ]);

                      postPatch =
                        (o.postPatch or "")
                        + ''
                          substituteInPlace pyproject.toml \
                            --replace-fail 'requires = ["setuptools","swig"]' 'requires = ["setuptools"]'
                        ''
                        + (
                          with pkgs;
                          if stdenv.isDarwin then
                            ''
                              substituteInPlace src/smartcard/scard/winscarddll.c \
                                --replace-fail "/System/Library/Frameworks/PCSC.framework/PCSC" \
                                          "${PCSC}/Library/Frameworks/PCSC.framework/PCSC"
                            ''
                          else
                            ''
                              substituteInPlace setup.py --replace-fail "pkg-config" "$PKG_CONFIG"
                              substituteInPlace src/smartcard/scard/winscarddll.c \
                                --replace-fail "libpcsclite.so.1" \
                                          "${lib.getLib pcsclite}/lib/libpcsclite${stdenv.hostPlatform.extensions.sharedLibrary}"
                            ''
                        );
                    });

                    yubigen = prev.yubigen.overrideAttrs (o: {
                      propagatedBuildInputs = (o.propagatedBuildInputs or [ ]) ++ (with pkgs; [ pam_u2f ]);

                      passthru = lib.recursiveUpdate o.passthru { dependencies.gpg = [ ]; };
                    });
                  })
                ]
              );
        in
        {
          packages = rec {
            default = yubigen;
            yubigen = pkgs.callPackage ./nix/package.nix {
              inherit (inputs) pyproject-nix;
              inherit pythonSet uv-workspace;
            };
          };

          devShells = rec {
            default = yubigen;
            yubigen = import ./nix/shell.nix {
              inherit
                inputs
                lib
                pkgs
                pythonSet
                self
                uv-workspace
                ;
            };
          };

          checks.pre-commit = inputs.git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              deadnix.enable = true;
              flake-checker.enable = true;
              nixfmt-rfc-style.enable = true;
              pyright = {
                enable = true;
                args =
                  let
                    virtualenv = pythonSet.mkVirtualEnv "yubigen-virtualenv" uv-workspace.deps.all;
                  in
                  [
                    "--pythonpath"
                    (lib.getExe' virtualenv "python")
                  ];
              };
              ruff.enable = true;
              ruff-format.enable = true;
              statix.enable = true;
            };
          };

          formatter = pkgs.nixfmt-rfc-style;
        };

      flake = {
        nixosModules = rec {
          default = yubigen;
          yubigen = import ./nix/nixos.nix { inherit inputs self; };
        };

        homeManagerModules = rec {
          default = yubigen;
          yubigen = import ./nix/home-manager.nix { inherit inputs self; };
        };
      };
    };
}
