"""
    CheckResult

Outcome of [`check`](@ref): the upstream `releases`, the `latest` release
version, the versions already `imported` (from `upstream/X.Y.Z` tags),
the latest of them (`imported`, or `nothing`), and `new_release`.
"""
struct CheckResult
    name::String
    releases::Vector{Release}
    latest::Union{Nothing, VersionNumber}
    imported_versions::Vector{VersionNumber}
    imported::Union{Nothing, VersionNumber}
    new_release::Bool
end

"""
    imported_versions(u; repo=nothing) -> Vector{VersionNumber}

Versions of the `upstream/X.Y.Z` tags, read with `git ls-remote --tags`
from `repo` (a path or URL) or, by default, from the GitHub repository.
"""
function imported_versions(u::Upstream; repo = nothing)
    remote = repo === nothing ? remote_url(u) : string(repo)
    r = run_git(["ls-remote", "--tags", remote])
    r.code == 0 || throw(UpstreamSyncError(
        "git ls-remote --tags $remote failed:\n$(strip(r.err))"))
    return parse_upstream_tags(r.out, u.tag_prefix)
end

"""
    check(u; repo=nothing, io=stdout, index_html=nothing) -> CheckResult

List the upstream releases (from `u.index_url`, or the given `index_html`),
the latest one and the latest imported one; report whether a newer release
exists.
"""
function check(u::Upstream; repo = nothing, io::IO = stdout,
        index_html::Union{Nothing, AbstractString} = nothing)
    html = index_html === nothing ? fetch_text(u.index_url) : index_html
    releases = parse_index(html, u.release_regex)
    isempty(releases) && throw(UpstreamSyncError(
        "no file matching $(u.release_regex.pattern) in $(u.index_url)"))
    latest = latest_release(releases)
    tags = imported_versions(u; repo)
    imported = isempty(tags) ? nothing : last(tags)
    new = is_newer(latest.version, imported)
    where_ = repo === nothing ? u.repo : string(repo)
    println(io, "$(u.name): $(u.index_url)")
    println(io, "  upstream releases: ", join(string.(r.version for r in releases), ", "))
    println(io, "  latest upstream:   $(latest.version) ($(latest.filename))")
    if imported === nothing
        println(io, "  latest imported:   none (no $(u.tag_prefix)X.Y.Z tag in $where_)")
    else
        println(io, "  latest imported:   $imported (tag $(tag_name(u, imported)) in $where_)")
    end
    if new
        println(io, "  status: NEW RELEASE AVAILABLE: $(u.name) $(latest.version)")
    else
        println(io, "  status: up to date")
    end
    return CheckResult(u.name, releases, latest.version, tags, imported, new)
end
