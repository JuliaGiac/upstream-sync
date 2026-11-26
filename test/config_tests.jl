@testitem "the shipped upstreams.toml is valid" begin
    cfg = UpstreamSync.load_config(UpstreamSync.default_config_path())
    @test haskey(cfg, "giac")
    g = cfg["giac"]
    @test g.name == "giac"
    @test g.repo == "JuliaGiac/giac"
    @test g.upstream_branch == "main"
    @test g.fork_branch == "dev"
    @test startswith(g.index_url, "https://www-fourier.univ-grenoble-alpes.fr/")
    @test g.download_url == g.index_url
    @test g.checksum_algorithm == "md5"
    @test ".github/" in g.keep_paths
    @test "src/" in g.export_paths
    @test UpstreamSync.release_filename(g, v"2.1.0") == "giac-2.1.0.tar.gz"
    # the template and the regex agree
    @test occursin(g.release_regex, UpstreamSync.release_filename(g, v"2.1.0"))
    @test g.tag_prefix == "upstream/"
    @test UpstreamSync.tag_name(g, v"2.1.0") == "upstream/2.1.0"
    @test UpstreamSync.import_branch(g, v"2.1.0") == "upstream-import/2.1.0"
    @test UpstreamSync.sync_branch(g, v"2.1.0") == "sync/2.1.0"
    @test UpstreamSync.repo_url(g) == "https://github.com/JuliaGiac/giac"
end

@testitem "config errors are reported" begin
    dir = mktempdir()
    p = joinpath(dir, "u.toml")
    write(p, "[x]\nrepo = \"a/b\"\n")
    @test_throws UpstreamSync.UpstreamSyncError UpstreamSync.load_config(p)
    write(p, """
    [x]
    repo = "a/b"
    index_url = "https://example.org/x/"
    release_regex = '^x-(.*)\\.tgz\$'
    release_file = "x-{version}.tgz"
    checksum_file = "SHA256SUMS"
    checksum_algorithm = "sha256"
    """)
    x = UpstreamSync.load_config(p)["x"]
    @test x.upstream_branch == "main" && x.fork_branch == "dev"  # defaults
    @test isempty(x.keep_paths)
    @test x.checksum_algorithm == "sha256"
    @test_throws UpstreamSync.UpstreamSyncError UpstreamSync.get_upstream(
        Dict("x" => x), "nope")
end
