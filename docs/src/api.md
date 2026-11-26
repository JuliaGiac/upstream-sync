# API

The command line tool is a thin wrapper around these functions; they can
also be used from Julia (`using UpstreamSync`).

## Entry points

```@docs
UpstreamSync
UpstreamSync.main
UpstreamSync.ExitCode
check
import_release
merge_plan
export_changes
```

## Results

```@docs
UpstreamSync.CheckResult
UpstreamSync.ImportResult
UpstreamSync.MergePlan
UpstreamSync.FileChange
UpstreamSync.Conflict
UpstreamSync.ExportReport
UpstreamSync.CommitInfo
```

## Configuration

```@docs
UpstreamSync.Upstream
UpstreamSync.load_config
UpstreamSync.default_config_path
UpstreamSync.get_upstream
UpstreamSync.fork_excluded
UpstreamSync.cache_dir
```

## Building blocks

```@docs
UpstreamSync.Release
UpstreamSync.parse_index
UpstreamSync.latest_release
UpstreamSync.parse_version
UpstreamSync.is_newer
UpstreamSync.parse_upstream_tags
UpstreamSync.imported_versions
UpstreamSync.parse_checksums
UpstreamSync.file_digest
UpstreamSync.checksum_ok
UpstreamSync.verify_checksum
UpstreamSync.fetch_text
UpstreamSync.fetch_release
UpstreamSync.extract_tarball
UpstreamSync.tarball_executables
UpstreamSync.build_tree
UpstreamSync.export_pathspecs
UpstreamSync.Area
UpstreamSync.area_title
UpstreamSync.pathmatch
UpstreamSync.classify
UpstreamSync.run_git
UpstreamSync.git
UpstreamSync.resolve_branch
UpstreamSync.check_not_stale
UpstreamSync.try_merge
UpstreamSync.default_sync_worktree
```

## Errors

```@docs
UpstreamSync.UpstreamSyncError
UpstreamSync.ChecksumMismatch
```
