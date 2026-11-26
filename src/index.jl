"""
    Release(version, filename)

An upstream release found in the download directory index.
"""
struct Release
    version::VersionNumber
    filename::String
end

const HREF_RX = r"href\s*=\s*(?:\"([^\"]*)\"|'([^']*)')"i

unescape_url(s::AbstractString) = replace(s,
    r"%([0-9A-Fa-f]{2})" => m -> string(Char(parse(UInt8, m[2:3]; base = 16))))

"""
    parse_index(html, regex) -> Vector{Release}

Releases listed in an (Apache-style) directory index: every link whose
file name matches `regex`, whose first capture group is the `X.Y.Z`
version. Sorted by version, one entry per version.
"""
function parse_index(html::AbstractString, rx::Regex)
    found = Dict{VersionNumber, String}()
    for m in eachmatch(HREF_RX, html)
        href = unescape_url(something(m.captures[1], m.captures[2]))
        startswith(href, "./") && (href = href[3:end])
        (occursin('?', href) || occursin('/', href) || isempty(href)) && continue
        mm = match(rx, href)
        (mm === nothing || isempty(mm.captures)) && continue
        cap = mm.captures[1]
        (cap === nothing || !occursin(VERSION_RX, cap)) && continue
        get!(found, VersionNumber(cap), String(href))
    end
    return sort!([Release(v, f) for (v, f) in found]; by = r -> r.version)
end

"""
    latest_release(releases) -> Union{Release, Nothing}
"""
latest_release(rs::AbstractVector{Release}) =
    isempty(rs) ? nothing : rs[argmax([r.version for r in rs])]
