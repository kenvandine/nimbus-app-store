# Nimbus App Store

A lightweight snap metadata backend for the [Nimbus appliance](https://github.com/kenvandine/nimbus) project. Provides a machine-readable catalog of AI agent snaps that can be side-loaded before they are published to the official Snap Store.

## Catalog

The main metadata file is [`catalog.json`](catalog.json), served at:

```
https://raw.githubusercontent.com/kenvandine/nimbus-app-store/main/catalog.json
```

It is regenerated automatically every day and whenever snap metadata or icons change. The catalog is self-describing — see [Schema](#schema) below.

## Snaps

| Snap | Title | Version | License |
|------|-------|---------|---------|
| `openclaw` | OpenClaw | ![openclaw](https://img.shields.io/github/v/release/kenvandine/openclaw-snap?label=) | MIT |
| `hermes-agent` | Hermes AI Agent | ![hermes](https://img.shields.io/github/v/release/kenvandine/hermes-snap?label=) | MIT |
| `nullclaw` | NullClaw | ![nullclaw](https://img.shields.io/github/v/release/kenvandine/nullclaw-snap?label=) | MIT |
| `odysseus` | Odysseus | ![odysseus](https://img.shields.io/github/v/release/kenvandine/odysseus-snap?label=) | AGPL-3.0 |
| `picoclaw` | PicoClaw | ![picoclaw](https://img.shields.io/github/v/release/kenvandine/picoclaw-snap?label=) | MIT |
| `zeroclaw` | ZeroClaw | ![zeroclaw](https://img.shields.io/github/v/release/kenvandine/zeroclaw-snap?label=) | Apache-2.0 |

## Side-loading

All snaps use classic confinement and must be installed with `--dangerous`:

```
sudo snap install --classic --dangerous <snap-file>.snap
```

The `install_command` field in each catalog entry contains the exact command for the current version.

## Schema

`catalog.json` has this top-level shape:

```json
{
  "schema_version": 1,
  "store_name": "Nimbus App Store",
  "store_description": "...",
  "base_url": "https://raw.githubusercontent.com/kenvandine/nimbus-app-store/main",
  "updated_at": "<ISO 8601>",
  "snaps": [ ... ]
}
```

Each snap entry:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Snap package name |
| `title` | string | Human-readable title |
| `summary` | string | One-line description |
| `description` | string | Full description (newline-separated paragraphs) |
| `version` | string | Latest released version |
| `grade` | string | `stable` or `devel` |
| `confinement` | string | `classic` or `strict` |
| `license` | string | SPDX license identifier |
| `categories` | array | Category tags |
| `icon` | string | Relative path to icon asset |
| `icon_url` | string | Absolute URL to icon asset |
| `screenshots` | array | List of screenshot objects (path + url) |
| `links.website` | string | Upstream project website |
| `links.source_code` | string | Snap packaging repository URL |
| `links.issues` | string | Issue tracker URL |
| `package_repo` | string | `owner/repo` of the snap packaging repository |
| `install_flags` | array | Flags required for `snap install` |
| `releases.amd64.filename` | string | Snap filename for amd64 |
| `releases.amd64.download_url` | string | Direct download URL |
| `releases.amd64.size` | integer | File size in bytes |
| `release_page` | string | GitHub release page URL |
| `published_at` | string | ISO 8601 release timestamp |
| `install_command` | string | Full `snap install` command for the current version |

## Assets

Icons are stored under `assets/<snap-name>/` and served via `raw.githubusercontent.com`. Screenshots go in `assets/<snap-name>/screenshots/` — add images there and list them in the snap's `snaps/<name>.json` to include them in the catalog.

## Updating the catalog

The catalog is regenerated automatically by the [update workflow](.github/workflows/update.yaml). To run it locally (requires the `gh` CLI):

```
python3 scripts/update-catalog.py
```

## Adding a snap

1. Create `snaps/<name>.json` with the static metadata (see existing files for the schema).
2. Add the icon to `assets/<name>/icon.png` (or `.svg`).
3. Open a pull request — the update workflow will generate the catalog entry on merge.
