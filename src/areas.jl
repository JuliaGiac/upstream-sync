"""
Area of the tree a file belongs to, used to group merge conflicts.
Values: `Area.BUILD`, `Area.SRC`, `Area.DOCS`, `Area.OTHER`.
"""
module Area
@enum T BUILD SRC DOCS OTHER
end

const AREA_KEYS = (Area.BUILD => "build", Area.SRC => "src", Area.DOCS => "docs")

"""
    area_title(area) -> String
"""
area_title(a::Area.T) = a == Area.BUILD ? "Meson/build" :
                        a == Area.SRC ? "src fixes" :
                        a == Area.DOCS ? "docs" : "other"

function glob_regex(pattern::AbstractString)
    out = IOBuffer()
    cs = collect(pattern)
    i = 1
    while i <= length(cs)
        c = cs[i]
        if c == '*' && i < length(cs) && cs[i + 1] == '*'
            if i + 1 < length(cs) && cs[i + 2] == '/'
                print(out, "(?:.*/)?")
                i += 3
            else
                print(out, ".*")
                i += 2
            end
            continue
        elseif c == '*'
            print(out, "[^/]*")
        elseif c == '?'
            print(out, "[^/]")
        elseif c in ".+()[]{}^\$|\\"
            print(out, '\\', c)
        else
            print(out, c)
        end
        i += 1
    end
    return String(take!(out))
end

"""
    pathmatch(pattern, path) -> Bool

Match a repository path against a pattern:

- `dir/` (trailing slash) matches everything below `dir/`;
- a pattern containing `/` is a glob on the whole path (`*`, `?`, `**`);
- a pattern without `/` is a glob on the file name (`meson.build`,
  `*.md`), at any depth.
"""
function pathmatch(pattern::AbstractString, path::AbstractString)
    if endswith(pattern, "/")
        return occursin(Regex("^" * glob_regex(pattern)), path)
    elseif occursin('/', pattern)
        return occursin(Regex("^" * glob_regex(pattern) * "\$"), path)
    else
        return occursin(Regex("^" * glob_regex(pattern) * "\$"), basename(path))
    end
end

"""
    classify(path, areas) -> Area.T

First area (in the order build, src, docs) with a matching pattern;
`Area.OTHER` otherwise. `areas` maps `"build"`, `"src"`, `"docs"` to
pattern lists (see [`pathmatch`](@ref)).
"""
function classify(path::AbstractString, areas::AbstractDict)
    for (area, key) in AREA_KEYS
        any(p -> pathmatch(p, path), get(areas, key, String[])) && return area
    end
    return Area.OTHER
end
