const VERSION_RX = r"^\d+\.\d+\.\d+$"

"""
    parse_version(s) -> VersionNumber

Parse a strict `X.Y.Z` release version (no `v` prefix, no suffix).
"""
function parse_version(s::AbstractString)
    occursin(VERSION_RX, s) ||
        throw(UpstreamSyncError("invalid version \"$s\": expected X.Y.Z"))
    return VersionNumber(s)
end

"""
    is_newer(latest, imported) -> Bool

Whether the `latest` upstream release is newer than the `imported` one.
`nothing` means "no release" (`latest`) or "nothing imported yet"
(`imported`).
"""
is_newer(latest::Union{Nothing, VersionNumber},
    imported::Union{Nothing, VersionNumber}) =
    latest !== nothing && (imported === nothing || latest > imported)

"""
    parse_upstream_tags(ls_remote_output, prefix) -> Vector{VersionNumber}

Versions of the `refs/tags/<prefix>X.Y.Z` tags in the output of
`git ls-remote --tags`, sorted and unique. Peeled entries (`^{}`) and
non-version tags are ignored.
"""
function parse_upstream_tags(text::AbstractString, prefix::AbstractString)
    head = "refs/tags/" * prefix
    versions = VersionNumber[]
    for line in eachline(IOBuffer(text))
        parts = split(line, '\t')
        length(parts) == 2 || continue
        ref = strip(parts[2])
        (endswith(ref, "^{}") || !startswith(ref, head)) && continue
        s = ref[(lastindex(head) + 1):end]
        occursin(VERSION_RX, s) && push!(versions, VersionNumber(s))
    end
    return sort!(unique!(versions))
end
