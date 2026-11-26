# Configuration

Upstreams are configured in `upstreams.toml` at the root of the project
(another file can be given with `--config FILE`). Each table describes one
fork:

```toml
[giac]
repo = "JuliaGiac/giac"
upstream_branch = "main"
fork_branch = "dev"
index_url = "https://www-fourier.univ-grenoble-alpes.fr/~parisse/giac/"
release_regex = '^giac-(\d+\.\d+\.\d+)\.tar\.gz$'
release_file = "giac-{version}.tar.gz"
checksum_file = "md5sum.txt"
checksum_algorithm = "md5"
keep_paths = [".github/"]
export_paths = ["src/", "check/"]
export_exclude = ["**/meson.build"]
export_modified_only = true
fork_excluded_paths = ["micropython-1.12/", "src/hist.*", "/configure", "..."]

[giac.areas]
build = ["meson.build", "configure.ac", "m4/", "..."]
src = ["src/"]
docs = ["doc/", "*.md", "..."]
```

| Key | Required | Default | Meaning |
|---|---|---|---|
| `repo` | yes | | GitHub repository of the fork (`owner/name`), used for `git ls-remote` and commit URLs |
| `index_url` | yes | | HTML directory listing where releases appear |
| `release_regex` | yes | | file names that are releases; capture group 1 is the `X.Y.Z` version |
| `release_file` | yes | | tarball name of a version, `{version}` is replaced by `X.Y.Z` |
| `checksum_file` | yes | | checksum list (`<hex>  <file>` lines) next to the tarballs |
| `checksum_algorithm` | | `md5` | `md5`, `sha1`, `sha256` or `sha512` |
| `download_url` | | `index_url` | base URL of the tarballs and checksum file (`file://` works) |
| `upstream_branch` | | `main` | branch with the pristine upstream tree |
| `fork_branch` | | `dev` | branch with the fork |
| `tag_prefix` | | `upstream/` | prefix of the release tags |
| `import_branch_prefix` | | `upstream-import/` | prefix of the import branches |
| `sync_branch_prefix` | | `sync/` | prefix of the merge-plan branches |
| `keep_paths` | | `[]` | paths of the upstream branch carried over by every import (`dir/` = folder); a tarball file inside them is dropped and listed in the commit message |
| `export_paths` | | `[]` | git pathspecs of the upstream sources whose changes are "our fixes" |
| `export_exclude` | | `[]` | git glob pathspecs removed from `export_paths` |
| `export_modified_only` | | `true` | only count modifications of files that exist upstream, not files we added or deleted |
| `fork_excluded_paths` | | `[]` | upstream files the fork branch intentionally does not carry; `merge-plan` reports a "deleted by us" conflict on them as expected (keep the deletion) rather than as a real conflict, and lists the files upstream adds under them (merged without a conflict) to be removed |
| `areas.build`, `areas.src`, `areas.docs` | | `[]` | patterns grouping merge-plan files; first match wins in the order build, src, docs; anything else is "other" |

Patterns (`areas`, `fork_excluded_paths`): `dir/` matches everything below
`dir/`; a pattern containing `/` is a glob on the whole path; a pattern
without `/` (`meson.build`, `*.md`) matches the file name at any depth; a
leading `/` anchors the pattern at the root (`/configure` is only the
top-level `configure`, `/mk*` matches `mkosx` but not `src/mkfoo`); `*`, `?`
and `**` are globs.

For giac, `fork_excluded_paths` lists what `dev` removed from the upstream
tree on purpose: `micropython-1.12/` (a submodule `micropython/` on `dev`),
the Xcas FLTK GUI sources (moved to s-celles/xcas, a submodule), the
autotools build replaced by Meson, legacy platform scripts and packaging,
and the plain-text docs converted to Markdown. MicroPython and Xcas are not
synced with upstream: Giac.jl only needs libgiac.

Branches are looked up as local branches first, then as `origin/<branch>`.
`import` (upstream branch) and `merge-plan` (fork branch) compare that ref
with the branch on `origin` (`git ls-remote origin`) and refuse a stale one
unless `--allow-stale`; without an `origin` remote only a note is printed.

## Environment

| Variable | Meaning |
|---|---|
| `UPSTREAM_SYNC_CACHE` | download cache (default: `cache/` in the project, ignored by git); `--cache DIR` overrides it. Tarballs are stored as `<cache>/<name>/<file>`; extraction and merge worktrees are created in `<cache>/work/` and removed afterwards. |
| `GITHUB_OUTPUT` | file to which `check --github-output` appends its results |
