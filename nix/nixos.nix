{ self, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.yubigen;
in
{
  options.programs.yubigen = {
    enable = lib.mkEnableOption "yubigen";
    enableUdevRules = lib.mkEnableOption "yubigen udev rules";
    package = lib.mkPackageOption self.packages.${pkgs.system} "yubigen" { };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable { environment.systemPackages = [ cfg.package ]; })
    (lib.mkIf cfg.enableUdevRules { services.udev.packages = [ cfg.package ]; })
  ];
}
