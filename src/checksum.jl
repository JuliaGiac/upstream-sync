const DIGESTS = Dict{String, Function}(
    "md5" => MD5.md5,
    "sha1" => SHA.sha1,
    "sha256" => SHA.sha256,
    "sha512" => SHA.sha512,
)

"""
    file_digest(path, algorithm) -> String

Lower-case hexadecimal digest of a file (`md5`, `sha1`, `sha256`, `sha512`).
"""
function file_digest(path::AbstractString, algorithm::AbstractString)
    f = get(DIGESTS, lowercase(algorithm), nothing)
    f === nothing && throw(UpstreamSyncError(
        "unsupported checksum algorithm \"$algorithm\" " *
        "(supported: $(join(sort!(collect(keys(DIGESTS))), ", ")))"))
    return bytes2hex(open(f, path))
end

"""
    checksum_ok(path, expected, algorithm) -> Bool
"""
checksum_ok(path::AbstractString, expected::AbstractString,
    algorithm::AbstractString) =
    file_digest(path, algorithm) == lowercase(strip(expected))

"""
    parse_checksums(text) -> Dict{String,String}

Parse a `md5sum`/`sha256sum`-style file (`<hex>  <file>` or
`<hex> *<file>` per line) into `file => lower-case hex`.
"""
function parse_checksums(text::AbstractString)
    sums = Dict{String, String}()
    for line in eachline(IOBuffer(text))
        m = match(r"^\s*([0-9A-Fa-f]{32,128})\s+\*?(\S.*?)\s*$", line)
        m === nothing || (sums[m[2]] = lowercase(m[1]))
    end
    return sums
end

"""
    verify_checksum(path, filename, checksums, algorithm) -> String

Check `path` against `checksums[filename]`; return the digest. Throws
[`ChecksumMismatch`](@ref) on mismatch and [`UpstreamSyncError`](@ref) if
`filename` has no published checksum.
"""
function verify_checksum(path::AbstractString, filename::AbstractString,
        checksums::AbstractDict, algorithm::AbstractString)
    haskey(checksums, filename) || throw(UpstreamSyncError(
        "no $(uppercase(algorithm)) checksum published for $filename"))
    expected = lowercase(checksums[filename])
    actual = file_digest(path, algorithm)
    actual == expected ||
        throw(ChecksumMismatch(filename, algorithm, expected, actual))
    return actual
end
