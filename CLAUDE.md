# ukrMassValuationSpatialExtract

Baseline for computing spatial covariates (distances on the sphere, exact raster extraction over parcel polygons) for mass valuation of agricultural land in Ukraine.

<!-- eb:conversation -->
## Communication standard

- Short replies: bullets, no preamble, no recap. Lead with the result.
- Code, commands, paths, quotes and error text stay verbatim, in fenced blocks.
- One question at a time, when the answer may change what you do next. Otherwise state the assumption and proceed.
- Do not narrate what you are about to do or restate what you did. Say what changed and what is left.
<!-- /eb:conversation -->

<!-- eb:docs -->
## Documentation of development work: `.docs/`

Each document is `NNNN-short-name.md`, next number = highest existing + 1. Templates are in `.docs/_templates/`; read the relevant template before writing a new entry. Never renumber, rename or delete an existing entry.

- `.docs/plans/`: detailed plans for multi-step tasks, ready for a fresh agent to implement: every step fully specified, references to the relevant context, and a status that tracks execution. Starts with date, author, status, goal.
- `.docs/handoffs/`: prompt and context that let a fresh agent pick up an unfinished task, written when the user asks: a full plan, the rest of one, or one task from it. With no plan attached, record the full context the task needs, so mentioning the handoff is enough to start. Starts with date, where things stand, how to verify, next steps.
- `.docs/notes/`: decisions, ideas, proposals or opinions from a chat session, written when the user says "note this" or "record", or when a decision is worth keeping. Starts with date, author, one-line summary, then the instruction quoted verbatim with only spelling, punctuation and structure fixed. If unsure whether to create a note, ask.
<!-- /eb:docs -->

<!-- eb:data -->
## Data and outputs

- `data/raw/`: source data as received. Never edit, rename or overwrite an existing file. Download scripts may add new source files in new subfolders (e.g. `data/raw/cod-ab/`, `data/raw/dem/`).
- Reference inputs (simulated parcels, elevators, roads) are generated once by a dedicated script, saved as Parquet/GeoParquet and committed as a fixed reference. That script is not re-run in the normal pipeline.
- `data/interim/`: intermediate files. Disposable, always regenerable from code.
- `data/clean/`: analysis-ready data, produced by code from `data/raw/`.
- Results: tables in `output/tables/`, figures in `output/figures/`. Everything under `output/` is produced by code and never edited by hand.
<!-- /eb:data -->

<!-- eb:r -->
## R

- Do all R work through the `run-r` skill: Positron's MCP server (`mcp__positron__*`). It covers connecting the server when the tools are missing; do not fall back to `Rscript` or `mcp-repl`.
- Prefer the `r-lib:*` skills, enabled for this project, over your own habits when writing R.
- User-facing messages use cli: `cli_abort()`, `cli_warn()`, `cli_inform()`, never bare `stop()`, `warning()`, `message()`.
- The project is a set of short, numbered R scripts in the project root. Each is run with `source()` and sources `00-setup.R` first.
- No helper functions, no `R/` package code, no vignettes. Only exceptions are those the plan in `.docs/plans/` allows.
- No regular expressions, no clever loops. Paths, year labels and variable names are written out in full.
- Each script header states In:, Out: and its purpose in one line.
- Code is tidyverse + `sf` + `terra` + `exactextractr`, written for novices, with few short comments.
- Build paths from the project root, never with `setwd()`.
<!-- /eb:r -->

<!-- eb:shiny -->
## Shiny

- Prefer the `shiny-dev:*` and `shiny:*` skills, enabled for this project, over your own habits when building an app.
- In R, layout and theming use bslib (`page_sidebar()`, `card()`, `bs_theme()`), never `fluidPage()`, `fluidRow()` or `shinythemes`.
<!-- /eb:shiny -->

<!-- eb:git -->
## Git

- Commit messages and pull-request text carry no email address and no AI attribution: no `Co-Authored-By`, no "Generated with". The hook in `.claude/hooks/no-coauthor.sh` blocks a violation; write different text, never work around it.
- Stage explicit paths, never `git add -A`. Commit only when asked.
<!-- /eb:git -->

