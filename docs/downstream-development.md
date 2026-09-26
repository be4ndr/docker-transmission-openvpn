# Downstream development

This fork keeps generic contributions separate from local production changes.

## Branch roles

- `upstream/master` is the external canonical upstream branch maintained by `haugene/docker-transmission-openvpn`.
- `upstream-sync` is the clean generic integration branch in this fork. It contains upstream-compatible changes and must not contain downstream-only files.
- `master` is this fork's local production branch. It may contain PIA-specialized behavior and local image or runtime optimizations, along with downstream policy files.

Start generic feature branches from `upstream-sync`. Start PIA-specific or otherwise local-only branches from `master`. Merge generic changes into `upstream-sync` first, then integrate them into `master`. Local-only changes must never merge back into `upstream-sync`.

## Local-only files

`AGENTS.md` and this `docs/downstream-development.md` document are local-only. Never add them to `upstream-sync` or include them in commits or pull requests intended for `haugene/docker-transmission-openvpn`.

## Upstream-first discovery

Before starting each new task, inspect the relevant upstream issues, pull requests, discussions, commits, documentation, and maintainer guidance. Use that discovery to classify the task as generic or local-only before creating a branch.

Before opening an upstream pull request, compare its final diff with `upstream/master` and confirm that no local-only files or downstream-specific changes are included.
