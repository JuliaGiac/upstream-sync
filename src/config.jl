"""
    Upstream

One fork and its upstream, as configured in `upstreams.toml` (see the
comments in that file for the meaning of every field).
"""
Base.@kwdef struct Upstream
    name::String
    repo::String
    description::String = ""
    upstream_branch::String = "main"
    fork_branch::String = "dev"
    index_url::String
    download_url::String
    release_regex::Regex
    release_file::String
    checksum_file::String
    checksum_algorithm::String = "md5"
    tag_prefix::String = "upstream/"
    import_branch_prefix::String = "upstream-import/"
    sync_branch_prefix::String = "sync/"
    keep_paths::Vector{String} = String[]
    export_paths::Vector{String} = String[]
    export_exclude::Vector{String} = String[]
    export_modified_only::Bool = true
    areas::Dict{String, Vector{String}} = Dict{String, Vector{String}}()
end

const REQUIRED_KEYS = ("repo", "index_url", "release_regex", "release_file",
    "checksum_file")

"""
    default_config_path() -> String

The `upstreams.toml` shipped at the root of this project.
"""
default_config_path() = joinpath(dirname(@__DIR__), "upstreams.toml")

strings(x) = String[string(s) for s in x]

function parse_upstream(name::AbstractString, t::AbstractDict)
    missing_keys = [k for k in REQUIRED_KEYS if !haskey(t, k)]
    isempty(missing_keys) || throw(UpstreamSyncError(
        "upstream \"$name\": missing key(s) $(join(missing_keys, ", "))"))
    rx = try
        Regex(t["release_regex"])
    catch e
        throw(UpstreamSyncError("upstream \"$name\": invalid release_regex: $e"))
    end
    occursin("{version}", t["release_file"]) || throw(UpstreamSyncError(
        "upstream \"$name\": release_file must contain {version}"))
    areas = Dict{String, Vector{String}}(
        string(k) => strings(v) for (k, v) in get(t, "areas", Dict()))
    index_url = string(t["index_url"])
    return Upstream(;
        name = string(name),
        repo = string(t["repo"]),
        description = string(get(t, "description", "")),
        upstream_branch = string(get(t, "upstream_branch", "main")),
        fork_branch = string(get(t, "fork_branch", "dev")),
        index_url,
        download_url = string(get(t, "download_url", index_url)),
        release_regex = rx,
        release_file = string(t["release_file"]),
        checksum_file = string(t["checksum_file"]),
        checksum_algorithm = lowercase(string(get(t, "checksum_algorithm", "md5"))),
        tag_prefix = string(get(t, "tag_prefix", "upstream/")),
        import_branch_prefix = string(get(t, "import_branch_prefix", "upstream-import/")),
        sync_branch_prefix = string(get(t, "sync_branch_prefix", "sync/")),
        keep_paths = strings(get(t, "keep_paths", String[])),
        export_paths = strings(get(t, "export_paths", String[])),
        export_exclude = strings(get(t, "export_exclude", String[])),
        export_modified_only = Bool(get(t, "export_modified_only", true)),
        areas,
    )
end

"""
    load_config(path = default_config_path()) -> Dict{String,Upstream}
"""
function load_config(path::AbstractString = default_config_path())
    isfile(path) || throw(UpstreamSyncError("configuration file not found: $path"))
    data = try
        TOML.parsefile(path)
    catch e
        throw(UpstreamSyncError("cannot parse $path: $(sprint(showerror, e))"))
    end
    cfg = Dict{String, Upstream}()
    for (name, t) in data
        t isa AbstractDict || continue
        cfg[name] = parse_upstream(name, t)
    end
    isempty(cfg) && throw(UpstreamSyncError("no upstream configured in $path"))
    return cfg
end

"""
    get_upstream(config, name) -> Upstream
"""
function get_upstream(cfg::AbstractDict, name::AbstractString)
    haskey(cfg, name) || throw(UpstreamSyncError(
        "unknown upstream \"$name\" (configured: $(join(sort!(collect(keys(cfg))), ", ")))"))
    return cfg[name]
end

release_filename(u::Upstream, v::VersionNumber) =
    replace(u.release_file, "{version}" => string(v))
tag_name(u::Upstream, v::VersionNumber) = u.tag_prefix * string(v)
import_branch(u::Upstream, v::VersionNumber) = u.import_branch_prefix * string(v)
sync_branch(u::Upstream, v::VersionNumber) = u.sync_branch_prefix * string(v)
repo_url(u::Upstream) = "https://github.com/" * u.repo
remote_url(u::Upstream) = repo_url(u) * ".git"
commit_url(u::Upstream, hash::AbstractString) = repo_url(u) * "/commit/" * hash

url_join(base::AbstractString, file::AbstractString) =
    endswith(base, "/") ? base * file : base * "/" * file
