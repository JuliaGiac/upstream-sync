"""
    CommitInfo(hash, date, subject, url, files)
"""
struct CommitInfo
    hash::String
    date::String
    subject::String
    url::String
    files::Vector{String}
end

"""
    ExportReport

Outcome of [`export_changes`](@ref): our `commits` touching the upstream
sources, the `diffstat` of `upstream...fork` on those paths, and the
`markdown` report.
"""
struct ExportReport
    name::String
    upstream_sha::String
    fork_sha::String
    commits::Vector{CommitInfo}
    diffstat::String
    markdown::String
end

"""
    export_pathspecs(u) -> Vector{String}

Git pathspecs for "our fixes": `export_paths` minus `export_exclude`
(git glob pathspecs, e.g. `**/meson.build`).
"""
export_pathspecs(u::Upstream) =
    vcat(u.export_paths, [":(glob,exclude)" * p for p in u.export_exclude])

function render_export(io::IO, u::Upstream, r::ExportReport, up_ref, fork_ref)
    println(io, "# Changes to upstream $(u.name) sources in $(u.repo)\n")
    println(io, "Branch [`$(u.fork_branch)`]($(repo_url(u))/tree/$(u.fork_branch)) ",
        "($(short(r.fork_sha))) compared with the upstream branch `$(u.upstream_branch)` ",
        "($(short(r.upstream_sha))); generated $(Dates.today()).\n")
    paths = join(("`$p`" for p in u.export_paths), ", ")
    excl = isempty(u.export_exclude) ? "" :
           "; excluded: " * join(("`$p`" for p in u.export_exclude), ", ")
    only = u.export_modified_only ?
           " Only commits that modify files present upstream are listed " *
           "(files we added or deleted are left out)." : ""
    println(io, "Paths: $paths$excl.$only\n")
    println(io, "## Commits ($(length(r.commits)))\n")
    isempty(r.commits) && println(io, "None.\n")
    for (i, c) in enumerate(r.commits)
        println(io, "$i. $(c.date) [`$(short(c.hash))`]($(c.url)) $(c.subject)")
        isempty(c.files) || println(io, "   (", join(("`$f`" for f in c.files), ", "), ")")
    end
    isempty(r.commits) || println(io)
    println(io, "## Diffstat (`$(u.upstream_branch)...$(u.fork_branch)`)\n")
    println(io, "```text")
    println(io, isempty(r.diffstat) ? "(no changes)" : r.diffstat)
    println(io, "```")
end

"""
    export_changes(u; repo, io=nothing, output=nothing) -> ExportReport

List our changes to the upstream sources: the commits on the fork branch
that are not on the upstream branch and touch `export_paths` (minus
`export_exclude`; with `export_modified_only`, only modifications of
existing files count), oldest first, with their GitHub URLs, plus the
diffstat of `upstream...fork` on the same paths. The Markdown is written
to `output` and/or printed to `io` when given.
"""
function export_changes(u::Upstream; repo, io = nothing, output = nothing)
    repo = check_repo(repo)
    up_ref, up_sha = resolve_branch(repo, u.upstream_branch)
    fork_ref, fork_sha = resolve_branch(repo, u.fork_branch)
    isempty(u.export_paths) && throw(UpstreamSyncError(
        "upstream \"$(u.name)\" has no export_paths configured"))
    specs = export_pathspecs(u)
    filter_ = u.export_modified_only ? ["--diff-filter=M"] : String[]
    log = git(repo, "log", "--no-merges", "--reverse", filter_...,
        "--format=%H%x1f%as%x1f%s", "$up_sha..$fork_sha", "--", specs...)
    commits = CommitInfo[]
    for line in split(log, '\n'; keepempty = false)
        h, d, s = split(line, '\x1f'; limit = 3)
        files = nulsplit(git(repo, "diff-tree", "--no-commit-id", "-r", "-z",
            "--name-only", filter_..., h, "--", specs...))
        push!(commits, CommitInfo(h, d, s, commit_url(u, h), String.(files)))
    end
    diffstat = git(repo, "diff", "--stat=100", filter_..., "$up_sha...$fork_sha",
        "--", specs...)
    r = ExportReport(u.name, up_sha, fork_sha, commits, diffstat, "")
    md = sprint(render_export, u, r, up_ref, fork_ref)
    r = ExportReport(u.name, up_sha, fork_sha, commits, diffstat, md)
    output === nothing || write(output, md)
    io === nothing || print(io, md)
    return r
end
