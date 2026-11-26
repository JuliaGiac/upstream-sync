# upstream-sync

Julia tooling that keeps the JuliaGiac forks in sync with Bernard Parisse's
upstream releases of [Giac](https://www-fourier.univ-grenoble-alpes.fr/~parisse/giac.html).

Upstream does not use a public version control system: releases are
published as tarballs (`giac-X.Y.Z.tar.gz`) with an `md5sum.txt` in
<https://www-fourier.univ-grenoble-alpes.fr/~parisse/giac/>. This project
turns each tarball into a tagged commit of the fork, prepares the merge of
that release into our fork, and lists our fixes so that they can be sent
back upstream.

Nothing here ever pushes, opens pull requests or posts anything: every
command works on a local clone and prints the next steps.

## The main/dev convention

Each fork (configured in [`upstreams.toml`](upstreams.toml)) has two
long-lived branches:

| Branch | Content |
|---|---|
| `main` | the **pristine upstream tree**, one commit per imported release, imported from the release tarball and tagged `upstream/X.Y.Z`. The only non-upstream files are the *kept paths* (for giac: `.github/`, the Dependabot configuration). |
| `dev` | **our fork**: Meson build, fixes, tests, site, CI. Upstream releases reach `dev` by merging `main` (or the import branch). |

So `git diff upstream/X.Y.Z dev` is exactly "what we changed", and
`git diff upstream/A upstream/B` is exactly "what upstream changed".

Only `giac` ([JuliaGiac/giac](https://github.com/JuliaGiac/giac)) is
configured. On its `dev` branch, MicroPython (`micropython/`, replacing
upstream's vendored `micropython-1.12/`) and the Xcas FLTK GUI
([s-celles/xcas](https://github.com/s-celles/xcas), extracted from the giac
tarball) are git submodules and are **deliberately not synced** with
upstream: Giac.jl only needs libgiac. Their upstream paths, like the
autotools files replaced by Meson, are listed in `fork_excluded_paths` so
that `merge-plan` treats upstream changes to them as expected.

## Installation

Requirements: Julia ≥ 1.10, `git` ≥ 2.28 and `tar` (with `gzip`/`bzip2`/`xz`)
on the `PATH`.

```sh
git clone https://github.com/JuliaGiac/upstream-sync.git
cd upstream-sync
julia --project=. -e 'using Pkg; Pkg.instantiate()'    # or: just instantiate
```

## Commands

```text
julia --project=. bin/upstream-sync.jl [--config FILE] [--cache DIR] <command> ...
```

With [just](https://github.com/casey/just): `just check`, `just import giac
2.1.0 ../giac`, `just merge-plan giac 2.1.0 ../giac`, `just export giac ../giac`.

### `check [NAME] [--repo PATH|URL] [--github-output]`

Lists the release versions found in the upstream index, the latest one and
the latest imported one (the highest `upstream/X.Y.Z` tag, read with
`git ls-remote --tags` from the GitHub repository, or from `--repo`), and
reports whether a newer release exists. Without `NAME`, every configured
upstream is checked. `--github-output` appends
`new_releases=<name> <X.Y.Z>,...` and `status=...` to `$GITHUB_OUTPUT`.

### `import NAME X.Y.Z --repo PATH [--force] [--offline] [--allow-stale]`

In a local clone of the fork:

1. downloads `giac-X.Y.Z.tar.gz` and `md5sum.txt` (the tarball is cached in
   `cache/`, or `$UPSTREAM_SYNC_CACHE`, and reused; the checksum file is
   always refreshed unless `--offline`) and verifies the checksum;
2. extracts the tarball and strips its top directory;
3. creates the branch `upstream-import/X.Y.Z` from `main` with one commit
   whose tree is **exactly** the tarball (bytes as published: no
   `.gitignore`, `.gitattributes` or end-of-line filtering; file modes from
   the tar headers) plus the kept paths of `main`. The commit is
   "import upstream giac X.Y.Z", with the source URL and checksum in its
   body; author and committer are your local git identity;
4. creates the annotated tag `upstream/X.Y.Z` on that commit.

The working tree and index of the clone are not touched (the commit is
built with a temporary index). Nothing is pushed; the next steps are
printed. `--force` replaces an existing branch and tag.

The import refuses to start when the local `main` differs from `main` on
`origin` (read with `git ls-remote origin`): an import based on a stale
`main` would, for instance, drop the kept `.github/` files committed since.
Update it first (`git fetch origin main:main`) or pass `--allow-stale`.

### `merge-plan NAME X.Y.Z --repo PATH [--output FILE] [--force] [--allow-stale] [--resolve-expected [--worktree DIR]]`

Creates the branch `sync/X.Y.Z` from `dev`, tries
`git merge --no-commit upstream-import/X.Y.Z` on it (in a temporary
worktree), aborts the merge, and writes a Markdown report
(`merge-plan-<name>-X.Y.Z.md` by default) with:

- the files changed upstream (added/modified/deleted, lines, per area);
- the upstream changes touching files we modified on `dev`;
- the **expected conflicts**: "deleted by us" conflicts on
  `fork_excluded_paths` (files `dev` intentionally does not carry, such as
  `micropython-1.12/`, the Xcas GUI sources and the autotools build), to be
  resolved by keeping the deletion;
- the **real conflicts** grouped by area: Meson/build, src fixes, docs,
  other (areas are configured in `upstreams.toml`), with their kind
  ("both modified", "deleted by us", ...).

Like `import`, it refuses a local `dev` that differs from `origin`'s unless
`--allow-stale`.

With `--resolve-expected`, the merge is not aborted: it is left in progress
in a worktree of `sync/X.Y.Z` (default: `<repo>-sync-X.Y.Z` next to the
clone, or `--worktree DIR`), with the expected conflicts resolved by
`git rm` and the real ones still marked. Nothing is committed: finish the
merge there, then `git worktree remove` it.

### `export NAME --repo PATH [--output FILE]`

Lists our changes to the upstream sources, as Markdown: the commits of
`dev` that are not on `main` and modify the configured source paths (for
giac `src/` and `check/`, without `meson.build` files), oldest first, each
with date, hash, subject and GitHub URL
(`https://github.com/JuliaGiac/giac/commit/<hash>`), and the diffstat of
`main...dev` on those paths. This is what the maintainer sends upstream as
links.

## Exit status

| Status | Meaning |
|---:|---|
| 0 | success; for `check`: every upstream is up to date |
| 1 | error (message on stderr) |
| 10 | `check` only: a release newer than the latest `upstream/X.Y.Z` tag exists |

## Release procedure

The weekly workflow [`check-upstream.yml`](.github/workflows/check-upstream.yml)
runs `check` and opens (or updates) an issue "New upstream release: giac
X.Y.Z" in this repository. Then, for giac X.Y.Z:

1. **Check** (optional, the issue already did it):
   `julia --project=. bin/upstream-sync.jl check giac`
2. **Import** into an up-to-date clone of the fork:
   ```sh
   git -C ../giac fetch origin && git -C ../giac branch -f main origin/main
   julia --project=. bin/upstream-sync.jl import giac X.Y.Z --repo ../giac
   ```
   Review it: `git -C ../giac show --stat upstream-import/X.Y.Z`.
3. **Publish the import** (this tool never pushes):
   ```sh
   git -C ../giac push origin upstream-import/X.Y.Z
   git -C ../giac push origin upstream/X.Y.Z
   gh pr create --repo JuliaGiac/giac --base main --head upstream-import/X.Y.Z \
     --title "import upstream giac X.Y.Z"
   ```
   Merge that pull request **with a merge commit** (not squash, not rebase)
   so that the tagged commit stays on `main`.
4. **Plan the fork update** (with `dev` up to date: `git -C ../giac pull --ff-only`):
   ```sh
   julia --project=. bin/upstream-sync.jl merge-plan giac X.Y.Z --repo ../giac \
     --resolve-expected
   ```
   Read `merge-plan-giac-X.Y.Z.md`: expected and real conflicts, upstream
   changes on files we patched. A "deleted by us" real conflict is a file
   `dev` removed outside `fork_excluded_paths`: keep the deletion or restore
   the file, and update `fork_excluded_paths` if the removal is intended.
5. **Merge into dev**: in the worktree `../giac-sync-X.Y.Z` (branch
   `sync/X.Y.Z`, merge in progress, expected conflicts already resolved),
   resolve the real conflicts, bump the version in `meson.build`, run the
   tests, `git commit`, push `sync/X.Y.Z` and open a pull request to `dev`.
   Then `git -C ../giac worktree remove ../giac-sync-X.Y.Z`.
6. **Send our fixes upstream**:
   `julia --project=. bin/upstream-sync.jl export giac --repo ../giac --output fixes.md`
   and send the links of the relevant commits to Bernard Parisse.
7. Close the issue.

## Configuration

See the comments at the top of [`upstreams.toml`](upstreams.toml) and the
[documentation](docs/src/configuration.md).

## Development

```sh
just test     # julia --project=. -e 'using Pkg; Pkg.test()'
just docs     # build the documentation (warnings are errors)
just llms     # regenerate llms.txt and llms-full.txt
```

Tests use [TestItemRunner](https://github.com/julia-vscode/TestItemRunner.jl)
and run fully offline: a saved copy of the upstream index, and a tiny
synthetic fork and release site generated on the fly.

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).
