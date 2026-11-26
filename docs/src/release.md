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
   git -C ../giac push origin upstream/X.Y.Z
   gh pr create --repo JuliaGiac/giac --base main --head upstream-import/X.Y.Z \
     --title "import upstream giac X.Y.Z"
   ```
   Merge that pull request **with a merge commit** (not squash, not rebase)
   so that the tagged commit stays on `main`.
4. **Plan the fork update**:
   ```sh
   julia --project=. bin/upstream-sync.jl merge-plan giac X.Y.Z --repo ../giac
   ```
   Read `merge-plan-giac-X.Y.Z.md`: conflicts by area, upstream changes on
   files we patched.
5. **Merge into dev**: `git switch sync/X.Y.Z && git merge
   upstream-import/X.Y.Z`, resolve the conflicts ("deleted by us" files are
   usually kept deleted: `git rm`), bump the version in `meson.build`, run
   the tests, push `sync/X.Y.Z` and open a pull request to `dev`.
6. **Send our fixes upstream**:
   `julia --project=. bin/upstream-sync.jl export giac --repo ../giac --output fixes.md`
   and send the links of the relevant commits to Bernard Parisse.
7. Close the issue.
