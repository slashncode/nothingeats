set shell := ["bash", "-euo", "pipefail", "-c"]

workspace := parent_directory(justfile_directory())
owner := "slashncode"
cluster := "nothingeats"

# List recipes
default:
    @just --list

# Install the pinned toolchain from mise.toml
tools:
    mise install

# Clone every repo from repos.txt next to this one (existing folders are skipped)
clone:
    #!/usr/bin/env bash
    set -euo pipefail
    grep -vE '^\s*(#|$)' repos.txt | while read -r repo; do
        target="{{ workspace }}/$repo"
        if [[ -d "$target" ]]; then
            echo "skip   $repo (exists)"
        elif gh repo view "{{ owner }}/$repo" >/dev/null 2>&1; then
            gh repo clone "{{ owner }}/$repo" "$target"
        else
            echo "absent $repo (not on GitHub yet)"
        fi
    done

# Show branch and dirty state of every local repo
status:
    #!/usr/bin/env bash
    set -euo pipefail
    grep -vE '^\s*(#|$)' repos.txt | while read -r repo; do
        target="{{ workspace }}/$repo"
        if [[ ! -d "$target/.git" ]]; then
            printf '%-36s %s\n' "$repo" "-"
            continue
        fi
        branch=$(git -C "$target" branch --show-current)
        changes=$(git -C "$target" status --porcelain | wc -l | tr -d ' ')
        printf '%-36s %-12s %s changed\n' "$repo" "$branch" "$changes"
    done

# Create the local k3d cluster
cluster-up:
    k3d cluster create --config k3d/cluster.yaml

# Delete the local k3d cluster
cluster-down:
    k3d cluster delete {{ cluster }}

# Bootstrap Flux on the local cluster from nothingeats-gitops (needs GITHUB_TOKEN; creates the repo if missing)
flux-bootstrap:
    flux bootstrap github \
        --owner={{ owner }} \
        --personal \
        --private=false \
        --repository=nothingeats-gitops \
        --branch=main \
        --path=clusters/local

# Cluster + Flux in one go
up: cluster-up flux-bootstrap

# Tear everything down
down: cluster-down
