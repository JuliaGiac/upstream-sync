using Documenter
using UpstreamSync

makedocs(;
    sitename = "UpstreamSync",
    modules = [UpstreamSync],
    authors = "Sébastien Celles",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        repolink = "https://github.com/JuliaGiac/upstream-sync",
        canonical = "https://juliagiac.github.io/upstream-sync",
        # The JuliaGiac look, copied from JuliaGiac/site-kit (sync.jl documenter)
        assets = [
            "assets/juliagiac.css",
            asset("assets/favicon.png", class = :ico, islocal = true),
        ],
        footer = "upstream-sync is part of [JuliaGiac](https://juliagiac.github.io/), " *
                 "which brings [Giac](https://www-fourier.univ-grenoble-alpes.fr/~parisse/giac.html) " *
                 "(Bernard Parisse and Renée De Graeve) to Julia. " *
                 "Powered by [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl).",
    ),
    pages = [
        "Home" => "index.md",
        "Commands" => "commands.md",
        "Release procedure" => "release.md",
        "Configuration" => "configuration.md",
        "API" => "api.md",
    ],
    remotes = nothing,
    checkdocs = :all,
    warnonly = false,
)
