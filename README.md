# amp-flake

A reproducible, automatically updated Nix flake for [Amp](https://ampcode.com),
the coding agent for terminals, editors, and desktop. The default package remains
the CLI; the desktop app is available separately as `amp-desktop`.

## Run Amp

```console
nix run github:winter-08/amp-flake
```

Install it into your profile:

```console
nix profile install github:winter-08/amp-flake
```

Or add the overlay to another flake:

```nix
{
  inputs.amp.url = "github:winter-08/amp-flake";

  outputs = { nixpkgs, amp, ... }: {
    # Add amp.overlays.default to your nixpkgs overlays.
  };
}
```

Amp is proprietary, so overlay consumers must allow the `amp` package with
`nixpkgs.config.allowUnfreePredicate`. Direct `nix run` and `nix profile`
usage through this flake already handles that configuration.

The package sets `AMP_SKIP_UPDATE_CHECK=1` because Nix store paths are
immutable. Updates are delivered through this flake instead of Amp's built-in
self-updater.

## Supported systems

- `aarch64-darwin`
- `x86_64-darwin`
- `aarch64-linux`
- `x86_64-linux` (uses Amp's baseline build for compatibility)

## Desktop app

```console
nix run github:winter-08/amp-flake#amp-desktop
nix profile install github:winter-08/amp-flake#amp-desktop
```

Desktop supports `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`.
There is no upstream Intel macOS desktop build. The native macOS app requires
**macOS 26 Tahoe or later**, independently of Nix's supported host platforms.
On macOS the package installs `Applications/Amp.app` and an `amp-desktop`
launcher. Home Manager's normal application integration can expose the app to
Finder. On Linux the package preserves the upstream desktop entry, icons, and
sign-in callback URL scheme. The host must support Chromium's user-namespace
sandbox; this package does not disable the sandbox.

Both packages are available in `overlays.default`. For overlay use, allow both
`amp` and `amp-desktop` in your unfree predicate. For example:

```nix
nixpkgs.config.allowUnfreePredicate = pkg:
  builtins.elem (nixpkgs.lib.getName pkg) [ "amp" "amp-desktop" ];
environment.systemPackages = [ pkgs.amp pkgs.amp-desktop ];
```

Desktop releases are pinned separately in `desktop-versions.json`: Linux uses
the official versioned `.deb` downloads, and macOS uses the official versioned
DMG from [Amp's Homebrew cask](https://github.com/ampcode/homebrew-tap/blob/main/Casks/amp%40beta.rb).
The Linux version/checksums come from the
[upstream-maintained AUR package](https://aur.archlinux.org/packages/amp-desktop-bin).
Desktop updates are currently **manual**, independent of the CLI update job.
Update the platform's version, URL, and SHA-256 together and run the checks.
Do not use the app's self-updater to modify immutable Nix store installations;
update this flake input and rebuild instead.

## Declarative configuration with Home Manager

Add this flake as `inputs.amp`, then import its module in your Home Manager
configuration. No overlay is required for the module's default packages:

```nix
{ inputs, ... }: {
  imports = [ inputs.amp.homeManagerModules.default ];

  programs.amp = {
    enable = true; # CLI, also used by the native macOS app's local runner
    desktop.enable = true; # independent: can be enabled without the CLI
    settings = {
      "amp.notifications.enabled" = true;
      "amp.permissions" = [
        { tool = "Bash"; matches = { cmd = "git push*"; }; action = "ask"; }
      ];
    };
  };
}
```

Pass `inputs` through `extraSpecialArgs` if using that example's argument.
`programs.amp.package` and `programs.amp.desktop.package` can override packages.
A nonempty `programs.amp.settings` writes `~/.config/amp/settings.json` on both
Linux and macOS. This is the documented [CLI settings](https://ampcode.com/docs/cli/settings)
file, not desktop UI preferences. The [native macOS local runner](https://ampcode.com/docs/apps/mac/runner)
uses the installed CLI and its settings/sign-in; ensure `amp` is on your login
shell's PATH. These settings do not configure cloud orbs or the Linux desktop
web shell. Desktop appearance and notification controls remain in the app.

When managed, edit the Nix configuration and rebuild instead of using
`amp config edit`. Home Manager will refuse to overwrite an existing settings
file without a backup/migration; preserve its contents in `settings` first.
An empty settings attribute set leaves the existing file alone. Authentication,
workspace state, browser storage, and desktop UI preferences remain writable
and are not managed by this module.

**Never put credentials or API keys in `settings`: generated files are in the
world-readable Nix store.** Sign in normally; the separate CLI credentials at
`~/.local/share/amp/secrets.json` are not managed. Settings must be enabled with
`programs.amp.enable`; enabling only the desktop installs just the desktop app.

## Automatic updates

[The update workflow](.github/workflows/update-amp.yml) checks Amp's official
release metadata every six hours. A no-op run downloads only the version file.
When a release changes, it:

1. fetches the immutable, versioned checksums for every supported platform;
2. updates `versions.json` atomically;
3. evaluates the flake for all four systems;
4. builds and smoke-tests the Linux package; and
5. commits the validated update directly to `main`.

All third-party actions are pinned to full commit SHAs, workflow permissions are
minimal, update runs are serialized, and curl retries transient failures.

Run the same updater locally with:

```console
nix develop --command ./scripts/update.sh
```

## Licensing

The flake and update tooling in this repository are MIT licensed. Amp is
downloaded from its official distribution service and remains subject to Amp's
own terms and license.
