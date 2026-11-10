# Spatial extraction pipeline: reference parcels to a long table of covariates

- **Date:** 2026-11-10 (v2, after independent review and user decisions)
- **Author:** Eduard Bukin (drafted with Claude)
- **Status:** draft

## Goal

A set of short R scripts in the project root, each run with `source()`, that:

1. download the public inputs (oblast boundaries, DEM);
2. generate **once** a fixed reference set of 1,000 parcels, elevators and roads, committed to git;
3. extract distance, soil, relief and crop-cover covariates for every parcel;
4. write one long table, `parcel_id | variable | value | source`, with **81 variables per parcel**;
5. print and save descriptive statistics.

A one-page README walks a novice through the repository. The repo ships no external data: users provide the soil and crop rasters, public inputs are downloaded by a script, and only the simulated reference inputs and the results are committed. A fresh clone plus `renv::restore()`, the two input paths and the scripts in order reproduces everything.

## How to execute this plan (orchestration)

An **orchestrator agent** runs this plan by dispatching sub-agents.

**What the orchestrator does:**
- dispatches and checks; it **never writes code and never runs R itself**;
- for each task, dispatches one **writer** sub-agent, then one **verifier** sub-agent, using the briefs in "Tasks";
- reads only the sub-agents' reports, not the code or the console output, to save context;
- if a verifier reports a failure, dispatches a new writer with the verifier's report and the original brief, then verifies again, at most 3 rounds. After that it stops and reports to the user;
- ticks the task's checkbox in this file when its verification passes, and keeps **Status** current (`active` while running, `done` at the end);
- **never commits**. Commits happen only when the user asks;
- asks the user only at the stop points named in the tasks.

**Every sub-agent brief must include:**
- this plan's path and the task ID;
- the instruction to read the project `CLAUDE.md`, then "Design rules", "Decisions", "Crop code table" and the task section before starting;
- the instruction to do all R work through Positron's MCP server (the `run-r` skill: `mcp__positron__*` tools), never `Rscript` or `mcp-repl`;
- the instruction to return a report of **at most 15 lines**: files changed, what was run, the pass/fail result of each acceptance check, and any deviation from the plan with its reason.

**R sessions.**
- All R runs through Positron's MCP server, in the user's Positron workspace.
- **Writers** run code in the user's foreground R console (`execute_code`).
- **Verifiers** start their own fresh R session, as the `run-r` skill describes:
  1. get the R `runtimeId`;
  2. call `workbench.action.language.runtime.startNewConsoleSession`;
  3. pass its `session_id` to every call;
  4. at the end, close it with `quit(save = "no")` and give the foreground back to the user's session.

  A fresh session is the only real clean state; `rm(list = ls())` doesn't unload packages or reset `sf_use_s2()`.
- **Only one sub-agent runs R at a time.** Writers may draft in parallel where the dependencies allow it, but every R run is serialised.
- Never restart or clear the user's own session.

**Writer duties:** write the script, source it once, fix errors, and report.

**Verifier duties:**
- Re-read the script against the design rules and acceptance criteria.
- Source `00-setup.R` and then the script in a fresh session.
- Check the outputs.
- Report pass or fail per criterion. The verifier does not fix code.

## Context

- The README objective: build a reference dataset of spatial covariates that other implementations (other software or teams) can compare against.
- All decisions below were confirmed by the user in chat on 2026-11-10, after an independent review of v1.
- The project `CLAUDE.md` has been updated to match this plan: root scripts, no `R/` package code, no vignettes, committed reference inputs.
- `renv` is initialised (R 4.6.1; `renv.lock` holds only renv). None of the spatial packages are installed.
- `.gitignore` ignores `data/raw/*` and `data/interim/*`. `data/clean/` and `output/` are tracked.
- `data/raw/oblast.geojson` exists locally. It is **left in place and not used**; oblasts come from COD-AB.
- **`data/raw/` rule:** existing files are never edited, renamed or deleted. Download scripts may add new subfolders.
- Input folders, outside the repo, read-only:
  - soil: `C:/Users/wb532966/OneDrive - WBG/DEC/data-EB/ukrSoilgridsData/data-raw/ukr`
    - SoilGrids GeoTIFFs, e.g. `clay_0-5cm_mean.tif`;
    - units are in `../README.md`, e.g. clay in g/kg and pH × 10;
    - the files may be OneDrive online-only; the user knows this, and they download on first read.
  - crop: `C:/Users/wb532966/OneDrive - WBG/DEC/data-EB/ukrCropCover/original-crop-cover-maps`
    - one classified GeoTIFF per year, with a `.qml` legend beside each;
    - all are EPSG:32636 (UTM 36N), 10 m, uint8, LZW, striped (not tiled);
    - 2020–2025 share one grid of 132874×88823 pixels; 2019 is 134691×90772;
    - only the 2019 map declares NoData (0). The others declare none, but 0 is background.
- **Known heavy operations to avoid:**
  - any whole-country raster computation on the 10 m crop maps (about 1.2e10 cells);
  - slope and aspect on GLO-30 over the whole country.

### Design rules (binding)

- **Simple code for novices.** tidyverse, `dplyr`, `sf`, `terra`, `exactextractr`. Short scripts, few short comments.
- **No helper functions, no `R/` folder, no vignettes.** Scripts sit in the project root.
  - The only allowed exception is a one-line inline `nearest_dist()` in `03-distance.R`.
- **No regular expressions, no clever loops, no `if` ladders.**
  - File paths, year labels and variable names are written out in full.
  - Each crop year gets its own explicit block.
  - Allowed: vectorised calls (`curl::multi_download()`), literal `names_prefix =`, `sprintf("%03d", ...)`, and a single guard `if (...) cli_abort(...)`.
- **Each script header** states what it reads (In:), what it writes (Out:), and its purpose in one line.
- **User-facing messages use cli** (`cli_inform()`, `cli_abort()`).
- **Paths** are built from the project root via objects defined in `00-setup.R`, never with `setwd()`.
- **Projections.**
  - Parcels may arrive in any CRS.
  - Each extraction block transforms the parcels to that raster's CRS (`st_transform(parcels, crs(r))`), extracts, and keeps only `parcel_id` plus the values.
  - `crs_work <- "EPSG:3035"` (LAEA Europe, equal-area, metres) is used to build parcel shapes, compute `area_ha` and draw maps.
- **Distances** are measured on the sphere: sf with s2 on lon/lat (EPSG:4326). They are cross-checked against ellipsoidal distances (T06).
- **Long table.**
  - Columns: `parcel_id | variable | value | source`.
  - **No `stat` column.** Each measurement method is its own variable: `_mean`, `_centroid`, `_edge`, `_max`, `_range`.
  - `source` takes one of `observed`, `h3_6`, `h3_5`, `oblast`. Only soil rows can be non-`observed`.

### Decisions (binding)

| Topic | Decision |
|---|---|
| Reference inputs | One script, `01-simulate-reference.R`, generates 1,000 parcels, 60 elevators and the roads **once**. They are saved as GeoParquet in `data/clean/reference/`, in EPSG:4326, and committed. The script opens with a guard that aborts if the files already exist, so the pipeline never regenerates them. 10,000 parcels come later, as a separate decision. |
| Parcels | Area 1–10 ha, mostly 2–4 ha, built in EPSG:3035. Rectangles and parallelograms. Cases: `interior`, `border` (crosses an oblast line), `town` (centre on soil NoData). Parcels may fall anywhere in Ukraine; maps are used as they are. |
| Oblasts | OCHA COD-AB Ukraine (HDX `cod-ab-ukr`), ADM1 layer, 27 features expected. Field names are mapped from whatever the release uses to `oblast_pcode`, `oblast_ua`, `oblast_en`. |
| DEM | Copernicus DEM, **`dem_product <- "GLO-90"` by default** (90 m). `"GLO-30"` is an opt-in the user runs; the plan never runs it. Tiles are combined with `terra::vrt(..., options = c("-resolution", "highest"))`. The README states that this is a surface model: trees and buildings are included. |
| Elevators, roads | Simulated in the reference script. Roads are clipped to Ukraine and densified with `st_segmentize()` to ≤ 1 km, so every software interprets the lines the same way. Real OSM roads are an optional, commented-out block. |
| Distance | Nearest feature only: `st_nearest_feature()` then `st_distance(..., by_element = TRUE)`. Measured from the centroid and from the edge. The gap between spherical and ellipsoidal distance is reported. |
| Soil | One topsoil 0–30 cm variable per property. For bdod, cec, cfvo, clay, nitrogen, ocd, phh2o, sand and silt, the depths are merged per pixel as `(5·d0_5 + 10·d5_15 + 15·d15_30) / 30`, then extracted. `ocs` is already 0–30 cm. Each of the 10 properties gets `_mean` (coverage-weighted) and `_centroid`: **20 variables**. Values stay in SoilGrids mapped units. |
| Soil NoData | Filled after extraction: H3 res-6 cell mean → H3 res-5 cell mean → oblast mean. The fill level goes in `source`. A marked "fill zones" block shows where users can swap in rayon or hromada polygons. Parcels with only partial soil coverage keep `observed`. |
| Relief | User methodology (T08). **6 variables**, polygon only. `flat_slope_deg <- 0.5` is a slope threshold, not a resolution. |
| Crop | **7 groups × 7 years = 49 variables**, named `crop_<group>_<year>`. Groups: `built`, `ag`, `forest`, `grass`, `bare`, `water`, `other`. One code → group table for all years (see "Crop code table"). Value 0 is NoData in every year. 2025: the winter crop pixels (2, 3) take precedence over the summer map, applied **per pixel inside each parcel**, never on the whole raster (T10). |
| Outputs | `output/tables/spatial_covariates.parquet` is committed. `spatial_covariates.csv` is written but gitignored. Descriptives go to `output/tables/` and `output/figures/`. |
| Script numbers | `00-setup.R`, `00b-download.R`, `01-simulate-reference.R`, `02-diagnostics.R`, `03-distance.R`, `04-soil.R`, `05-relief.R`, `06-crop.R`, `07-crop-2025.R`, `21-combine.R`, `22-descriptives.R`. |
| Variable count | 6 distance + 20 soil + 6 relief + 49 crop = **81**. |

### Crop code table (harmonised across years, binding)

Categories are matched by label. Some categories move between codes: "Not cultivated" is 22 in 2022 and 20 from 2023; "Damaged forest" is 23 in 2022 and 25 from 2024. No code means two unrelated things in different years, so **one `tribble(code, group)` in `00-setup.R` serves every year.** The wide table below is copied into the README, so users can see where each year's codes go.

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

The table as R code in `00-setup.R`:

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

Codes not in the table become `other`. Value 0 is set to NA when reading, with `NAflag(r) <- 0`.

## Tasks

| Task | Can start after | Writer parallel with |
|---|---|---|
| T01 environment and checks | — | — |
| T02 `00-setup.R` | T01 | — |
| T03 `00b-download.R` | T02 | — |
| T04 `01-simulate-reference.R` | T03 | — |
| T05 `02-diagnostics.R` | T04 | T06–T10 |
| T06–T10 extraction scripts | T04 (T08 also needs T03's DEM) | each other |
| T11 `21-combine.R` | T06–T10 | — |
| T12 `22-descriptives.R` | T11 | T13 |
| T13 README | T11 | T12 |
| T14 full run and handover | everything | — |

R runs are always serialised; see "R sessions".

---

### T01: environment and checks

- [ ] **Writer brief.**
  1. In the user's R session, install into the project renv library: `tidyverse`, `sf`, `terra`, `exactextractr`, `arrow`, `h3jsr`, `curl`, `cli`, `lwgeom`, `osmextract`. Then run `renv::snapshot(type = "all")`, so every package and its version is in `renv.lock`. The implicit snapshot would record nothing, because no scripts exist yet.
     - If `h3jsr` fails to install or load (it needs V8), report it. Stop point.
  2. Check that GDAL has a Parquet driver: `"Parquet" %in% sf::st_drivers()$name`. If not, check that the `geoarrow` package can write sf. Report which works. Stop point if neither does.
  3. Soil rasters:
     - record the CRS, resolution, NoData and value range of the 28 files used in T07 (9 properties × 0-5, 5-15 and 15-30 cm, plus `ocs_0-30cm_mean.tif`);
     - check that all 28 share one grid with `terra::compareGeom()`;
     - check the CRS of the 7 crop files, and that 2020–2025 summer and winter share dimensions.
  4. Write `.docs/notes/0001-input-raster-check.md` (follow `.docs/_templates/note.md`) with the findings.
- [ ] **Acceptance:**
  - `renv::status()` is clean and `renv.lock` lists every package above;
  - the note covers all soil and crop files.
- [ ] **Stop points:**
  - h3jsr unusable;
  - no GeoParquet writer;
  - soil layers not on one grid.

### T02: `00-setup.R`

- [ ] **Writer brief.** Create `00-setup.R`, which every other script sources first. It contains:
  - `library()` for the T01 packages (`osmextract` excluded), `sf_use_s2(TRUE)`.
  - Parameters, each with a one-line comment:
    - `n_parcels <- 1000`;
    - `crs_work <- "EPSG:3035"`;
    - `dem_product <- "GLO-90"` (`"GLO-30"` allowed);
    - `flat_slope_deg <- 0.5`.
  - `soil_dir` and `crop_dir` (see Context).
  - The crop file paths written out in full, one object per year:

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
    - downloads: `codab_dir <- "data/raw/cod-ab"`, `dem_dir <- "data/raw/dem"`;
    - reference: `data/clean/reference/parcels.parquet`, `elevators.parquet`, `roads.parquet`;
    - interim: `data/interim/oblasts.gpkg`, `dem.vrt`, `soil_topsoil_0_30cm.tif`, and each `long_*.parquet`;
    - outputs: the files in `output/tables/` and `output/figures/`.
  - `dir.create(..., recursive = TRUE, showWarnings = FALSE)` for every output folder.
- [ ] **Acceptance:**
  - sources clean in a fresh session;
  - `all(file.exists(<all input paths>))`;
  - follows the design rules.

### T03: `00b-download.R`

- [ ] **Writer brief.** The header lists, for each download: source URL, licence, approximate size and destination. Each block skips files that already exist.
  - **COD-AB block:**
    - Find the current shapefile zip resource URL for HDX dataset `cod-ab-ukr` (via `https://data.humdata.org/api/3/action/package_show?id=cod-ab-ukr`) and hard-code it.
    - Download to `codab_dir` and unzip.
    - Read the ADM1 layer. Rename its P-code, Ukrainian name and English name fields to `oblast_pcode`, `oblast_ua` and `oblast_en`, using whatever names the release has; report them.
    - Inform about the feature count (27 expected).
    - Write `data/interim/oblasts.gpkg`.
  - **DEM block:**
    - Product table:

      ```r
      dem_products <- tribble(
        ~product, ~bucket,                                         ~code,
        "GLO-30", "https://copernicus-dem-30m.s3.amazonaws.com",  "10",
        "GLO-90", "https://copernicus-dem-90m.s3.amazonaws.com",  "30"
      ) |> filter(product == dem_product)
      ```

    - Tile boxes:
      - `st_make_grid(cellsize = 1, offset = c(22, 44), n = c(19, 9), crs = 4326)`, keeping boxes that intersect the dissolved oblasts;
      - tile ID: `str_c("Copernicus_DSM_COG_", code, "_N", lat, "_00_E", sprintf("%03d", lon), "_00_DEM")`, where lat and lon are the box's lower-left corner;
      - URL: `{bucket}/{id}/{id}.tif`; destination: `file.path(dem_dir, dem_product, str_c(id, ".tif"))`.
    - Download with `curl::multi_download()`. Tiles over the sea return 404; inform about the count and continue.
    - Build `data/interim/dem.vrt` with `vrt(files, options = c("-resolution", "highest"))`. A comment explains that tiles north of 50°N have coarser longitude spacing.
  - **Optional OSM roads**, commented out: `osmextract::oe_get("Ukraine", layer = "lines")`. Main roads are `highway %in% c("motorway","trunk","primary")`, local roads `c("secondary","tertiary")`. Output goes to `data/raw/osm/`, with a note that it replaces the simulated roads in `03-distance.R`.
- [ ] **Acceptance:**
  - runs with GLO-90;
  - `oblasts.gpkg` exists with the three renamed fields;
  - `rast(dem.vrt)` covers Ukraine;
  - a second run downloads nothing.
- [ ] Note for the orchestrator: if a download exceeds the MCP call timeout, the writer may run it in a separate R session and poll for completion.

### T04: `01-simulate-reference.R` (run once, then committed)

- [ ] **Writer brief.**
  - **In:** `oblasts.gpkg`, `clay_0-5cm_mean.tif`. **Out:** `data/clean/reference/parcels.parquet`, `elevators.parquet`, `roads.parquet` (GeoParquet, EPSG:4326, using the writer chosen in T01).
  - First line after the setup: `if (file.exists(parcels_path)) cli_abort("Reference inputs already exist. They are fixed: do not regenerate.")`. The header explains that this script ran once to create the committed reference, and is not part of the normal run.
  - `set.seed(20261110)`.
  - **Parcel centres**, in EPSG:3035, split 70 % `interior`, 15 % `border`, 15 % `town`:
    - `interior`: `st_sample()` in the dissolved country, keeping points more than 1 km from any oblast boundary;
    - `border`: `st_sample()` on the internal oblast boundaries (oblast boundary lines minus the national outline), dropping points within 1 km of the national border;
    - `town`: `terra::spatSample()` on the soil NA cells, masked to Ukraine, shifted by at most 100 m.
  - **Shape**, inline in `mutate()` and `pmap()`, no helper function:
    - `area_ha = pmin(pmax(rlnorm(n, log(3), 0.25), 1), 10)`;
    - aspect ratio `runif(n, 1.5, 6)`;
    - angle `runif(n, 0, pi)`;
    - shear `if_else(runif(n) < 0.5, 0, runif(n, 0.2, 0.5))`.

    Build each parcel from a unit square by applying scale, then shear, then rotation, then translation to the centre.
  - **Parcel attributes:**
    - `parcel_id` (`sprintf("P%05d", ...)`), `case`, `area_ha` (recomputed with `st_area` in EPSG:3035);
    - `oblast` = `oblast_pcode` with the largest overlap (`st_join(..., largest = TRUE)`);
    - `h3_6`, `h3_5` = H3 cells of the WGS84 centroid (`h3jsr::point_to_cell()`).
  - **Elevators:** 60 points from `st_sample()` in the country, with `elevator_id`.
  - **Roads:**
    - main: 10 lines between random pairs of oblast centroids;
    - local: 150 lines from random points, 5–20 km long in a random direction;
    - all clipped to the country (`st_intersection`), densified to ≤ 1 km (`st_segmentize(dfMaxLength = 1000)` in EPSG:3035), with `road_id` and `type`.
  - Transform everything to EPSG:4326 and write. Print counts by case, an area summary and road counts.
- [ ] **Acceptance:**
  - 1,000 parcels with unique IDs and valid geometries;
  - at least 75 % of areas in 2–4 ha, all in 1–10 ha;
  - every `border` parcel intersects at least 2 oblasts;
  - at least 80 % of `town` parcels have more than 50 % of their area on soil NoData;
  - none of `oblast`, `h3_6` or `h3_5` is NA;
  - all features lie inside Ukraine;
  - re-sourcing aborts with the guard message.
- [ ] **Stop point:** report the outputs to the orchestrator, which asks the user to look at the maps from T05 before anything is committed. The user commits.

### T05: `02-diagnostics.R`

- [ ] **Writer brief.**
  - **In:** oblasts, the reference files, `clay_0-5cm_mean.tif`. **Out:** `output/figures/parcels-map.png`, `output/figures/parcels-zoom.png`.
  - National map in EPSG:3035: oblast outlines, parcels as points coloured by `case`, elevators, roads by type.
  - Zoom map: three panels showing one `interior`, one `border` and one `town` parcel with their surroundings. The town panel shows the soil NoData area.
  - Print counts and areas by `case` and `oblast`.
- [ ] **Acceptance:** both PNGs exist and look right; the verifier views them with Read. The table prints.

### T06: `03-distance.R`

- [ ] **Writer brief.**
  - **In:** the reference files, transformed to EPSG:4326. **Out:** `data/interim/long_distance.parquet`, `output/tables/distance_sphere_vs_ellipsoid.csv`.
  - Variables, in metres, each computed as `st_distance(from, to[st_nearest_feature(from, to), ], by_element = TRUE)`, with "from" being `st_centroid()` or the polygon:
    - `dist_elevator_centroid`, `dist_elevator_edge`;
    - `dist_road_main_centroid`, `dist_road_main_edge`;
    - `dist_road_local_centroid`, `dist_road_local_edge`.
  - `pivot_longer()` to `parcel_id | variable | value`, with `value = as.numeric(...)` and `source = "observed"`.
  - **Check block:**
    - recompute the same nearest pairs with `sf_use_s2(FALSE)`, which gives ellipsoidal distance via lwgeom, then switch s2 back on;
    - write per variable: the mean and maximum absolute gap in metres, and the mean relative gap in %;
    - print the summary.
- [ ] **Acceptance:**
  - 6 rows per parcel, no NA;
  - every edge distance ≤ its centroid distance;
  - the ellipsoid gap table exists, with mean relative gap < 0.5 %;
  - a spot check of 3 parcels against `st_distance()` to all features gives the same minimum.

### T07: `04-soil.R`

- [ ] **Writer brief.**
  - **In:** parcels, oblasts, 28 SoilGrids rasters. **Out:** `data/interim/soil_topsoil_0_30cm.tif`, `data/interim/long_soil.parquet`.
  - Topsoil stack, one explicit expression per property, paths in full:

    ```r
    # Topsoil 0-30 cm: thickness-weighted average of the 0-5, 5-15 and 15-30 cm layers
    soil_clay_0_30cm <- (5  * rast(file.path(soil_dir, "clay_0-5cm_mean.tif")) +
                         10 * rast(file.path(soil_dir, "clay_5-15cm_mean.tif")) +
                         15 * rast(file.path(soil_dir, "clay_15-30cm_mean.tif"))) / 30
    ```

    Do this for bdod, cec, cfvo, clay, nitrogen, ocd, phh2o, sand and silt. Add `ocs_0-30cm_mean.tif` as `soil_ocs_0_30cm`. Combine with `c()`, name the layers, and `writeRaster()` the stack.
  - H3 cells: unique `h3_6` and `h3_5` from parcels, turned into polygons with `h3jsr::cell_to_polygon()`. They are derived here, not stored.
  - Transform parcels, H3 cells and oblasts to `crs(soil)`.
  - Parcel values:
    - `exact_extract(soil, parcels, "mean", append_cols = "parcel_id")` for `_mean`;
    - `terra::extract(soil, vect(st_centroid(parcels)), ID = FALSE)` for `_centroid`.

    Pivot to long with `value_raw`.
  - Fill-zones block, marked with a banner comment:
    - zone means via `exact_extract(soil, zones, "mean")` for the H3-6 cells, the H3-5 cells and the oblasts;
    - a comment explains how to swap in rayon or hromada polygons (COD-AB ADM2/ADM3 in `codab_dir`): replace the zone layer, its ID column, and the matching parcel column.
  - Join the zone means, then:
    - `value = coalesce(value_raw, h3_6_value, h3_5_value, oblast_value)`;
    - `source = case_when(!is.na(value_raw) ~ "observed", !is.na(h3_6_value) ~ "h3_6", !is.na(h3_5_value) ~ "h3_5", !is.na(oblast_value) ~ "oblast")`.

    `cli_abort()` if any `value` is still NA.
  - Variable names: `soil_<prop>_0_30cm_mean` and `soil_<prop>_0_30cm_centroid`, written out in full.
  - Header documents the units and the fill order. Print counts by `source`.
- [ ] **Acceptance:**
  - 20 rows per parcel, no NA;
  - non-`observed` rows come mostly from `town` parcels;
  - spot check: for one parcel, the centroid value equals the weighted formula computed by hand from the three depth rasters.

### T08: `05-relief.R` (user methodology, binding)

Methodology from the user:
- Statistics come from the whole parcel polygon, never from the centroid or from the pixels whose centre falls inside. Each pixel counts by its coverage fraction, using `exactextractr::exact_extract()`.
- Aspect is clockwise from north, in degrees (0 = north, 90 = east, 180 = south). A flat pixel (slope < `flat_slope_deg`) contributes 0 to both aspect variables.
- Slope and aspect are computed in a projected CRS in metres, or with a geodesic-aware method. Never on a DEM in degrees treated as metres, and never in Web Mercator.
- A parcel smaller than one pixel still gets values, from the pixel or pixels it covers.
- Output: one value per parcel per variable, all complete.

- [ ] **Writer brief.**
  - **In:** parcels, `data/interim/dem.vrt`. **Out:** `data/interim/long_relief.parquet`.
  - Crop the DEM to the parcels' extent plus about 0.05° (one `crop()` call).
  - `terrain(dem, c("slope", "aspect"), unit = "degrees")` on the lon/lat DEM. terra uses ellipsoidal cell distances for lon/lat input; the header says so.
  - Per-pixel exposure:
    - `south = -cos(aspect × π/180)`, `east = sin(aspect × π/180)`;
    - both 0 where `slope < flat_slope_deg`.
  - One `exact_extract()` on `c(elev, slope, south, east)` with `c("mean", "max", "min")`. Keep:

    | Variable | Definition |
    |---|---|
    | `relief_elev_mean` | coverage-weighted mean elevation, m |
    | `relief_slope_mean` | coverage-weighted mean slope, degrees |
    | `relief_slope_max` | max slope over pixels touching the parcel, degrees |
    | `relief_elev_range` | max − min elevation over pixels touching the parcel, m |
    | `relief_aspect_south` | coverage-weighted mean of `south`, −1 to 1 |
    | `relief_aspect_east` | coverage-weighted mean of `east`, −1 to 1 |

  - `cli_abort()` if any value is NA. `source = "observed"`.
- [ ] **Acceptance:**
  - 6 rows per parcel, no NA;
  - aspect values in [−1, 1], slope in [0, 90], range ≥ 0.

### T09: `06-crop.R` (2019–2024)

- [ ] **Writer brief.**
  - **In:** parcels, `crop_2019` … `crop_2024`, `crop_groups`. **Out:** `data/interim/long_crop.parquet`.
  - Six explicit blocks with the same shape, the year written out in full in each:
    1. `r <- rast(crop_2019)`; `NAflag(r) <- 0`;
    2. `p <- st_transform(parcels, crs(r))`;
    3. `exact_extract(r, p, "frac", append_cols = "parcel_id")`;
    4. `pivot_longer(starts_with("frac_"), names_to = "code", names_prefix = "frac_", names_transform = as.integer, values_to = "share", values_drop_na = TRUE)`;
    5. `left_join(crop_groups, by = "code")`, then `mutate(group = coalesce(group, "other"))`;
    6. `summarise(value = sum(share), .by = c(parcel_id, group))`;
    7. `complete(parcel_id = parcels$parcel_id, group = c("built", "ag", "forest", "grass", "bare", "water", "other"), fill = list(value = 0))`;
    8. `mutate(variable = str_c("crop_", group, "_2019"))`.
  - Bind the six years, with `source = "observed"`.
  - Comment: `"frac"` is the share of the parcel's **classified** (non-NoData) area. A parcel entirely on NoData gets 0 for every group; print how many such parcel-years there are.
- [ ] **Acceptance:**
  - 7 rows per parcel per year, no NA;
  - shares in [0, 1];
  - per parcel-year the shares sum to 1 ± 0.01, or 0 for fully-NoData parcels, which are counted and reported;
  - no `frac_0` column appears;
  - `town` parcels have a higher mean `crop_built_*` than `interior` ones.

### T10: `07-crop-2025.R` (winter over summer)

- [ ] **Writer brief.**
  - **In:** parcels, `crop_2025_summer`, `crop_2025_winter`, `crop_groups`. **Out:** `data/interim/long_crop_2025.parquet`.
  - Comment block explaining the rule:
    - the winter map marks winter cereal (2) and winter rapeseed (3);
    - inside each parcel, a pixel takes the winter code where winter is 2 or 3, and the summer code otherwise;
    - winter non-crop and NoData pixels never overwrite summer;
    - the rule is applied per pixel inside parcels, not on the whole 1.2e10-cell raster.
  - Steps:
    1. `summer <- rast(crop_2025_summer)`, `winter <- rast(crop_2025_winter)`, `NAflag()` 0 on both;
    2. the grids have identical dimensions but origins about 1–2 m apart: `if (any(dim(winter) != dim(summer))) cli_abort(...)`, then `ext(winter) <- ext(summer)`, with a comment that a sub-pixel shift of the metadata equals nearest-pixel matching;
    3. `pixels <- exact_extract(c(summer, winter), p, include_cols = "parcel_id") |> bind_rows()`, which gives each pixel's summer and winter code with its `coverage_fraction`;
    4. `mutate(code = if_else(winter %in% c(2, 3), winter, summer))`, then drop NA `code`;
    5. join `crop_groups`, set missing groups to `"other"`, and compute `summarise(value = sum(coverage_fraction), .by = c(parcel_id, group))` divided by the parcel's total classified coverage;
    6. `complete()` the 7 groups with 0; `variable = str_c("crop_", group, "_2025")`.
- [ ] **Acceptance:**
  - same checks as T09;
  - the verifier compares, once in the console, `crop_ag_2025` against a summer-only extraction. They must be identical wherever the winter map has no crop pixel in the parcel, and the number of parcels that change is reported.

### T11: `21-combine.R`

- [ ] **Writer brief.**
  - Read and bind `long_distance`, `long_soil`, `long_relief`, `long_crop` and `long_crop_2025`.
  - Checks, each with `cli_abort()` on failure:
    - exactly one row per `parcel_id` × `variable`;
    - no NA `value`;
    - `source` within the four levels;
    - every parcel has the same 81 variables.
  - Write `output/tables/spatial_covariates.parquet` and `output/tables/spatial_covariates.csv`.
  - Add `output/tables/spatial_covariates.csv` to `.gitignore`.
  - Print parcels, variables, total rows and rows by `source`.
- [ ] **Acceptance:** both files exist with 81,000 rows each; `.gitignore` is updated.

### T12: `22-descriptives.R`

- [ ] **Writer brief.**
  - **In:** `spatial_covariates.parquet`, parcels (for `case`).
  - Soil, centroid vs polygon:
    - a hard-coded `tribble(mean_var, centroid_var)` with 10 pairs;
    - per pair: Pearson, Spearman, mean absolute difference and n, on `observed` rows only and on all rows;
    - write `output/tables/soil_centroid_vs_polygon.csv`;
    - faceted scatter plot with a 45° line, saved to `output/figures/soil_centroid_vs_polygon.png`.
  - Summaries, each printed and written to `output/tables/`:
    - crop share by group and year, and the share of parcels with `crop_ag` > 0.5 (`crop_by_year.csv`);
    - distance quantiles (`distance_summary.csv`);
    - relief quantiles (`relief_summary.csv`);
    - soil rows by `source` × `case` (`soil_source_by_case.csv`).
- [ ] **Acceptance:** all files exist; correlations in [−1, 1]; the PNG looks right.

### T13: `README.md`, the one-page guide

- [ ] **Writer brief.** Rewrite `README.md`, keeping the Objective section:
  - **Quick start:** clone, `renv::restore()`, set `soil_dir` and `crop_dir` in `00-setup.R`, then source `00b-download.R`, `02-diagnostics.R`, `03`–`07`, `21` and `22` in order.
    - Explain that `01-simulate-reference.R` already ran once, and that its committed outputs in `data/clean/reference/` are the fixed reference.
  - **Data**, in three groups:
    - "You provide": soil and crop, with folders and units;
    - "Downloaded": COD-AB and Copernicus DEM, with source, licence and size, the `dem_product` setting, and the note that Copernicus is a surface model;
    - "Simulated reference": parcels, elevators, roads.
  - **Run order:** a table of each script (linked) with In / Out / purpose.
  - **Walk-through:** one short section per script, embedding the 5–10 key lines copied verbatim from the script.
  - **Output schema:** `parcel_id | variable | value | source`. All 81 variables by family, with units, and the `source` levels.
  - **Methods:**
    - spherical nearest distance and the ellipsoid check;
    - exact extraction with coverage fractions;
    - soil 0–30 cm weighting and fill order;
    - relief definitions;
    - the **wide crop code table**, copied from this plan;
    - the 2025 winter-over-summer rule.
  - **Licences and attribution:**
    - SoilGrids: CC BY 4.0;
    - Copernicus DEM: © DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH 2014–2018, provided under COPERNICUS by the European Union and ESA;
    - COD-AB: licence as stated on HDX;
    - crop maps: "licence to be confirmed by the data owner".
  - About one printed page plus the code excerpts. No hand-typed numbers from `output/`.
- [ ] **Acceptance:**
  - every named file exists;
  - the excerpts match the scripts verbatim;
  - the variable count is 81.

### T14: full run and handover

- [ ] **Verifier only**, no writer:
  1. In a fresh R session, source in order: `00-setup.R`, `02-diagnostics.R`, `03-distance.R`, `04-soil.R`, `05-relief.R`, `06-crop.R`, `07-crop-2025.R`, `21-combine.R`, `22-descriptives.R`.
     - Skip `00b-download.R`, whose outputs exist, and `01-simulate-reference.R`, which must abort if sourced; confirm that it does.
  2. Record the run time of each script, the final row and variable counts, and any warnings.
- [ ] **Orchestrator:**
  - fill in "Outcome";
  - set Status to `done`;
  - report to the user:
    - files created;
    - the files to commit: scripts, README, `renv.lock`, `.gitignore`, `data/clean/reference/*.parquet`, `output/tables/*.parquet` and the small CSVs, and `output/figures/*.png`;
    - that nothing has been committed yet.

## Open questions

- Licence of the crop-cover maps, for the README attribution.
- Scaling to 10,000 parcels: a later, separate decision. It would mean regenerating the reference set and committing it again.
- Optional wide output (one row per parcel): not done unless asked.

## Outcome

Filled in when the status becomes done or superseded.
