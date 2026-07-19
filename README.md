# rust-template

GitHub template repository for new Rust projects. Provides CI, a staging
branch for dependabot updates, a scheduled security audit, release tagging
and three publish workflows out of the box.

## Use it

1. Click "Use this template" -> "Create a new repository" on GitHub.
2. Trim the files to the project type - see [Project types](#project-types).
3. Rename the package in `Cargo.toml`. If the Dockerfile stays,
   update the binary path in it (the `target/release/rust-template` line).
4. Optionally set the committer identity for release commits:
   pass `name` and `email` to the [bump-release] step in `bump-and-release.yml`;
   by default it is resolved from the token.
5. Create a `dependencies` branch from `master`: dependabot targets it, and the
   sync workflow requires it to exist.
6. Add the secrets listed in [Secrets](#secrets).

## Project types

The template carries the union of files for three project shapes,
and its CI checks a single pinned toolchain on a single target.
Deleting the extra files is the small part;
the per-shape decisions are the toolchain policy and the version axis,
and those cannot be preconfigured -
make the calls below right after creating the repository.

### Library

- Replace `src/main.rs` with `src/lib.rs`; delete `Dockerfile`, `.dockerignore`,
  `publish-docker-hub.yml` and `publish-ghcr.yml`.
- `publish-crates.yml` is the release channel. Add `CARGO_REGISTRY_TOKEN`
  and the `description` and `license` fields `cargo publish` requires.
- The compiler is not yours anymore: consumers build the crate
  with whatever toolchain they have,
  so green checks on the pinned version say nothing about them.
  Declare `rust-version` in `Cargo.toml` -
  current stable at project start is a sane floor.
  It is not the same number as a toolchain pin:
  the pin may be fresh, MSRV is a promise of a minimum.
  Gate it with a light job (`cargo hack check --rust-version`),
  and consider a non-blocking `beta` job as an early warning about the next stable.
- The pin itself is questionable here:
  dropping `rust-toolchain.toml` makes CI track the runner's moving stable,
  which is closer to what consumers run.
  Keeping it is fine too - just remember it covers CI only.
- The `build` job in `ci.yml` is optional: the checks already compile the crate.

### Binary installed with cargo install

- Delete `Dockerfile`, `.dockerignore`,
  `publish-docker-hub.yml` and `publish-ghcr.yml`.
- `publish-crates.yml` is the release channel:
  `cargo install` fetches the crate from crates.io
  and compiles it on the user's machine with the user's toolchain.
  The compiler story is therefore the library one:
  declare and gate `rust-version`,
  treat the toolchain pin as a CI detail that never reaches users.

### Binary running in a container

- Delete `publish-crates.yml`; `CARGO_REGISTRY_TOKEN` is not needed.
- Pick a registry: `publish-ghcr.yml` works with the built-in `GITHUB_TOKEN`,
  `publish-docker-hub.yml` needs the `DOCKERHUB_*` secrets. Keep one or both.
- This is the shape the template's defaults are built for.
  You control the compiler end to end,
  so keep the `rust-toolchain.toml` pin and bump it deliberately;
  `rust-version` and a version matrix buy nothing here.
- Update the binary path in `Dockerfile` and mind the runtime-image caveats -
  see [Dockerfile](#dockerfile).
  CI (ubuntu) and the runtime image share glibc,
  so tests and the shipped binary see the same libc.
  Moving the runtime to musl (alpine) silently breaks that alignment -
  then a `x86_64-unknown-linux-musl` check in CI becomes your job.

Everything else - CI, the `dependencies` branch flow, audit, bump-and-release,
dependabot - applies to all three shapes.

The shapes are axes, not exclusive cases: a crate can be a library with a CLI,
or ship to crates.io and a registry at once. Union the files,
and when the toolchain policies collide the crates.io side wins -
external consumers force `rust-version`, the container merely prefers a pin.

One axis is absent on purpose: an environment matrix.
For a single target triple pure Rust behaves identically
across Linux distributions, so a distro axis catches nothing.
The axes that do exist - target triple (gnu/musl), OS family -
are project-specific; add them in the project when it actually targets them.

## Dependency flow

Dependabot opens weekly PRs into the `dependencies` branch, where updates
accumulate away from the trunk. Each PR is gated by lite CI (`ci-dependencies.yml`):
the reusable checks alone, without the release build that full CI adds.

On every push to `master` the sync workflow merges the trunk
into `dependencies` ([branch-sync]): a clean merge is pushed,
a lockfile-only conflict is regenerated automatically,
a source conflict opens a PR to resolve by hand.
Delivery back to the trunk is a single reviewed PR `dependencies -> master`,
opened by hand whenever the accumulated updates are worth taking;
it runs the full `ci.yml`.

[branch-sync]: https://github.com/voidmason/branch-sync

## Workflows

| File                     | Trigger                               | Purpose                                        |
|--------------------------|---------------------------------------|------------------------------------------------|
| `ci.yml`                 | push/PR on master, manual             | checks -> release build                        |
| `checks.yml`             | workflow_call                         | fmt + clippy + check + test, reused as a gate  |
| `ci-dependencies.yml`    | push/PR on dependencies, manual       | lite CI for dependency bumps: checks, no build |
| `sync-dependencies.yml`  | push on master, manual                | merge master into the dependencies branch      |
| `audit.yml`              | weekly cron, manifest changes, manual | `cargo audit` against the RustSec advisory DB  |
| `bump-and-release.yml`   | manual                                | bump version, tag, GitHub Release              |
| `publish-crates.yml`     | manual on a tag                       | publish to crates.io                           |
| `publish-docker-hub.yml` | manual on a tag                       | build and push image to Docker Hub, multi-arch |
| `publish-ghcr.yml`       | manual on a tag                       | build and push image to ghcr.io, multi-arch    |

### CI

`checks.yml` is the shared entry gate. It runs `fmt`, `clippy`, `cargo check`
and `cargo test --all-features` on the toolchain from `rust-toolchain.toml`.
`ci.yml` chains the gate, then a release build; `ci-dependencies.yml` runs the
gate alone.

Keep `rust-toolchain.toml`: neither the CI jobs nor the Dockerfile
carry a toolchain step. Without it, CI falls back to the runner's bundled Rust
and the Docker build to the image's.
Whether pinning is right at all depends on the project shape -
see [Project types](#project-types).

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

The whole job is a single [bump-release] call.
Version math is delegated to `cargo set-version` (cargo-edit);
the action only routes the input:

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

The checks gate comes first; nothing is bumped or tagged if it fails.
Then [bump-release] runs `cargo set-version` (Cargo.lock follows),
commits the changed manifests, tags `vX.Y.Z[-beta.N]`,
and atomically pushes the commit and tag to the selected branch.
It uses `RELEASE_TOKEN` throughout: a push made with the default `GITHUB_TOKEN`
would not trigger other workflows,
so CI and the dependencies sync would skip the bump commit.
The same action then creates the GitHub Release -
final tags only, a beta stays a plain tag - also via `RELEASE_TOKEN`.

[bump-release]: https://github.com/voidmason/bump-release

### Publish

Each publish workflow is triggered manually with "Use workflow from:
tags/vX.Y.Z". A guard rejects runs from a branch. Each one first runs the
reusable checks against the tagged commit and publishes only if they pass.

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

GHCR publish uses the built-in `GITHUB_TOKEN` (`packages: write`). No extra
secret. The GitHub Release is created by `bump-and-release` with `RELEASE_TOKEN`,
not `GITHUB_TOKEN`.

## Dockerfile

Multi-stage build: compile on `rust:1-bookworm`, run from `distroless/cc-debian12`.
Both are Debian 12, so the binary gets the same glibc at build and at run time -
a load-bearing pairing; bump the builder and runtime tags together.

The binary path is `target/release/rust-template`. Rename it to match the
package name in `Cargo.toml`, or the `COPY --from=builder` step fails.

A `.dockerignore` keeps `.git`, `target` and local env files out of the build
context.

`distroless/cc` ships only glibc, libgcc and libssl, and has no package manager.
A crate that dynamically links another C library builds cleanly but fails at
startup on the missing `.so` - link it statically or vendor it (openssl's
`vendored` feature, or rustls), or change the runtime base. Build-time `-dev`
packages still go in the builder stage via `apt-get`.
