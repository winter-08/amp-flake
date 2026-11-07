#!/usr/bin/env python3
"""Update desktop pins from release metadata without evaluating upstream code."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

LINUX_METADATA = "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=amp-desktop-bin"
MAC_METADATA = "https://raw.githubusercontent.com/ampcode/homebrew-tap/main/Casks/amp@beta.rb"
CURL = ["curl", "--fail", "--location", "--retry", "3", "--retry-all-errors",
        "--connect-timeout", "30", "--max-time", "300", "--show-error", "--silent"]


def fetch_text(url):
    return subprocess.check_output([*CURL, url], text=True)


def unique(pattern, text):
    matches = re.findall(pattern, text, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one metadata field matching {pattern!r}")
    return matches[0]


def sri(hex_hash):
    return "sha256-" + base64.b64encode(bytes.fromhex(hex_hash)).decode()


def releases(linux, mac):
    # Parse only literal version/checksum fields. Never source PKGBUILD or run Ruby.
    version = unique(r"^pkgver=([0-9]+(?:\.[0-9]+)+)$", linux)
    result = {}
    for system, arch, deb_arch in [
        ("x86_64-linux", "x86_64", "amd64"),
        ("aarch64-linux", "aarch64", "arm64"),
    ]:
        digest = unique(rf"^sha256sums_{arch}=\('([0-9a-f]{{64}})'\)$", linux)
        result[system] = {
            "version": version,
            "url": f"https://static.ampcode.com/linux/{version}/amp-desktop-{version}-{deb_arch}.deb",
            "hash": sri(digest),
        }
    short, build = unique(r'^\s*version "([0-9]+(?:\.[0-9]+)*),([0-9]+)"\s*$', mac)
    digest = unique(r'^\s*sha256 "([0-9a-f]{64})"\s*$', mac)
    # Fail closed if upstream changes the platform or minimum OS contract.
    unique(r'^\s*depends_on arch: (:arm64)\s*$', mac)
    unique(r'^\s*depends_on macos: (:tahoe)\s*$', mac)
    version = f"{short}-{build}"
    result["aarch64-darwin"] = {
        "version": version,
        "url": f"https://static.ampcode.com/mac/Amp-{version}.dmg",
        "hash": sri(digest),
    }
    return {"platforms": result}


def verify_download(url, expected):
    with tempfile.TemporaryDirectory(prefix="amp-desktop-download-") as directory:
        target = Path(directory) / "artifact"
        subprocess.run([*CURL, "--output", str(target), url], check=True)
        with target.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").digest()
        actual = "sha256-" + base64.b64encode(digest).decode()
        if actual != expected:
            raise ValueError(f"Checksum mismatch for {url}: expected {expected}, got {actual}")


def version_key(version):
    if not re.fullmatch(r"[0-9]+(?:[.-][0-9]+)*", version):
        raise ValueError(f"Invalid desktop version: {version!r}")
    return tuple(int(part) for part in re.split(r"[.-]", version))


def update(path, fetch=fetch_text, verify=verify_download):
    current = json.loads(path.read_text())
    desired = releases(fetch(LINUX_METADATA), fetch(MAC_METADATA))
    if set(current["platforms"]) != set(desired["platforms"]):
        raise ValueError("Unexpected desktop platform set")
    changed = []
    for system, new in desired["platforms"].items():
        old = current["platforms"][system]
        if new == old:
            continue
        if version_key(new["version"]) <= version_key(old["version"]):
            raise ValueError(f"Refusing downgrade or changed immutable release for {system}")
        changed.append((system, new))
    if not changed:
        print("Amp desktop is already current; no artifacts downloaded.")
        return False
    # All changed artifacts must verify before replacing any pins.
    for system, new in changed:
        print(f"Verifying {system} {new['version']}...")
        verify(new["url"], new["hash"])
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent,
                                         prefix=".desktop-versions.", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(desired, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print("Updated desktop-versions.json.")
    return True


if __name__ == "__main__":
    update(Path(__file__).resolve().parent.parent / "desktop-versions.json")
