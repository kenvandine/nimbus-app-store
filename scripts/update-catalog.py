#!/usr/bin/env python3
"""Regenerate catalog.json from static snap metadata and live GitHub release info."""

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

STORE_BASE_URL = "https://raw.githubusercontent.com/kenvandine/nimbus-app-store/main"
REPO_ROOT = Path(__file__).parent.parent


def gh_api(path):
    result = subprocess.run(
        ["gh", "api", path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def get_release_info(package_repo, snap_name):
    release = gh_api(f"repos/{package_repo}/releases/latest")
    if not release:
        return None

    snap_asset = next(
        (
            a for a in release.get("assets", [])
            if a["name"].startswith(f"{snap_name}_") and a["name"].endswith("_amd64.snap")
        ),
        None,
    )
    if not snap_asset:
        return None

    return {
        "version": release["tag_name"],
        "release_page": release["html_url"],
        "published_at": release["published_at"],
        "releases": {
            "amd64": {
                "filename": snap_asset["name"],
                "download_url": snap_asset["browser_download_url"],
                "size": snap_asset.get("size"),
            }
        },
    }


def main():
    snaps_dir = REPO_ROOT / "snaps"
    snap_files = sorted(snaps_dir.glob("*.json"))

    snaps = []
    errors = []

    for snap_file in snap_files:
        with open(snap_file) as f:
            snap = json.load(f)

        snap_name = snap["name"]
        package_repo = snap.get("package_repo")
        # A snap with a "channel" is installed from the Snap Store on that
        # channel; one without is sideloaded from its GitHub release asset
        # (the legacy --dangerous path, kept for snaps not yet published).
        channel = snap.get("channel")
        flags = snap.get("install_flags", ["--classic"])

        # Resolve icon URL from local path
        icon_path = snap.get("icon", "")
        if icon_path:
            snap["icon_url"] = f"{STORE_BASE_URL}/{icon_path}"

        if package_repo:
            release_info = get_release_info(package_repo, snap_name)
            if release_info:
                snap.update(release_info)
            elif channel:
                # Store snaps carry their version in the store, not a GitHub
                # release, so a missing release asset is not fatal here.
                print(f"NOTE: no GitHub release for store snap {snap_name}; "
                      f"version will come from the store", file=sys.stderr)
                snap.setdefault("version", None)
            else:
                errors.append(f"no release found for {snap_name} ({package_repo})")
                snap["version"] = None
                snap["releases"] = {}

        if channel:
            # Store snaps are installed by name from a channel — the GitHub
            # release download link is never used, so drop it from the catalog.
            snap.pop("releases", None)
            snap["install_command"] = (
                f"sudo snap install {' '.join(flags)} --channel={channel} {snap_name}"
            )
        elif snap.get("releases", {}).get("amd64"):
            filename = snap["releases"]["amd64"]["filename"]
            snap["install_command"] = (
                f"sudo snap install {' '.join(flags)} {filename}"
            )

        snaps.append(snap)

    catalog = {
        "schema_version": 1,
        "store_name": "Nimbus App Store",
        "store_description": (
            "Snap packages for the Nimbus appliance — AI agents and assistants "
            "published to the Snap Store."
        ),
        "base_url": STORE_BASE_URL,
        "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "snaps": snaps,
    }

    catalog_path = REPO_ROOT / "catalog.json"
    with open(catalog_path, "w") as f:
        json.dump(catalog, f, indent=2)
        f.write("\n")

    print(f"catalog.json updated: {len(snaps)} snaps", file=sys.stderr)
    for err in errors:
        print(f"WARNING: {err}", file=sys.stderr)

    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
