{ self, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.yubigen;

  tomlFormat = pkgs.formats.toml { };
in
{
  options.programs.yubigen = {
    enable = lib.mkEnableOption "yubigen";
    enableSshIntegration = lib.mkEnableOption "yubigen OpenSSH integration";
    package = lib.mkPackageOption self.packages.${pkgs.system} "yubigen" { };

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
          Unit = {
            Description = "yubigen-ssh @ /%I";
            After = [ "%i.device" ];
            BindsTo = [ "%i.device" ];
          };

          Service = {
            Type = "oneshot";
            ExecStart = "${lib.getExe cfg.package} ssh register /%I %i";
            ExecStop = "${lib.getExe cfg.package} ssh unregister %i";
            RemainAfterExit = true;
          };
        };
      })
    ]
  );
}
