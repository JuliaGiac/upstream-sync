# Commands

```text
julia --project=. bin/upstream-sync.jl [--config FILE] [--cache DIR] <command> ...
```

With [just](https://github.com/casey/just): `just check`, `just import giac
2.1.0 ../giac`, `just merge-plan giac 2.1.0 ../giac`, `just export giac ../giac`.

## `check [NAME] [--repo PATH|URL] [--github-output]`

Lists the release versions found in the upstream index, the latest one and
the latest imported one (the highest `upstream/X.Y.Z` tag, read with
`git ls-remote --tags` from the GitHub repository, or from `--repo`), and
reports whether a newer release exists. Without `NAME`, every configured
upstream is checked. `--github-output` appends
`new_releases=<name> <X.Y.Z>,...` and `status=...` to `$GITHUB_OUTPUT`.

## `import NAME X.Y.Z --repo PATH [--force] [--offline]`

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

## `merge-plan NAME X.Y.Z --repo PATH [--output FILE] [--force]`

Creates the branch `sync/X.Y.Z` from `dev`, tries
`git merge --no-commit upstream-import/X.Y.Z` on it (in a temporary
worktree), aborts the merge, and writes a Markdown report
(`merge-plan-<name>-X.Y.Z.md` by default) with:

- the files changed upstream (added/modified/deleted, lines, per area);
- the upstream changes touching files we modified on `dev`;
- the conflicting files grouped by area: Meson/build, src fixes, docs,
  other (areas are configured in `upstreams.toml`), with their kind
  ("both modified", "deleted by us", ...).

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
