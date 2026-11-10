# Spatial extraction pipeline: simulated parcels to a long table of covariates

- **Date:** 2026-11-10
- **Author:** Eduard Bukin (drafted with Claude)
- **Status:** draft

## Goal

A set of short R scripts in the project root, each run with `source()`, that:

1. download the public inputs (oblast boundaries, DEM);
2. simulate test parcels, elevators and roads;
3. extract distance, soil, relief and crop-cover covariates for every parcel;
4. write one long table, `parcel_id | variable | value | source`, to `output/tables/` as CSV and Parquet;
5. print and save descriptive statistics.

A one-page README walks a novice through the repository step by step. The repo ships no data: users provide the soil and crop rasters, and everything else is downloaded or simulated. A fresh clone plus `renv::restore()` and the scripts in order reproduces everything.

## How to execute this plan (orchestration)

An **orchestrator agent** runs this plan by dispatching sub-agents.

**What the orchestrator does:**
- dispatches and checks; it **never writes code and never runs R itself**;
- for each task, dispatches one **writer** sub-agent, then one **verifier** sub-agent, using the briefs in "Tasks";
- reads only the sub-agents' short reports, not the code or the console output, to save context;
- if a verifier reports a failure, dispatches a new writer with the verifier's report and the original brief, then verifies again, at most 3 rounds. After that it stops and reports to the user.
- ticks the task's checkbox in this file when its verification passes, and keeps **Status** current (`active` while running, `done` at the end);
- **never commits**. At the end it reports to the user, who decides about commits;
- asks the user only for the decisions listed as stop points.

**Every sub-agent brief must include:**
- this plan's path and the task ID;
- the instruction to read `CLAUDE.md`, "Design rules", "Decisions" and the task section before starting;
- the instruction to do all R work through Positron's MCP server (the `run-r` skill), never `Rscript`;
- the instruction to return a report of **at most 15 lines**: files changed, what was run, the pass/fail result of each acceptance check, and any deviation from the plan with its reason.

**R sessions.** There is one shared Positron R console. Only one sub-agent may run R in it at a time. Writers may work in parallel where the dependencies allow it, but runs are serialised: verifier B starts only after verifier A has reported. A sub-agent may open its own parallel R session as the `run-r` skill describes, and must close it afterwards.

**Writer duties:** write the script, source it once with `n_parcels = 1000`, fix errors, and report.

**Verifier duties:**
- Re-read the script against "Design rules", "Decisions" and the task's acceptance criteria.
- Source it from a clean R session (`rm(list = ls())`, then `source("00-setup.R")` and the script).
- Check the outputs.
- Report pass or fail per criterion. The verifier does not fix code.

## Context

- The README objective: build a reference dataset of spatial covariates that other implementations (other software or teams) can compare against.
- All decisions below were confirmed by the user in chat on 2026-11-10.
- `renv` is initialised (R 4.6.1, `renv.lock` with only renv). None of the spatial packages are installed.
- `data/raw/*` and `data/interim/*` are gitignored. `data/raw/oblast.geojson` exists locally but is **not used**; oblasts come from COD-AB. Never edit, rename or delete anything in `data/raw/`.
- Input folders, outside the repo, read-only:
  - soil: `C:/Users/wb532966/OneDrive - WBG/DEC/data-EB/ukrSoilgridsData/data-raw/ukr`. SoilGrids GeoTIFFs, e.g. `clay_0-5cm_mean.tif`. Units are documented in `../README.md`, e.g. clay in g/kg and pH × 10.
  - crop: `C:/Users/wb532966/OneDrive - WBG/DEC/data-EB/ukrCropCover/original-crop-cover-maps`. One classified GeoTIFF per year, each with a `.qml` legend beside it.

### Design rules (binding)

- **Simple code for novices.** tidyverse, `dplyr`, `sf`, `terra`, `exactextractr`. Short scripts, few short comments.
- **No helper functions, no `R/` folder, no vignettes.** Scripts sit in the project root.
  - The only allowed exception is a one-line inline `nearest_dist()` in `03-distance.R`. Write it out in full instead if it reads better.
- **No regular expressions, no clever loops.** File paths, year labels and variable names are written out in full. Each crop year gets its own explicit block. Vectorised calls like `curl::multi_download(urls, dests)` are fine.
- **Each script header** states what it reads (In:), what it writes (Out:), and its purpose in one line.
- **User-facing messages use cli** (`cli_inform()`, `cli_abort()`), never `stop()`, `warning()` or `message()`.
- **Paths** are built from the project root, never with `setwd()`.
- **Projections.**
  - Parcels may arrive in any CRS.
  - Each extraction block transforms the parcels to that raster's CRS (`st_transform(parcels, crs(r))`), extracts, and keeps only `parcel_id` plus the values.
  - Saved parcels keep their input CRS.
  - `crs_work` is used only to build parcel shapes and the map.
- **Distances** are measured on the sphere: sf with s2 on lon/lat (EPSG:4326).
- **Long table.**
  - Columns: `parcel_id | variable | value | source`.
  - **No `stat` column.** Each measurement method is its own variable: `_mean`, `_centroid`, `_edge`, `_max`, `_range`.
  - `source` takes one of `observed`, `h3_6`, `h3_5`, `oblast`. Only soil rows can be non-`observed`.

### Decisions (binding)

| Topic | Decision |
|---|---|
| Parcels | `n_parcels <- 1000` in setup (target 10,000+). Area 1–10 ha, mostly 2–4 ha. Rectangles and parallelograms. Cases: `interior`, `border` (crosses an oblast line), `town` (falls where soil is NoData). No duplicate parcels. |
| Oblasts | OCHA COD-AB Ukraine (HDX `cod-ab-ukr`), ADM1 layer, fields `ADM1_PCODE`, `ADM1_UA`, `ADM1_EN`. ADM2 and ADM3 come in the same zip. |
| DEM | Copernicus DEM. **The resolution is a user setting in `00-setup.R`**: `dem_product <- "GLO-30"` (30 m, default) or `"GLO-90"` (90 m, smaller and faster). Tiles are combined with `terra::vrt()`. |
| Elevators, roads | Simulated, nothing downloaded. Real OSM roads are an optional, commented-out block. |
| Distance | Nearest feature only: `st_nearest_feature()` then `st_distance(..., by_element = TRUE)`. Measured from the centroid and from the edge. |
| Soil | **One topsoil 0–30 cm variable per property.** For bdod, cec, cfvo, clay, nitrogen, ocd, phh2o, sand and silt, the three depths are merged per pixel as a thickness-weighted average, `(5·d0_5 + 10·d5_15 + 15·d15_30) / 30`, then extracted. `ocs` is already 0–30 cm. That gives 10 properties, each with `_mean` (coverage-weighted polygon mean) and `_centroid`: 20 variables. Values stay in SoilGrids mapped units. |
| Soil NoData | Filled after extraction, in order: H3 res-6 cell mean → H3 res-5 cell mean → oblast mean. The fill level goes in `source`. A clearly marked "fill zones" block shows users where to swap in rayon or hromada polygons. |
| Relief | User methodology, task T09. Six variables, polygon only, no centroid. `flat_slope_deg <- 0.5` is the slope **threshold** below which a pixel counts as flat; it is unrelated to DEM resolution. |
| Crop groups | `built`, `ag`, `forest`, `grass`, `other`. Uncultivated land is natural but still agricultural land, so it goes to **`grass`**. `other` = water, wetland, and any code not listed. Codes are extracted raw with `"frac"`, joined to that year's code → group table and summed. |
| Crop years | 2019–2025, one block per file. 2025 = winter crop pixels laid over the summer map, then extracted. |
| Outputs | Long table as CSV and Parquet, plus descriptives as printed summaries, CSVs and PNGs. |
| Script numbers | `00`–`07` for inputs and extraction, `21` combine, `22` descriptives. The gap leaves room for later scripts. |

### Crop code → group (base table from the user)

| Group | Codes (labels from the user and the `.qml` files) |
|---|---|
| `built` | 1 Artificial |
| `ag` | 2 Wheat, 3 Rapeseed, 4 Buckwheat, 5 Maize, 6 Sugar beet, 7 Sunflower, 8 Soybeans, 9 Other crops, 15 Barley, 16 Peas, 17 Alfalfa, 19 Grape, 21 Potatoes, 24 Tomato, 26 Nut trees, 27 Other cereal |
| `forest` | 10 Forest, 23 Damaged forest, 25 Damaged forest |
| `grass` | 11 Grassland/Pasture, 12 Bare land, 18 Gardens, parks/Low trees, **20 Uncultivated**, **22 Uncultivated** |
| `other` | 13 Water, 14 Wetland, and any code not listed |

Each year's legend may differ. Task T01 lists every legend. If a year's code means something other than in this table, that year's block gets its own table and a comment saying why. Any code labelled "Uncultivated" always goes to `grass`.

## Tasks

The list shows the order of tasks and which can be written in parallel.

| Task | Can start after | Writer parallel with |
|---|---|---|
| T01 | — | — |
| T02 | T01 | — |
| T03 | T02 | — |
| T04, T05 | T03 | each other |
| T06 | T04, T05 | T07–T11 |
| T07–T11 | T04, T05 (T09 also needs T03's DEM) | each other |
| T12 | T07–T11 | — |
| T13 | T12 | T14 |
| T14 | T12 | T13 |
| T15 | everything | — |

Verifier runs are always serialised; see "R sessions".

---

### T01: environment and input check

- [ ] **Writer brief:**
  1. Install into the project renv library, from a fresh R session in the project: `tidyverse`, `sf`, `terra`, `exactextractr`, `arrow`, `h3jsr`, `curl`, `cli`, `osmextract`. Then `renv::snapshot()` so every package and its version is in `renv.lock`.
  2. Without writing any script, inspect in the R console every raster listed in T02's year → file table, plus `clay_0-5cm_mean.tif`. Record CRS, resolution, extent, NoData value and value range. For crop files, also parse the `.qml` legend (`<item label=... value=...>`), or the palette entries if the colour ramp is absent.
  3. Write `.docs/notes/0001-input-raster-check.md` (follow `.docs/_templates/note.md`) with:
     - one table of raster properties;
     - one table of codes and labels per crop year;
     - a column showing the group each code gets under "Crop code → group", flagging codes that are missing from the base table or labelled differently.
- [ ] **Acceptance:**
  - `renv::status()` reports no issues;
  - `renv.lock` lists all the packages above;
  - the note covers all 8 crop files and the soil file.
- [ ] **Stop point (orchestrator asks the user):** if any crop code is unlisted or labelled in conflict with the base table, apart from those labelled "Uncultivated". Also if `SummerMap_Ukraine_2025_WB.tif` is in a geographic CRS: then propose EPSG:3035 as `crs_work`.

### T02: `00-setup.R`

- [ ] **Writer brief:** create `00-setup.R`, which every later script sources first. It contains:
  - `library()` calls for the packages from T01; `sf_use_s2(TRUE)`; `set.seed(20261110)`.
  - Parameters, each with a one-line comment:
    - `n_parcels <- 1000`;
    - `dem_product <- "GLO-30"` (`"GLO-90"` allowed);
    - `flat_slope_deg <- 0.5`;
    - `crs_work` (from T01; the CRS of the summer 2025 map unless the user decided otherwise).
  - Input folders `soil_dir` and `crop_dir` (see Context).
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

  - Download folders: `codab_dir <- "data/raw/cod-ab"`, `dem_dir <- "data/raw/dem"`.
  - Interim and output paths, one object each: parcels, H3 cells, elevators, roads, `dem.vrt`, the soil stack, `crop_2025.tif`, each `long_*.parquet`, the final tables and the figures.
  - `dir.create(..., recursive = TRUE, showWarnings = FALSE)` for `data/interim`, `output/tables`, `output/figures` and the download folders.
- [ ] **Acceptance:**
  - `source("00-setup.R")` runs clean in a fresh session;
  - every input path exists (`all(file.exists(...))`);
  - the script follows the design rules.

### T03: `00b-download.R`

- [ ] **Writer brief.** The header lists, for each download: source URL, licence, approximate size and destination. Each block skips files that already exist.
  - **COD-AB block:**
    - Find the current shapefile zip resource URL for HDX dataset `cod-ab-ukr`, for example with `https://data.humdata.org/api/3/action/package_show?id=cod-ab-ukr`, and hard-code it.
    - Download to `codab_dir` and unzip.
    - Read ADM1 and print the number of features: 27 expected (24 oblasts, Crimea, Kyiv city, Sevastopol). Inform if it differs.
    - Save ADM1 as `data/interim/oblasts.gpkg` keeping `ADM1_PCODE`, `ADM1_UA`, `ADM1_EN`.
  - **DEM block**, driven by `dem_product`:
    - GLO-30: bucket `https://copernicus-dem-30m.s3.amazonaws.com`, tile ID `Copernicus_DSM_COG_10_N{lat}_00_E{lon:03d}_00_DEM`.
    - GLO-90: bucket `https://copernicus-dem-90m.s3.amazonaws.com`, tile ID `Copernicus_DSM_COG_30_N{lat}_00_E{lon:03d}_00_DEM`.
    - Use the two-row `tribble` of product → bucket and code, and `filter(product == dem_product)`. No `if` ladder.
    - Tile grid: `expand_grid(lat = 44:52, lon = 22:40)`. Keep only tiles whose 1°×1° box intersects the dissolved oblasts.
    - URL: `{bucket}/{id}/{id}.tif`, destination `dem_dir/{dem_product}/{id}.tif`.
    - Download with `curl::multi_download()`. Tiles over the sea return 404; inform about the count and continue.
    - Build `data/interim/dem.vrt` with `terra::vrt()` from the files that exist.
  - **Optional OSM roads block**, commented out: `osmextract::oe_get("Ukraine", layer = "lines")`. Main roads are `highway %in% c("motorway","trunk","primary")`, local roads `c("secondary","tertiary")`. It writes to `data/raw/osm/`, and a comment says it replaces the simulated roads in T07.
- [ ] **Acceptance:**
  - a run with `dem_product = "GLO-90"` succeeds first, which is fast; GLO-30 follows (long, about 2–3 GB);
  - `oblasts.gpkg` has 27 features or the count is reported;
  - `rast("data/interim/dem.vrt")` covers Ukraine's extent;
  - a re-run downloads nothing.
- [ ] Note for the orchestrator: the GLO-30 download takes a long time. The verifier may run it in a separate R session.

### T04: `01a-simulate-parcels.R`

- [ ] **Writer brief.**
  - **In:** `oblasts.gpkg`, `clay_0-5cm_mean.tif`. **Out:** `data/interim/parcels.gpkg`, `data/interim/h3_cells.gpkg`.
  - Centre points by case (70 % `interior`, 15 % `border`, 15 % `town`), in `crs_work`:
    - `interior`: `st_sample()` in the dissolved country, keeping points more than 1 km from any oblast boundary;
    - `border`: `st_sample()` on the internal oblast boundaries (the oblast boundary lines minus the national outline), dropping points within 1 km of the national border;
    - `town`: random cells where the soil layer is NA inside Ukraine, via `terra::spatSample()` on the NA mask, then shifted 0–1 km.
  - Shape, in metres, inline in `mutate()` and `pmap()`, no helper function:
    - `area_ha = pmin(pmax(rlnorm(n, log(3), 0.3), 1), 10)`;
    - aspect ratio `runif(n, 1.5, 6)`;
    - angle `runif(n, 0, pi)`;
    - shear 0 for half the parcels and `runif(0.2, 0.5)` for the rest.

    Build each parcel from a unit square by applying scale, then shear, then rotation, then translation to the centre.
  - Attributes:
    - `parcel_id` (`sprintf("P%05d", ...)`), `case`, `area_ha` (recomputed with `st_area`);
    - `oblast` = `ADM1_PCODE` with the largest overlap (`st_join(..., largest = TRUE)`);
    - `h3_6`, `h3_5` = H3 cells of the WGS84 centroid (`h3jsr::point_to_cell()`).
  - H3 cells: the unique cells as polygons (`h3jsr::cell_to_polygon()`), with `h3_id` and `res`.
  - Print counts by case and an area summary.
- [ ] **Acceptance:**
  - `n_parcels` rows, unique `parcel_id`, all geometries valid;
  - about 80 % of areas between 2 and 4 ha, all between 1 and 10 ha;
  - every `border` parcel intersects at least 2 oblasts;
  - at least 80 % of `town` parcels have more than 50 % of their area on soil NoData;
  - none of `oblast`, `h3_6` or `h3_5` is NA.

### T05: `01b-simulate-features.R`

- [ ] **Writer brief.**
  - **In:** `oblasts.gpkg`. **Out:** `data/interim/elevators.gpkg`, `data/interim/roads.gpkg`.
  - Elevators: 60 points from `st_sample()` in the dissolved country, with `elevator_id`.
  - Main roads: 10 straight lines between random pairs of oblast centroids (`type = "main"`).
  - Local roads: 150 lines from random start points, 5–20 km long in a random direction, clipped to the country (`type = "local"`).
  - Header comment: these features are fake. Replace the `read_sf()` lines in `03-distance.R` with real data if you have it.
- [ ] **Acceptance:** counts as specified, all features inside Ukraine, `type` has exactly two values.

### T06: `02-diagnostics.R`

- [ ] **Writer brief.**
  - **In:** oblasts, parcels, elevators, roads, `clay_0-5cm_mean.tif`. **Out:** `output/figures/parcels-map.png`, `output/figures/parcels-zoom.png`.
  - National map: oblast outlines, parcels as points coloured by `case`, elevators, roads by type.
  - Zoom map: three panels showing one `interior`, one `border` and one `town` parcel with their surroundings. The town panel shows the soil NoData area.
  - Print a table of counts and areas by `case` and `oblast`.
- [ ] **Acceptance:** both PNGs exist and look right; the verifier checks this with Read on the image files. The table prints.

### T07: `03-distance.R`

- [ ] **Writer brief.**
  - **In:** parcels, elevators, roads, all transformed to EPSG:4326. **Out:** `data/interim/long_distance.parquet`.
  - Variables, in metres, each computed as `st_distance(from, to[st_nearest_feature(from, to), ], by_element = TRUE)`:
    - `dist_elevator_centroid`, `dist_elevator_edge`;
    - `dist_road_main_centroid`, `dist_road_main_edge`;
    - `dist_road_local_centroid`, `dist_road_local_edge`.

    "From" is `st_centroid()` for `_centroid` and the polygon for `_edge`.
  - `pivot_longer()` to `parcel_id | variable | value`, `source = "observed"`, numeric `value` without units (`as.numeric`).
- [ ] **Acceptance:**
  - 6 rows per parcel, no NA;
  - every edge distance is less than or equal to its centroid distance;
  - a spot check of 3 parcels against `st_distance()` to all features gives the same minimum.

### T08: `04-soil.R`

- [ ] **Writer brief.**
  - **In:** parcels, H3 cells, oblasts, 28 SoilGrids rasters. **Out:** `data/interim/soil_topsoil_0_30cm.tif`, `data/interim/long_soil.parquet`.
  - Topsoil stack, one explicit expression per property, paths in full:

    ```r
    # Topsoil 0-30 cm: thickness-weighted average of the 0-5, 5-15 and 15-30 cm layers
    soil_clay_0_30cm <- (5  * rast(file.path(soil_dir, "clay_0-5cm_mean.tif")) +
                         10 * rast(file.path(soil_dir, "clay_5-15cm_mean.tif")) +
                         15 * rast(file.path(soil_dir, "clay_15-30cm_mean.tif"))) / 30
    ```

    Do this for bdod, cec, cfvo, clay, nitrogen, ocd, phh2o, sand and silt. Add `ocs_0-30cm_mean.tif` as `soil_ocs_0_30cm`. Combine with `c()`, set names, and `writeRaster()` the 10-layer stack.
  - Transform parcels, H3 cells and oblasts to `crs(soil)`.
  - Extract:
    - `_mean`: `exact_extract(soil, parcels, "mean", append_cols = "parcel_id")`;
    - `_centroid`: `terra::extract(soil, vect(st_centroid(parcels)), ID = FALSE)`.
  - Fill-zones block, marked with a banner comment:
    - `exact_extract(soil, h3_cells, "mean", append_cols = c("h3_id", "res"))` and `exact_extract(soil, oblasts, "mean", append_cols = "ADM1_PCODE")`;
    - a comment explains how to swap in rayon or hromada polygons (COD-AB ADM2/ADM3 in `codab_dir`): replace the zone layer and its ID column, and the matching column in `parcels`.
  - Long and fill:
    - pivot parcel values to long, join the zone means by `h3_6`, `h3_5` and `oblast`;
    - `value = coalesce(value, h3_6_value, h3_5_value, oblast_value)`;
    - `source = case_when(!is.na(value_raw) ~ "observed", !is.na(h3_6_value) ~ "h3_6", !is.na(h3_5_value) ~ "h3_5", .default = "oblast")`.
  - Header documents the units (SoilGrids mapped units; see the soil data README) and the fill order. Print counts by `source` and `case`.
- [ ] **Acceptance:**
  - 20 rows per parcel, no NA;
  - non-`observed` rows come mostly from `town` parcels;
  - spot check: for one parcel, the stacked value equals the weighted formula computed by hand from the three depth rasters at its centroid.

### T09: `05-relief.R` (user methodology, binding)

Methodology from the user:
- Statistics come from the whole parcel polygon, never from the centroid or from the pixels whose centre falls inside. Each pixel counts by its coverage fraction, using `exactextractr::exact_extract()`.
- Aspect is measured clockwise from north, in degrees (0 = north, 90 = east, 180 = south). A flat pixel contributes 0 to both aspect variables.
- Slope and aspect are computed in a projected CRS in metres, or with a geodesic-aware method. Never on a DEM in degrees treated as metres, and never in Web Mercator.
- A parcel smaller than one pixel still gets values, from the pixel or pixels it covers.
- Output: one value per parcel per variable, all complete.

- [ ] **Writer brief.**
  - **In:** parcels, `data/interim/dem.vrt`. **Out:** `data/interim/long_relief.parquet`.
  - To keep the computation small, crop the DEM to the parcels' bounding box plus a 2 km buffer, in the DEM's CRS.
  - `terrain(dem, c("slope", "aspect"), unit = "degrees")` on the lon/lat DEM. terra measures cell distances on the ellipsoid for lon/lat input, so this is geodesic-aware. The header says so.
  - Exposure per pixel:
    - `south = -cos(aspect × π/180)`, `east = sin(aspect × π/180)`;
    - both set to 0 where `slope < flat_slope_deg`.
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
  - aspect values within [−1, 1];
  - slope within [0, 90];
  - `relief_elev_range` ≥ 0;
  - the script runs with both `dem_product` values.

### T10: `06-crop.R`

- [ ] **Writer brief.**
  - **In:** parcels and the crop files for 2019–2024. **Out:** `data/interim/long_crop.parquet`.
  - Six explicit blocks, one per year, all with the same shape, and the year written out in full in each:
    1. `r <- rast(crop_2019)`;
    2. `p <- st_transform(parcels, crs(r))`;
    3. `exact_extract(r, p, "frac", append_cols = "parcel_id")`;
    4. `pivot_longer()` of `frac_*` with `names_prefix = "frac_"` to `code` (integer) and `share`;
    5. `left_join()` to that year's `tribble(code, group)`, with codes from "Crop code → group" and T01's note;
    6. `group = coalesce(group, "other")`;
    7. `summarise(value = sum(share), .by = c(parcel_id, group))`;
    8. `complete()` the five groups with 0;
    9. `variable = str_c("crop_", group, "_2019")`.

    If all years share the same legend, one `crop_groups` tribble defined at the top is fine. Otherwise each block gets its own table.
  - Bind the six years, `source = "observed"`.
- [ ] **Acceptance:**
  - 5 rows per parcel per year, no NA;
  - shares within [0, 1];
  - the five shares sum to between 0.99 and 1.01 per parcel-year, or to the parcel's classified share if the raster has NoData, which must then be reported;
  - `town` parcels have a clearly higher `crop_built_*` than `interior` ones.

### T11: `07-crop-2025.R`

- [ ] **Writer brief.**
  - **In:** parcels, `crop_2025_summer`, `crop_2025_winter`. **Out:** `data/interim/crop_2025.tif`, `data/interim/long_crop_2025.parquet`.
  - Comment block explaining the rule:
    - the winter map marks winter cereal (2) and winter rapeseed (3);
    - where the winter map has a crop, it replaces the summer value;
    - elsewhere the summer value is kept;
    - non-crop and missing winter pixels never overwrite summer.
  - Steps:
    1. `winter <- classify(rast(crop_2025_winter), cbind(c(2, 3), c(2, 3)), others = NA)`;
    2. if `!compareGeom(winter, summer, stopOnError = FALSE)`, then `winter <- project(winter, summer, method = "near")`;
    3. `crop_2025 <- cover(winter, summer)`;
    4. `writeRaster()`.
  - Then extract and group as in T10, with the summer 2025 legend table and the suffix `_2025`.
- [ ] **Acceptance:**
  - same checks as T10;
  - mean `crop_ag_2025` is at least as high as the same extraction on the summer map alone (the verifier computes this once in the console);
  - `crop_2025.tif` has the summer map's grid.

### T12: `21-combine.R`

- [ ] **Writer brief.**
  - Read and bind `long_distance`, `long_soil`, `long_relief`, `long_crop` and `long_crop_2025`. Columns: `parcel_id | variable | value | source`.
  - Checks, each with `cli_abort()` on failure:
    - exactly one row per `parcel_id` × `variable`;
    - no NA `value`;
    - `source` within the four allowed levels;
    - every parcel has the same set of variables.
  - Write `output/tables/spatial_covariates.parquet` (`arrow::write_parquet`) and `output/tables/spatial_covariates.csv` (`readr::write_csv`).
  - Print parcels, variables, total rows and rows by `source`.
- [ ] **Acceptance:**
  - both files exist and match in row count;
  - variables per parcel = 6 distance + 20 soil + 6 relief + 35 crop (5 groups × 7 years) = **67**.

### T13: `22-descriptives.R`

- [ ] **Writer brief.**
  - **In:** `output/tables/spatial_covariates.parquet`, parcels (for `case`).
  - Soil, centroid vs polygon:
    - a hard-coded `tribble(mean_var, centroid_var)` with 10 pairs;
    - per pair: Pearson, Spearman, mean absolute difference and n, on `observed` rows only and on all rows;
    - write `output/tables/soil_centroid_vs_polygon.csv`;
    - faceted scatter plot with a 45° line, saved to `output/figures/soil_centroid_vs_polygon.png`.
  - Summaries, each printed and written to `output/tables/`:
    - mean crop-group share by year, and the share of parcels with `crop_ag` > 0.5 by year (`crop_by_year.csv`);
    - distance quantiles by variable (`distance_summary.csv`);
    - relief quantiles (`relief_summary.csv`);
    - rows by `source` × `case` (`soil_source_by_case.csv`).
- [ ] **Acceptance:** every file exists; correlations lie between −1 and 1; the PNG looks right (checked with Read).

### T14: `README.md`, the one-page guide

- [ ] **Writer brief.** Rewrite `README.md`, keeping the Objective section:
  - **Quick start:** clone, `renv::restore()`, set `soil_dir` and `crop_dir` in `00-setup.R`, then source the scripts in order.
  - **Data**, in three groups:
    - "You provide": soil and crop, with their folders and units;
    - "Downloaded by `00b-download.R`": COD-AB and Copernicus DEM, with source, licence, size, and the `dem_product` setting;
    - "Simulated": parcels, elevators, roads.
  - **Run order:** a table of each script (linked) with In / Out / purpose.
  - **Walk-through:** one short section per script, embedding the 5–10 key lines copied from the actual script.
  - **Output schema:** `parcel_id | variable | value | source`. List every variable family with unit and meaning, and the `source` levels.
  - **Methods:**
    - spherical nearest distance;
    - exact extraction with coverage fractions;
    - soil 0–30 cm weighting and fill order;
    - relief definitions and flat threshold;
    - crop grouping including uncultivated → grass;
    - the 2025 winter-over-summer rule.
  - Replace the old "one row per parcel" wording with the long table.
  - At most about one printed page plus the code excerpts. No hand-edited numbers from `output/`.
- [ ] **Acceptance:**
  - every script and file named exists;
  - the code excerpts match the scripts verbatim;
  - the variable count matches T12.

### T15: full run and handover

- [ ] **Verifier only**, no writer:
  1. In a fresh R session, source `00-setup.R` through `22-descriptives.R` in order with `n_parcels = 1000`. Record the run time of each script.
  2. Repeat with `n_parcels = 10000`, by changing the parameter only in the session, not in the file.
  3. Report run times, the final row and variable counts, and any warnings.
- [ ] **Orchestrator:**
  - fill in "Outcome" with what shipped, the run times, any deviations, and links to the notes;
  - set Status to `done`;
  - report to the user: files created, how to verify, and that nothing is committed.

## Open questions

- Whether `21-combine.R` should also write a wide file (one row per parcel) as a convenience. Not done unless the user asks.

## Outcome

Filled in when the status becomes done or superseded.
