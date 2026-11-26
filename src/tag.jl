"""
    TagResult

Outcome of [`tag_release`](@ref): the annotated `tag` on `commit` (of the
upstream branch, `ref`), whose tree is the import `tree`; `how` tells how
the commit was found.
"""
struct TagResult
    name::String
    version::VersionNumber
    tag::String
    commit::String
    tree::String
    ref::String
    how::String
end

struct CommitRecord
    hash::String
    tree::String
    message::String
end

# History of `ref`, newest first.
function history(repo, ref)
    out = git(repo, "log", "--format=%H%x1f%T%x1f%B%x1e", ref)
    records = CommitRecord[]
    for rec in split(out, '\x1e')
        parts = split(lstrip(rec, '\n'), '\x1f'; limit = 3)
        length(parts) == 3 || continue
        push!(records, CommitRecord(parts[1], parts[2], parts[3]))
    end
    return records
end

tree_line(msg) = (m = match(r"^Tree: ([0-9a-f]{40,64})\s*$"m, msg); m === nothing ? nothing : m[1])

"""
    tag_message(u, version, import_message) -> String

The message of the `upstream/X.Y.Z` tag: the source URL and checksum lines
of the import commit message.
"""
function tag_message(u::Upstream, v::VersionNumber, msg::AbstractString)
    src = match(r"^Source: .*$"m, msg)
    sum = match(Regex("^" * uppercase(u.checksum_algorithm) * raw": [0-9a-f]+  .*$", "m"), msg)
    (src === nothing || sum === nothing) && throw(UpstreamSyncError(
        "the import commit message of $(u.name) $v has no Source/checksum lines"))
    return """
    upstream $(u.name) $v

    $(src.match)
    $(sum.match)

    Assisted-by: AI
    """
end

"""
    tag_release(u, version; repo, io=stdout, force=false, offline=false)
        -> TagResult

Run after the import pull request is merged, with any merge method. Fetch
the upstream branch from `origin` (unless `offline`; without an `origin`
remote the local branch is used), then find on it the commit with the tree
of the import:

- the import commit itself if it is on the branch (merge commit or
  fast-forward);
- otherwise the oldest commit with the same tree (squash or rebase merge).

The import tree is read from the import branch (`upstream-import/X.Y.Z`,
local or `origin/`), or, once that branch is deleted, from the
"import upstream <name> X.Y.Z" commit on the upstream branch: the `Tree:`
line of its message, or else (imports made before that line existed) its
own tree. Create the annotated tag `upstream/X.Y.Z` there, with the source URL
and checksum of the import. Refuse when no commit matches, or when the tag
already exists on another commit (unless `force`). Never pushes.
"""
function tag_release(u::Upstream, v::VersionNumber; repo, io::IO = stdout,
        force::Bool = false, offline::Bool = false)
    repo = check_repo(repo)
    b = u.upstream_branch
    imp = import_branch(u, v)
    tag = tag_name(u, v)
    has_origin = run_git(["remote", "get-url", "origin"]; dir = repo).code == 0
    if has_origin && !offline
        println(io, "fetching $b from origin ...")
        git(repo, "fetch", "-q", "origin", "+refs/heads/$b:refs/remotes/origin/$b")
        # the import branch may already be deleted on origin
        run_git(["fetch", "-q", "origin", "+refs/heads/$imp:refs/remotes/origin/$imp"];
            dir = repo)
    end
    up_ref = if has_origin && ref_exists(repo, "refs/remotes/origin/$b")
        "refs/remotes/origin/$b"
    else
        println(io, "note: no origin/$b, using the local branch $b")
        first(resolve_branch(repo, b))
    end
    up_sha = git(repo, "rev-parse", "$up_ref^{commit}")
    hist = history(repo, up_sha)

    # the import commit, or its message found on the upstream branch
    import_sha, tree, msg = nothing, nothing, nothing
    for ref in ("refs/heads/$imp", "refs/remotes/origin/$imp")
        ref_exists(repo, ref) || continue
        import_sha = git(repo, "rev-parse", "$ref^{commit}")
        tree = git(repo, "rev-parse", "$import_sha^{tree}")
        msg = git(repo, "log", "-1", "--format=%B", import_sha)
        break
    end
    if import_sha === nothing
        title = "import upstream $(u.name) $v"
        is_import(m) = startswith(m, title) &&
                       (ncodeunits(m) == ncodeunits(title) ||
                        codeunit(m, ncodeunits(title) + 1) in (UInt8(' '), UInt8('\n')))
        # prefer a message recording the import tree; else the oldest
        # "import upstream" commit (squash/rebase keep the tree): its own tree
        i = findfirst(r -> is_import(r.message) && tree_line(r.message) !== nothing, hist)
        i === nothing && (i = findlast(r -> is_import(r.message), hist))
        i === nothing && throw(UpstreamSyncError(
            "no branch $imp (local or origin), and no \"$title\" commit on " *
            "$up_ref: run `import $(u.name) $v` first"))
        msg = hist[i].message
        tree = something(tree_line(msg), hist[i].tree)
    end

    # the commit of the upstream branch to tag
    target, how = nothing, ""
    if import_sha !== nothing &&
       run_git(["merge-base", "--is-ancestor", import_sha, up_sha]; dir = repo).code == 0
        target, how = import_sha, "the import commit is on $b (merge commit or fast-forward)"
    else
        i = findlast(r -> r.tree == tree, hist)
        i === nothing && throw(UpstreamSyncError(
            "no commit on $up_ref has the tree of the import ($(short(tree))): " *
            "is the pull request $imp -> $b merged?"))
        target, how = hist[i].hash, "same tree as the import (squash or rebase merge)"
    end

    if ref_exists(repo, "refs/tags/$tag")
        current = git(repo, "rev-parse", "refs/tags/$tag^{commit}")
        if current == target
            println(io, "$tag is already on $(short(target)), nothing to do")
            return TagResult(u.name, v, tag, target, tree, up_ref, how)
        end
        force || throw(UpstreamSyncError(
            "tag $tag already exists on $(short(current)), not on the merged commit " *
            "$(short(target)) (use --force to move it)"))
    end
    git(repo, "tag", "-a", (force ? ("-f",) : ())..., "-F", "-", tag, target;
        input = tag_message(u, v, msg))
    println(io, """
    Tagged $tag on $(short(target)) ($how, $up_ref).
    Nothing was pushed. Next step:
      git -C $repo push origin $tag""")
    return TagResult(u.name, v, tag, target, tree, up_ref, how)
end
