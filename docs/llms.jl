# Generate llms.txt and llms-full.txt (https://llmstxt.org) from docs/src.
# Run from the project root: julia --project=docs docs/llms.jl  (or: just llms)

using UpstreamSync
using Markdown

const ROOT = dirname(@__DIR__)
const SRC = joinpath(ROOT, "docs", "src")
const BLOB = "https://github.com/JuliaGiac/upstream-sync/blob/main/"
const PAGES = [
    ("index.md", "Overview", "purpose, the main/dev convention, installation"),
    ("commands.md", "Commands", "check, import, merge-plan, export and exit status"),
    ("release.md", "Release procedure", "step by step, from the weekly issue to dev"),
    ("configuration.md", "Configuration", "upstreams.toml keys and environment"),
    ("api.md", "API", "Julia functions and result types"),
]

# Replace ```@docs blocks by the docstrings they list.
function expand_docs(text)
    return replace(text, r"```@docs\n(.*?)```"s => function (block)
        names = split(strip(match(r"```@docs\n(.*?)```"s, block)[1]), '\n')
        parts = String[]
        for name in names
            doc = Core.eval(Main, :(@doc $(Meta.parse(strip(name)))))
            text = doc isa Base.Docs.DocStr ? join(string.(doc.text)) : Markdown.plain(doc)
            push!(parts, "### `$(strip(name))`\n\n" * strip(text))
        end
        join(parts, "\n\n")
    end)
end

function main()
    summary = "Julia tooling that keeps the JuliaGiac forks (main = pristine " *
              "upstream tree tagged upstream/X.Y.Z, dev = our fork) in sync with " *
              "Bernard Parisse's Giac release tarballs: check for releases, import " *
              "a tarball as a tagged commit, plan the merge into dev, export our " *
              "fixes as GitHub commit links."
    open(joinpath(ROOT, "llms.txt"), "w") do io
        println(io, "# UpstreamSync\n")
        println(io, "> ", summary, "\n")
        println(io, "Command line: `julia --project=. bin/upstream-sync.jl <command>`; ",
            "exit status 0 = ok/up to date, 1 = error, 10 = new upstream release. ",
            "Nothing is ever pushed.\n")
        println(io, "## Docs\n")
        for (file, title, desc) in PAGES
            println(io, "- [$title]($(BLOB)docs/src/$file): $desc")
        end
        println(io, "\n## Optional\n")
        println(io, "- [Configuration file]($(BLOB)upstreams.toml): the configured upstreams")
        println(io, "- [Full documentation]($(BLOB)llms-full.txt): all pages in one file")
    end
    open(joinpath(ROOT, "llms-full.txt"), "w") do io
        println(io, "# UpstreamSync\n")
        println(io, "> ", summary, "\n")
        for (file, _, _) in PAGES
            text = read(joinpath(SRC, file), String)
            file == "api.md" && (text = expand_docs(text))
            println(io, "\n", strip(text), "\n")
        end
    end
    println("wrote llms.txt and llms-full.txt")
end

main()
