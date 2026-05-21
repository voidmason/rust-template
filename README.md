# rust-template

GitHub template repository for new Rust projects. Provides CI, dependabot,
release tagging and three publish workflows out of the box.

## Use it

1. Click "Use this template" -> "Create a new repository" on GitHub.
2. Rename the package in `Cargo.toml` and update the binary path in `Dockerfile`
   (the `target/release/rust-template` line).
3. Add the secrets listed in [Secrets](#secrets).
4. Push to `master`. The first `sync-dependencies` run creates the
   `dependencies` branch.

## Branches

| Branch         | Role                                                             |
|----------------|------------------------------------------------------------------|
| `master`       | Main line. Protected by required PR.                             |
| `dependencies` | Receives dependabot PRs and accumulates updates.                 |
| `deps-sync`    | Throwaway branch for resolving `master` -> `dependencies` conflicts. |

Dependabot opens PRs into `dependencies`, not `master`, so dependency churn
stays out of the main line until a human merges it.

`sync-dependencies.yml` runs on each push to `master` and fast-forwards
`dependencies` when possible. On conflict it force-pushes a fresh snapshot of
`master` to `deps-sync` and opens (or reuses) a PR `deps-sync -> dependencies`
for manual conflict resolution.

## Workflows

| File                                | Trigger                            | Purpose                                                       |
|-------------------------------------|------------------------------------|---------------------------------------------------------------|
| `ci.yml`                            | push/PR on master, manual          | fmt, clippy, test matrix (rust x distro), release build       |
| `ci-deps.yml`                       | push/PR on dependencies, deps-sync | cargo check + cargo test                                      |
| `sync-dependencies.yml`             | push on master, manual             | sync `master` into `dependencies`                             |
| `bump-and-release.yml`              | manual                             | bump version, tag, optional GitHub Release                    |
| `publish-crates.yml`                | manual on a tag                    | publish to crates.io                                          |
| `publish-docker-hub.yml`            | manual on a tag                    | build and push image to Docker Hub, multi-arch                |
| `publish-ghcr.yml`                  | manual on a tag                    | build and push image to ghcr.io, multi-arch                   |

Commit-message or PR-title marker `[skip-CI]` skips `ci.yml` and `ci-deps.yml`.

### Test matrix

`ci.yml` runs `cargo test --all-features` across:

- rust: `stable`, `beta`
- env: `ubuntu-latest`, `debian:12`, `archlinux:latest`, `rust:1-alpine`

8 jobs total, `fail-fast: false`. Distros run via `container:`.

### Bump and release

Manual trigger from any branch (selected via "Use workflow from"). Inputs:

| Input           | Type    | Default | Effect                                                  |
|-----------------|---------|---------|---------------------------------------------------------|
| `version`       | choice  | patch   | bump level: patch / minor / major                       |
| `beta`          | boolean | false   | append `-beta.N` suffix; N is auto-incremented per base |
| `force_release` | boolean | false   | create GitHub Release even for a beta tag               |
| `commit_note`   | string  | ""      | optional text appended to the bump commit message       |

The job updates `Cargo.toml`, commits, tags `vX.Y.Z[-beta.N]`, pushes to the
selected branch. A second job creates a GitHub Release unless the tag is beta
and `force_release` is false. Beta releases are marked `--prerelease`.

### Publish

Each publish workflow is triggered manually with "Use workflow from:
tags/vX.Y.Z". A guard rejects runs from a branch. Docker tags are derived from
the tag name; `latest` is set only for non-beta tags.

## Dependabot

Two ecosystems, both targeting `dependencies`:

- `cargo` - weekly, max 5 open PRs, minor+patch grouped, major opens its own PR
- `github-actions` - weekly, max 5 open PRs, same grouping

## Secrets

Add these in repository settings before using the relevant workflow:

| Secret                 | Used by                  | Notes                                                                        |
|------------------------|--------------------------|------------------------------------------------------------------------------|
| `RELEASE_TOKEN`        | bump, sync, release      | PAT with `contents: write`, `pull-requests: write`. Required so tag pushes trigger downstream workflows; the default `GITHUB_TOKEN` does not. |
| `CARGO_REGISTRY_TOKEN` | publish-crates           | crates.io API token                                                          |
| `DOCKERHUB_USERNAME`   | publish-docker-hub       | Docker Hub login                                                             |
| `DOCKERHUB_TOKEN`      | publish-docker-hub       | Docker Hub access token                                                      |

GHCR uses the built-in `GITHUB_TOKEN` with `packages: write`. No extra secret.

## Dockerfile

Minimal alpine multi-stage. The binary path in the runtime stage is
`target/release/rust-template`. Rename it together with the package name in
`Cargo.toml`, otherwise the `COPY --from=builder` step fails.

Crates with C dependencies under musl need extra apk packages in the builder
stage (for example `openssl-dev pkgconfig`).
