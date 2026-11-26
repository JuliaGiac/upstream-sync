"""
    UpstreamSync

Keep forks that follow the `main`/`dev` convention in sync with upstream
release tarballs:

- `main` holds the pristine upstream tree, imported from release tarballs
  and tagged `upstream/X.Y.Z`;
- `dev` holds the fork (build system, fixes, CI, site).

The entry point for scripts is [`main`](@ref); the building blocks are
[`check`](@ref), [`import_release`](@ref), [`tag_release`](@ref),
[`merge_plan`](@ref) and
[`export_changes`](@ref). Nothing is ever pushed.
"""
module UpstreamSync

using Dates: Dates
using Downloads: Downloads
using MD5: MD5
using SHA: SHA
using Tar: Tar
using TOML: TOML

export check, import_release, tag_release, merge_plan, export_changes

include("errors.jl")
include("versions.jl")
include("index.jl")
include("checksum.jl")
include("areas.jl")
include("config.jl")
include("git.jl")
include("fetch.jl")
include("check.jl")
include("import.jl")
include("tag.jl")
include("mergeplan.jl")
include("export.jl")
include("cli.jl")

end # module
