# ukrMassValuationSpatialExtract

A baseline for computing spatial covariates for the mass valuation of agricultural land in Ukraine: a fixed set of 1,000 simulated parcels in Poltava oblast, with 81 covariates each (distance, soil, relief, crop cover), that other implementations can compare against.

**Website (methods, variables, full code):** <https://ebukin.github.io/ukrMassValuationSpatialExtract/>

## Quick start

1. Open the project in R (4.6 or later) from the project root and run `renv::restore()`.
2. Set the paths to your soil and crop rasters in `00-setup.R` (`soil_dir`, `crop_dir`).
3. Download the public inputs once: `source("00b-download.R")`.
4. Run the scripts below in order, each with `source()`.

## Run order

| Script | Purpose |
|---|---|
| `00-setup.R` | Packages, parameters and paths; sourced by every script |
| `00b-download.R` | Download COD-AB oblast boundaries and Copernicus DEM tiles |
| `01-simulate-reference.R` | Simulated the committed reference parcels, elevators and roads once; not part of the normal run |
| `02-diagnostics.R` | Maps of the reference inputs |
| `03-distance.R` | Distances to elevators and roads, on the sphere |
| `04-soil.R` | SoilGrids topsoil 0–30 cm, polygon mean and centroid, NoData filled |
| `05-relief.R` | Elevation, slope and aspect from the Copernicus DEM |
| `06-crop.R` | Crop group shares, 2019–2024 |
| `07-crop-2025.R` | Crop group shares, 2025 (winter over summer) |
| `21-combine.R` | One long table: `output/tables/spatial_covariates.parquet` |
| `22-descriptives.R` | Summary tables and figures in `output/` |

The website is rendered locally with `quarto render site` into `docs/`.
