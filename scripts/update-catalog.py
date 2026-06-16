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
        "install_command": (
            "sudo snap install "
            + " ".join(["--classic", "--dangerous"])
            + f" {snap_asset['name']}"
        ),
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

        # Resolve icon URL from local path
        icon_path = snap.get("icon", "")
        if icon_path:
            snap["icon_url"] = f"{STORE_BASE_URL}/{icon_path}"

        if package_repo:
            release_info = get_release_info(package_repo, snap_name)
            if release_info:
                snap.update(release_info)
            else:
                errors.append(f"no release found for {snap_name} ({package_repo})")
                snap["version"] = None
                snap["releases"] = {}

        snaps.append(snap)

    catalog = {
        "schema_version": 1,
        "store_name": "Nimbus App Store",
        "store_description": (
            "Snap packages for the Nimbus appliance — AI agents and assistants "
            "available for side-loading before they are published to the Snap Store."
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
