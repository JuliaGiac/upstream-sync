struct GitResult
    code::Int
    out::String
    err::String
end

"""
    run_git(args; dir=nothing, input=nothing, env=nothing) -> GitResult

Run `git [-C dir] args...` without throwing, capturing stdout and stderr.
"""
function run_git(args::AbstractVector{<:AbstractString};
        dir::Union{Nothing, AbstractString} = nothing,
        input::Union{Nothing, AbstractString} = nothing,
        env = nothing)
    cmd = dir === nothing ? `git $args` : `git -C $dir $args`
    env === nothing || (cmd = addenv(cmd, env))
    out, err = IOBuffer(), IOBuffer()
    inp = input === nothing ? devnull : IOBuffer(input)
    p = run(pipeline(ignorestatus(cmd); stdin = inp, stdout = out, stderr = err))
    return GitResult(p.exitcode, String(take!(out)), String(take!(err)))
end

"""
    git(repo, args...; input=nothing, env=nothing) -> String

Run git in `repo`; return stdout without the trailing newline; throw an
[`UpstreamSyncError`](@ref) if git fails.
"""
function git(repo::AbstractString, args::AbstractString...; kw...)
    r = run_git(collect(args); dir = repo, kw...)
    r.code == 0 || throw(UpstreamSyncError(
        "git $(join(args, ' ')) failed in $repo:\n$(strip(r.err))"))
    return chomp(r.out)
end

ref_exists(repo, ref) =
    run_git(["rev-parse", "--verify", "--quiet", ref * "^{object}"]; dir = repo).code == 0

"""
    resolve_branch(repo, branch) -> (ref, sha)

A local branch `refs/heads/<branch>`, or else `refs/remotes/origin/<branch>`.
"""
function resolve_branch(repo::AbstractString, branch::AbstractString)
    for ref in ("refs/heads/" * branch, "refs/remotes/origin/" * branch)
        r = run_git(["rev-parse", "--verify", "--quiet", ref * "^{commit}"]; dir = repo)
        r.code == 0 && return (ref, strip(r.out))
    end
    throw(UpstreamSyncError("branch \"$branch\" not found in $repo " *
                            "(neither local nor origin/$branch)"))
end

function check_repo(repo)
    repo === nothing && throw(UpstreamSyncError("--repo <path> is required"))
    isdir(repo) || throw(UpstreamSyncError("repository not found: $repo"))
    run_git(["rev-parse", "--git-dir"]; dir = repo).code == 0 ||
        throw(UpstreamSyncError("not a git repository: $repo"))
    return abspath(repo)
end

short(sha::AbstractString) = first(sha, 7)

# NUL-separated git output -> paths
nulsplit(s::AbstractString) = filter!(!isempty, split(s, '\0'))
