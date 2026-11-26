# Commands

```text
julia --project=. bin/upstream-sync.jl [--config FILE] [--cache DIR] <command> ...
```

With [just](https://github.com/casey/just): `just check`, `just import giac
2.1.0 ../giac`, `just tag giac 2.1.0 ../giac`, `just merge-plan giac 2.1.0
../giac`, `just export giac ../giac`.

## `check [NAME] [--repo PATH|URL] [--github-output]`

Lists the release versions found in the upstream index, the latest one and
the latest imported one (the highest `upstream/X.Y.Z` tag, read with
`git ls-remote --tags` from the GitHub repository, or from `--repo`), and
reports whether a newer release exists. Without `NAME`, every configured
upstream is checked. `--github-output` appends
`new_releases=<name> <X.Y.Z>,...` and `status=...` to `$GITHUB_OUTPUT`.

## `import NAME X.Y.Z --repo PATH [--force] [--offline] [--allow-stale]`

In a local clone of the fork:

1. downloads `giac-X.Y.Z.tar.gz` and `md5sum.txt` (the tarball is cached in
   `cache/`, or `$UPSTREAM_SYNC_CACHE`, and reused; the checksum file is
   always refreshed unless `--offline`) and verifies the checksum;
2. extracts the tarball and strips its top directory;
3. creates the branch `upstream-import/X.Y.Z` from `main` with one commit
   whose tree is **exactly** the tarball (bytes as published: no
   `.gitignore`, `.gitattributes` or end-of-line filtering; file modes from
   the tar headers) plus the kept paths of `main`. The commit is
   "import upstream giac X.Y.Z", with the source URL, the checksum and the
   tree hash (`Tree: <hash>`) in its body; author and committer are your
   local git identity.

It does **not** tag: the pull request may be merged with a method that
rewrites the commit (squash, rebase), so the tag is created afterwards by
`tag`.

The working tree and index of the clone are not touched (the commit is
built with a temporary index). Nothing is pushed; the next steps are
printed. `--force` replaces an existing branch and tag.

The import refuses to start when the local `main` differs from `main` on
`origin` (read with `git ls-remote origin`): an import based on a stale
`main` would, for instance, drop the kept `.github/` files committed since.
Update it first (`git fetch origin main:main`) or pass `--allow-stale`.

## `tag NAME X.Y.Z --repo PATH [--force] [--offline]`

Run once the import pull request is merged, **with any merge method**:

1. fetches `main` from `origin` (unless `--offline`);
2. finds the commit of `origin/main` with the tree of the import: the
   import commit itself if it is on `main` (merge commit, fast-forward),
   otherwise the oldest commit with the same tree (squash, rebase). The
   import tree is read from the `upstream-import/X.Y.Z` branch (local or
   `origin/`), or, if that branch was deleted, from the "import upstream
   giac X.Y.Z" commit on `main` (its `Tree:` line, or its own tree);
3. creates the annotated tag `upstream/X.Y.Z` there, with the source URL
   and checksum of the import.

It refuses when no commit of `main` has that tree (pull request not merged
yet) or when `upstream/X.Y.Z` already exists on another commit (`--force`
moves it); it is a no-op when the tag is already right. It prints the
`git push origin upstream/X.Y.Z` command and never pushes.

## `merge-plan NAME X.Y.Z --repo PATH [--output FILE] [--force] [--allow-stale] [--resolve-expected [--worktree DIR]]`

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

## `export NAME --repo PATH [--output FILE]`

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
