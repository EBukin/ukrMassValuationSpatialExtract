# Spatial extraction pipeline: reference parcels in Poltava oblast to a long table of covariates, and a bilingual website

- **Date:** 2026-11-10 (v3: Poltava study area, execution review, parallel R sessions, website)
- **Author:** Eduard Bukin (drafted with Claude)
- **Status:** active

## Goal

A set of short R scripts in the project root, each run with `source()`, that:

1. download the public inputs (oblast boundaries, a 30 m DEM for Poltava oblast);
2. generate **once** a fixed reference set of 1,000 parcels, elevators and roads in **Poltava oblast**, committed to git;
3. extract distance, soil, relief and crop-cover covariates for every parcel;
4. write one long table, `parcel_id | variable | value | source`, with **81 variables per parcel**;
5. print and save descriptive statistics.

On top of that:

- a **bilingual website** (English first, then Ukrainian, with a language switch), built with Quarto and published on **GitHub Pages**. Section by section, it explains every indicator, the methodology and the variable names, and embeds the full code of each script;
- a short README that points to the site.

The repo ships no external data. Users provide the soil and crop rasters, public inputs are downloaded by a script, and only the simulated reference inputs, the results and the website are committed.

## How to execute this plan (orchestration)

An **orchestrator agent** runs this plan by dispatching sub-agents.

**What the orchestrator does:**
- dispatches and checks; it **never writes code and never runs R itself**;
- for each task, dispatches one **writer** sub-agent, then one **verifier** sub-agent (Agent tool, `general-purpose`, model `opus`), using the briefs in "Tasks". The kickoff prompt is in `.docs/handoffs/0001-execute-plan-0001.md`;
- reads only the sub-agents' reports, never code or console output, to save context;
- if a verifier reports a failure, dispatches a new writer with the verifier's report and the original brief, then verifies again, at most 3 rounds. After that it stops and reports to the user;
- ticks the task's checkbox in this file when its verification passes, and keeps **Status** current (`active` while running, `done` at the end);
- **commits and pushes** only at the milestones marked "Commit point", and only if the user has authorised that for this run (see "Autonomy"). Otherwise it stops at each commit point and asks;
- stops for the user only at the stop points named in the tasks.

**Every sub-agent brief must include:**
- this plan's path and the task ID;
- the instruction to read the project `CLAUDE.md`, then "Design rules", "Decisions", "Crop code table" and the task section before starting;
- the instruction to do all R work through Positron's MCP server (the `run-r` skill: `mcp__positron__*` tools), never `Rscript` or `mcp-repl`;
- the session lifecycle from "R sessions": start its own session, use it for every call, then `quit()` it and hand back the foreground;
- the instruction to return a report of **at most 15 lines**: files changed, what was run, the pass/fail result of each acceptance check, any deviation from the plan with its reason, and the words "session closed".

**Long jobs are approved in advance.** The `run-r` skill says not to start a long job without asking. For this plan, any job in a sub-agent's own session is approved, so sub-agents must not stop to ask.

### R sessions

Parallel sessions were tested on 2026-11-10. Two agents ran 15-second jobs that overlapped in time, and both R processes were gone after `quit()`.

- All R runs through Positron's MCP server, in the user's Positron workspace. **No sub-agent runs code in the user's console.**
- **Every R-running sub-agent (writer or verifier) starts its own R session at the beginning and closes it at the end:**
  1. `run_positron_command` `workbench.action.language.runtime.getActiveSessions` with `["r"]`: note the R `runtimeId` and the user's foreground `sessionId`.
  2. `run_positron_command` `workbench.action.language.runtime.startNewConsoleSession` with `[runtimeId]`, which returns the agent's `sessionId`.
  3. Pass that `session_id` to **every** `execute_code` / `evaluate_code` call. Never rely on the foreground default, since all sessions share the display name `R 4.6.1`.
  4. Finish with `execute_code` `quit(save = "no")` and `timeout_s` 5, even after a failure. The call always times out because the process dies; `list_sessions` then shows `exited` and the memory is freed.
  5. `run_positron_command` `workbench.action.language.runtime.selectSession` with the user's `sessionId`, to hand the foreground back.
- New sessions start in the project folder on the project's renv library (`.Rprofile` → `renv/activate.R`), as tested.
- A fresh session is also the clean state verifiers need.
- **Parallelism:** at most **3 R sessions** running at once. Never two agents in one session. Tasks that write the same file never run together, and T03 (downloads) runs alone.
- Never restart, clear or `quit()` the user's own session.
- If a report lacks "session closed", the orchestrator dispatches a small agent to `quit()` that session.
- **The 600-second limit:** `execute_code` interrupts the kernel after `timeout_s` (at most 600). To stay under it:
  - run one script, or one block of a script, per call, with `timeout_s = 600`;
  - split the work into smaller calls where needed: one crop year per call while developing, one download block per call;
  - **while developing only**, a sub-agent may run a long job in the background with `callr::r_bg(\(f) source(f), list("<script>.R"))` and poll it with `evaluate_code`. `callr` never appears in the project scripts.

### Autonomy

**Granted by the user on 2026-11-10.** The orchestrator runs from T01 to T16 without the user:

1. **Commits and pushes** to `origin/main` at the commit points (A–D) are authorised. Stage explicit paths only; commit messages carry no AI attribution.
2. **Enabling GitHub Pages** for the public repo is authorised.
3. **The map review is waived.** The user reviews the maps later, on the website. The maps must be embedded there (T13).
4. **Reading the OneDrive input folders** (soil, crop) is authorised, through R.

The remaining stop points are failure cases only:
- a package can't be installed;
- no GeoParquet writer works;
- no H3 route works (T01 step 3b);
- a download still fails with the SSL workaround;
- the soil layers are not on one grid.

At a stop point the orchestrator reports to the user and waits.

## Context

- The README objective: build a reference dataset of spatial covariates that other implementations (other software or teams) can compare against.
- All decisions below were confirmed by the user in chat on 2026-11-10, after two independent reviews.
- The project `CLAUDE.md` matches this plan: root scripts, no `R/` package code, no vignettes, committed reference inputs, one R session per agent.
- Git remote: `origin` = `https://github.com/EBukin/ukrMassValuationSpatialExtract` (public), branch `main`.
- Quarto 1.9 is installed.
- `renv` is initialised (R 4.6.1), and the user's console is on the project library. Only renv is installed.
- `.gitignore` ignores `data/raw/*` and `data/interim/*`. `data/clean/`, `output/` and `docs/` are tracked.
- `data/raw/oblast.geojson` is left in place and not used.
- **`data/raw/` rule:** existing files are never edited, renamed or deleted. Download scripts may add new subfolders.
- **Network:** HTTPS to HDX and to the AWS buckets fails with the Schannel error `CRYPT_E_NO_REVOCATION_CHECK`; CRAN works. Downloads need the revocation check off (T03).
- Input folders, outside the repo, read-only:
  - soil: `C:/Users/wb532966/OneDrive - WBG/DEC/data-EB/ukrSoilgridsData/data-raw/ukr`
    - SoilGrids GeoTIFFs, e.g. `clay_0-5cm_mean.tif`; units in `../README.md`;
    - may be OneDrive online-only (the user knows this); they download on first read.
  - crop: `C:/Users/wb532966/OneDrive - WBG/DEC/data-EB/ukrCropCover/original-crop-cover-maps`
    - one classified GeoTIFF per year, EPSG:32636, 10 m, uint8, LZW, striped;
    - 2020–2025 share 132874×88823 pixels; 2019 is 134691×90772;
    - only the 2019 map declares NoData (0), but 0 is background in every year.
- **COD-AB** (checked via the HDX API): resources `ukr_admin_boundaries.{shp,gdb,geojson}.zip`, modified 2026-01-26, licence CC BY-IGO. Field names are probably lowercase (`adm1_pcode`, `adm1_name`, `adm1_name1`); T03 maps them.
- **Copernicus DEM:** bucket and tile naming confirmed (GLO-90 N50 E030 returns HTTP 200). North of 50°N, tiles have 1.5× the longitude spacing of the tiles to the south.

### Design rules (binding)

- **Simple code for novices.** tidyverse, `dplyr`, `sf`, `terra`, `exactextractr`. Short scripts, few short comments.
- **No helper functions, no `R/` folder, no vignettes.** Scripts sit in the project root. Allowed exceptions:
  - a one-line inline `nearest_dist()` in `03-distance.R`;
  - an anonymous function inside `pmap()` in `01-simulate-reference.R`.
- **No regular expressions, no clever loops, no `if` ladders.**
  - File paths, year labels and variable names are written out in full.
  - Each crop year gets its own explicit block.
  - Allowed:
    - vectorised calls (`curl::multi_download()`);
    - literal `names_prefix =`;
    - `sprintf("%03d", ...)`;
    - **any number of one-line guard checks** `if (<condition>) cli_abort(...)`.
- **Each script header** states what it reads (In:), what it writes (Out:), and its purpose in one line.
- **User-facing messages use cli** (`cli_inform()`, `cli_abort()`).
- **Paths** come from objects defined in `00-setup.R`, never `setwd()`.
- **No reprojection or resampling of rasters**; vectors are transformed to each raster's CRS instead. The only raster operations allowed are:
  - the virtual mosaic of DEM tiles (`vrt()`);
  - `crop()`;
  - per-pixel arithmetic on rasters that share a grid (soil depths; slope and aspect);
  - `terrain()`.
- **Projections.**
  - Each extraction block transforms the parcels to that raster's CRS, extracts, and keeps only `parcel_id` plus the values.
  - `crs_work <- "EPSG:3035"` (equal-area, metres) is used to build parcel shapes, compute `area_ha` and draw maps.
- **Distances** are measured on the sphere: sf with s2 on lon/lat (EPSG:4326), cross-checked against ellipsoidal distances.
- **Long table.**
  - Columns: `parcel_id | variable | value | source`.
  - No `stat` column; each measurement method is its own variable (`_mean`, `_centroid`, `_edge`, `_max`, `_range`).
  - `source` takes one of `observed`, `h3_6`, `h3_5`, `oblast`; only soil rows can be non-`observed`.

### Decisions (binding)

| Topic | Decision |
|---|---|
| Study area | **Poltava oblast** (`study_oblast_en <- "Poltava"` in setup; the P-code is looked up from COD-AB). It has towns (Poltava, Kremenchuk, Lubny, ...), the Dnipro and the Kremenchuk reservoir, and 7 neighbouring oblasts. All simulated features lie inside Poltava. A `border` parcel may extend into a neighbour. |
| Reference inputs | `01-simulate-reference.R` generates 1,000 parcels, 30 elevators and the roads **once**. They are written as GeoParquet in `data/clean/reference/`, in EPSG:4326, and committed. A guard aborts the script if the files already exist. |
| Parcels | 1,000; area 1–10 ha, mostly 2–4 ha, built in EPSG:3035; rectangles and parallelograms. Cases: 70 % `interior`; 15 % `border`, crossing Poltava's boundary with a neighbouring oblast; 15 % `nodata`, centred on soil NoData (towns, rivers, the reservoir). At least 30 `nodata` parcels sit near a town and at least 30 near water (checked in T04). |
| Oblasts | OCHA COD-AB Ukraine, ADM1, national file. Fields renamed to `oblast_pcode`, `oblast_ua`, `oblast_en`. |
| DEM | Copernicus **GLO-30 by default** (`dem_product <- "GLO-30"`; `"GLO-90"` is the switch). Only tiles intersecting Poltava oblast plus a 10 km buffer, about 12 tiles. Merged with `vrt()` and **no resampling step of our own**. Tiles north of 50°N have coarser longitude spacing; the virtual mosaic repeats their pixels on the finer grid (GDAL nearest neighbour, on the fly, no extra computation). That can add small stair-steps to slope and aspect in Poltava's northern strip. The website documents this limitation. |
| Elevators, roads | Simulated in the reference script, inside Poltava: 30 elevators, 4 main roads, 50 local roads. Roads are densified to ≤ 1 km with `st_segmentize()`. Real OSM roads are an optional, commented-out block. |
| Distance | Nearest feature only: `st_nearest_feature()` then `st_distance(..., by_element = TRUE)`, from the centroid and from the edge. The gap between spherical and ellipsoidal distance is reported. |
| Soil | One topsoil 0–30 cm variable per property: `(5·d0_5 + 10·d5_15 + 15·d15_30) / 30`, computed per pixel on the cropped grid. `ocs` is already 0–30 cm. The 10 properties × (`_mean`, `_centroid`) give **20 variables**. SoilGrids mapped units. |
| Soil NoData | Fill order: H3 res-6 → H3 res-5 → oblast mean (Poltava and its neighbours). The level goes in `source`. A marked "fill zones" block shows where to swap in rayon or hromada polygons. Partial soil coverage counts as `observed`. |
| Relief | User methodology (T08). **6 variables**, polygon only. `flat_slope_deg <- 0.5`. |
| Crop | **7 groups × 7 years = 49 variables**, named `crop_<group>_<year>`. Groups: `built`, `ag`, `forest`, `grass`, `bare`, `water`, `other`. One code table for all years. 0 is NoData. 2025: winter crop pixels (2, 3) take precedence over summer, applied per pixel inside parcels. |
| Variable count | 6 + 20 + 6 + 49 = **81**. |
| Outputs | `output/tables/spatial_covariates.parquet` (committed); `spatial_covariates.csv` (written, gitignored); descriptives in `output/tables/` and `output/figures/`. |
| Website | Quarto website in `site/`, rendered to `docs/` and served by GitHub Pages from `main` `/docs`. English pages in `site/en/`, Ukrainian in `site/uk/`, with a navbar language switch. Each script page embeds the full script verbatim from the root file. Variable names, code and file names stay in English on the Ukrainian pages. |
| Script numbers | `00-setup.R`, `00b-download.R`, `01-simulate-reference.R`, `02-diagnostics.R`, `03-distance.R`, `04-soil.R`, `05-relief.R`, `06-crop.R`, `07-crop-2025.R`, `21-combine.R`, `22-descriptives.R`. |

### Crop code table (harmonised across years, binding)

Categories are matched by label. "Not cultivated" is 22 in 2022 and 20 from 2023; "Damaged forest" is 23 in 2022 and 25 from 2024. No code means two unrelated things in different years, so **one `tribble(code, group)` in `00-setup.R` serves every year.** This wide table is reproduced on the website.

| group | category | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 summer | 2025 winter |
|---|---|---|---|---|---|---|---|---|---|
| built | Artificial | 1 | 1 | 1 | 1 | 1 | 1 | 1 | |
| ag | Wheat | 2 | 2 | 2 | 2 | 2 | 2 | 2 | |
| ag | Winter cereal | | | | | | | | 2 |
| ag | Rapeseed | 3 | 3 | 3 | 3 | 3 | 3 | 3 | |
| ag | Winter rapeseed | | | | | | | | 3 |
| ag | Buckwheat | 4 | 4 | 4 | 4 | 4 | 4 | 4 | |
| ag | Maize | 5 | 5 | 5 | 5 | 5 | 5 | 5 | |
| ag | Sugar beet | 6 | 6 | 6 | 6 | 6 | 6 | 6 | |
| ag | Sunflower | 7 | 7 | 7 | 7 | 7 | 7 | 7 | |
| ag | Soybeans | 8 | 8 | 8 | 8 | 8 | 8 | 8 | |
| ag | Other crops | 9 | 9 | 9 | 9 | 9 | 9 | 9 | |
| ag | Barley | 15 | 15 | 15 | 15 | 15 | 15 | 15 (Winter barley) | |
| ag | Peas | 16 | 16 | 16 | 16 | 16 | 16 | 16 | |
| ag | Alfalfa | 17 | 17 | 17 | 17 | 17 | 17 | 17 | |
| ag | Grape | 19 | 19 | 19 | 19 | 19 | 19 | 19 | |
| ag | Potatoes | | | | 21 | 21 | 21 | 21 | |
| ag | Tomato | | | | | | | 24 | |
| ag | Nut trees | | | | | | | 26 | |
| ag | Other cereal | | | | | | | 27 | |
| forest | Forest | 10 | 10 | 10 | 10 | 10 | 10 | 10 | |
| forest | Damaged forest | | | | 23 | | 25 | 25 | |
| grass | Grassland | 11 | 11 | 11 | 11 | 11 | 11 | 11 | |
| grass | Gardens, parks / Low trees | 18 | 18 | 18 | 18 | | 18 | 18 (Low trees) | |
| bare | Bare land | 12 | 12 | 12 | 12 | 12 | 12 | 12 | |
| bare | Not cultivated / Uncultivated | | | | 22 | 20 | 20 | 20 | |
| water | Water | 13 | 13 | 13 | 13 | 13 | 13 | 13 | |
| water | Wetland | 14 | 14 | 14 | 14 | 14 | 14 | 14 | |
| other | any code not listed | | | | | | | | |
| (NoData) | 0 | NA | NA | NA | NA | NA | NA | NA | NA |

```r
crop_groups <- tribble(
  ~code, ~group,
  1,  "built",
  2,  "ag",  3,  "ag",  4,  "ag",  5,  "ag",  6,  "ag",  7,  "ag",  8,  "ag",  9,  "ag",
  15, "ag",  16, "ag",  17, "ag",  19, "ag",  21, "ag",  24, "ag",  26, "ag",  27, "ag",
  10, "forest", 23, "forest", 25, "forest",
  11, "grass",  18, "grass",
  12, "bare",   20, "bare",   22, "bare",
  13, "water",  14, "water"
)
```

## Tasks

| Task | Can start after | Parallel with |
|---|---|---|
| T01 environment and checks | — | — |
| T02 `00-setup.R` | T01 | — |
| T03 `00b-download.R` | T02 | — (runs alone) |
| T04 `01-simulate-reference.R` | T03 | — |
| T05 `02-diagnostics.R` | T04 | T06–T10 |
| T06–T10 extraction scripts | T04 | each other (at most 3 R sessions) |
| T11 `21-combine.R` | T06–T10 | — |
| T12 `22-descriptives.R` | T11 | — |
| T13 website, English | T12 | — |
| T14 website, Ukrainian | T13 | — |
| T15 GitHub Pages publish | T14 | — |
| T16 full run and handover | T15 | — |

---

### T01: environment and checks

- [x] **Writer brief**, in its own R session:
  1. `renv::settings$snapshot.type("all")`.
  2. Install into the project library, one or a few packages per call (600 s limit): `tidyverse`, `sf`, `terra`, `exactextractr`, `arrow`, `geoarrow`, `h3o`, `curl`, `cli`, `lwgeom`, `osmextract`, `knitr`, `rmarkdown`. Then `renv::snapshot()`.
     - **No `h3jsr`**: it depends on V8 (JavaScript), which is fragile on Windows.
  3b. **H3 route.** Prove with 3 test points in Poltava that `h3o` can do two things:
     - return the res-6 and res-5 cell IDs of a point: `h3o::h3_from_points(points, resolution)`, then `as.character()`;
     - turn cell IDs into hexagon polygons: `sf::st_as_sfc()` on the H3 vector, or `h3o::sfc()`.

     Record the exact calls in the note. If `h3o` fails, try `h3r` (C bindings: `latLngToCell()`, `cellToBoundary()`). If both fail, it is a stop point; do not invent a non-H3 grid.
  3. Choose **one** GeoParquet read/write pair that every script will use:
     - if `"Parquet" %in% sf::st_drivers()$name`, use `st_write(..., driver = "Parquet")` and `st_read()`;
     - otherwise, use `geoarrow` with `arrow::write_parquet()` / `read_parquet()` + `st_as_sf()`.

     Round-trip a small sf object to prove it works. Record the exact two lines.
  4. Test the SSL workaround with one small request:
     - `curl::curl_fetch_memory("https://data.humdata.org/api/3/action/package_show?id=cod-ab-ukr", handle = curl::new_handle(ssl_options = 2))`, where 2 = no-revoke;
     - if that fails, try `Sys.setenv(CURL_SSL_BACKEND = "openssl")` in a fresh session before curl loads;
     - record which works.
  5. Record raster facts:
     - for the 28 soil files used in T07: CRS, resolution, NoData, and one grid (`compareGeom()`);
     - for the 8 crop files: CRS and extent;
     - for the 2025 summer and winter maps: origins, and their difference in metres.
  6. Write `.docs/notes/0001-input-raster-check.md` (template `.docs/_templates/note.md`) with all findings, including the chosen GeoParquet pair and the SSL method.
- [x] **Acceptance:**
  - `renv::status()` is clean and `renv.lock` lists the packages;
  - the GeoParquet round trip and the SSL test pass;
  - the note is complete.
- [x] **Stop points:**
  - a package can't be installed;
  - no GeoParquet pair works;
  - the SSL test fails both ways;
  - soil layers are not on one grid.

### T02: `00-setup.R`

- [x] **Writer brief.** `00-setup.R` is sourced first by every script. It contains:
  - `library()` for the T01 packages, excluding `osmextract`, `knitr` and `rmarkdown`; `sf_use_s2(TRUE)`.
  - Parameters, each with a one-line comment:
    - `n_parcels <- 1000`;
    - `study_oblast_en <- "Poltava"`;
    - `crs_work <- "EPSG:3035"`;
    - `dem_product <- "GLO-30"` (or `"GLO-90"`);
    - `flat_slope_deg <- 0.5`.
  - `soil_dir`, `crop_dir`, and the crop file objects `crop_2019` … `crop_2024`, `crop_2025_summer`, `crop_2025_winter`, written out in full:

    | Object | File |
    |---|---|
    | `crop_2019` | `GEE_15102019.tif` |
    | `crop_2020` | `ukr_2020.tif` |
    | `crop_2021` | `Ukr_October2021.tif` |
    | `crop_2022` | `Ukraine_August2022_corr.tif` |
    | `crop_2023` | `Ukraine_2023_01_September.tif` |
    | `crop_2024` | `Ukraine_september_2024.tif` |
    | `crop_2025_summer` | `SummerMap_Ukraine_2025_WB.tif` |
    | `crop_2025_winter` | `Winter2025_Rape_Cereal.tif` |

  - `crop_groups`, exactly as in "Crop code table".
  - Paths, one object each:
    - `codab_dir`, `dem_dir`;
    - reference: `data/clean/reference/parcels.parquet`, `elevators.parquet`, `roads.parquet`;
    - interim: `data/interim/oblasts.gpkg`, `dem.vrt`, `soil_topsoil_0_30cm.tif`, each `long_*.parquet`;
    - all output files.
  - `dir.create(..., recursive = TRUE, showWarnings = FALSE)` for the output folders.
- [x] **Acceptance:**
  - sources clean in a fresh session;
  - the 8 crop files and `soil_dir` exist; downloads and reference files are not checked here;
  - follows the design rules.

### T03: `00b-download.R` (runs alone)

- [x] **Writer brief.** The header lists each download's source URL, licence, size and destination. Each block skips existing files. One handle is used for all downloads, using T01's SSL method, with a comment explaining why: `h <- curl::new_handle(ssl_options = 2)  # this network cannot check certificate revocation`.
  - **COD-AB block:**
    - download the ADM1-containing zip (shapefile or geojson variant, whichever T01 confirms) into `codab_dir` and unzip;
    - rename fields to `oblast_pcode`, `oblast_ua`, `oblast_en`, and report the original names;
    - inform about the count (27 expected);
    - write `data/interim/oblasts.gpkg`, all oblasts.
  - **DEM block:**
    - product table:

      ```r
      dem_products <- tribble(
        ~product, ~bucket,                                         ~code,
        "GLO-30", "https://copernicus-dem-30m.s3.amazonaws.com",  "10",
        "GLO-90", "https://copernicus-dem-90m.s3.amazonaws.com",  "30"
      ) |> filter(product == dem_product)
      ```

    - tile boxes from `st_make_grid(cellsize = 1, offset = c(22, 44), n = c(19, 9), crs = 4326)`, kept where they intersect Poltava plus 10 km;
    - corner coordinates via `round()`;
    - tile ID: `str_c("Copernicus_DSM_COG_", code, "_N", lat, "_00_E", sprintf("%03d", lon), "_00_DEM")`;
    - URL: `{bucket}/{id}/{id}.tif`; destination: `file.path(dem_dir, dem_product, str_c(id, ".tif"))`;
    - `res <- curl::multi_download(urls, dests, handle = h)`;
    - `file.remove()` the destinations whose `status_code != 200`, because a 404 leaves an error page on disk;
    - `vrt(files_ok, filename = dem_vrt_path)`, with **no** resolution or resampling options. A comment explains that the tiles north of 50°N have coarser longitude spacing, which GDAL repeats on the fly.
  - **Optional OSM roads**, commented out: `osmextract::oe_get("Ukraine", layer = "lines")`. Main = `motorway`, `trunk`, `primary`; local = `secondary`, `tertiary`; output to `data/raw/osm/`.
- [x] **Acceptance:**
  - `oblasts.gpkg` has the three fields and includes Poltava;
  - `rast(dem.vrt)` covers Poltava plus 10 km;
  - no stub files remain;
  - a second run downloads nothing.

### T04: `01-simulate-reference.R` (run once, then committed)

- [x] **Writer brief.**
  - **In:** `oblasts.gpkg`, `clay_0-5cm_mean.tif`, `crop_2024` (only to tell towns from water when checking). **Out:** the three reference files, written with T01's GeoParquet pair, in EPSG:4326.
  - Guard: `if (file.exists(parcels_path)) cli_abort("Reference inputs already exist. They are fixed: do not regenerate.")`. The header explains that this ran once to create the committed reference, and is not part of the normal run.
  - **While T04 is open**, writers may delete `data/clean/reference/*` before re-sourcing.
  - `set.seed(20261110)`.
  - `poltava` = the oblast where `oblast_en == study_oblast_en`; neighbours = oblasts touching it. Work in EPSG:3035.
  - Parcel centres:
    - `interior` (700): `st_sample(poltava)`, keeping points more than 1 km from Poltava's boundary;
    - `border` (150): `st_sample()` on the parts of Poltava's boundary shared with neighbouring oblasts;
    - `nodata` (150): `terra::spatSample()` on the soil NA cells inside Poltava shrunk by 1 km, shifted by at most 100 m.
  - Shape, inline in `mutate()` and `pmap()`:
    - `area_ha = pmin(pmax(rlnorm(n, log(3), 0.25), 1), 10)`;
    - aspect ratio `runif(n, 1.5, 6)`;
    - angle `runif(n, 0, pi)`;
    - shear `if_else(runif(n) < 0.5, 0, runif(n, 0.2, 0.5))`.

    Build from a unit square by scale → shear → rotate → translate.
  - Attributes:
    - `parcel_id` (`sprintf("P%05d", ...)`), `case`, `area_ha` (`st_area` in EPSG:3035);
    - `oblast` (largest overlap);
    - `h3_6`, `h3_5`: H3 cell IDs (character) of the WGS84 centroid, using the calls recorded in T01's note (`h3o`).
  - Elevators: 30 points from `st_sample(poltava)`.
  - Roads:
    - main: 4 lines crossing Poltava between random points on its boundary;
    - local: 50 lines of 5–20 km from random points in a random direction;
    - all clipped to Poltava and densified to ≤ 1 km (`st_segmentize(dfMaxLength = 1000)`), with `road_id` and `type`.
  - Print counts by case, an area summary, and road counts.
- [x] **Acceptance**, checked from the outputs; the verifier does not re-run the script and only confirms that the guard aborts:
  - 1,000 parcels with unique IDs and valid geometries;
  - at least 75 % in 2–4 ha, all in 1–10 ha;
  - every `border` parcel intersects Poltava and at least one neighbour;
  - at least 70 % of `nodata` parcels have more than 50 % of their area on soil NoData;
  - among `nodata` parcels, at least 30 have crop code 1 (built) as the majority pixel in 2024, and at least 30 have water (13 or 14) in the parcel or within 500 m. If either count is short, the writer adds targeted samples and reports it;
  - elevators and roads lie inside Poltava.
- [x] The map review is waived (see "Autonomy"). The verifier's checks decide.
- [x] **Commit point A** (after T05 passes): `data/clean/reference/*.parquet`, `00-setup.R`, `00b-download.R`, `01-simulate-reference.R`, `02-diagnostics.R`, `renv.lock`, `renv/settings.json`, `.docs/notes/0001-input-raster-check.md`, this plan.

### T05: `02-diagnostics.R`

- [x] **Writer brief.**
  - **In:** oblasts, the reference files, `clay_0-5cm_mean.tif`. **Out:** `output/figures/parcels-map.png`, `output/figures/parcels-zoom.png`.
  - Poltava map in EPSG:3035: Poltava and its neighbours' outlines, parcels coloured by `case`, elevators, roads by type, and the soil NoData area shaded.
  - Zoom: three panels, one parcel each for `interior`, `border` and `nodata`.
  - Print counts and areas by `case` and `oblast`.
- [x] **Acceptance:** both PNGs exist and look right (the verifier views them with Read); the table prints.

### T06: `03-distance.R`

- [ ] **Writer brief.**
  - **In:** the reference files in EPSG:4326. **Out:** `data/interim/long_distance.parquet`, `output/tables/distance_sphere_vs_ellipsoid.csv`.
  - Variables, in metres, via `st_distance(from, to[st_nearest_feature(from, to), ], by_element = TRUE)`:
    - `dist_elevator_centroid`, `dist_elevator_edge`;
    - `dist_road_main_centroid`, `dist_road_main_edge`;
    - `dist_road_local_centroid`, `dist_road_local_edge`.
  - Long format, with `value = as.numeric()` and `source = "observed"`.
  - Check block: recompute the same pairs with `sf_use_s2(FALSE)` (ellipsoidal via lwgeom), then turn s2 back on. Write per variable the mean and max absolute gap in m and the mean relative gap in %, and print it.
- [ ] **Acceptance:**
  - 6 rows per parcel, no NA;
  - edge ≤ centroid;
  - mean relative gap < 0.5 %;
  - a 3-parcel spot check against all features matches.

### T07: `04-soil.R`

- [x] **Writer brief.**
  - **In:** parcels, oblasts, 28 SoilGrids rasters. **Out:** `data/interim/soil_topsoil_0_30cm.tif`, `data/interim/long_soil.parquet`.
  - Crop each depth raster to Poltava plus its neighbours (in the soil CRS) before the arithmetic. One explicit expression per property:

    ```r
    # Topsoil 0-30 cm: thickness-weighted average of the 0-5, 5-15 and 15-30 cm layers
    soil_clay_0_30cm <- (5  * crop(rast(file.path(soil_dir, "clay_0-5cm_mean.tif")),   study_box) +
                         10 * crop(rast(file.path(soil_dir, "clay_5-15cm_mean.tif")),  study_box) +
                         15 * crop(rast(file.path(soil_dir, "clay_15-30cm_mean.tif")), study_box)) / 30
    ```

    Do this for bdod, cec, cfvo, clay, nitrogen, ocd, phh2o, sand and silt. Add the cropped `ocs_0-30cm_mean.tif`. Combine with `c()`, name the layers, and `writeRaster()`.
  - H3 hexagon polygons from the parcels' unique `h3_6` and `h3_5` IDs, using the calls recorded in T01's note (`h3o`). They are derived here, not stored.
  - Parcel values:
    - `exact_extract(soil, parcels, "mean", append_cols = "parcel_id")` for `_mean`;
    - `terra::extract(soil, vect(st_centroid(parcels)), ID = FALSE)` for `_centroid`;
    - long, with `value_raw`.
  - Fill-zones block, with a banner comment:
    - zone means over the H3-6 cells, the H3-5 cells, and Poltava with its neighbours;
    - a comment explains how to swap in rayon or hromada polygons (COD-AB ADM2/ADM3).
  - Fill:
    - `value = coalesce(value_raw, h3_6_value, h3_5_value, oblast_value)`;
    - `source = case_when(!is.na(value_raw) ~ "observed", !is.na(h3_6_value) ~ "h3_6", !is.na(h3_5_value) ~ "h3_5", !is.na(oblast_value) ~ "oblast")`;
    - `if (anyNA(...)) cli_abort(...)`.
  - Names: `soil_<prop>_0_30cm_mean` and `soil_<prop>_0_30cm_centroid`, in full. Header documents units and fill order. Print counts by `source` and `case`.
- [x] **Acceptance:**
  - 20 rows per parcel, no NA;
  - non-`observed` rows mostly from `nodata` parcels;
  - spot check: one centroid value equals the formula computed by hand.

### T08: `05-relief.R` (user methodology, binding)

Methodology from the user:
- Statistics come from the whole parcel polygon via `exactextractr::exact_extract()`, each pixel weighted by its coverage fraction; never from the centroid or from pixel centres.
- Aspect is clockwise from north in degrees. A flat pixel (slope < `flat_slope_deg`) contributes 0 to both aspect variables.
- Slope and aspect use a projected CRS in metres or a geodesic-aware method, never degrees treated as metres and never Web Mercator.
- A parcel smaller than one pixel still gets values.
- Output: complete values for every parcel.

- [ ] **Writer brief.**
  - **In:** parcels, `dem.vrt`. **Out:** `data/interim/long_relief.parquet`.
  - `dem <- crop(rast(dem_vrt_path), <parcels' extent + 0.02°>)`.
  - `terrain(dem, c("slope", "aspect"), unit = "degrees")`. For lon/lat input, terra computes cell distances on the ellipsoid; the verifier confirms this from terra's documentation and the header cites it.
  - Exposure:
    - `south <- ifel(slope < flat_slope_deg, 0, -cos(aspect * pi / 180))`;
    - `east <- ifel(slope < flat_slope_deg, 0, sin(aspect * pi / 180))`.
  - One `exact_extract()` on `c(elev, slope, south, east)` with `c("mean", "max", "min")`. Keep:

    | Variable | Definition |
    |---|---|
    | `relief_elev_mean` | coverage-weighted mean elevation, m |
    | `relief_slope_mean` | coverage-weighted mean slope, degrees |
    | `relief_slope_max` | max slope over pixels touching the parcel |
    | `relief_elev_range` | max − min elevation over pixels touching the parcel, m |
    | `relief_aspect_south` | coverage-weighted mean of `south`, −1 to 1 |
    | `relief_aspect_east` | coverage-weighted mean of `east`, −1 to 1 |

  - `if (anyNA(...)) cli_abort(...)`; `source = "observed"`.
- [ ] **Acceptance:**
  - 6 rows per parcel, no NA;
  - aspect in [−1, 1], slope in [0, 90], range ≥ 0;
  - runs in under 600 s with GLO-30.

### T09: `06-crop.R` (2019–2024)

- [x] **Writer brief.**
  - **In:** parcels, `crop_2019` … `crop_2024`, `crop_groups`. **Out:** `data/interim/long_crop.parquet`.
  - Six explicit blocks, the year written in full in each:
    1. `r <- rast(crop_2019); NAflag(r) <- 0`;
    2. `p <- st_transform(parcels, crs(r))`;
    3. `exact_extract(r, p, "frac", append_cols = "parcel_id")`;
    4. `pivot_longer(starts_with("frac_"), names_to = "code", names_prefix = "frac_", names_transform = as.integer, values_to = "share", values_drop_na = TRUE)`;
    5. `left_join(crop_groups, by = "code") |> mutate(group = coalesce(group, "other"))`;
    6. `summarise(value = sum(share), .by = c(parcel_id, group))`;
    7. `complete(parcel_id = parcels$parcel_id, group = c("built","ag","forest","grass","bare","water","other"), fill = list(value = 0))`;
    8. `mutate(variable = str_c("crop_", group, "_2019"))`.
  - While developing, run one block per call (600 s limit).
  - Comment: `"frac"` is the share of the parcel's classified (non-NoData) area; a parcel entirely on NoData gets 0 for all groups, and the count is printed.
- [x] **Acceptance:**
  - 7 rows per parcel-year, no NA;
  - shares in [0, 1], summing to 1 ± 0.01, or 0 if fully NoData (reported);
  - no `frac_0`;
  - `nodata` parcels have a higher mean `crop_built_*` + `crop_water_*` than `interior` ones.

### T10: `07-crop-2025.R` (winter over summer)

- [ ] **Writer brief.**
  - **In:** parcels, `crop_2025_summer`, `crop_2025_winter`, `crop_groups`. **Out:** `data/interim/long_crop_2025.parquet`.
  - Comment block explaining the rule:
    - the winter map marks winter cereal (2) and winter rapeseed (3);
    - inside each parcel, a pixel takes the winter code where winter is 2 or 3, otherwise the summer code;
    - winter non-crop and NoData never overwrite summer;
    - applied per pixel inside parcels, never on the whole raster.
  - Steps:
    1. `summer <- rast(crop_2025_summer); names(summer) <- "summer"; NAflag(summer) <- 0`, and the same for `winter`;
    2. guards:
       - `if (any(dim(winter) != dim(summer))) cli_abort(...)`;
       - `if (max(abs(c(xmin(winter) - xmin(summer), ymax(winter) - ymax(summer)))) > 5) cli_abort(...)`;
    3. `ext(winter) <- ext(summer)`, with a comment that the sub-pixel shift of the metadata equals nearest-pixel matching;
    4. `pixels <- exact_extract(c(summer, winter), p, include_cols = "parcel_id") |> bind_rows()`;
    5. `mutate(code = if_else(winter %in% c(2, 3), winter, summer))`, then `filter(!is.na(code))`;
    6. join `crop_groups` with `"other"` for missing groups; `summarise(value = sum(coverage_fraction), .by = c(parcel_id, group))`; divide by the parcel's total; `complete()` the 7 groups with 0; `variable = str_c("crop_", group, "_2025")`.
- [ ] **Acceptance:**
  - same checks as T09;
  - against a summer-only extraction (computed once by the verifier), results are identical wherever the parcel has no winter crop pixel; the number of changed parcels is reported.

### T11: `21-combine.R`

- [ ] **Writer brief.**
  - Bind the five `long_*.parquet` files.
  - Guard checks (`cli_abort()`):
    - one row per `parcel_id` × `variable`;
    - no NA;
    - `source` in the four levels;
    - 81 variables per parcel.
  - Write `spatial_covariates.parquet` and `.csv`, and add the CSV path to `.gitignore`.
  - Print parcels, variables, rows and rows by `source`.
- [ ] **Acceptance:** 81,000 rows in both files; `.gitignore` updated.

### T12: `22-descriptives.R`

- [ ] **Writer brief.**
  - **In:** `spatial_covariates.parquet`, parcels.
  - Soil centroid vs polygon:
    - a hard-coded 10-pair `tribble(mean_var, centroid_var)`;
    - Pearson, Spearman, mean absolute difference and n, on `observed` rows only and on all rows;
    - write `output/tables/soil_centroid_vs_polygon.csv`;
    - faceted scatter plot with a 45° line, saved to `output/figures/soil_centroid_vs_polygon.png`.
  - Summaries, printed and written as CSV:
    - crop share by group and year, and the share with `crop_ag` > 0.5 (`crop_by_year.csv`);
    - distance quantiles (`distance_summary.csv`);
    - relief quantiles (`relief_summary.csv`);
    - soil `source` × `case` (`soil_source_by_case.csv`).
- [ ] **Acceptance:** all files exist; correlations in [−1, 1]; the PNG looks right.
- [ ] **Commit point B:** scripts `03`–`07`, `21`, `22`, `.gitignore`, `output/tables/*.parquet`, the small `output/tables/*.csv` (not `spatial_covariates.csv`), `output/figures/*.png`, this plan.

### T13: website, English (Quarto)

- [ ] **Writer brief.** Use the `quarto:quarto-authoring` skill.
  - Structure:
    - `site/_quarto.yml`: website, `output-dir: ../docs`, navbar with the pages and a **language menu** (English ↔ Українська) linking each page to its counterpart;
    - `site/index.qmd`: redirects or links to `en/index.html`.
  - English pages in `site/en/`:
    1. `index.qmd`: objective, study area (Poltava), what the dataset is for, quick start (`renv::restore()`, set paths, run order).
    2. `data.qmd`:
       - you provide (soil, crop);
       - downloaded (COD-AB, Copernicus DEM, with licences and attribution: SoilGrids CC BY 4.0; Copernicus DEM © DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH 2014–2018, provided under COPERNICUS by the EU and ESA; COD-AB CC BY-IGO; crop maps "licence to be confirmed");
       - simulated reference.
    3. `pipeline.qmd`: run-order table (script, In, Out, purpose), and a diagram (Mermaid) of the data flow.
    4. One page per indicator family, each with the methodology in detail, the variable names with units, the decisions behind them, and the **full script embedded verbatim**, read from the root file with a non-evaluated chunk:

       ````
       ```{r}
       #| file: ../../03-distance.R
       #| eval: false
       ```
       ````

       The pages:
       - `distance.qmd`: nearest feature, centroid vs edge, sphere vs ellipsoid gap table (read from `output/tables/` at render time);
       - `soil.qmd`: 0–30 cm weighting, mean vs centroid, the H3 → oblast fill and how to swap zones, the centroid-vs-polygon figure;
       - `relief.qmd`: the user methodology, aspect encoding, flat threshold, DEM product switch, the surface-model and north-of-50°N limitations;
       - `crop.qmd`: the wide crop code table, grouping, NoData, the 2025 winter-over-summer rule;
       - `reference.qmd`: how the parcels, elevators and roads were simulated (embed `01-simulate-reference.R` and `02-diagnostics.R`), with the maps.
    5. `output.qmd`: the long-table schema, all 81 variables (name, unit, family, meaning), the `source` levels, the summary tables.
  - The site is **multi-page and static**. It is rendered **locally** with `quarto render site` (through Bash), into `docs/`, and `docs/` is committed. GitHub Pages only serves the committed files: no GitHub Actions, and no rendering on GitHub.
  - Figures and tables are read from the committed `output/`; nothing is recomputed at render time.
  - **The parcel maps** (`parcels-map.png`, `parcels-zoom.png`) and the soil figure must appear on the site. The user reviews the maps there.
  - Replace `README.md` with a short version: objective, a link to the site `https://ebukin.github.io/ukrMassValuationSpatialExtract/`, quick start, run order.
- [ ] **Acceptance:**
  - `quarto render site` succeeds with no warnings about missing files;
  - every embedded script matches the root file;
  - all 81 variables are listed;
  - the language menu exists (links to `uk/` may 404 until T14).

### T14: website, Ukrainian

- [ ] **Writer brief.**
  - Translate every `site/en/*.qmd` into `site/uk/*.qmd` (same file names), and set `lang: uk` in each.
  - Translate prose, headings, table headers and figure captions.
  - **Keep in English:** variable names, code, file names, package and function names, URLs.
  - Use one consistent glossary and put it at the end of `site/uk/output.qmd`, for example:
    - parcel = ділянка;
    - covariate = коваріата;
    - soil = ґрунт;
    - crop cover = посівний покрив;
    - oblast = область;
    - hromada = громада;
    - slope = схил;
    - aspect = експозиція.
  - Embedded scripts use the same `#| file:` chunks.
  - Render.
- [ ] **Acceptance:**
  - every English page has a Ukrainian counterpart;
  - the language switch works both ways on every page;
  - the render succeeds;
  - a second sub-agent (reviewer) reads 3 Ukrainian pages against the English ones for accuracy and terminology and reports issues, which a writer then fixes.

### T15: GitHub Pages publish

- [ ] **Writer brief.**
  1. Make sure `docs/` contains the rendered site and a `.nojekyll` file.
  2. **Commit point C:** `site/`, `docs/`, `README.md`, this plan; push to `origin/main`.
  3. Enable Pages from `main` `/docs`: `gh api -X POST repos/EBukin/ukrMassValuationSpatialExtract/pages -f "source[branch]=main" -f "source[path]=/docs"`. If Pages already exists, use `-X PUT`.
  4. Wait for the build (`gh api repos/EBukin/ukrMassValuationSpatialExtract/pages/builds/latest`) and fetch `https://ebukin.github.io/ukrMassValuationSpatialExtract/`.
- [ ] **Acceptance:** the English and Ukrainian index pages return HTTP 200, and the language switch links resolve.

### T16: full run and handover

- [ ] **Verifier only**, in a fresh R session:
  1. Source, one script per call: `00-setup.R`, `02-diagnostics.R`, `03-distance.R`, `04-soil.R`, `05-relief.R`, `06-crop.R`, `07-crop-2025.R`, `21-combine.R`, `22-descriptives.R`.
  2. Skip `00b-download.R`, whose outputs exist. Confirm that `01-simulate-reference.R` aborts if sourced.
  3. Report the time per script, the final counts, any warnings, and whether the outputs differ from those committed at commit point B (they should be identical).
- [ ] **Orchestrator:**
  - fill in "Outcome" and set Status to `done`;
  - final commit point D (this plan) and push;
  - report to the user: what shipped, the site URL, how to verify, and the run times.

## Open questions

- Licence of the crop-cover maps (the site says "to be confirmed").
- Scaling to 10,000 parcels or a larger area: a later decision. It would mean regenerating the reference set and committing it again.

## Outcome

Filled in when the status becomes done or superseded.
