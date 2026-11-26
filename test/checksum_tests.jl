@testitem "parse the real md5sum.txt format" begin
    text = read(joinpath(@__DIR__, "fixtures", "md5sum.txt"), String)
    sums = UpstreamSync.parse_checksums(text)
    @test sums["giac-2.1.0.tar.gz"] == "7db03a6329e9c8c65e1831c92a9914fd"
    @test sums["giac-2.0.0.tar.gz"] == "8470f57e26c3f4e3b7639e7df0be3060"
    @test sums["giac-2.0.0.tar.bz2"] == "f64c432c3461e67526dabcf460328838"
    @test !haskey(sums, "giac-3.0.0.tar.gz")
    # binary-mode marker and upper case are accepted, junk lines skipped
    s2 = UpstreamSync.parse_checksums("ABCDEF0123456789ABCDEF0123456789 *x.tgz\njunk\n\n")
    @test s2 == Dict("x.tgz" => "abcdef0123456789abcdef0123456789")
end

@testitem "checksum verification: good and bad" begin
    dir = mktempdir()
    f = joinpath(dir, "hello.txt")
    write(f, "hello\n")
    md5hello = "b1946ac92492d2347c6235b4d2611184"
    sha256hello = "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
    @test UpstreamSync.file_digest(f, "md5") == md5hello
    @test UpstreamSync.file_digest(f, "sha256") == sha256hello
    @test UpstreamSync.checksum_ok(f, md5hello, "md5")
    @test UpstreamSync.checksum_ok(f, uppercase(md5hello), "md5")
    @test !UpstreamSync.checksum_ok(f, "0"^32, "md5")
    @test_throws UpstreamSync.UpstreamSyncError UpstreamSync.file_digest(f, "crc32")

    sums = Dict("hello.txt" => md5hello)
    @test UpstreamSync.verify_checksum(f, "hello.txt", sums, "md5") == md5hello
    bad = Dict("hello.txt" => "0"^32)
    @test_throws UpstreamSync.ChecksumMismatch UpstreamSync.verify_checksum(
        f, "hello.txt", bad, "md5")
    @test_throws UpstreamSync.UpstreamSyncError UpstreamSync.verify_checksum(
        f, "hello.txt", Dict{String, String}(), "md5")
end
