"""
    UpstreamSyncError(msg)

A user-facing error (bad configuration, missing branch, network failure,
...). The CLI prints the message and exits with status 1 (see [`ExitCode`](@ref)).
"""
struct UpstreamSyncError <: Exception
    msg::String
end

Base.showerror(io::IO, e::UpstreamSyncError) = print(io, e.msg)

"""
    ChecksumMismatch(file, algorithm, expected, actual)

The downloaded `file` does not have the checksum published upstream.
"""
struct ChecksumMismatch <: Exception
    file::String
    algorithm::String
    expected::String
    actual::String
end

function Base.showerror(io::IO, e::ChecksumMismatch)
    print(io, "$(uppercase(e.algorithm)) checksum mismatch for $(e.file): ",
        "expected $(e.expected), got $(e.actual)")
end

"""
Exit status of the `upstream-sync` command line tool.

- `ExitCode.OK` (0): success; for `check`, every upstream is up to date.
- `ExitCode.ERROR` (1): an error occurred.
- `ExitCode.NEW_RELEASE` (10): `check` found an upstream release newer than
  the latest `upstream/X.Y.Z` tag.
"""
module ExitCode
const T = Int
const OK = 0
const ERROR = 1
const NEW_RELEASE = 10
end
