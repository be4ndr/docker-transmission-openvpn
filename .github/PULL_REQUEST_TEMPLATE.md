## Change

Describe the change and why it is needed.

## Branch and scope

- [ ] Generic change targeting `upstream-sync`
- [ ] Local-only change targeting `master`

For generic changes intended for upstream, compare the final diff with `upstream/master` and exclude `AGENTS.md`, `docs/downstream-development.md`, and other downstream-only changes. Provider configuration contributions for upstream belong in [vpn-configs-contrib](https://github.com/haugene/vpn-configs-contrib).

## Breaking or compatibility changes

State whether this change breaks existing behavior, changes configuration or environment variables, changes compatibility, or is backwards compatible.

## Validation

List the checks run and any behavior that remains unverified. Include local runtime testing when the change affects VPN or tunnel behavior. Remove credentials and tokens from logs before sharing them.

## Documentation

Note any user-facing documentation updated, or explain why none was needed.
