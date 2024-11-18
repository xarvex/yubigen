{
  description = "yubigen";

  inputs = {
    devenv.url = "github:cachix/devenv";

    devenv-root = {
      url = "file+file:///dev/null";
      flake = false;
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };

    systems.url = "github:nix-systems/default";
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
      imports = [ inputs.devenv.flakeModule ];

      systems = import inputs.systems;

      perSystem =
        { config, pkgs, ... }:
        let
          poetry2nix = inputs.poetry2nix.lib.mkPoetry2Nix { inherit pkgs; };

          gpgme =
            if lib.versionOlder pkgs.gpgme.version "1.24" then
              pkgs.gpgme.overrideAttrs (
                finalAttrs: previousAttrs: {
                  version = "1.24.0";

                  src = pkgs.fetchurl {
                    url = "mirror://gnupg/gpgme/gpgme-${finalAttrs.version}.tar.bz2";
                    hash = "sha256-YeOmrYkyP+z6/xdrwXKPuMMxLy+qg0JNnVB3uiD199o=";
                  };

                  nativeBuildInputs = with pkgs; [
                    autoreconfHook
                    gnupg
                    pkg-config
                    texinfo
                  ];
                  buildInputs = [ ];

                  patches = lib.lists.drop 1 previousAttrs.patches;

                  postPatch = null;
                }
              )
            else
              pkgs.gpgme;
          python_gpgme =
            if lib.versionOlder pkgs.gpgme.version "1.24" then
              pkgs.python3.pkgs.buildPythonPackage {
                inherit (gpgme) version src patches;

                pname = "gpgme";

                pyproject = true;

                postPatch = ''
                  substituteInPlace lang/python/setup.py.in \
                    --replace-fail "gpgme_h = '''" "gpgme_h = '${lib.getDev gpgme}/include/gpgme.h'"
                '';

                configureFlags = gpgme.configureFlags ++ [ "--enable-languages=python" ];

                postConfigure = ''
                  cd lang/python
                '';

                preBuild = ''
                  make copystamp
                '';

                build-system = with pkgs; [ python3.pkgs.setuptools ];

                nativeBuildInputs = with pkgs; [ swig ];
                buildInputs = [ gpgme ];

                pythonImportsCheck = [ "gpg" ];

                meta = gpgme.meta // {
                  description = "Python bindings to the GPGME API of the GnuPG cryptography library";
                  homepage = "https://dev.gnupg.org/source/gpgme/browse/master/lang/python/";
                };
              }
            else
              pkgs.python312Packages.gpgme;
        in
        {
          packages = rec {
            default = yubigen;

            yubigen =
              let
                pyproject = (pkgs.lib.importTOML ./pyproject.toml).tool.poetry;
              in
              poetry2nix.mkPoetryApplication {
                projectDir = ./.;
                meta = {
                  inherit (pyproject) description;

                  homepage = pyproject.repository;
                  license = lib.licenses.mit;
                  maintainers = with lib.maintainers; [ xarvex ];
                  mainProgram = pyproject.name;
                  platforms = lib.platforms.linux;
                };

                nativeBuildInputs = with pkgs; [ installShellFiles ];
                propagatedBuildInputs = [
                  pkgs.pam_u2f
                  python_gpgme
                ];

                postPatch = ''
                  substituteInPlace lib/udev/rules.d/69-yubigen.rules \
                    --replace '/usr/bin/env systemd-escape' '${lib.getExe' pkgs.systemdMinimal "systemd-escape"}'
                '';
                postInstall = ''
                  cp -r --parents lib "$out"

                  installShellCompletion --cmd yubigen \
                    --bash <(_YUBIGEN_COMPLETE=bash_source "$out/bin/yubigen") \
                    --fish <(_YUBIGEN_COMPLETE=fish_source "$out/bin/yubigen") \
                    --zsh  <(_YUBIGEN_COMPLETE=zsh_source  "$out/bin/yubigen")
                '';
              };
          };

          devenv.shells = rec {
            default = yubigen;

            yubigen =
              let
                cfg = config.devenv.shells.yubigen;
              in
              {
                devenv.root =
                  let
                    devenvRoot = builtins.readFile inputs.devenv-root.outPath;
                  in
                  # If not overridden (/dev/null), --impure is necessary.
                  lib.mkIf (devenvRoot != "") devenvRoot;

                name = "yubigen";

                packages =
                  [
                    (poetry2nix.mkPoetryEnv {
                      projectDir = ./.;
                      python = cfg.languages.python.package;
                    })
                  ]
                  ++ (with pkgs; [
                    codespell

                    pam_u2f
                    python_gpgme
                  ]);

                scripts.poetry-install.exec = ''
                  ${lib.getExe cfg.languages.python.poetry.package} lock --no-update
                  ${lib.getExe cfg.languages.python.poetry.package} install --only-root
                '';

                languages = {
                  nix.enable = true;
                  python = {
                    enable = true;
                    poetry.enable = true;
                  };
                };

                pre-commit.hooks = {
                  deadnix.enable = true;
                  flake-checker.enable = true;
                  nixfmt-rfc-style.enable = true;
                  pyright.enable = true;
                  ruff.enable = true;
                  ruff-format.enable = true;
                  statix.enable = true;
                };
              };
          };

          formatter = pkgs.nixfmt-rfc-style;
        };

      flake = {
        nixosModules = rec {
          default = yubigen;

          yubigen =
            {
              config,
              lib,
              pkgs,
              ...
            }:
            let
              selfPkgs = self.packages.${pkgs.system};

              cfg = config.programs.yubigen;
            in
            {
              options.programs.yubigen = {
                enableUdevRules = lib.mkEnableOption "yubigen udev rules";
                package = lib.mkPackageOption selfPkgs "yubigen" { };
              };

              config = lib.mkIf cfg.enableUdevRules { services.udev.packages = [ cfg.package ]; };
            };
        };

        homeManagerModules = rec {
          default = yubigen;

          yubigen =
            {
              config,
              lib,
              pkgs,
              ...
            }:
            let
              selfPkgs = self.packages.${pkgs.system};

              cfg = config.programs.yubigen;

              tomlFormat = pkgs.formats.toml { };
            in
            {
              options.programs.yubigen = {
                enable = lib.mkEnableOption "yubigen";
                enableSshIntegration = lib.mkEnableOption "yubigen OpenSSH integration";
                package = lib.mkPackageOption selfPkgs "yubigen" { };

                settings = lib.mkOption {
                  inherit (tomlFormat) type;

                  default = { };
                  example = lib.literalExpression ''
                    {
                      ssh.applications = {
                        Example = "example.com";
                        Work = [
                          "github.com"
                          "gitlab.com"
                        ];
                      };
                    };
                  '';
                  description = "Configuration used for yubigen.";
                };
              };

              config = lib.mkIf cfg.enable (
                lib.mkMerge [
                  {
                    home.packages = [ cfg.package ];

                    xdg.configFile.yubigen = lib.mkIf (cfg.settings != { }) {
                      source = tomlFormat.generate "yubigen-settings" cfg.settings;
                    };
                  }

                  (lib.mkIf cfg.enableSshIntegration {
                    programs.ssh.includes = lib.optional config.programs.ssh.enable "${config.xdg.stateHome}/yubigen/ssh/config_*";

                    systemd.user.services."yubigen-ssh@" = {
                      Service = {
                        ExecStart = "${lib.getExe cfg.package} ssh register /%I %i";
                        ExecStop = "${lib.getExe cfg.package} ssh unregister %i";
                        RemainAfterExit = true;
                        Type = "oneshot";
                      };

                      Unit = {
                        After = [ "%i.device" ];
                        BindsTo = [ "%i.device" ];
                        Description = "yubigen-ssh @ /%I";
                      };
                    };
                  })
                ]
              );
            };
        };
      };
    };
}
