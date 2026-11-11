# 00-setup.R
# In:  nothing (checks that the soil folder and the 8 crop rasters exist)
# Out: packages, parameters and path objects in the session; creates the reference, interim and output folders
# Purpose: shared setup, sourced first by every numbered script.

library(tidyverse)
library(sf)
library(terra)
library(exactextractr)
library(arrow)
library(geoarrow) # GDAL has no Parquet driver here: GeoParquet is read and written with geoarrow + arrow
library(h3o)
library(curl)
library(cli)
library(lwgeom)

sf_use_s2(TRUE)

# Paths are relative to the project root, so scripts must run from there
if (!file.exists("00-setup.R")) {
  cli_abort("Run the scripts from the project root folder.")
}

# Parameters ------------------------------------------------------------------

n_parcels <- 1000 # number of simulated reference parcels
study_oblast_en <- "Poltavska" # Poltava oblast (UA53); COD-AB uses the adjectival English name "Poltavska"
crs_work <- "EPSG:3035" # equal-area CRS in metres, for parcel shapes, areas and maps
dem_product <- "GLO-30" # Copernicus DEM product: "GLO-30" (default) or "GLO-90"
flat_slope_deg <- 0.5 # pixels with a slope below this (degrees) count as flat

# Input folders (outside the repo, read-only) ---------------------------------

soil_dir <- "C:/Users/wb532966/OneDrive - WBG/DEC/data-EB/ukrSoilgridsData/data-raw/ukr"
crop_dir <- "C:/Users/wb532966/OneDrive - WBG/DEC/data-EB/ukrCropCover/original-crop-cover-maps"

crop_2019 <- file.path(crop_dir, "GEE_15102019.tif")
crop_2020 <- file.path(crop_dir, "ukr_2020.tif")
crop_2021 <- file.path(crop_dir, "Ukr_October2021.tif")
crop_2022 <- file.path(crop_dir, "Ukraine_August2022_corr.tif")
crop_2023 <- file.path(crop_dir, "Ukraine_2023_01_September.tif")
crop_2024 <- file.path(crop_dir, "Ukraine_september_2024.tif")
crop_2025_summer <- file.path(crop_dir, "SummerMap_Ukraine_2025_WB.tif")
crop_2025_winter <- file.path(crop_dir, "Winter2025_Rape_Cereal.tif")

if (!dir.exists(soil_dir)) {
  cli_abort("Soil folder not found: {.path {soil_dir}}")
}
if (!file.exists(crop_2019)) {
  cli_abort("Crop map not found: {.path {crop_2019}}")
}
if (!file.exists(crop_2020)) {
  cli_abort("Crop map not found: {.path {crop_2020}}")
}
if (!file.exists(crop_2021)) {
  cli_abort("Crop map not found: {.path {crop_2021}}")
}
if (!file.exists(crop_2022)) {
  cli_abort("Crop map not found: {.path {crop_2022}}")
}
if (!file.exists(crop_2023)) {
  cli_abort("Crop map not found: {.path {crop_2023}}")
}
if (!file.exists(crop_2024)) {
  cli_abort("Crop map not found: {.path {crop_2024}}")
}
if (!file.exists(crop_2025_summer)) {
  cli_abort("Crop map not found: {.path {crop_2025_summer}}")
}
if (!file.exists(crop_2025_winter)) {
  cli_abort("Crop map not found: {.path {crop_2025_winter}}")
}

# Crop codes to groups, one table for every year (0 is NoData; unlisted codes become "other")
## ---- crop-groups
crop_groups <- tribble(
  ~code , ~group   ,
      1 , "built"  ,
      2 , "ag"     ,  3 , "ag"     ,  4 , "ag"     ,  5 , "ag" ,  6 , "ag" ,  7 , "ag" ,  8 , "ag" ,  9 , "ag" ,
     15 , "ag"     , 16 , "ag"     , 17 , "ag"     , 19 , "ag" , 21 , "ag" , 24 , "ag" , 26 , "ag" , 27 , "ag" ,
     10 , "forest" , 23 , "forest" , 25 , "forest" ,
     11 , "grass"  , 18 , "grass"  ,
     12 , "bare"   , 20 , "bare"   , 22 , "bare"   ,
     13 , "water"  , 14 , "water"
)
## ---- end-crop-groups

# Downloaded inputs -----------------------------------------------------------

codab_dir <- "data/raw/cod-ab"
dem_dir <- "data/raw/dem"

# Reference inputs (simulated once, committed) --------------------------------

reference_dir <- "data/clean/reference"
parcels_path <- "data/clean/reference/parcels.parquet"
elevators_path <- "data/clean/reference/elevators.parquet"
roads_path <- "data/clean/reference/roads.parquet"

# Interim files ---------------------------------------------------------------

interim_dir <- "data/interim"
oblasts_path <- "data/interim/oblasts.gpkg"
dem_vrt_path <- "data/interim/dem.vrt"
soil_topsoil_path <- "data/interim/soil_topsoil_0_30cm.tif"
long_distance_path <- "data/interim/long_distance.parquet"
long_soil_path <- "data/interim/long_soil.parquet"
long_relief_path <- "data/interim/long_relief.parquet"
long_crop_path <- "data/interim/long_crop.parquet"
long_crop_2025_path <- "data/interim/long_crop_2025.parquet"

# Outputs ---------------------------------------------------------------------

tables_dir <- "output/tables"
figures_dir <- "output/figures"
covariates_parquet_path <- "output/tables/spatial_covariates.parquet"
covariates_csv_path <- "output/tables/spatial_covariates.csv"
distance_check_path <- "output/tables/distance_sphere_vs_ellipsoid.csv"
soil_centroid_vs_polygon_path <- "output/tables/soil_centroid_vs_polygon.csv"
crop_by_year_path <- "output/tables/crop_by_year.csv"
distance_summary_path <- "output/tables/distance_summary.csv"
relief_summary_path <- "output/tables/relief_summary.csv"
soil_source_by_case_path <- "output/tables/soil_source_by_case.csv"
parcels_map_path <- "output/figures/parcels-map.png"
parcels_zoom_path <- "output/figures/parcels-zoom.png"
soil_centroid_vs_polygon_png_path <- "output/figures/soil_centroid_vs_polygon.png"

dir.create(reference_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(interim_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)

cli_inform(
  "Setup done: study oblast {study_oblast_en}, DEM {dem_product}, {n_parcels} parcels."
)
