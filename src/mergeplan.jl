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
`conflicts` the real conflicts left by `git merge`, `expected` the
"deleted by us" conflicts on `fork_excluded_paths` (resolved by keeping the
deletion), `worktree` the directory holding the merge in progress (with
`resolve_expected`, else `nothing`), `markdown` the report.
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
    expected::Vector{Conflict}
    worktree::Union{Nothing, String}
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

function list_conflicts(wt)
    porcelain = git(wt, "status", "--porcelain=v1", "-z", "--no-renames",
        "--untracked-files=no")
    conflicts = Tuple{String, String}[]
    for entry in nulsplit(porcelain)
        length(entry) > 3 || continue
        code = entry[1:2]
        haskey(CONFLICT_CODES, code) && push!(conflicts, (entry[4:end], code))
    end
    return conflicts
end

"""
    try_merge(repo, sync, import_ref, wt; keep=false, resolve=raw -> String[])
        -> Vector{(path, code)}

`git merge --no-commit import_ref` in a new worktree `wt` of branch `sync`
and return the conflicted paths with their porcelain codes. Without `keep`
the merge is aborted and the worktree removed. With `keep`, the paths
returned by `resolve(conflicts)` are `git rm`-ed and the worktree is left
with the merge in progress.
"""
function try_merge(repo, sync, import_ref, wt; keep::Bool = false,
        resolve = raw -> String[])
    git(repo, "worktree", "add", "--quiet", wt, sync)
    ok = false
    try
        r = run_git(["-c", "merge.renameLimit=100000", "merge", "--no-commit",
                "--no-ff", "--no-edit", import_ref]; dir = wt,
            env = Dict("GIT_MERGE_AUTOEDIT" => "no"))
        conflicts = list_conflicts(wt)
        merging = run_git(["rev-parse", "-q", "--verify", "MERGE_HEAD"]; dir = wt).code == 0
        if r.code != 0 && isempty(conflicts) && !merging
            throw(UpstreamSyncError("git merge failed:\n$(strip(r.err))\n$(strip(r.out))"))
        end
        if keep
            paths = resolve(conflicts)
            for chunk in Iterators.partition(paths, 500)
                git(wt, "rm", "-q", "--", chunk...)
            end
            ok = true
            return conflicts
        end
        # Abort. In-tree .gitattributes (eol=...) can make pristine files look
        # modified, so `merge --abort` may refuse; the worktree is thrown
        # away anyway, so fall back to a hard reset.
        if merging && run_git(["merge", "--abort"]; dir = wt).code != 0
            run_git(["reset", "--hard", "--quiet"]; dir = wt)
        end
        return conflicts
    finally
        if !ok
            run_git(["worktree", "remove", "--force", wt]; dir = repo)
            rm(wt; recursive = true, force = true)
            run_git(["worktree", "prune"]; dir = repo)
        end
    end
end

"""
    default_sync_worktree(u, version, repo) -> String

Where `merge-plan --resolve-expected` leaves the merge: `<repo>-sync-X.Y.Z`
next to the clone.
"""
default_sync_worktree(u::Upstream, v::VersionNumber, repo::AbstractString) =
    joinpath(dirname(rstrip(abspath(repo), '/')),
        basename(rstrip(abspath(repo), '/')) * "-sync-$v")

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

    if p.worktree !== nothing
        println(io, "**Merge left in progress** in the worktree `$(p.worktree)` ",
            "(branch `$(p.sync_branch)`): expected conflicts resolved with `git rm`, ",
            "real conflicts still marked, nothing committed.\n")
    end
    println(io, "## Expected conflicts ($(length(p.expected)))\n")
    if isempty(p.expected)
        println(io, "None.\n")
    else
        println(io, "Files the fork intentionally does not carry ",
            "(`fork_excluded_paths`) and that upstream changed: resolved by ",
            "keeping the deletion (`git rm`)",
            p.worktree === nothing ? ", or automatically with `--resolve-expected`" : "",
            ".\n")
        for a in instances(Area.T)
            cs = filter(c -> c.area == a, p.expected)
            isempty(cs) && continue
            println(io, "<details><summary>$(area_title(a)) ($(length(cs)))</summary>\n")
            for c in cs
                println(io, "- `$(c.path)`")
            end
            println(io, "\n</details>\n")
        end
    end
    println(io, "## Conflicts ($(length(p.conflicts)))\n")
    if !isempty(p.conflicts)
        statuses = sort!(unique(c.status for c in p.conflicts))
        println(io, "By kind: ", join(("$(count(c -> c.status == s, p.conflicts)) $s"
                                       for s in statuses), ", "), ".")
        any(c -> c.status == "deleted by us", p.conflicts) && println(io,
            "\n\"deleted by us\" = files the fork removed, outside ",
            "`fork_excluded_paths`, that upstream changed (content or mode): ",
            "keep the deletion (`git rm`) or restore them, and consider adding ",
            "them to `fork_excluded_paths`.")
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
    2. $(p.worktree === nothing ?
        "`git switch $(p.sync_branch) && git merge $(p.import_branch)` (or " *
        "`$(u.upstream_branch)`), `git rm` the expected conflicts," :
        "in `$(p.worktree)`:") resolve the real conflicts, run the tests,
       `git commit`.
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
               io=stdout, force=false, allow_stale=false,
               resolve_expected=false, worktree=nothing) -> MergePlan

Create the branch `sync/X.Y.Z` from the fork branch, try
`git merge --no-commit upstream-import/X.Y.Z` on it (in a temporary
worktree, so the working tree of `repo` is not touched), abort the merge,
and write a Markdown report to `output` (default
`merge-plan-<name>-X.Y.Z.md` in the current directory).

"Deleted by us" conflicts on `fork_excluded_paths` are reported as
expected, apart from the real conflicts. With `resolve_expected`, the merge
is not aborted: it is left in progress in `worktree` (default
[`default_sync_worktree`](@ref)) with the expected conflicts resolved by
`git rm` and the real ones still marked. Nothing is committed or pushed.
Refuses a local fork branch that differs from `origin`'s unless
`allow_stale`.
"""
function merge_plan(u::Upstream, v::VersionNumber; repo,
        cache::AbstractString = cache_dir(), output = nothing, io::IO = stdout,
        force::Bool = false, allow_stale::Bool = false,
        resolve_expected::Bool = false, worktree = nothing)
    repo = check_repo(repo)
    wt_keep = resolve_expected ?
              abspath(worktree === nothing ? default_sync_worktree(u, v, repo) : worktree) :
              nothing
    wt_keep !== nothing && ispath(wt_keep) && throw(UpstreamSyncError(
        "worktree directory $wt_keep already exists; remove it " *
        "(git -C $repo worktree remove $wt_keep) or pass --worktree DIR"))
    # the import: its branch, or the upstream/X.Y.Z tag once it is merged
    # and the branch deleted
    imp = import_branch(u, v)
    imp_ref = findfirst(r -> ref_exists(repo, r), ["refs/heads/$imp",
        "refs/remotes/origin/$imp", "refs/tags/$(tag_name(u, v))"])
    imp_ref === nothing && throw(UpstreamSyncError(
        "neither branch $imp nor tag $(tag_name(u, v)) found in $repo: " *
        "run `import $(u.name) $v` first"))
    imp_ref = ["refs/heads/$imp", "refs/remotes/origin/$imp",
        "refs/tags/$(tag_name(u, v))"][imp_ref]
    import_sha = git(repo, "rev-parse", "$imp_ref^{commit}")
    imp = replace(imp_ref, r"^refs/(heads|tags)/" => "")
    previous_sha = git(repo, "rev-parse", "$import_sha^1")
    fork_ref, fork_sha = resolve_branch(repo, u.fork_branch)
    check_not_stale(repo, u.fork_branch, fork_ref, fork_sha; allow_stale, io)
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
    is_expected((p, c)) = c == "DU" && fork_excluded(u, p)
    resolve(raw) = [p for (p, c) in raw if is_expected((p, c))]
    raw = if wt_keep === nothing
        workroot = joinpath(cache, "work")
        mkpath(workroot)
        tmp = mktempdir(workroot; prefix = "merge-plan-", cleanup = false)
        try
            try_merge(repo, sync, import_sha, joinpath(tmp, "worktree"))
        finally
            rm(tmp; recursive = true, force = true)
        end
    else
        mkpath(dirname(wt_keep))
        try_merge(repo, sync, import_sha, wt_keep; keep = true, resolve)
    end
    mk(p, c) = Conflict(p, CONFLICT_CODES[c], classify(p, u.areas))
    conflicts = sort!([mk(p, c) for (p, c) in raw if !is_expected((p, c))];
        by = c -> c.path)
    expected = sort!([mk(p, c) for (p, c) in raw if is_expected((p, c))];
        by = c -> c.path)
    added = sum((max(c.added, 0) for c in changes); init = 0)
    deleted = sum((max(c.deleted, 0) for c in changes); init = 0)
    plan = MergePlan(u.name, v, u.fork_branch, fork_sha, imp, import_sha,
        previous_sha, base_sha, sync, changes, overlap, conflicts, expected,
        wt_keep, length(changes), added, deleted, "")
    md = sprint(render_plan, u, plan)
    plan = MergePlan(ntuple(i -> getfield(plan, i), fieldcount(MergePlan) - 1)..., md)
    out = output === nothing ? "merge-plan-$(u.name)-$v.md" : output
    write(out, md)
    println(io, "$(length(changes)) upstream files changed (+$added/-$deleted), ",
        "$(length(overlap)) also modified on $(u.fork_branch), ",
        "$(length(conflicts)) real conflict(s), $(length(expected)) expected ",
        "(fork_excluded_paths)")
    wt_keep === nothing || println(io, "merge left in progress in $wt_keep ",
        "(expected conflicts resolved, nothing committed)")
    println(io, "report written to $out")
    return plan
end
