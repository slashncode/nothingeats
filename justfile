set shell := ["bash", "-euo", "pipefail", "-c"]

workspace := parent_directory(justfile_directory())
owner := "slashncode"
cluster := "nothingeats"
context := "k3d-nothingeats"

# List recipes
default:
    @just --list

# Install the pinned toolchain from mise.toml
tools: link-toolchain
    mise install

# Link mise.toml into the workspace root so every sibling repo gets the same toolchain
link-toolchain:
    #!/usr/bin/env bash
    set -euo pipefail
    link="{{ workspace }}/mise.toml"
    if [[ ! -e "$link" ]]; then
        ln -s "{{ justfile_directory() }}/mise.toml" "$link"
        echo "linked $link"
    fi
    mise trust --quiet "$link"

# Clone every repo from repos.txt next to this one (existing folders are skipped)
clone: link-toolchain
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

# Put the SOPS age key into the cluster so Flux can decrypt secrets
sops-key:
    #!/usr/bin/env bash
    set -euo pipefail
    key="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/nothingeats.agekey}"
    if [[ ! -f "$key" ]]; then
        echo "Missing age key $key. Restore it from your password manager or create one with: age-keygen -o $key" >&2
        exit 1
    fi
    kubectl --context {{ context }} create namespace flux-system --dry-run=client -o yaml | kubectl --context {{ context }} apply -f -
    kubectl --context {{ context }} -n flux-system create secret generic sops-age --from-file=age.agekey="$key" \
        --dry-run=client -o yaml | kubectl --context {{ context }} apply -f -

# Install Flux from nothingeats-gitops (clusters/local), with image automation and a read-write deploy key
flux-bootstrap:
    GITHUB_TOKEN="$(gh auth token)" flux bootstrap github \
        --context={{ context }} \
        --owner={{ owner }} \
        --personal \
        --private=false \
        --repository=nothingeats-gitops \
        --branch=main \
        --path=clusters/local \
        --read-write-key \
        --components-extra=image-reflector-controller,image-automation-controller

# Flux objects that are not ready
flux-status:
    flux --context={{ context }} get all -A --status-selector ready=false

# Cluster, SOPS key and Flux in one go
up: cluster-up sops-key flux-bootstrap

# Tear everything down
down: cluster-down
