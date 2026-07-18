# amp-flake

A reproducible, automatically updated Nix flake for [Amp](https://ampcode.com),
the coding agent for terminals and editors.

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
