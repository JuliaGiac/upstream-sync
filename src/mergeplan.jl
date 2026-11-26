"""
    FileChange(path, status, added, deleted, area)

One file changed upstream between two imports (`status`: `A`, `M`, `D`,
`T`; `added`/`deleted` lines, `-1` for binary files).
"""
struct FileChange
    path::String
    status::String
    added::Int
    deleted::Int
    area::Area.T
end

"""
    Conflict(path, status, area)

A file left conflicted by `git merge` (`status` such as "both modified",
"deleted by us").
"""
struct Conflict
    path::String
    status::String
    area::Area.T
end

"""
    MergePlan

Outcome of [`merge_plan`](@ref). `changes` are the upstream file changes,
`overlap` the upstream-changed files that the fork also modified,
`conflicts` the files `git merge` could not merge, `markdown` the report.
"""
struct MergePlan
    name::String
    version::VersionNumber
    fork_branch::String
    fork_sha::String
    import_branch::String
    import_sha::String
    previous_sha::String
    base_sha::String
    sync_branch::String
    changes::Vector{FileChange}
    overlap::Vector{String}
    conflicts::Vector{Conflict}
    upstream_files_changed::Int
    lines_added::Int
    lines_deleted::Int
    markdown::String
end

const CONFLICT_CODES = Dict(
    "DD" => "both deleted", "AU" => "added by us", "UD" => "deleted by them",
    "UA" => "added by them", "DU" => "deleted by us", "AA" => "both added",
    "UU" => "both modified")

function upstream_changes(repo, from, to, areas)
    status = Dict{String, String}()
    toks = nulsplit(git(repo, "diff", "--no-renames", "--name-status", "-z", from, to))
    for i in 1:2:(length(toks) - 1)
        status[toks[i + 1]] = toks[i]
    end
    changes = FileChange[]
    for line in nulsplit(git(repo, "diff", "--no-renames", "--numstat", "-z", from, to))
        a, d, p = split(line, '\t'; limit = 3)
        push!(changes, FileChange(p, get(status, p, "M"),
            a == "-" ? -1 : parse(Int, a), d == "-" ? -1 : parse(Int, d),
            classify(p, areas)))
    end
    return sort!(changes; by = c -> c.path)
end

function try_merge(repo, sync, import_ref, workroot)
    mkpath(workroot)
    tmp = mktempdir(workroot; prefix = "merge-plan-", cleanup = false)
    wt = joinpath(tmp, "worktree")
    git(repo, "worktree", "add", "--quiet", wt, sync)
    try
        r = run_git(["-c", "merge.renameLimit=100000", "merge", "--no-commit",
                "--no-ff", "--no-edit", import_ref]; dir = wt,
            env = Dict("GIT_MERGE_AUTOEDIT" => "no"))
        porcelain = git(wt, "status", "--porcelain=v1", "-z", "--no-renames",
            "--untracked-files=no")
        conflicts = Tuple{String, String}[]
        for entry in nulsplit(porcelain)
            length(entry) > 3 || continue
            code = entry[1:2]
            haskey(CONFLICT_CODES, code) && push!(conflicts, (entry[4:end], code))
        end
        merging = run_git(["rev-parse", "-q", "--verify", "MERGE_HEAD"]; dir = wt).code == 0
        if r.code != 0 && isempty(conflicts) && !merging
            throw(UpstreamSyncError("git merge failed:\n$(strip(r.err))\n$(strip(r.out))"))
        end
        # Abort. In-tree .gitattributes (eol=...) can make pristine files look
        # modified, so `merge --abort` may refuse; the worktree is thrown
        # away anyway, so fall back to a hard reset.
        if merging && run_git(["merge", "--abort"]; dir = wt).code != 0
            run_git(["reset", "--hard", "--quiet"]; dir = wt)
        end
        return conflicts
    finally
        run_git(["worktree", "remove", "--force", wt]; dir = repo)
        rm(tmp; recursive = true, force = true)
        run_git(["worktree", "prune"]; dir = repo)
    end
end

fmt_lines(n) = n < 0 ? "bin" : string(n)

function render_plan(io::IO, u::Upstream, p::MergePlan)
    name, v = p.name, p.version
    println(io, "# Merge plan: $name $v into `$(p.fork_branch)`\n")
    println(io, "- Upstream import: `$(p.import_branch)` ($(short(p.import_sha))), ",
        "previous upstream tree $(short(p.previous_sha))")
    println(io, "- Fork: `$(p.fork_branch)` ($(short(p.fork_sha))), merge base ",
        "$(short(p.base_sha))")
    println(io, "- Sync branch: `$(p.sync_branch)` (created from `$(p.fork_branch)`; ",
        "the trial merge was aborted, nothing committed or pushed)")
    println(io, "- Generated: $(Dates.today())\n")

    println(io, "## Upstream changes\n")
    nA = count(c -> c.status == "A", p.changes)
    nM = count(c -> c.status == "M", p.changes)
    nD = count(c -> c.status == "D", p.changes)
    println(io, "$(p.upstream_files_changed) files changed ($nA added, $nM modified, ",
        "$nD deleted), +$(p.lines_added) / -$(p.lines_deleted) lines.\n")
    println(io, "| Area | Files | + | - |")
    println(io, "|---|---:|---:|---:|")
    for a in instances(Area.T)
        cs = filter(c -> c.area == a, p.changes)
        isempty(cs) && continue
        println(io, "| $(area_title(a)) | $(length(cs)) | ",
            sum(max(c.added, 0) for c in cs), " | ", sum(max(c.deleted, 0) for c in cs), " |")
    end
    println(io)

    println(io, "## Upstream changes touching files we modified ($(length(p.overlap)))\n")
    if isempty(p.overlap)
        println(io, "None.\n")
    else
        bypath = Dict(c.path => c for c in p.changes)
        for f in p.overlap
            c = bypath[f]
            println(io, "- `$f` ($(c.status), +$(fmt_lines(c.added)) / ",
                "-$(fmt_lines(c.deleted)), $(area_title(c.area)))")
        end
        println(io)
    end

    println(io, "## Conflicts ($(length(p.conflicts)))\n")
    if !isempty(p.conflicts)
        statuses = sort!(unique(c.status for c in p.conflicts))
        println(io, "By kind: ", join(("$(count(c -> c.status == s, p.conflicts)) $s"
                                       for s in statuses), ", "), ".")
        any(c -> c.status == "deleted by us", p.conflicts) && println(io,
            "\n\"deleted by us\" = files the fork removed and upstream changed ",
            "(content or mode); keeping the deletion is `git rm` on them.")
        println(io)
    end
    if isempty(p.conflicts)
        println(io, "None: `git merge $(p.import_branch)` into `$(p.fork_branch)` is clean.\n")
    end
    for a in instances(Area.T)
        cs = filter(c -> c.area == a, p.conflicts)
        isempty(cs) && continue
        println(io, "### $(area_title(a)) ($(length(cs)))\n")
        for c in cs
            println(io, "- `$(c.path)` ($(c.status))")
        end
        println(io)
    end

    println(io, "## Next steps\n")
    println(io, """
    1. Make sure `$(p.import_branch)` is merged into `$(u.upstream_branch)` and
       the tag `$(u.tag_prefix)$v` is pushed.
    2. `git switch $(p.sync_branch) && git merge $(p.import_branch)` (or
       `$(u.upstream_branch)`), resolve the conflicts above, run the tests.
    3. Push `$(p.sync_branch)` and open a pull request to `$(p.fork_branch)`.
    """)

    println(io, "<details><summary>All upstream changes ($(length(p.changes)) files)</summary>\n")
    println(io, "| Status | File | + | - | Area |")
    println(io, "|---|---|---:|---:|---|")
    for c in p.changes
        println(io, "| $(c.status) | `$(c.path)` | $(fmt_lines(c.added)) | ",
            "$(fmt_lines(c.deleted)) | $(area_title(c.area)) |")
    end
    println(io, "\n</details>")
end

"""
    merge_plan(u, version; repo, cache=cache_dir(), output=nothing,
               io=stdout, force=false) -> MergePlan

Create the branch `sync/X.Y.Z` from the fork branch, try
`git merge --no-commit upstream-import/X.Y.Z` on it (in a temporary
worktree, so the working tree of `repo` is not touched), abort the merge,
and write a Markdown report to `output` (default
`merge-plan-<name>-X.Y.Z.md` in the current directory). Nothing is pushed.
"""
function merge_plan(u::Upstream, v::VersionNumber; repo,
        cache::AbstractString = cache_dir(), output = nothing, io::IO = stdout,
        force::Bool = false)
    repo = check_repo(repo)
    imp = import_branch(u, v)
    ref_exists(repo, "refs/heads/" * imp) || throw(UpstreamSyncError(
        "branch $imp not found in $repo: run `import $(u.name) $v` first"))
    import_sha = git(repo, "rev-parse", "refs/heads/$imp^{commit}")
    previous_sha = git(repo, "rev-parse", "$import_sha^1")
    fork_ref, fork_sha = resolve_branch(repo, u.fork_branch)
    base_sha = git(repo, "merge-base", fork_sha, import_sha)
    sync = sync_branch(u, v)
    if ref_exists(repo, "refs/heads/" * sync) && !force
        current = git(repo, "rev-parse", "refs/heads/$sync^{commit}")
        current == fork_sha || throw(UpstreamSyncError(
            "branch $sync already exists in $repo and differs from $(u.fork_branch) " *
            "(use --force to reset it)"))
    end
    git(repo, "branch", "-f", sync, fork_sha)

    changes = upstream_changes(repo, previous_sha, import_sha, u.areas)
    ours = Set(nulsplit(git(repo, "diff", "--no-renames", "--name-only", "-z",
        base_sha, fork_sha)))
    overlap = sort!([c.path for c in changes if c.path in ours])
    println(io, "trial merge of $imp into $sync ...")
    raw = try_merge(repo, sync, imp, joinpath(cache, "work"))
    conflicts = sort!([Conflict(p, CONFLICT_CODES[c], classify(p, u.areas)) for (p, c) in raw];
        by = c -> c.path)
    added = sum((max(c.added, 0) for c in changes); init = 0)
    deleted = sum((max(c.deleted, 0) for c in changes); init = 0)
    plan = MergePlan(u.name, v, u.fork_branch, fork_sha, imp, import_sha,
        previous_sha, base_sha, sync, changes, overlap, conflicts,
        length(changes), added, deleted, "")
    md = sprint(render_plan, u, plan)
    plan = MergePlan(ntuple(i -> getfield(plan, i), fieldcount(MergePlan) - 1)..., md)
    out = output === nothing ? "merge-plan-$(u.name)-$v.md" : output
    write(out, md)
    println(io, "$(length(changes)) upstream files changed (+$added/-$deleted), ",
        "$(length(overlap)) also modified on $(u.fork_branch), ",
        "$(length(conflicts)) conflict(s)")
    println(io, "report written to $out")
    return plan
end
