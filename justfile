# Main entry points of upstream-sync. Run `just` to list the recipes.

julia := env_var_or_default("JULIA", "julia")
cli := julia + " --project=" + justfile_directory() + " " + justfile_directory() / "bin" / "upstream-sync.jl"

default:
    @just --list

# Install the dependencies
instantiate:
    {{julia}} --project=. -e 'using Pkg; Pkg.instantiate()'

# Check for new upstream releases (exit 10 = new release available)
check name="":
    {{cli}} check {{name}}

# Import upstream release VERSION of NAME into the clone REPO (never pushes)
import name version repo *flags:
    {{cli}} import {{name}} {{version}} --repo {{repo}} {{flags}}

# Trial-merge upstream-import/VERSION into the fork branch, write a report
merge-plan name version repo *flags:
    {{cli}} merge-plan {{name}} {{version}} --repo {{repo}} {{flags}}

# List our fixes to the upstream sources (Markdown with GitHub links)
export name repo *flags:
    {{cli}} export {{name}} --repo {{repo}} {{flags}}

# Run the test suite
test:
    {{julia}} --project=. -e 'using Pkg; Pkg.test()'

# Build the documentation (warnings are errors)
docs:
    {{julia}} --project=docs -e 'using Pkg; Pkg.instantiate()'
    {{julia}} --project=docs docs/make.jl

# Regenerate llms.txt and llms-full.txt from docs/src
llms:
    {{julia}} --project=docs docs/llms.jl

# Remove the download cache and the documentation build
clean:
    rm -rf cache docs/build
