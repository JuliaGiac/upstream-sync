# Helpers shared by the end-to-end test items: a tiny fake upstream release
# site (tarballs, md5sum.txt, index.html) and a tiny fork repository that
# follows the main/dev convention. Everything is local and offline.

@testmodule Synthetic begin
    using MD5

    # Isolate git from the developer's global and system configuration
    # (signing, hooks, default branch, ...).
    const GIT_ENV = [
        "GIT_CONFIG_GLOBAL" => "/dev/null",
        "GIT_CONFIG_NOSYSTEM" => "1",
        "GIT_AUTHOR_DATE" => nothing,
        "GIT_COMMITTER_DATE" => nothing,
    ]

    isolated(f) = withenv(f, GIT_ENV...)

    git(dir, args...) = isolated() do
        run(pipeline(`git -C $dir $args`; stdout = devnull, stderr = devnull))
    end
    gitout(dir, args...) = isolated(() -> readchomp(`git -C $dir $args`))

    function write_files(root, files)
        for (path, content) in files
            full = joinpath(root, path)
            mkpath(dirname(full))
            write(full, content)
            endswith(path, ".sh") && chmod(full, 0o755)
        end
    end

    const V100 = Dict(
        "src/a.cc" => "int a() { return 1; }\n",
        "src/b.cc" => "int b() { return 2; }\n",
        "doc/manual.txt" => "manual 1.0.0\n",
        "README" => "pkg 1.0.0\n",
        "configure.ac" => "AC_INIT([pkg], [1.0.0])\n",
        "bin/run.sh" => "#!/bin/sh\necho run\n",
    )

    const V110 = Dict(
        "src/a.cc" => "int a() { return 10; }\n",
        "src/b.cc" => "int b() { return 2; }\n",
        "src/c.cc" => "int c() { return 3; }\n",
        "doc/manual.txt" => "manual 1.1.0\n",
        "README" => "pkg 1.1.0\n",
        "configure.ac" => "AC_INIT([pkg], [1.1.0])\n",
        "bin/run.sh" => "#!/bin/sh\necho run\n",
        # Pristine-import traps: CRLF bytes guarded by a .gitattributes that
        # would normalise them, an ignored file, and an upstream .github/
        # that must not replace the kept one.
        "data/crlf.txt" => "a\r\nb\r\n",
        ".gitattributes" => "*.txt text eol=lf\n",
        ".gitignore" => "*.o\n",
        "obj.o" => "not really an object\n",
        ".github/workflows/upstream.yml" => "name: upstream\n",
    )

    """
    Create a release site in `site` with `pkg-<v>.tar.gz` tarballs (top
    directory `pkg-<v>/`), `md5sum.txt` and an Apache-like `index.html`.
    """
    function make_site(site; releases = ["1.0.0" => V100, "1.1.0" => V110])
        mkpath(site)
        sums = String[]
        rows = String[]
        for (v, files) in releases
            stage = mktempdir()
            top = joinpath(stage, "pkg-$v")
            write_files(top, files)
            tarball = joinpath(site, "pkg-$v.tar.gz")
            run(`tar -czf $tarball -C $stage pkg-$v`)
            push!(sums, bytes2hex(open(md5, tarball)) * "  pkg-$v.tar.gz")
            push!(rows, "<tr><td><a href=\"pkg-$v.tar.gz\">pkg-$v.tar.gz</a></td></tr>")
            rm(stage; recursive = true)
        end
        push!(rows, "<tr><td><a href=\"pkg_stable.tgz\">pkg_stable.tgz</a></td></tr>")
        write(joinpath(site, "md5sum.txt"), join(sums, "\n") * "\n")
        write(joinpath(site, "index.html"),
            "<html><body><table>\n" * join(rows, "\n") * "\n</table></body></html>\n")
        return site
    end

    """
    Create the fork: `main` = files of 1.0.0 committed by hand plus a
    `.github/dependabot.yml` commit; `dev` = our fixes and Meson build.
    Returns a Dict of the interesting dev commits.
    """
    function make_repo(repo)
        mkpath(repo)
        git(repo, "init", "-q", "-b", "main")
        git(repo, "config", "user.name", "Test User")
        git(repo, "config", "user.email", "test@example.org")
        write_files(repo, V100)
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "initial commit")
        write_files(repo, Dict(".github/dependabot.yml" => "version: 2\n"))
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "chore(ci): dependabot")

        git(repo, "checkout", "-q", "-b", "dev")
        commits = Dict{String, String}()
        function commit!(key, msg, files; delete = String[])
            write_files(repo, files)
            for d in delete
                git(repo, "rm", "-q", d)
            end
            git(repo, "add", "-A")
            git(repo, "commit", "-q", "-m", msg)
            commits[key] = gitout(repo, "rev-parse", "HEAD")
        end
        commit!("meson", "feat: add Meson build",
            Dict("meson.build" => "project('pkg')\n",
                "src/meson.build" => "lib = library('pkg')\n"))
        commit!("fix", "fix: a() returns the right value",
            Dict("src/a.cc" => "int a() { return 42; }\n"))
        commit!("newfile", "feat: add a new source file",
            Dict("src/extra.cc" => "int extra() { return 0; }\n"))
        commit!("docs", "docs: clarify the manual",
            Dict("doc/manual.txt" => "manual 1.0.0, clarified\n"))
        commit!("autotools", "chore: remove autotools", Dict{String, String}();
            delete = ["configure.ac"])
        commit!("readme", "docs: drop the plain-text README", Dict{String, String}();
            delete = ["README"])
        return commits
    end

    """Write an upstreams.toml for the synthetic upstream `pkg`."""
    function write_config(path, site; name = "pkg")
        url = "file://" * abspath(site) * "/"
        write(path, """
        [$name]
        repo = "Example/pkg"
        upstream_branch = "main"
        fork_branch = "dev"
        index_url = "$(url)index.html"
        download_url = "$url"
        release_regex = '^pkg-(\\d+\\.\\d+\\.\\d+)\\.tar\\.gz\$'
        release_file = "pkg-{version}.tar.gz"
        checksum_file = "md5sum.txt"
        checksum_algorithm = "md5"
        keep_paths = [".github/"]
        export_paths = ["src/"]
        export_exclude = ["**/meson.build"]
        export_modified_only = true
        fork_excluded_paths = ["/configure.ac", "m4/"]

        [$name.areas]
        build = ["meson.build", "configure.ac", "Makefile.am"]
        src = ["src/"]
        docs = ["doc/", "README"]
        """)
        return path
    end

    """
    Give `repo` a bare `origin` (fetched), and return a function that pushes
    one more commit to `branch` on origin from another clone, making the
    local branch of `repo` stale.
    """
    function add_origin(root, repo)
        origin = joinpath(root, "origin.git")
        git(root, "clone", "-q", "--bare", repo, origin)
        git(repo, "remote", "add", "origin", origin)
        git(repo, "fetch", "-q", "origin")
        n = Ref(0)
        function advance(branch)
            other = mktempdir()
            git(other, "clone", "-q", "-b", branch, origin, "w")
            w = joinpath(other, "w")
            git(w, "config", "user.name", "Someone Else")
            git(w, "config", "user.email", "else@example.org")
            n[] += 1
            write_files(w, Dict(".github/extra-$(n[]).yml" => "x: $(n[])\n"))
            git(w, "add", "-A")
            git(w, "commit", "-q", "-m", "chore: pushed elsewhere")
            git(w, "push", "-q", "origin", branch)
            return gitout(w, "rev-parse", "HEAD")
        end
        return advance
    end

    """A complete fresh sandbox: site, repo, config and cache directory."""
    function sandbox()
        root = mktempdir()
        site = make_site(joinpath(root, "site"))
        repo = joinpath(root, "repo")
        commits = make_repo(repo)
        config = write_config(joinpath(root, "upstreams.toml"), site)
        cache = joinpath(root, "cache")
        return (; root, site, repo, commits, config, cache)
    end
end
