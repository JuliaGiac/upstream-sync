"""
    cache_dir() -> String

Download cache: `\$UPSTREAM_SYNC_CACHE`, or `cache/` at the project root
(ignored by git). Tarballs are stored as `<cache>/<name>/<file>`.
"""
cache_dir() = get(ENV, "UPSTREAM_SYNC_CACHE", joinpath(dirname(@__DIR__), "cache"))

function download_to(url::AbstractString, dest::AbstractString)
    mkpath(dirname(dest))
    tmp = dest * ".part"
    try
        Downloads.download(url, tmp)
    catch e
        rm(tmp; force = true)
        throw(UpstreamSyncError("download failed: $url\n$(sprint(showerror, e))"))
    end
    mv(tmp, dest; force = true)
    return dest
end

"""
    fetch_text(url) -> String
"""
function fetch_text(url::AbstractString)
    buf = IOBuffer()
    try
        Downloads.download(url, buf)
    catch e
        throw(UpstreamSyncError("download failed: $url\n$(sprint(showerror, e))"))
    end
    return String(take!(buf))
end

"""
    fetch_release(u, version; cache, offline=false, io=stdout)

Download (or reuse from the cache) the release tarball and the checksum
file, and verify the checksum. The checksum file is always refreshed unless
`offline`; a cached tarball that no longer matches is downloaded again once
(upstream sometimes re-uploads a release under the same name). Returns
`(; url, path, filename, checksum)`.
"""
function fetch_release(u::Upstream, v::VersionNumber; cache::AbstractString,
        offline::Bool = false, io::IO = stdout)
    dir = joinpath(cache, u.name)
    mkpath(dir)
    filename = release_filename(u, v)
    url = url_join(u.download_url, filename)
    sumurl = url_join(u.download_url, u.checksum_file)
    sumpath = joinpath(dir, u.checksum_file)
    if offline
        isfile(sumpath) || throw(UpstreamSyncError("offline: $sumpath not cached"))
    else
        println(io, "fetching $sumurl")
        download_to(sumurl, sumpath)
    end
    sums = parse_checksums(read(sumpath, String))
    haskey(sums, filename) || throw(UpstreamSyncError(
        "$filename is not listed in $(u.checksum_file); is $v really released?"))
    tarball = joinpath(dir, filename)
    cached = isfile(tarball)
    if cached
        println(io, "using cached $tarball")
    else
        offline && throw(UpstreamSyncError("offline: $tarball not cached"))
        println(io, "downloading $url")
        download_to(url, tarball)
    end
    checksum = try
        verify_checksum(tarball, filename, sums, u.checksum_algorithm)
    catch e
        (e isa ChecksumMismatch && cached && !offline) || (rm(tarball; force = true); rethrow())
        println(io, "cached $filename does not match the published checksum, downloading again")
        download_to(url, tarball)
        try
            verify_checksum(tarball, filename, sums, u.checksum_algorithm)
        catch
            rm(tarball; force = true)
            rethrow()
        end
    end
    println(io, "$(uppercase(u.checksum_algorithm)) OK: $checksum  $filename")
    return (; url, path = tarball, filename, checksum)
end

"""
    extract_tarball(tarball, workdir) -> String

Extract with the system `tar` into a fresh directory below `workdir` and
return the tarball's single top-level directory.
"""
function extract_tarball(tarball::AbstractString, workdir::AbstractString)
    mkpath(workdir)
    dest = mktempdir(workdir; prefix = "extract-", cleanup = false)
    err = IOBuffer()
    p = run(pipeline(ignorestatus(`tar -xf $tarball -C $dest`); stderr = err))
    p.exitcode == 0 || throw(UpstreamSyncError(
        "tar failed on $tarball:\n$(String(take!(err)))"))
    entries = readdir(dest)
    (length(entries) == 1 && isdir(joinpath(dest, entries[1])) &&
     !islink(joinpath(dest, entries[1]))) || throw(UpstreamSyncError(
        "$tarball does not have a single top-level directory: $(join(first(entries, 5), ", "))"))
    return joinpath(dest, entries[1])
end
