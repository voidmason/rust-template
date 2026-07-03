# rust-template

GitHub template repository for new Rust projects. Provides CI, a staging
branch for dependabot updates, a scheduled security audit, release tagging
and three publish workflows out of the box.

## Use it

1. Click "Use this template" -> "Create a new repository" on GitHub.
2. Rename the package in `Cargo.toml` and update the binary path in `Dockerfile`
   (the `target/release/rust-template` line).
3. Adjust the committer identity in `bump-and-release.yml` (the "Configure git"
   step) - it is hardcoded to the template author.
4. Create a `dependencies` branch from `master`: dependabot targets it, and the
   sync workflow requires it to exist.
5. Add the secrets listed in [Secrets](#secrets).

## Dependency flow

Dependabot opens weekly PRs into the `dependencies` branch, where updates
accumulate away from the trunk. Each PR is gated by the lite CI
(`ci-dependencies.yml`): the reusable checks plus a single test run - enough to
catch a broken bump without spending the full matrix on every bot PR.

On every push to `master` the sync workflow merges the trunk into
`dependencies` ([branch-sync-action]): a clean merge is pushed, a lockfile-only
conflict is regenerated automatically, a source conflict opens a PR to resolve
by hand. Delivery back to the trunk is a single reviewed PR
`dependencies -> master`, which runs the full `ci.yml`.

[branch-sync-action]: https://github.com/nerjs/branch-sync-action

## Workflows

| File                     | Trigger                               | Purpose                                        |
|--------------------------|---------------------------------------|------------------------------------------------|
| `ci.yml`                 | push/PR on master, manual             | checks -> test matrix -> release build         |
| `checks.yml`             | workflow_call                         | fmt + clippy + `cargo check`, reused as a gate |
| `ci-dependencies.yml`    | push/PR on dependencies, manual       | lite CI for dependency bumps: checks + tests   |
| `sync-dependencies.yml`  | push on master, manual                | merge master into the dependencies branch      |
| `audit.yml`              | weekly cron, manifest changes, manual | `cargo audit` against the RustSec advisory DB  |
| `bump-and-release.yml`   | manual                                | bump version, tag, GitHub Release              |
| `publish-crates.yml`     | manual on a tag                       | publish to crates.io                           |
| `publish-docker-hub.yml` | manual on a tag                       | build and push image to Docker Hub, multi-arch |
| `publish-ghcr.yml`       | manual on a tag                       | build and push image to ghcr.io, multi-arch    |

### CI

`checks.yml` is the shared entry gate: `fmt`, `clippy` and `cargo check` run in
parallel on the toolchain from `rust-toolchain.toml`. `ci.yml` chains it into
the test matrix and finishes with a release build.

`cargo test --all-features` runs across:

- rust: `stable` and `beta`; `beta` is `continue-on-error`, so an upcoming
  release regression is visible without failing the run
- env: `ubuntu-latest` and `archlinux:latest` (via `container:`, with a pacman
  prep step before checkout)

4 jobs, `fail-fast: false`. The job-level `RUSTUP_TOOLCHAIN` overrides
`rust-toolchain.toml`, and `dtolnay/rust-toolchain` installs the requested
version - the arch container has no preinstalled Rust.

Keep `rust-toolchain.toml`: every job outside the test matrix (checks, the lite
CI, `build`, the bump and publish gates) carries no toolchain step, as does the
Dockerfile. Remove the file and they silently fall back to the runner's bundled
Rust.

### Bump and release

Manual trigger from any branch (selected via "Use workflow from"). The only
input besides `commit_note` is `version` - it carries the whole intent, there
are no separate beta flags.

| `version`    | What it does           | Example                 | Release    |
|--------------|------------------------|-------------------------|------------|
| `patch`      | `--bump patch`         | `0.1.1 -> 0.1.2`        | full       |
| `minor`      | `--bump minor`         | `0.1.1 -> 0.2.0`        | full       |
| `major`      | `--bump major`         | `0.1.1 -> 1.0.0`        | full       |
| `beta`       | `--bump beta`          | `0.1.1 -> 0.1.2-beta.1` | prerelease |
| `beta-minor` | next minor + `-beta.1` | `0.1.1 -> 0.2.0-beta.1` | prerelease |
| `beta-major` | next major + `-beta.1` | `0.1.1 -> 1.0.0-beta.1` | prerelease |
| `finalize`   | `--bump release`       | `0.1.2-beta.3 -> 0.1.2` | full       |

Version math is delegated to `cargo set-version` (cargo-edit); bash only routes
the action:

- `beta` is universal: on a release version it starts a patch pre-release, on
  any pre-release it increments the counter (`beta.1 -> beta.2 -> ...`). cargo
  picks by current state, so there is no separate "continue".
- `beta-minor`/`beta-major` exist because `--bump beta` always patches the base,
  so a minor/major pre-release cannot be started in one command.
- A beta series is tied to one target version. While the version is a
  pre-release, repeating `beta` accumulates `beta.N`. Switching the level
  mid-series starts a new one (`beta-minor`/`beta-major`).
- `finalize` strips the suffix. With no active pre-release it is a no-op: the
  workflow fails loudly instead of producing an empty commit.
- prerelease vs full GitHub Release is chosen by the `-beta.N` suffix in the
  tag, not a separate flag.

The checks gate and a test run come first; nothing is bumped or tagged if they
fail. Then `cargo set-version` bumps every crate (Cargo.lock follows), the job
commits the changed manifests, tags `vX.Y.Z[-beta.N]` and pushes commit and tag
to the selected branch. The push uses `RELEASE_TOKEN`: a push made with the
default `GITHUB_TOKEN` does not trigger other workflows, so CI and the
dependencies sync would skip the bump commit. A second job creates a GitHub
Release through `GITHUB_TOKEN`.

### Publish

Each publish workflow is triggered manually with "Use workflow from:
tags/vX.Y.Z". A guard rejects runs from a branch. Each one first runs the
reusable checks against the tagged commit and publishes only if they pass;
tests are not repeated at publish time - the tag is expected to point at a
commit that already went through CI.

`publish-crates` takes a `dry_run` flag, `publish-docker-hub` asks for the
image name (`namespace/name`), GHCR derives everything from the repository.
Docker tags come from the tag name; `latest` is set only for non-beta tags.

Publish is manual on purpose, so a tag without a published artifact is allowed.
If you switch to auto-publishing on tag push, you will need a PAT: a tag pushed
with `GITHUB_TOKEN` does not trigger other workflows.

### Audit

`cargo audit` checks the dependency tree against the RustSec advisory database
every Monday at 06:00 UTC, on any push touching `Cargo.toml`/`Cargo.lock`, and
on demand. The schedule surfaces new advisories even when the repository is
quiet.

## Dependabot

Two ecosystems, both opening PRs into the `dependencies` branch:

- `cargo` - weekly, max 5 open PRs, minor+patch grouped, major opens its own PR
- `github-actions` - weekly, max 5 open PRs, same grouping

## Secrets

Add these in repository settings before using the relevant workflow:

| Secret                 | Used by                             | Notes                   |
|------------------------|-------------------------------------|-------------------------|
| `RELEASE_TOKEN`        | bump-and-release, sync-dependencies | PAT, see below          |
| `CARGO_REGISTRY_TOKEN` | publish-crates                      | crates.io API token     |
| `DOCKERHUB_USERNAME`   | publish-docker-hub                  | Docker Hub login        |
| `DOCKERHUB_TOKEN`      | publish-docker-hub                  | Docker Hub access token |

`RELEASE_TOKEN` is a PAT with contents and pull requests read/write (classic:
`repo`), plus the `workflow` scope - a sync can carry changes under
`.github/workflows`. A PAT rather than `GITHUB_TOKEN` because pushes made with
the default token do not trigger the workflows that must run on the pushed
commits: CI on the bump commit, the lite CI on a synced `dependencies`.

The GitHub Release step and GHCR publish use the built-in `GITHUB_TOKEN`
(`contents: write` and `packages: write`). No extra secret.

## Dockerfile

Minimal alpine multi-stage. The binary path in the runtime stage is
`target/release/rust-template`. Rename it together with the package name in
`Cargo.toml`, otherwise the `COPY --from=builder` step fails.

A `.dockerignore` keeps `.git`, `target` and local env files out of the build
context.

Crates with C dependencies under musl need extra apk packages in the builder
stage (for example `openssl-dev pkgconfig`).
