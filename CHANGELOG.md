# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The documentation has the JuliaGiac look (style, logo and favicon from
  JuliaGiac/site-kit, `sync.jl documenter`) and links back to
  https://juliagiac.github.io/.
- The documentation is published to https://juliagiac.github.io/upstream-sync/
  by `.github/workflows/pages.yml` on every push to `main`.
- `import` and `merge-plan` refuse to work from a local upstream (resp.
  fork) branch that differs from the same branch on `origin` (read with
  `git ls-remote`), with the command to update it; `--allow-stale`
  overrides.
- `fork_excluded_paths`: upstream files the fork branch intentionally does
  not carry. `merge-plan` reports "deleted by us" conflicts on them as
  expected conflicts, separately from the real ones.
- `merge-plan --resolve-expected [--worktree DIR]`: leaves the merge in
  progress in a worktree of `sync/X.Y.Z` (default `<repo>-sync-X.Y.Z`) with
  the expected conflicts resolved by `git rm`; nothing is committed.
- Path patterns accept a leading `/` to anchor at the root of the tree.
- `tag NAME X.Y.Z --repo PATH`: after the import pull request is merged
  with any method (merge commit, squash, rebase), fetches the upstream
  branch, finds the commit with the import's tree and creates the annotated
  tag `upstream/X.Y.Z` on it; refuses when nothing matches or when the tag
  exists on another commit (`--force`); never pushes.
- Import commits record their tree hash (`Tree: <hash>`), so `tag` works
  after the import branch is deleted.
- `merge-plan` falls back to the `upstream/X.Y.Z` tag when the import
  branch no longer exists.
- `merge-plan` lists the files upstream added outside `fork_excluded_paths`
  ("New upstream files"), which the fork's build may need to list.

### Fixed

- `merge-plan` missed the files upstream added under `fork_excluded_paths`:
  `git merge` adds them without a conflict (2.1.0 brought ten
  `micropython-1.12/` files back into `dev`). They are now reported as
  "Excluded additions" and removed by `--resolve-expected`.

### Changed

- `import` no longer creates the `upstream/X.Y.Z` tag: a squash or rebase
  merge of the import pull request rewrites the commit, so tagging is done
  afterwards by `tag`. The printed next steps and the release procedure
  are updated accordingly.
- giac: `fork_excluded_paths` lists `micropython-1.12/`, the Xcas GUI
  sources, the autotools build, legacy scripts and plain-text docs removed
  on `dev`. For 2.1.0 this leaves 1 real conflict (`check/geo.out`) out of
  117.

### Removed

- The xcas TODO in `upstreams.toml`: MicroPython and Xcas are submodules of
  the giac fork's `dev` and are not synced with upstream.

## [0.1.0] - 2026-11-26

### Added

- `UpstreamSync` Julia package and the `bin/upstream-sync.jl` command line
  tool, with `just` recipes.
- `upstreams.toml` configuring the `giac` fork (JuliaGiac/giac, `main` =
  pristine upstream tree, `dev` = fork); `xcas` documented as a TODO.
- `check`: lists the releases of the upstream index, the latest one and the
  latest imported `upstream/X.Y.Z` tag (`git ls-remote --tags`); exit status
  0 = up to date, 1 = error, 10 = new release; `--github-output`.
- `import`: downloads (cached in `cache/` or `$UPSTREAM_SYNC_CACHE`) and
  verifies the release tarball against the published checksum file, and
  commits its exact content (no `.gitignore`/`.gitattributes` filtering,
  file modes from the tar headers) plus the kept paths on the branch
  `upstream-import/X.Y.Z`, tagged `upstream/X.Y.Z`. Uses a temporary index:
  the working tree is not touched. `--force`, `--offline`.
- `merge-plan`: creates `sync/X.Y.Z` from the fork branch, trial-merges the
  import in a temporary worktree and writes a Markdown report (upstream
  changes per area, upstream changes on files we modified, conflicts by
  area and kind).
- `export`: Markdown list of our commits touching the upstream sources,
  with GitHub commit URLs and the diffstat of `upstream...fork`.
- Offline test suite (TestItemRunner) with a saved copy of the upstream
  index and a synthetic fork and release site.
- GitHub Actions: CI (Julia 1.10 and 1, documentation build), weekly
  `check-upstream` opening or updating a "New upstream release" issue,
  Dependabot for actions.
- Documentation (Documenter), `llms.txt` and `llms-full.txt`.

[Unreleased]: https://github.com/JuliaGiac/upstream-sync/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/JuliaGiac/upstream-sync/releases/tag/v0.1.0
