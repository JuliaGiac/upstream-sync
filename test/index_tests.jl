@testitem "parse the real (trimmed) giac index" begin
    html = read(joinpath(@__DIR__, "fixtures", "giac-index.html"), String)
    rx = r"^giac-(\d+\.\d+\.\d+)\.tar\.gz$"
    releases = UpstreamSync.parse_index(html, rx)
    versions = [r.version for r in releases]
    @test issorted(versions)
    @test allunique(versions)
    @test versions == VersionNumber.([
        "0.8.6", "1.2.0", "1.2.1", "1.2.2", "1.2.3", "1.4.9", "1.5.0",
        "1.6.0", "1.7.0", "1.9.0", "2.0.0", "2.1.0"])
    @test last(releases).filename == "giac-2.1.0.tar.gz"
    @test UpstreamSync.latest_release(releases).version == v"2.1.0"
    filenames = Set(r.filename for r in releases)
    # unrelated files of the same directory are ignored
    for other in ("giacR_1.0.1.tar.gz", "giac_stable.tgz", "giac-2.1.0.tar.bz2",
        "giac-1.1.2.README", "giac-1.0.0-1.i386.rpm", "emgiac3.tgz")
        @test other ∉ filenames
    end
end

@testitem "parse_index ignores sorting links and decodes hrefs" begin
    html = """
    <a href="?C=N;O=D">Name</a> <a href="/~parisse/">Parent</a>
    <a href="giac-1.10.0.tar.gz">x</a> <a href="giac-1.9.0.tar.gz">y</a>
    <a href="./giac-1.9.0.tar.gz">dup</a> <a href='giac%2D2.0.0.tar.gz'>z</a>
    """
    rs = UpstreamSync.parse_index(html, r"^giac-(\d+\.\d+\.\d+)\.tar\.gz$")
    @test [r.version for r in rs] == [v"1.9.0", v"1.10.0", v"2.0.0"]
    @test isempty(UpstreamSync.parse_index("<html></html>", r"^x-(.*)$"))
    @test UpstreamSync.latest_release(UpstreamSync.Release[]) === nothing
end

@testitem "versions: sorting, tags and comparison" begin
    @test sort(UpstreamSync.parse_version.(["2.1.0", "1.10.0", "1.9.0"])) ==
          [v"1.9.0", v"1.10.0", v"2.1.0"]
    @test_throws UpstreamSync.UpstreamSyncError UpstreamSync.parse_version("2.1")
    @test_throws UpstreamSync.UpstreamSyncError UpstreamSync.parse_version("v2.1.0")

    lsremote = """
    194ff510872c5b871e316bf5c7dfbe942273bef8\trefs/tags/v2.0.1
    1111111111111111111111111111111111111111\trefs/tags/upstream/2.1.0
    2222222222222222222222222222222222222222\trefs/tags/upstream/2.1.0^{}
    3333333333333333333333333333333333333333\trefs/tags/upstream/2.0.0
    4444444444444444444444444444444444444444\trefs/tags/upstream/1.10.0
    5555555555555555555555555555555555555555\trefs/tags/upstream/not-a-version
    """
    tags = UpstreamSync.parse_upstream_tags(lsremote, "upstream/")
    @test tags == [v"1.10.0", v"2.0.0", v"2.1.0"]
    @test isempty(UpstreamSync.parse_upstream_tags("", "upstream/"))

    @test UpstreamSync.is_newer(v"2.1.0", v"2.0.0")
    @test !UpstreamSync.is_newer(v"2.0.0", v"2.0.0")
    @test !UpstreamSync.is_newer(v"1.9.0", v"2.0.0")
    @test UpstreamSync.is_newer(v"1.0.0", nothing)  # nothing imported yet
    @test !UpstreamSync.is_newer(nothing, nothing)
end

@testitem "path patterns and areas" begin
    m = UpstreamSync.pathmatch
    @test m("src/", "src/gen.cc")
    @test !m("src/", "srcx/gen.cc")
    @test m("meson.build", "meson.build")
    @test m("meson.build", "src/meson.build")      # basename match
    @test m("**/meson.build", "src/sub/meson.build")
    @test m("**/meson.build", "meson.build")
    @test m("*.md", "docs/README.md")
    @test !m("*.md", "src/a.cc")
    @test m("doc/*.tex", "doc/a.tex")
    @test !m("doc/*.tex", "doc/fr/a.tex")
    @test m("config.h*", "config.h.in")
    @test m(".github/", ".github/workflows/ci.yml")

    areas = Dict("build" => ["meson.build", "configure.ac"], "src" => ["src/"],
        "docs" => ["doc/", "*.md"])
    A = UpstreamSync.Area
    @test UpstreamSync.classify("src/meson.build", areas) == A.BUILD  # build wins
    @test UpstreamSync.classify("src/gen.cc", areas) == A.SRC
    @test UpstreamSync.classify("doc/fr/a.tex", areas) == A.DOCS
    @test UpstreamSync.classify("README.md", areas) == A.DOCS
    @test UpstreamSync.classify("po/fr.po", areas) == A.OTHER
    @test UpstreamSync.area_title(A.BUILD) == "Meson/build"
    @test UpstreamSync.area_title(A.SRC) == "src fixes"
end
