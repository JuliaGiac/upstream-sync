@testitem "end to end: check, import, merge-plan, export" setup = [Synthetic] begin
    using UpstreamSync: Area
    S = Synthetic
    sb = S.sandbox()
    u = UpstreamSync.load_config(sb.config)["pkg"]
    repo = sb.repo
    quiet = IOBuffer()

    S.isolated() do
        # -- check: nothing imported yet -> a new release is available
        r = UpstreamSync.check(u; repo, io = quiet)
        @test [x.version for x in r.releases] == [v"1.0.0", v"1.1.0"]
        @test r.latest == v"1.1.0"
        @test r.imported === nothing
        @test r.new_release

        # -- import 1.0.0: must reproduce main's tree exactly (baseline)
        imp = UpstreamSync.import_release(u, v"1.0.0"; repo, cache = sb.cache,
            io = quiet)
        @test imp.branch == "upstream-import/1.0.0"
        @test imp.tag == "upstream/1.0.0"
        @test S.gitout(repo, "rev-parse", "upstream-import/1.0.0") == imp.commit
        @test S.gitout(repo, "rev-parse", "upstream/1.0.0^{commit}") == imp.commit
        @test S.gitout(repo, "cat-file", "-t", "upstream/1.0.0") == "tag"
        @test S.gitout(repo, "rev-parse", "$(imp.commit)^") ==
              S.gitout(repo, "rev-parse", "main")
        @test isempty(S.gitout(repo, "diff", "--name-only", "main", imp.commit))
        msg = S.gitout(repo, "log", "-1", "--format=%B", imp.commit)
        @test startswith(msg, "import upstream pkg 1.0.0")
        @test occursin("file://", msg) && occursin(imp.checksum, msg)
        @test endswith(strip(msg), "Assisted-by: AI")
        @test S.gitout(repo, "log", "-1", "--format=%an <%ae>", imp.commit) ==
              "Test User <test@example.org>"
        # the working tree and current branch are untouched
        @test S.gitout(repo, "rev-parse", "--abbrev-ref", "HEAD") == "dev"
        @test isempty(S.gitout(repo, "status", "--porcelain"))

        # importing twice is refused, --force replaces
        @test_throws UpstreamSync.UpstreamSyncError UpstreamSync.import_release(
            u, v"1.0.0"; repo, cache = sb.cache, io = quiet)
        UpstreamSync.import_release(u, v"1.0.0"; repo, cache = sb.cache,
            io = quiet, force = true)

        # -- check: 1.0.0 imported, 1.1.0 newer
        r = UpstreamSync.check(u; repo, io = quiet)
        @test r.imported == v"1.0.0"
        @test r.new_release

        # -- import 1.1.0 on top of main
        imp2 = UpstreamSync.import_release(u, v"1.1.0"; repo, cache = sb.cache,
            io = quiet)
        c = imp2.commit
        files = split(S.gitout(repo, "ls-tree", "-r", "--name-only", c), '\n')
        @test "src/c.cc" in files
        @test ".github/dependabot.yml" in files              # kept path
        @test ".github/workflows/upstream.yml" ∉ files      # kept path wins
        @test "obj.o" in files                              # .gitignore ignored
        @test S.gitout(repo, "show", "$c:src/a.cc") == "int a() { return 10; }"
        crlf = read(`git -C $repo cat-file blob $c:data/crlf.txt`, String)
        @test crlf == "a\r\nb\r\n"                          # no eol filter
        @test startswith(S.gitout(repo, "ls-tree", c, "bin/run.sh"), "100755")
        @test startswith(S.gitout(repo, "ls-tree", c, "src/a.cc"), "100644")
        r = UpstreamSync.check(u; repo, io = quiet)
        @test r.imported == v"1.1.0" && !r.new_release

        # -- merge-plan 1.1.0 into dev
        out = joinpath(sb.root, "plan.md")
        plan = UpstreamSync.merge_plan(u, v"1.1.0"; repo, cache = sb.cache,
            output = out, io = quiet)
        conflicts = Dict(c.path => c for c in plan.conflicts)
        @test Set(keys(conflicts)) == Set(["src/a.cc", "doc/manual.txt", "configure.ac"])
        @test conflicts["src/a.cc"].area == Area.SRC
        @test conflicts["doc/manual.txt"].area == Area.DOCS
        @test conflicts["configure.ac"].area == Area.BUILD
        @test conflicts["configure.ac"].status == "deleted by us"
        @test Set(plan.overlap) == Set(["src/a.cc", "doc/manual.txt", "configure.ac"])
        @test plan.upstream_files_changed >= 6
        report = read(out, String)
        @test report == plan.markdown
        @test occursin("# Merge plan: pkg 1.1.0", report)
        @test occursin("### Meson/build", report)
        @test occursin("### src fixes", report)
        @test occursin("`src/a.cc`", report)
        @test occursin("2 both modified, 1 deleted by us", report)
        # the merge was aborted, nothing pushed or committed, repo untouched
        @test S.gitout(repo, "rev-parse", "sync/1.1.0") == S.gitout(repo, "rev-parse", "dev")
        @test S.gitout(repo, "rev-parse", "--abbrev-ref", "HEAD") == "dev"
        @test isempty(S.gitout(repo, "status", "--porcelain"))
        @test !isfile(joinpath(repo, ".git", "MERGE_HEAD"))
        worktrees = filter(startswith("worktree "),
            split(S.gitout(repo, "worktree", "list", "--porcelain"), '\n'))
        @test length(worktrees) == 1

        # -- export: our fixes to upstream sources, with GitHub links
        ex = UpstreamSync.export_changes(u; repo)
        subjects = [c.subject for c in ex.commits]
        @test subjects == ["fix: a() returns the right value"]
        fix = sb.commits["fix"]
        @test ex.commits[1].hash == fix
        @test ex.commits[1].url == "https://github.com/Example/pkg/commit/$fix"
        @test ex.commits[1].files == ["src/a.cc"]
        @test occursin("src/a.cc", ex.diffstat)
        @test !occursin("meson.build", ex.diffstat)
        @test !occursin("extra.cc", ex.diffstat)
        @test occursin("https://github.com/Example/pkg/commit/$fix", ex.markdown)
    end
end

@testitem "import refuses a bad checksum and creates nothing" setup = [Synthetic] begin
    S = Synthetic
    sb = S.sandbox()
    sums = joinpath(sb.site, "md5sum.txt")
    write(sums, replace(read(sums, String), r"^[0-9a-f]{32}(?=  pkg-1\.1\.0)"m => "0"^32))
    u = UpstreamSync.load_config(sb.config)["pkg"]
    S.isolated() do
        @test_throws UpstreamSync.ChecksumMismatch UpstreamSync.import_release(
            u, v"1.1.0"; repo = sb.repo, cache = sb.cache, io = IOBuffer())
        @test isempty(S.gitout(sb.repo, "tag", "--list"))
        @test !occursin("upstream-import", S.gitout(sb.repo, "branch", "--list"))
        # a version that is not on the site fails cleanly
        @test_throws Exception UpstreamSync.import_release(
            u, v"9.9.9"; repo = sb.repo, cache = sb.cache, io = IOBuffer())
    end
end

@testitem "offline import reuses the download cache" setup = [Synthetic] begin
    S = Synthetic
    sb = S.sandbox()
    u = UpstreamSync.load_config(sb.config)["pkg"]
    S.isolated() do
        UpstreamSync.import_release(u, v"1.0.0"; repo = sb.repo, cache = sb.cache,
            io = IOBuffer())
        @test isfile(joinpath(sb.cache, "pkg", "pkg-1.0.0.tar.gz"))
        @test isfile(joinpath(sb.cache, "pkg", "md5sum.txt"))
        rm(sb.site; recursive = true)   # upstream unreachable
        imp = UpstreamSync.import_release(u, v"1.0.0"; repo = sb.repo,
            cache = sb.cache, io = IOBuffer(), force = true, offline = true)
        @test isempty(S.gitout(sb.repo, "diff", "--name-only", "main", imp.commit))
    end
end

@testitem "CLI: exit codes and commands" setup = [Synthetic] begin
    S = Synthetic
    sb = S.sandbox()
    S.isolated() do
        run_cli(args...) = UpstreamSync.main(["--config", sb.config, "--cache",
                sb.cache, args...]; io = IOBuffer())
        @test UpstreamSync.ExitCode.OK == 0
        @test UpstreamSync.ExitCode.ERROR == 1
        @test UpstreamSync.ExitCode.NEW_RELEASE == 10
        @test run_cli("check", "pkg", "--repo", sb.repo) == 10
        @test run_cli("import", "pkg", "1.1.0", "--repo", sb.repo) == 0
        @test run_cli("check", "--repo", sb.repo) == 0
        out = joinpath(sb.root, "plan.md")
        @test run_cli("merge-plan", "pkg", "1.1.0", "--repo", sb.repo,
            "--output", out) == 0
        @test isfile(out)
        exp = joinpath(sb.root, "export.md")
        @test run_cli("export", "pkg", "--repo", sb.repo, "--output", exp) == 0
        @test occursin("fix: a() returns the right value", read(exp, String))
        @test run_cli("check", "nope") == 1
        @test run_cli("frobnicate") == 1
        @test run_cli("import", "pkg", "1.1") == 1            # bad version, no repo
        @test run_cli("--help") == 0
        # GitHub Actions output for the weekly workflow
        rm(sb.repo; recursive = true)
        S.make_repo(sb.repo)
        ghout = joinpath(sb.root, "gh_output")
        touch(ghout)
        withenv("GITHUB_OUTPUT" => ghout) do
            @test run_cli("check", "--repo", sb.repo, "--github-output") == 10
        end
        txt = read(ghout, String)
        @test occursin("new_releases=pkg 1.1.0", txt)
    end
end

@testitem "file modes come from the tar headers, not the file system" setup = [Synthetic] begin
    S = Synthetic
    site = S.make_site(mktempdir(); releases = ["1.1.0" => S.V110])
    tarball = joinpath(site, "pkg-1.1.0.tar.gz")
    @test UpstreamSync.tarball_executables(tarball) == Set(["bin/run.sh"])
    # build_tree trusts the given set even if the extracted files say otherwise
    # (some mounts report every file as rwx)
    repo = mktempdir()
    S.git(repo, "init", "-q", "-b", "main")
    root = mktempdir()
    S.write_files(root, Dict("a.sh" => "x\n", "b.txt" => "y\n"))
    chmod(joinpath(root, "b.txt"), 0o755)
    S.isolated() do
        tree, _ = UpstreamSync.build_tree(repo, root, String[], nothing;
            executables = Set(["a.sh"]))
        ls = S.gitout(repo, "ls-tree", tree)
        @test occursin(r"^100755 blob \w+\ta\.sh$"m, ls)
        @test occursin(r"^100644 blob \w+\tb\.txt$"m, ls)
    end
end
