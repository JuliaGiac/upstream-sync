using Documenter
using UpstreamSync

makedocs(;
    sitename = "UpstreamSync",
    modules = [UpstreamSync],
    authors = "Sébastien Celles",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        repolink = "https://github.com/JuliaGiac/upstream-sync",
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
