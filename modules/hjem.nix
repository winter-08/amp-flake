{ self }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.amp;
  jsonFormat = pkgs.formats.json { };
  system = pkgs.stdenv.hostPlatform.system;
in
{
  _class = "hjem";
  options.programs.amp = {
    enable = lib.mkEnableOption "the Amp CLI";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.amp;
      description = "Amp CLI package to install.";
    };
    settings = lib.mkOption {
      type = lib.types.attrsOf jsonFormat.type;
      default = { };
      description = ''
        Declarative CLI settings written to ~/.config/amp/settings.json.
        These also apply to local CLI runners launched by the macOS app, not
        desktop appearance or cloud orbs. Do not include API keys or secrets:
        this file is stored in the world-readable Nix store.
      '';
    };
    desktop = {
      enable = lib.mkEnableOption "the Amp desktop app";
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = self.packages.${system}.amp-desktop or null;
        description = "Desktop package; unavailable on Intel macOS.";
      };
    };
  };

  config = lib.mkIf (cfg.enable || cfg.desktop.enable) {
    assertions = [
      {
        assertion = !cfg.desktop.enable || cfg.desktop.package != null;
        message = "Amp desktop supports x86_64-linux, aarch64-linux and aarch64-darwin only.";
      }
      {
        assertion = cfg.enable || cfg.settings == { };
        message = "Enable programs.amp.enable to manage Amp CLI settings.";
      }
    ];
    packages = lib.optional cfg.enable cfg.package
      ++ lib.optional (cfg.desktop.enable && cfg.desktop.package != null) cfg.desktop.package;
    # Amp documents this path on both Linux and macOS. Do not redirect it to
    # ~/Library/Application Support or own the directory containing credentials.
    files.".config/amp/settings.json" = lib.mkIf (cfg.enable && cfg.settings != { }) {
      source = jsonFormat.generate "amp-settings.json" cfg.settings;
    };
  };
}
