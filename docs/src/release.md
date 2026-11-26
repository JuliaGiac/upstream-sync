# Release procedure

The weekly workflow [`check-upstream.yml`](https://github.com/JuliaGiac/upstream-sync/blob/main/.github/workflows/check-upstream.yml)
runs `check` and opens (or updates) an issue "New upstream release: giac
X.Y.Z" in this repository. Then, for giac X.Y.Z:

1. **Check** (optional, the issue already did it):
   `julia --project=. bin/upstream-sync.jl check giac`
2. **Import** into an up-to-date clone of the fork:
   ```sh
   git -C ../giac fetch origin && git -C ../giac branch -f main origin/main
   julia --project=. bin/upstream-sync.jl import giac X.Y.Z --repo ../giac
   ```
   Review it: `git -C ../giac show --stat upstream-import/X.Y.Z`.
3. **Publish the import** (this tool never pushes):
   ```sh
   git -C ../giac push origin upstream-import/X.Y.Z
   gh pr create --repo JuliaGiac/giac --base main --head upstream-import/X.Y.Z \
     --title "import upstream giac X.Y.Z"
   ```
   Merge that pull request with **any** method (merge commit, squash or
   rebase).
4. **Tag the merged commit**, then push the tag:
   ```sh
   julia --project=. bin/upstream-sync.jl tag giac X.Y.Z --repo ../giac
   git -C ../giac push origin upstream/X.Y.Z
   ```
   `check` reads these `upstream/X.Y.Z` tags as the imported versions.
5. **Plan the fork update** (with `dev` up to date: `git -C ../giac pull --ff-only`):
   ```sh
   julia --project=. bin/upstream-sync.jl merge-plan giac X.Y.Z --repo ../giac \
     --resolve-expected
   ```
   Read `merge-plan-giac-X.Y.Z.md`: expected and real conflicts, upstream
   changes on files we patched. A "deleted by us" real conflict is a file
   `dev` removed outside `fork_excluded_paths`: keep the deletion or restore
   the file, and update `fork_excluded_paths` if the removal is intended.
6. **Merge into dev**: in the worktree `../giac-sync-X.Y.Z` (branch
   `sync/X.Y.Z`, merge in progress, expected conflicts already resolved),
   resolve the real conflicts, bump the version in `meson.build`, run the
   tests, `git commit`, push `sync/X.Y.Z` and open a pull request to `dev`.
   Then `git -C ../giac worktree remove ../giac-sync-X.Y.Z`.
7. **Send our fixes upstream**:
   `julia --project=. bin/upstream-sync.jl export giac --repo ../giac --output fixes.md`
   and send the links of the relevant commits to Bernard Parisse.
8. Close the issue.
