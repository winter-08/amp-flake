{
  description = "A reproducible Nix flake for the Amp coding agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixpkgs unstable dropped Intel macOS in 26.11. The 26.05 Darwin branch
    # remains supported through the end of 2026.
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-darwin,
      self,
    }:
    let
      release = builtins.fromJSON (builtins.readFile ./versions.json);
      supportedSystems = builtins.attrNames release.platforms;
      nixpkgsFor = system: if system == "x86_64-darwin" then nixpkgs-darwin else nixpkgs;
      pkgsFor =
        system:
        import (nixpkgsFor system) {
          inherit system;
          # Amp is proprietary. This keeps direct flake usage self-contained;
          # overlay consumers should allow the `amp` package themselves.
          config.allowUnfreePredicate = package: nixpkgs.lib.getName package == "amp";
        };
      forAllSystems = function: nixpkgs.lib.genAttrs supportedSystems (system: function (pkgsFor system));

      mkAmp =
        pkgs:
        let
          platform = release.platforms.${pkgs.stdenv.hostPlatform.system};
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "amp";
          inherit (release) version;

          src = pkgs.fetchurl {
            url = "https://static.ampcode.com/cli/${release.version}/amp-${platform.target}";
            inherit (platform) hash;
          };

          dontUnpack = true;
          strictDeps = true;

          nativeBuildInputs = [
            pkgs.makeWrapper
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
          buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            pkgs.stdenv.cc.cc.lib
          ];

          installPhase = ''
            runHook preInstall

            install -Dm755 "$src" "$out/libexec/amp/amp"
            makeWrapper "$out/libexec/amp/amp" "$out/bin/amp" \
              --set AMP_SKIP_UPDATE_CHECK 1

            runHook postInstall
          '';

          passthru.updateScript = ./scripts/update.sh;

          meta = {
            description = "Frontier coding agent for the terminal and editor";
            homepage = "https://ampcode.com";
            license = pkgs.lib.licenses.unfree;
            mainProgram = "amp";
            platforms = supportedSystems;
            sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
          };
        };
    in
    {
      overlays.default = final: _prev: {
        amp = mkAmp final;
      };

      packages = forAllSystems (
        pkgs:
        let
          amp = mkAmp pkgs;
        in
        {
          inherit amp;
          default = amp;
        }
      );

      apps = forAllSystems (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
        in
        {
          amp = {
            type = "app";
            program = "${self.packages.${system}.amp}/bin/amp";
            meta.description = "Run the Amp coding agent";
          };
          default = self.apps.${system}.amp;
        }
      );

      checks = forAllSystems (pkgs: {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.amp;
        repository =
          pkgs.runCommand "amp-flake-checks"
            {
              nativeBuildInputs = [
                pkgs.actionlint
                pkgs.jq
                pkgs.shellcheck
              ];
            }
            ''
              jq --exit-status '
                (.version | type == "string" and length > 0) and
                (.platforms | keys == [
                  "aarch64-darwin",
                  "aarch64-linux",
                  "x86_64-darwin",
                  "x86_64-linux"
                ]) and
                ([.platforms[].hash | startswith("sha256-")] | all)
              ' ${./versions.json} >/dev/null
              actionlint -shellcheck=shellcheck ${./.github/workflows/check.yml} ${./.github/workflows/update-amp.yml}
              shellcheck ${./scripts/update.sh}
              touch "$out"
            '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.curl
            pkgs.jq
            pkgs.nixfmt
            pkgs.shellcheck
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
