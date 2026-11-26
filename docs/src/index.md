# UpstreamSync

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

Each fork (configured in [`upstreams.toml`](https://github.com/JuliaGiac/upstream-sync/blob/main/upstreams.toml)) has two
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

## Contents

- [Commands](commands.md) and [exit status](commands.md#Exit-status)
- [Release procedure](release.md)
- [Configuration](configuration.md)
- [API](api.md)
