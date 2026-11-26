"""
    ImportResult

Outcome of [`import_release`](@ref): the new `commit`, its `branch` and
annotated `tag`, the source `url` and `checksum`, the `parent` commit
(the upstream branch), and the tarball paths `dropped` because they fall in
a kept path.
"""
struct ImportResult
    name::String
    version::VersionNumber
    commit::String
    parent::String
    branch::String
    tag::String
    url::String
    checksum::String
    dropped::Vector{String}
end

under(path, prefixes) = any(p -> path == rstrip(p, '/') ||
        startswith(path, endswith(p, "/") ? p : p * "/"), prefixes)

function decompressor(tarball::AbstractString)
    f = lowercase(tarball)
    any(e -> endswith(f, e), (".gz", ".tgz")) && return `gzip -dc $tarball`
    any(e -> endswith(f, e), (".bz2", ".tbz", ".tbz2")) && return `bzip2 -dc $tarball`
    any(e -> endswith(f, e), (".xz", ".txz")) && return `xz -dc $tarball`
    endswith(f, ".zst") && return `zstd -dc $tarball`
    return `cat $tarball`
end

"""
    tarball_executables(tarball) -> Set{String}

Regular files of the tarball (top directory stripped) whose owner execute
bit is set in the tar header. The extracted files are not trusted for this:
some file systems (ACL or network mounts) report every file as executable.
"""
function tarball_executables(tarball::AbstractString)
    proc = open(ignorestatus(decompressor(tarball)))
    headers = try
        Tar.list(proc; strict = false)
    finally
        close(proc)
    end
    exec = Set{String}()
    for h in headers
        (h.type == :file && (h.mode & 0o100) != 0) || continue
        parts = split(chopprefix(h.path, "./"), '/'; limit = 2)
        length(parts) == 2 && push!(exec, parts[2])
    end
    return exec
end

# Every file of `root` as (relative path, kind) with kind :file, :exec, :link.
# `executables` (if given) decides :exec instead of the file system.
function list_files(root::AbstractString; executables = nothing)
    out = Tuple{String, Symbol}[]
    function walk(dir, rel)
        for name in sort!(readdir(dir))
            full = joinpath(dir, name)
            r = isempty(rel) ? name : rel * "/" * name
            name == ".git" && throw(UpstreamSyncError(
                "the tarball contains a .git entry ($r); refusing to import it"))
            occursin('\n', r) && throw(UpstreamSyncError("file name with a newline: $(repr(r))"))
            st = lstat(full)
            if islink(st)
                push!(out, (r, :link))
            elseif isdir(st)
                walk(full, r)
            elseif isfile(st)
                exec = executables === nothing ? (filemode(st) & 0o100) != 0 :
                       r in executables
                push!(out, (r, exec ? :exec : :file))
            end
        end
    end
    walk(root, "")
    return out
end

"""
    build_tree(repo, root, keep_paths, upstream_sha; executables=nothing)
        -> (tree, dropped)

Write a git tree with the exact bytes of every file below `root` (no
`.gitattributes`/`.gitignore`/eol filtering), with the `keep_paths` taken
from `upstream_sha` instead. File modes are 100755 for the paths in
`executables` (default: the owner execute bit on disk). Uses a temporary
index: the working tree and the real index of `repo` are not touched.
"""
function build_tree(repo, root, keep_paths, upstream_sha; executables = nothing)
    files = list_files(root; executables)
    dropped = [p for (p, _) in files if under(p, keep_paths)]
    files = [(p, k) for (p, k) in files if !under(p, keep_paths)]
    regular = [(p, k) for (p, k) in files if k != :link]
    shas = String[]
    if !isempty(regular)
        input = join((joinpath(root, p) for (p, _) in regular), '\n') * "\n"
        shas = split(git(repo, "hash-object", "-w", "--no-filters", "--stdin-paths";
            input), '\n')
        length(shas) == length(regular) || throw(UpstreamSyncError(
            "git hash-object returned $(length(shas)) ids for $(length(regular)) files"))
    end
    entries = IOBuffer()
    for ((p, k), sha) in zip(regular, shas)
        print(entries, k == :exec ? "100755" : "100644", " blob ", sha, '\t', p, '\0')
    end
    for (p, k) in files
        k == :link || continue
        sha = git(repo, "hash-object", "-w", "--no-filters", "--stdin";
            input = readlink(joinpath(root, p)))
        print(entries, "120000 blob ", sha, '\t', p, '\0')
    end
    if !isempty(keep_paths)
        kept = git(repo, "ls-tree", "-r", "-z", "--full-tree", upstream_sha, "--",
            (rstrip(k, '/') for k in keep_paths)...)
        isempty(kept) || print(entries, kept, endswith(kept, '\0') ? "" : "\0")
    end
    tmp = mktempdir(; prefix = "upstream-sync-index-")
    try
        env = Dict("GIT_INDEX_FILE" => joinpath(tmp, "index"))
        git(repo, "update-index", "-z", "--add", "--index-info";
            input = String(take!(entries)), env)
        tree = git(repo, "write-tree"; env)
        return (tree, dropped)
    finally
        rm(tmp; recursive = true, force = true)
    end
end

function import_message(u, v, src, extra)
    algo = uppercase(u.checksum_algorithm)
    kept = isempty(u.keep_paths) ? "" :
           "\nKept from $(u.upstream_branch): $(join(u.keep_paths, ", "))"
    return """
    import upstream $(u.name) $v

    Source: $(src.url)
    $algo: $(src.checksum)  $(src.filename)$kept
    $extra
    Assisted-by: AI
    """
end

"""
    import_release(u, version; repo, cache=cache_dir(), io=stdout,
                   force=false, offline=false) -> ImportResult

Import an upstream release tarball into the local clone `repo`:
download (cached) and verify it, then create the commit
"import upstream <name> X.Y.Z" whose tree is the tarball's content (top
directory stripped) plus the kept paths of the upstream branch, on the new
branch `upstream-import/X.Y.Z` (parent: the upstream branch), and the
annotated tag `upstream/X.Y.Z`. Author and committer are the local git
identity. The working tree is not touched and nothing is pushed.
With `force`, an existing branch and tag are replaced.
"""
function import_release(u::Upstream, v::VersionNumber; repo,
        cache::AbstractString = cache_dir(), io::IO = stdout,
        force::Bool = false, offline::Bool = false)
    repo = check_repo(repo)
    branch = import_branch(u, v)
    tag = tag_name(u, v)
    if !force
        ref_exists(repo, "refs/heads/" * branch) && throw(UpstreamSyncError(
            "branch $branch already exists in $repo (use --force to replace it)"))
        ref_exists(repo, "refs/tags/" * tag) && throw(UpstreamSyncError(
            "tag $tag already exists in $repo (use --force to replace it)"))
    end
    up_ref, up_sha = resolve_branch(repo, u.upstream_branch)
    src = fetch_release(u, v; cache, offline, io)
    root = extract_tarball(src.path, joinpath(cache, "work"))
    tree, dropped = try
        println(io, "building the tree from $(basename(root))/ ...")
        build_tree(repo, root, u.keep_paths, up_sha;
            executables = tarball_executables(src.path))
    finally
        rm(dirname(root); recursive = true, force = true)
    end
    isempty(dropped) || println(io, "dropped $(length(dropped)) tarball file(s) ",
        "inside kept paths: ", join(first(dropped, 5), ", "),
        length(dropped) > 5 ? ", ..." : "")
    extra = isempty(dropped) ? "" :
            "Tarball files replaced by kept paths: $(join(dropped, ", "))\n"
    msg = import_message(u, v, src, extra)
    commit = git(repo, "commit-tree", tree, "-p", up_sha; input = msg)
    git(repo, "branch", (force ? ("-f",) : ())..., branch, commit)
    tagmsg = """
    upstream $(u.name) $v

    Source: $(src.url)
    $(uppercase(u.checksum_algorithm)): $(src.checksum)  $(src.filename)

    Assisted-by: AI
    """
    git(repo, "tag", "-a", (force ? ("-f",) : ())..., "-F", "-", tag, commit;
        input = tagmsg)
    stat = git(repo, "diff", "--shortstat", up_sha, commit)
    println(io, """

    Created commit $(short(commit)) "import upstream $(u.name) $v"
      on branch $branch (parent: $(u.upstream_branch) = $(short(up_sha)), from $up_ref)
      tagged $tag
      change from $(u.upstream_branch): $(isempty(stat) ? "none (identical trees)" : strip(stat))

    Nothing was pushed. Next steps:
      1. git -C $repo push origin $branch
         git -C $repo push origin $tag
      2. open a pull request $branch -> $(u.upstream_branch), e.g.
         gh pr create --repo $(u.repo) --base $(u.upstream_branch) --head $branch \\
           --title "import upstream $(u.name) $v"
      3. merge it with a merge commit (not squash, not rebase) so that the
         tagged commit $(short(commit)) stays on $(u.upstream_branch)
      4. prepare the fork update:
         julia --project=. bin/upstream-sync.jl merge-plan $(u.name) $v --repo $repo
    """)
    return ImportResult(u.name, v, commit, up_sha, branch, tag, src.url,
        src.checksum, dropped)
end
