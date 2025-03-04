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
    enableUdevRules = lib.mkEnableOption "yubigen udev rules";
    package = lib.mkPackageOption self.packages.${pkgs.system} "yubigen" { };
  };

  config = lib.mkIf cfg.enableUdevRules { services.udev.packages = [ cfg.package ]; };
}
