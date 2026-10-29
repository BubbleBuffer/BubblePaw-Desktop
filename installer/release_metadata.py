#!/usr/bin/env python3
"""Validate release identity and generate the downloadable update manifest."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone
from urllib.parse import quote


VERSION = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
)


def validate_version(value):
    match = VERSION.fullmatch(value)
    if not match or any(
        part.isdigit() and len(part) > 1 and part.startswith("0")
        for part in (match.group(4) or "").split(".")
    ):
        raise ValueError("pubspec version must be X.Y.Z[-suffix], without +build metadata")
    return value


def asset_names(version):
    return {
        "windows-x64": f"BubblePaw-{version}-windows-x64-setup.exe",
        "linux-x64": f"BubblePaw-{version}-linux-x64.tar.gz",
    }


def prepare(channel, tag, sha, pubspec=Path("pubspec.yaml"), now=None):
    matches = re.findall(r"^version:\s*([^\s#]+)\s*(?:#.*)?$", pubspec.read_text(), re.M)
    if len(matches) != 1:
        raise ValueError("pubspec.yaml must have exactly one version field")
    base = validate_version(matches[0])
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("source commit must be a full lowercase Git SHA")
    if channel == "stable":
        if tag != f"v{base}":
            raise ValueError(f"tag {tag!r} must exactly match pubspec version v{base}")
        version = base
    else:
        tag = "nightly"
        date = (now or datetime.now(timezone.utc)).strftime("%Y%m%d")
        version = f"{base}-nightly.{date}+{sha[:7]}"
    return {"channel": channel, "tag": tag, "sha": sha, "version": version,
            "build_name": version.split("+", 1)[0]}


def manifest(directory, channel, version, tag, repository, now=None):
    if channel not in ("stable", "nightly"):
        raise ValueError("unsupported channel")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("invalid repository")
    release_url = f"https://github.com/{repository}/releases/tag/{quote(tag, safe='')}"
    download_url = f"https://github.com/{repository}/releases/download/{quote(tag, safe='')}"
    assets = {}
    for platform, name in asset_names(version).items():
        path = directory / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"missing or empty release asset: {path}")
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        assets[platform] = {
            "url": f"{download_url}/{quote(name, safe='')}",
            "sha256": digest,
            "size": path.stat().st_size,
            "kind": "inno" if platform == "windows-x64" else "tar.gz",
        }
    result = {
        "channel": channel, "version": version,
        "published_at": (now or datetime.now(timezone.utc)).isoformat().replace("+00:00", "Z"),
        "notes_url": release_url, "assets": assets,
    }
    manifest_path = directory / "update.json"
    manifest_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    names = [*asset_names(version).values(), "update.json"]
    checksums = []
    for name in names:
        with (directory / name).open("rb") as stream:
            checksums.append(f"{hashlib.file_digest(stream, 'sha256').hexdigest()}  {name}\n")
    (directory / "SHA256SUMS").write_text("".join(checksums), encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    identity = commands.add_parser("prepare")
    identity.add_argument("--channel", choices=("stable", "nightly"), required=True)
    identity.add_argument("--tag", default="")
    identity.add_argument("--sha", required=True)
    identity.add_argument("--output", type=Path)
    publish = commands.add_parser("manifest")
    publish.add_argument("--directory", type=Path, required=True)
    publish.add_argument("--channel", required=True)
    publish.add_argument("--version", required=True)
    publish.add_argument("--tag", required=True)
    publish.add_argument("--repository", required=True)
    args = parser.parse_args()
    if args.command == "prepare":
        actual_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
        if actual_sha != args.sha:
            raise ValueError("checkout does not match the requested source commit")
        result = prepare(args.channel, args.tag, args.sha)
        if args.output:
            with args.output.open("a", encoding="utf-8") as output:
                for key, value in result.items():
                    output.write(f"{key}={value}\n")
        print(json.dumps(result))
    else:
        print(json.dumps(manifest(args.directory, args.channel, args.version, args.tag, args.repository)))


if __name__ == "__main__":
    main()
