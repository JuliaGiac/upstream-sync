#!/usr/bin/env julia
# Command line entry point of UpstreamSync.
#
#   julia --project=<path to upstream-sync> bin/upstream-sync.jl <command> ...
#
# Exit status: 0 = success / up to date, 1 = error,
#              10 = `check` found a new upstream release.

using UpstreamSync

exit(UpstreamSync.main(ARGS))
