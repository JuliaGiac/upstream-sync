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

Currently configured: `giac` ([JuliaGiac/giac](https://github.com/JuliaGiac/giac)).
`xcas` ([s-celles/xcas](https://github.com/s-celles/xcas)) is a commented
TODO in `upstreams.toml`: its sources are a subset of the giac tarball and
its `main` only holds a README, so what `main` should contain must be
decided first.

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
