# Handoff: execute plan 0001 (spatial extraction pipeline and bilingual website)

- **Date:** 2026-11-10
- **Author:** Eduard Bukin (drafted with Claude)
- **Plan:** `.docs/plans/0001-spatial-extraction-pipeline.md` (v3)

## Where things stand

The task: execute plan 0001 end to end, tasks T01 to T16. That means R scripts that extract distance, soil, relief and crop covariates for 1,000 simulated parcels in Poltava oblast, a long output table of 81 variables, and a bilingual (English and Ukrainian) Quarto website on GitHub Pages.

- **Done:**
  - plan v3, reviewed twice;
  - `CLAUDE.md` aligned with the plan;
  - `renv` initialised;
  - remote `origin` set and pushed;
  - parallel Positron R sessions tested.
- **In progress:** nothing.
- **Not started:** T01–T16. No package beyond renv is installed, and no script exists.

## Files touched

- `.docs/plans/0001-spatial-extraction-pipeline.md`: the plan. Binding.
- `CLAUDE.md`: project rules (root scripts, R session lifecycle, data and website rules).

## How to verify

- The plan's Status reads `done` and every task box is ticked.
- `output/tables/spatial_covariates.parquet` has 81,000 rows (1,000 parcels × 81 variables).
- `https://ebukin.github.io/ukrMassValuationSpatialExtract/` returns HTTP 200 in English and in Ukrainian, with a working language switch.

## Next steps

1. Paste the kickoff prompt below into a fresh Claude Code session on Opus, in this project folder, with Positron open on this workspace.

### Kickoff prompt

````
You are the ORCHESTRATOR for plan .docs/plans/0001-spatial-extraction-pipeline.md in this repo. Execute it from T01 to T16.

Read first, fully: CLAUDE.md, the plan, and .docs/handoffs/0001-execute-plan-0001.md. The plan is binding. Its "Design rules", "Decisions", "Crop code table", "R sessions" and "Autonomy" sections override your habits.

Your role:
- You never write, edit, read or run project code, and you never run R. All of that is done by sub-agents.
- You dispatch sub-agents with the Agent tool (subagent_type "general-purpose", model "opus").
- You give each sub-agent a complete brief, read its short report, decide, and tick the plan's checkboxes and Status.
- Per task: one writer, then one independent verifier.
  - The verifier gets the task brief and acceptance criteria, not the writer's conclusions.
  - On failure: a new writer gets the verifier report, then re-verify. At most 3 rounds, then stop and report to the user.
- Run tasks in parallel where the plan's task table allows it, with at most 3 R sessions at once. T03 runs alone.
- Keep your own context small. Never ask a sub-agent for code or console dumps; reports are at most 15 lines.

Every sub-agent brief must contain:
1. The plan path and task ID, and the instruction to read CLAUDE.md, the plan's binding sections and the task section before starting.
2. "Do all R work through Positron's MCP server (mcp__positron__* tools; load them with ToolSearch; follow the run-r skill). Never use Rscript or mcp-repl. Never run code in the user's console."
3. The session lifecycle from the plan's "R sessions":
   - getActiveSessions to find runtimeId and the user's sessionId;
   - startNewConsoleSession;
   - pass session_id on every call;
   - quit(save = "no") with timeout_s 5 at the end, even after a failure;
   - selectSession to hand back the user's session.
   It must end its report with "session closed".
4. "Long jobs in your own session are pre-approved. Keep each execute_code call under 600 s (one script or one block per call). While developing you may use callr::r_bg and poll, but callr never appears in project scripts."
5. The report format: files changed, what ran, pass/fail per acceptance check, deviations with reasons, "session closed". At most 15 lines.

Authorisations granted by the user (plan "Autonomy"):
- commit and push to origin/main at commit points A–D, staging explicit paths only, with no AI attribution in messages;
- enable GitHub Pages from main /docs;
- the map review is waived (maps must be on the website);
- reading the OneDrive input folders through R.

Stop and report to the user only at the plan's failure stop points:
- package install failure;
- no GeoParquet writer;
- no H3 route (h3o / h3r);
- SSL workaround failure;
- soil layers not on one grid.

Commits are done by a sub-agent you dispatch at each commit point, with the exact file list from the plan.

When T16 passes:
- fill in the plan's Outcome and set Status to done;
- dispatch the final commit and push;
- report to the user: what shipped, the site URL, run times, deviations, and open questions.
````

## Gotchas

- **Decisions already made; do not reopen:**
  - Poltava only;
  - 1,000 parcels in a 70/15/15 split (interior / border / nodata);
  - GLO-30 default with no DEM resampling or reprojection (the tile spacing north of 50°N is accepted and documented);
  - a long table with no `stat` column;
  - soil 0–30 cm thickness-weighted, filled H3-6 → H3-5 → oblast;
  - 7 crop groups with code 18 → grass and not-cultivated → bare;
  - 2025 winter over summer per pixel inside parcels;
  - root scripts, no helpers, no regex;
  - EPSG:3035 for building parcels;
  - simulated elevators and roads.
- **No `h3jsr`** (V8 is fragile). Use `h3o`, fall back to `h3r`, otherwise stop. Never substitute a non-H3 grid.
- **SSL on this network:** downloads need `curl::new_handle(ssl_options = 2)` (no revocation check). CRAN works without it.
- **The MCP `execute_code` limit** interrupts the kernel after 600 s.
- **One agent cannot run two R jobs in parallel**, because its own tool calls are serialised. Parallelism comes from several sub-agents, each with its own session.
- **Closing a session:** `quit()` always reports a timeout; that is expected. Exited sessions stay listed in Positron until the user closes them.
- **The `01-simulate-reference.R` guard** aborts if the reference exists. While T04 is open, writers may delete `data/clean/reference/*`; the verifier checks the outputs and does not re-run the script.
- **Website:** static, rendered locally into `docs/` and committed. No GitHub Actions.
- **Never commit** soil, crop or DEM data. `data/raw/*` and `data/interim/*` are gitignored.
- **Keep Positron open** on this workspace for the whole run; all R goes through it.
