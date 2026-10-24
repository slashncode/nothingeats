# CLAUDE.md

Hub repo of NothingEats: architecture overview (`README.md`), the pinned toolchain (`mise.toml`), workspace recipes (`justfile`), and the local k3d cluster config (`k3d/cluster.yaml`).

The cross-repo plan and session rules live in the workspace root one level up (`../CLAUDE.md`), if that workspace is checked out. Read it first.

## Commands

- `mise install` — install the pinned toolchain
- `just --list` — all recipes
- `just clone` — clone every repo from `repos.txt` next to this one
- `just status` — branch and dirty state of every local repo
- `just cluster-up` / `just cluster-down` — local k3d cluster
- `just flux-bootstrap` — bootstrap Flux from `nothingeats-gitops` (`clusters/local`), needs `GITHUB_TOKEN`
- `just up` / `just down` — cluster + Flux in one go
- `just dev <service>` / `just dev-stop <service>` — Tilt inner loop for one service (Flux suspended meanwhile)

## Conventions

- Tool versions are pinned exactly in `mise.toml`; `kubectl` matches the k3s minor version in `k3d/cluster.yaml`.
- k3s' bundled Traefik is disabled; Traefik is installed by Flux so its version and Gateway API config live in git.
- Infra is reachable from the host on 15432 (Postgres), 19094 (Kafka), 19200 (Elasticsearch), 16379 (Valkey), 11025 (Mailpit SMTP). The k3d mappings target NodePorts 30432/30094/30200/30379/30025, which must match the NodePort services in `nothingeats-gitops`; Kafka's external listener must advertise `localhost:19094`.
- New repos are added to `repos.txt` and to the table in `README.md`.
