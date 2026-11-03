{ pkgs, self }:
let
  inherit (pkgs) lib;
  evaluate = settings: (lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      self.homeManagerModules.default
      {
        options.home.packages = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
        options.home.file = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
        options.assertions = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      }
      settings
    ];
  }).config;
  disabled = evaluate { };
  cli = evaluate { programs.amp = { enable = true; settings."amp.notifications.enabled" = false; }; };
  desktop = evaluate { programs.amp.desktop.enable = true; };
  supported = builtins.hasAttr "amp-desktop" self.packages.${pkgs.stdenv.hostPlatform.system};
in
assert disabled.home.packages == [ ];
assert builtins.length cli.home.packages == 1;
assert lib.all (x: x.assertion) cli.assertions;
assert (if supported then builtins.length desktop.home.packages == 1 && lib.all (x: x.assertion) desktop.assertions
  else !(lib.all (x: x.assertion) desktop.assertions));
pkgs.runCommand "amp-home-manager-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
  jq -e '."amp.notifications.enabled" == false' ${cli.home.file.".config/amp/settings.json".source}
  touch "$out"
''
