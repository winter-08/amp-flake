#!/usr/bin/env bash
set -euo pipefail

readonly storage_base="https://static.ampcode.com/cli"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
repository_root="$(dirname -- "$script_dir")"
readonly repository_root
readonly versions_file="$repository_root/versions.json"

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

fetch() {
  curl \
    --fail \
    --location \
    --retry 3 \
    --retry-all-errors \
    --show-error \
    --silent \
    "$1"
}

fetch_hash() {
  local version="$1"
  local target="$2"
  local checksum

  checksum="$(fetch "$storage_base/$version/$target-amp.sha256")"
  checksum="${checksum%%[[:space:]]*}"

  if [[ ! "$checksum" =~ ^[0-9a-f]{64}$ ]]; then
    printf 'error: invalid checksum for %s: %s\n' "$target" "$checksum" >&2
    return 1
  fi

  nix hash convert --hash-algo sha256 --to sri "$checksum"
}

for command in curl jq nix; do
  need_command "$command"
done

latest_version="$(fetch "$storage_base/cli-version.txt")"
latest_version="${latest_version%%[[:space:]]*}"

if [[ ! "$latest_version" =~ ^[0-9]+(\.[0-9]+)*-[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
  printf 'error: invalid Amp version: %s\n' "$latest_version" >&2
  exit 1
fi

current_version="$(jq --raw-output '.version' "$versions_file")"
if [[ "$current_version" == "$latest_version" ]]; then
  printf 'Amp is already current at %s.\n' "$current_version"
  exit 0
fi

printf 'Updating Amp from %s to %s...\n' "$current_version" "$latest_version"

darwin_arm64_hash="$(fetch_hash "$latest_version" darwin-arm64)"
darwin_x64_hash="$(fetch_hash "$latest_version" darwin-x64)"
linux_arm64_hash="$(fetch_hash "$latest_version" linux-arm64)"
linux_x64_hash="$(fetch_hash "$latest_version" linux-x64-baseline)"

temporary_file="$(mktemp "$repository_root/.versions.json.XXXXXX")"
trap 'rm -f -- "$temporary_file"' EXIT

jq --null-input \
  --arg version "$latest_version" \
  --arg darwinArm64Hash "$darwin_arm64_hash" \
  --arg darwinX64Hash "$darwin_x64_hash" \
  --arg linuxArm64Hash "$linux_arm64_hash" \
  --arg linuxX64Hash "$linux_x64_hash" \
  '{
    version: $version,
    platforms: {
      "aarch64-darwin": {
        target: "darwin-arm64",
        hash: $darwinArm64Hash
      },
      "aarch64-linux": {
        target: "linux-arm64",
        hash: $linuxArm64Hash
      },
      "x86_64-darwin": {
        target: "darwin-x64",
        hash: $darwinX64Hash
      },
      "x86_64-linux": {
        target: "linux-x64-baseline",
        hash: $linuxX64Hash
      }
    }
  }' >"$temporary_file"

mv -- "$temporary_file" "$versions_file"
trap - EXIT

printf 'Updated versions.json to Amp %s.\n' "$latest_version"
