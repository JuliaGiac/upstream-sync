const USAGE = """
usage: upstream-sync [--config FILE] [--cache DIR] <command> [arguments]

commands:
  check [NAME] [--repo PATH|URL] [--github-output]
      List the upstream releases, the latest one and the latest imported one
      (upstream/X.Y.Z tags, read with git ls-remote from GitHub or --repo).
      Exit status: 0 up to date, 10 new release available, 1 error.
  import NAME X.Y.Z --repo PATH [--force] [--offline]
      Download (cached) and verify the release tarball, commit its content on
      a new branch upstream-import/X.Y.Z from the upstream branch and tag it
      upstream/X.Y.Z. Never pushes.
  merge-plan NAME X.Y.Z --repo PATH [--output FILE] [--force]
      On a new branch sync/X.Y.Z from the fork branch, try merging
      upstream-import/X.Y.Z, write a Markdown report, abort the merge.
  export NAME --repo PATH [--output FILE]
      List our commits touching the upstream sources, with GitHub links, as
      Markdown.

options:
  --config FILE    configuration (default: upstreams.toml of this project)
  --cache DIR      download cache (default: \$UPSTREAM_SYNC_CACHE or ./cache)
  --repo PATH      local clone of the fork (check: also a URL)
  --output FILE    where to write the Markdown report
  --force          replace existing branches/tags created by a previous run
  --offline        import from the download cache only
  --github-output  check: append new_releases=... to \$GITHUB_OUTPUT
  -h, --help       show this help
"""

const VALUE_OPTIONS = ("--config", "--cache", "--repo", "--output")
const FLAG_OPTIONS = ("--force", "--offline", "--github-output", "--help", "-h")

function parse_cli(args::AbstractVector{<:AbstractString})
    opts = Dict{String, Any}()
    pos = String[]
    i = 1
    while i <= length(args)
        a = args[i]
        if a in VALUE_OPTIONS
            i < length(args) || throw(UpstreamSyncError("option $a needs a value"))
            opts[a] = args[i + 1]
            i += 2
            continue
        elseif a in FLAG_OPTIONS
            opts[a == "-h" ? "--help" : a] = true
        elseif startswith(a, "-")
            throw(UpstreamSyncError("unknown option $a"))
        else
            push!(pos, a)
        end
        i += 1
    end
    return opts, pos
end

function nargs(pos, n, usage)
    length(pos) == n || throw(UpstreamSyncError("usage: upstream-sync $usage"))
end

function cmd_check(cfg, opts, pos, io)
    length(pos) <= 2 || throw(UpstreamSyncError("usage: upstream-sync check [NAME]"))
    names = length(pos) == 2 ? [pos[2]] : sort!(collect(keys(cfg)))
    repo = get(opts, "--repo", nothing)
    repo !== nothing && length(names) > 1 && throw(UpstreamSyncError(
        "--repo needs an upstream NAME when several upstreams are configured"))
    new = String[]
    for (k, name) in enumerate(names)
        k > 1 && println(io)
        r = check(get_upstream(cfg, name); repo, io)
        r.new_release && push!(new, "$name $(r.latest)")
    end
    if get(opts, "--github-output", false)
        path = get(ENV, "GITHUB_OUTPUT", "")
        isempty(path) && throw(UpstreamSyncError("--github-output: GITHUB_OUTPUT is not set"))
        open(path, "a") do f
            println(f, "new_releases=", join(new, ","))
            println(f, "status=", isempty(new) ? "up-to-date" : "new-release")
        end
    end
    return isempty(new) ? ExitCode.OK : ExitCode.NEW_RELEASE
end

"""
    main(args; io=stdout) -> Int

Command line entry point (see `bin/upstream-sync.jl` and
[`ExitCode`](@ref)). Returns the exit status instead of exiting.
"""
function main(args::AbstractVector{<:AbstractString} = ARGS; io::IO = stdout)
    err = io === stdout ? stderr : io
    try
        opts, pos = parse_cli(args)
        if get(opts, "--help", false) || isempty(pos)
            print(io, USAGE)
            return isempty(pos) && !get(opts, "--help", false) ? ExitCode.ERROR : ExitCode.OK
        end
        cfg = load_config(get(opts, "--config", default_config_path()))
        cache = abspath(get(opts, "--cache", cache_dir()))
        repo = get(opts, "--repo", nothing)
        force = get(opts, "--force", false)
        cmd = pos[1]
        if cmd == "check"
            return cmd_check(cfg, opts, pos, io)
        elseif cmd == "import"
            nargs(pos, 3, "import NAME X.Y.Z --repo PATH")
            v = parse_version(pos[3])
            import_release(get_upstream(cfg, pos[2]), v; repo, cache, io, force,
                offline = get(opts, "--offline", false))
        elseif cmd == "merge-plan"
            nargs(pos, 3, "merge-plan NAME X.Y.Z --repo PATH")
            v = parse_version(pos[3])
            merge_plan(get_upstream(cfg, pos[2]), v; repo, cache, io, force,
                output = get(opts, "--output", nothing))
        elseif cmd == "export"
            nargs(pos, 2, "export NAME --repo PATH")
            out = get(opts, "--output", nothing)
            export_changes(get_upstream(cfg, pos[2]); repo, output = out,
                io = out === nothing ? io : nothing)
            out === nothing || println(io, "report written to $out")
        else
            throw(UpstreamSyncError("unknown command \"$cmd\"\n\n$USAGE"))
        end
        return ExitCode.OK
    catch e
        if e isa UpstreamSyncError || e isa ChecksumMismatch
            println(err, "error: ", sprint(showerror, e))
        else
            println(err, "error: ", sprint(showerror, e, catch_backtrace()))
        end
        return ExitCode.ERROR
    end
end
