# Downstream development

This fork keeps generic contributions separate from local production changes.

## Branch roles

- `upstream/master` is the external canonical upstream branch maintained by `haugene/docker-transmission-openvpn`.
- `upstream-sync` is the clean generic integration branch in this fork. It contains upstream-compatible changes and must not contain `AGENTS.md`, this document, or downstream-only workflow cleanup.
- `master` is this fork's local production branch. It contains local agent and project policy and may eventually contain PIA-specialized behavior and local image or runtime optimizations.

For generic work, use `upstream-sync` → generic feature branch → `upstream-sync` → `master`. For PIA-specific or other local work, use `master` → local feature branch → `master`. Local-only changes must never flow back into `upstream-sync`.

## Local-only files

`AGENTS.md`, this `docs/downstream-development.md` document, and the removal of upstream maintainer automation are local-only. Never add them to `upstream-sync` or include them in commits or pull requests intended for `haugene/docker-transmission-openvpn`.

This fork has no active GitHub Actions workflows. Local validation guidance is in `AGENTS.md`. Future workflows need an explicit review of publishing targets, secrets, branch triggers, and repository assumptions before they are added.

## Upstream-first discovery

Before starting each new implementation or audit task, inspect the relevant upstream issues, pull requests, discussions, commits, documentation, and maintainer guidance. Use that discovery to classify the task as generic or local-only before creating a branch.

Before opening an upstream pull request, compare its final diff with `upstream/master` and confirm that no local-only files or downstream-specific changes are included.
