#!/usr/bin/env python3
"""Stage complete GitHub assets before publishing a stable or rolling release."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

from release_metadata import asset_names


class GitHub:
    def __init__(self):
        self.base = os.environ.get("GITHUB_API_URL", "https://api.github.com")
        self.repo = os.environ["GITHUB_REPOSITORY"]
        self.token = os.environ["GH_TOKEN"]

    def request(self, method, path, data=None, missing_ok=False, content_type="application/json"):
        url = path if path.startswith("https://") else f"{self.base}/repos/{self.repo}/{path}"
        body = json.dumps(data).encode() if data is not None and not isinstance(data, bytes) else data
        request = Request(url, data=body, method=method, headers={
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json", "Content-Type": content_type,
            "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "BubblePaw-release",
        })
        try:
            with urlopen(request, timeout=120) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except HTTPError as error:
            if missing_ok and error.code == 404:
                return None
            # GitHub's response identifies permission/ruleset failures without exposing tokens.
            raise RuntimeError(f"GitHub {method} {path}: HTTP {error.code}: "
                               f"{error.read().decode(errors='replace')}") from error

    def tag_commit(self, tag):
        reference = self.request("GET", f"git/ref/tags/{quote(tag, safe='')}", missing_ok=True)
        if reference is None:
            return None
        obj = reference["object"]
        for _ in range(10):
            if obj["type"] == "commit":
                return obj["sha"]
            if obj["type"] != "tag":
                raise ValueError("release tag does not point to a commit")
            obj = self.request("GET", f"git/tags/{obj['sha']}")["object"]
        raise ValueError("release tag annotation chain is too deep")


def nightly_unchanged(api, sha):
    if api.tag_commit("nightly") != sha:
        return False
    release = api.request("GET", "releases/tags/nightly", missing_ok=True)
    if release is None or release["draft"]:
        return False
    names = {asset["name"] for asset in release["assets"] if asset["state"] == "uploaded"}
    # A leftover tag or partially uploaded release must be repairable by rerunning.
    return ("update.json" in names and "SHA256SUMS" in names
            and any(name.endswith("-windows-x64-setup.exe") for name in names)
            and any(name.endswith("-linux-x64.tar.gz") for name in names))


def validate_assets(directory, channel, version, tag, repository):
    names = [*asset_names(version).values(), "update.json", "SHA256SUMS"]
    if any(not (directory / name).is_file() for name in names):
        raise ValueError("release directory is missing required files")
    update = json.loads((directory / "update.json").read_text(encoding="utf-8"))
    if update["channel"] != channel or update["version"] != version:
        raise ValueError("manifest release identity does not match publication")
    sums = {}
    for line in (directory / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
        digest, name = line.split("  ", 1)
        if not re.fullmatch("[0-9a-f]{64}", digest) or name in sums:
            raise ValueError("invalid checksum manifest")
        sums[name] = digest
    if set(sums) != set(names[:-1]):
        raise ValueError("checksum manifest has unexpected entries")
    for name in names[:-1]:
        with (directory / name).open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != sums[name]:
                raise ValueError(f"checksum mismatch: {name}")
    for platform, name in asset_names(version).items():
        asset = update["assets"][platform]
        expected_url = f"https://github.com/{repository}/releases/download/{quote(tag, safe='')}/{quote(name, safe='')}"
        if (asset["url"] != expected_url or asset["sha256"] != sums[name]
                or asset["size"] != (directory / name).stat().st_size):
            raise ValueError(f"incorrect asset manifest: {platform}")
    return names


def publish(api, directory, channel, version, tag, sha):
    names = validate_assets(directory, channel, version, tag, api.repo)
    old = api.request("GET", f"releases/tags/{quote(tag, safe='')}", missing_ok=True)
    if channel == "stable" and old is not None:
        raise ValueError("stable release already exists; refusing to replace it")
    if channel == "stable" and api.tag_commit(tag) != sha:
        raise ValueError("stable tag no longer matches the built source commit")
    if channel == "nightly" and old is not None and old.get("immutable"):
        raise ValueError("rolling nightly cannot replace an immutable release")
    stage_tag = (f"nightly-staging-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}"
                 if channel == "nightly" else tag)
    staged = api.request("POST", "releases", {
        "tag_name": stage_tag, "target_commitish": sha,
        "name": f"BubblePaw {version}",
        "body": (f"{'Nightly build' if channel == 'nightly' else 'Release'} of `{sha}`.\n\n"
                 "Download the Windows installer or extract the Linux bundle. "
                 "Checksums are in SHA256SUMS; update metadata is in update.json."),
        "draft": True, "prerelease": channel == "nightly", "make_latest": "false",
    })
    replaced = False
    try:
        upload_url = staged["upload_url"].split("{", 1)[0]
        for name in names:
            data = (directory / name).read_bytes()
            uploaded = api.request("POST", f"{upload_url}?name={quote(name, safe='')}",
                                   data, content_type="application/octet-stream")
            if uploaded["state"] != "uploaded" or uploaded["size"] != len(data):
                raise ValueError(f"incomplete GitHub asset upload: {name}")
            if uploaded.get("digest") and uploaded["digest"] != f"sha256:{hashlib.sha256(data).hexdigest()}":
                raise ValueError(f"GitHub asset digest mismatch: {name}")
        if channel == "nightly":
            # All builds, local validation and uploads have succeeded before touching the old release.
            if old is not None:
                api.request("DELETE", f"releases/{old['id']}")
            replaced = True
            api.request("DELETE", "git/refs/tags/nightly", missing_ok=True)
            api.request("POST", "git/refs", {"ref": "refs/tags/nightly", "sha": sha})
        api.request("PATCH", f"releases/{staged['id']}", {
            "tag_name": tag, "target_commitish": sha, "draft": False,
            # Suffix-bearing stable versions are full releases and explicitly become latest.
            "prerelease": channel == "nightly",
            "make_latest": "false" if channel == "nightly" else "true",
        })
    except Exception:
        if not replaced:
            api.request("DELETE", f"releases/{staged['id']}")
        else:
            print(f"Publication interrupted after nightly replacement; staged assets remain in draft release {staged['id']}.")
        raise
    if channel == "nightly":
        # GitHub may have materialized the draft's temporary tag; it is no longer used.
        api.request("DELETE", f"git/refs/tags/{stage_tag}", missing_ok=True)
    print(f"Published {channel} {version} at https://github.com/{api.repo}/releases/tag/{tag}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("nightly-check", "publish"))
    parser.add_argument("--sha", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--directory", type=Path)
    parser.add_argument("--channel", choices=("stable", "nightly"))
    parser.add_argument("--version")
    parser.add_argument("--tag")
    args = parser.parse_args()
    api = GitHub()
    if args.command == "nightly-check":
        should_build = not nightly_unchanged(api, args.sha)
        if args.output:
            with args.output.open("a", encoding="utf-8") as output:
                output.write(f"should_build={str(should_build).lower()}\n")
        print("New main commit: build nightly" if should_build else "Main is unchanged: skip nightly")
    else:
        if not all((args.directory, args.channel, args.version, args.tag)):
            parser.error("publish requires --directory, --channel, --version and --tag")
        publish(api, args.directory, args.channel, args.version, args.tag, args.sha)


if __name__ == "__main__":
    main()
