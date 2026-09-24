# Agent guide

## Project map

This repository builds `haugene/transmission-openvpn`: Transmission runs when an OpenVPN tunnel is up and stops when it goes down. `Dockerfile` builds the main Ubuntu based image on `haugene/transmission-base`; `openvpn/start.sh` prepares VPN configuration, credentials, routes, and firewall rules. OpenVPN calls `openvpn/tunnelUp.sh` and `openvpn/tunnelDown.sh`, which manage Transmission and Privoxy. See `docs/building-blocks.md` for the lifecycle and `docs/config-options.md` for public settings.

- `openvpn/`: startup, provider setup, config downloads and edits, tunnel callbacks, and environment persistence.
- `transmission/`: daemon lifecycle, default settings, environment overrides, and user/permission setup.
- `privoxy/scripts/`, `scripts/`: proxy lifecycle, health check, routing, and self healing.
- `proxy/`, `plugins/rss/`: separate nginx proxy and RSS images; each has its own Dockerfile.
- `docs/`, `mkdocs.yml`: MkDocs Material site. `README.md` and `docker-compose.yml` provide usage examples.
- `.github/workflows/`: multi architecture image builds and MkDocs deployment.

## Development and validation

Use a Linux environment with Bash and Docker for runtime work: the image uses Linux networking, `/dev/net/tun`, `NET_ADMIN`, `ip`, iptables/UFW, and OpenVPN callbacks. The main Dockerfile installs Python and shell utilities in the image; the docs workflow uses Python 3.11 with `mkdocs` and `mkdocs-material`. The Compose file is an example using the published image, not a local build definition.

- Build locally from the matching contexts: `docker build -t transmission-openvpn:local .`, `docker build -t transmission-openvpn-proxy:local ./proxy`, or `docker build -t transmission-rss:local ./plugins/rss`. `.github/workflows/docker-image-builds.yml` is the authority for CI contexts and platforms (`linux/amd64`, `linux/arm`, `linux/arm64`). These builds download base images and dependencies.
- For docs, install `mkdocs` and `mkdocs-material`, then run `mkdocs build` from the root. `.github/workflows/mkdocs.yml` deploys the site on `master`.
- No checked in automated test suite or lint/static analysis job is defined. For changed Bash scripts, run `bash -n` on the affected files; for changed Python, run `python3 -m py_compile` on the affected files. For changes to image behavior, build the affected image and test the relevant VPN/tunnel behavior in a suitable Docker environment. Do not claim a live VPN check unless one was actually run.
- Before finishing, inspect the diff, run `git diff --check`, and run `git status --short`; report any validation that could not run.

## Change rules and sensitive areas

Keep changes focused and backwards compatible with existing environment variables, persisted `/config/transmission-home` settings, `/data` downloads, provider selection, and user mounted `/scripts` hooks (`docs/config-options.md`). Update the docs when changing user facing configuration. The PR template asks for local testing, no commented out code, and PRs against `dev`; it directs VPN provider configuration updates to `haugene/vpn-configs-contrib` rather than this repository.

Treat `openvpn/start.sh`, tunnel callbacks, `transmission/start.sh`, `scripts/route-pre-down.sh`, provider scripts, and firewall/routing code as security sensitive: changes can affect the VPN only startup guarantee or leak traffic. Preserve the tunnel address binding and stop behavior when editing them.

`CREATE_TUN_DEVICE=true` is the image default and recreates `/dev/net/tun` during startup. When mapping the host's `/dev/net/tun` into the container, set `CREATE_TUN_DEVICE=false`; startup then checks that the path is a character device and can be opened for reading and writing. Keep `NET_ADMIN` for OpenVPN and network setup. When changing TUN handling, keep `docker-compose.yml` and the configuration examples in sync, and test both device modes and failure paths in a suitable Docker environment.

Credentials can come from environment variables or `/run/secrets/openvpn_creds` and `/run/secrets/rpc_creds`; startup writes or links credential files under `/config`. Never commit real credentials, downloaded VPN configuration, generated `settings.json`, or persisted runtime files. Example credentials in `README.md` and `docker-compose.yml` are placeholders. Check logs and shell tracing for secret exposure when changing configuration handling.

Follow the checked in PR template and CI workflows above; personal Codex skills are not repository policy.

## Secrets and VPN Credentials

- Never place VPN credentials, tokens, passwords, or other secrets in prompts, Git, run artifacts, logs, documentation, or command-line arguments.
- For local PIA integration tests, credentials may be provided through an external environment file outside the repository and outside `~/ai`, for example:

  `~/.config/transmission-openvpn/pia.env`

- Treat credential files as opaque secret inputs.
- Agents may reference the file path and pass it to Docker with `--env-file`, but must not read, display, copy, modify, or persist its contents.
- Do not record secret values in `task.md`, `research.md`, `plan.md`, `implementation.md`, `review.md`, `qa.md`, or `metrics.json`.
- Do not commit credential files.
- Local credential files should have restrictive permissions such as `chmod 600`.
- Prefer test containers and temporary test volumes; do not reuse production configuration or data unless explicitly approved.