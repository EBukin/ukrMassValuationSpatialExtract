# 04-soil.R
# In:  data/clean/reference/parcels.parquet, data/interim/oblasts.gpkg, 28 SoilGrids rasters in soil_dir
# Out: data/interim/soil_topsoil_0_30cm.tif, data/interim/long_soil.parquet
# Purpose: topsoil (0-30 cm) soil properties per parcel (polygon mean and centroid), with NoData filled.
#
# Units are SoilGrids mapped units (not converted):
#   bdod cg/cm3, cec mmol(c)/kg, cfvo cm3/dm3, clay g/kg, nitrogen cg/kg,
#   ocd hg/m3, phh2o pH x 10, sand g/kg, silt g/kg, ocs t/ha (already 0-30 cm).
# Topsoil = (5 * d0_5 + 10 * d5_15 + 15 * d15_30) / 30, per pixel.
# NoData fill order: H3 res-6 cell mean -> H3 res-5 cell mean -> oblast mean.
# The level used goes in `source`. A parcel partly covered by soil data counts as "observed".

source("00-setup.R")

# Parcels and study area in the soil CRS --------------------------------------

parcels <- arrow::read_parquet(parcels_path, as_data_frame = FALSE) |>
  st_as_sf()
oblasts <- st_read(oblasts_path, quiet = TRUE)

poltava <- oblasts |> filter(oblast_en == study_oblast_en)
study_oblasts <- oblasts |> filter(lengths(st_intersects(oblasts, poltava)) > 0) # Poltava and its neighbours

soil_crs <- crs(rast(file.path(soil_dir, "clay_0-5cm_mean.tif"))) # Interrupted Goode Homolosine

parcels_soil <- st_transform(parcels, soil_crs)
study_oblasts_soil <- st_transform(study_oblasts, soil_crs)
study_box <- vect(study_oblasts_soil) # crop() uses its extent

cli_inform(
  "Study area: {study_oblast_en} and {nrow(study_oblasts) - 1} neighbouring oblasts."
)

# Topsoil 0-30 cm rasters -----------------------------------------------------

# Topsoil 0-30 cm: thickness-weighted average of the 0-5, 5-15 and 15-30 cm layers
soil_bdod_0_30cm <- (5 *
  crop(rast(file.path(soil_dir, "bdod_0-5cm_mean.tif")), study_box) +
  10 * crop(rast(file.path(soil_dir, "bdod_5-15cm_mean.tif")), study_box) +
  15 * crop(rast(file.path(soil_dir, "bdod_15-30cm_mean.tif")), study_box)) /
  30

soil_cec_0_30cm <- (5 *
  crop(rast(file.path(soil_dir, "cec_0-5cm_mean.tif")), study_box) +
  10 * crop(rast(file.path(soil_dir, "cec_5-15cm_mean.tif")), study_box) +
  15 * crop(rast(file.path(soil_dir, "cec_15-30cm_mean.tif")), study_box)) /
  30

soil_cfvo_0_30cm <- (5 *
  crop(rast(file.path(soil_dir, "cfvo_0-5cm_mean.tif")), study_box) +
  10 * crop(rast(file.path(soil_dir, "cfvo_5-15cm_mean.tif")), study_box) +
  15 * crop(rast(file.path(soil_dir, "cfvo_15-30cm_mean.tif")), study_box)) /
  30

soil_clay_0_30cm <- (5 *
  crop(rast(file.path(soil_dir, "clay_0-5cm_mean.tif")), study_box) +
  10 * crop(rast(file.path(soil_dir, "clay_5-15cm_mean.tif")), study_box) +
  15 * crop(rast(file.path(soil_dir, "clay_15-30cm_mean.tif")), study_box)) /
  30

soil_nitrogen_0_30cm <- (5 *
  crop(rast(file.path(soil_dir, "nitrogen_0-5cm_mean.tif")), study_box) +
  10 * crop(rast(file.path(soil_dir, "nitrogen_5-15cm_mean.tif")), study_box) +
  15 *
    crop(rast(file.path(soil_dir, "nitrogen_15-30cm_mean.tif")), study_box)) /
  30

soil_ocd_0_30cm <- (5 *
  crop(rast(file.path(soil_dir, "ocd_0-5cm_mean.tif")), study_box) +
  10 * crop(rast(file.path(soil_dir, "ocd_5-15cm_mean.tif")), study_box) +
  15 * crop(rast(file.path(soil_dir, "ocd_15-30cm_mean.tif")), study_box)) /
  30

soil_phh2o_0_30cm <- (5 *
  crop(rast(file.path(soil_dir, "phh2o_0-5cm_mean.tif")), study_box) +
  10 * crop(rast(file.path(soil_dir, "phh2o_5-15cm_mean.tif")), study_box) +
  15 * crop(rast(file.path(soil_dir, "phh2o_15-30cm_mean.tif")), study_box)) /
  30

soil_sand_0_30cm <- (5 *
  crop(rast(file.path(soil_dir, "sand_0-5cm_mean.tif")), study_box) +
  10 * crop(rast(file.path(soil_dir, "sand_5-15cm_mean.tif")), study_box) +
  15 * crop(rast(file.path(soil_dir, "sand_15-30cm_mean.tif")), study_box)) /
  30

soil_silt_0_30cm <- (5 *
  crop(rast(file.path(soil_dir, "silt_0-5cm_mean.tif")), study_box) +
  10 * crop(rast(file.path(soil_dir, "silt_5-15cm_mean.tif")), study_box) +
  15 * crop(rast(file.path(soil_dir, "silt_15-30cm_mean.tif")), study_box)) /
  30

# Organic carbon stock is already given for 0-30 cm
soil_ocs_0_30cm <- crop(
  rast(file.path(soil_dir, "ocs_0-30cm_mean.tif")),
  study_box
)

soil <- c(
  soil_bdod_0_30cm,
  soil_cec_0_30cm,
  soil_cfvo_0_30cm,
  soil_clay_0_30cm,
  soil_nitrogen_0_30cm,
  soil_ocd_0_30cm,
  soil_phh2o_0_30cm,
  soil_sand_0_30cm,
  soil_silt_0_30cm,
  soil_ocs_0_30cm
)
names(soil) <- c(
  "soil_bdod_0_30cm",
  "soil_cec_0_30cm",
  "soil_cfvo_0_30cm",
  "soil_clay_0_30cm",
  "soil_nitrogen_0_30cm",
  "soil_ocd_0_30cm",
  "soil_phh2o_0_30cm",
  "soil_sand_0_30cm",
  "soil_silt_0_30cm",
  "soil_ocs_0_30cm"
)

writeRaster(soil, soil_topsoil_path, overwrite = TRUE)
soil <- rast(soil_topsoil_path)

# Parcel values ---------------------------------------------------------------

# Polygon mean, weighted by the share of each pixel inside the parcel (NoData pixels are skipped)
soil_mean <- exact_extract(
  soil,
  parcels_soil,
  "mean",
  append_cols = "parcel_id",
  progress = FALSE
) |>
  pivot_longer(
    -parcel_id,
    names_to = "property",
    names_prefix = "mean.",
    values_to = "value_raw"
  ) |>
  mutate(variable = paste0(property, "_mean"))

# Value of the pixel under the parcel centroid
soil_centroid <- terra::extract(
  soil,
  vect(st_centroid(parcels_soil)),
  ID = FALSE
) |>
  mutate(parcel_id = parcels_soil$parcel_id) |>
  pivot_longer(-parcel_id, names_to = "property", values_to = "value_raw") |>
  mutate(variable = paste0(property, "_centroid"))

soil_long <- bind_rows(soil_mean, soil_centroid) |>
  mutate(value_raw = if_else(is.nan(value_raw), NA, value_raw)) |> # a parcel with no soil data gives NaN
  left_join(
    st_drop_geometry(parcels) |> select(parcel_id, case, oblast, h3_6, h3_5),
    by = "parcel_id"
  )

# =============================================================================
# FILL ZONES
# Mean soil value in each zone, used where a parcel has no soil data.
# To use rayon or hromada polygons instead of H3 cells, read COD-AB ADM2 (rayon)
# or ADM3 (hromada) from data/raw/cod-ab, add the zone code to the parcels with
# st_join(), and replace the H3 zones below with those polygons and codes.
# =============================================================================

# H3 hexagons of the parcels' cells, built from the cell IDs
hex_6 <- tibble(h3_6 = unique(parcels$h3_6)) |>
  mutate(geometry = h3o::h3_from_strings(h3_6) |> st_as_sfc()) |>
  st_as_sf() |>
  st_transform(soil_crs)

hex_5 <- tibble(h3_5 = unique(parcels$h3_5)) |>
  mutate(geometry = h3o::h3_from_strings(h3_5) |> st_as_sfc()) |>
  st_as_sf() |>
  st_transform(soil_crs)

zone_h3_6 <- exact_extract(
  soil,
  hex_6,
  "mean",
  append_cols = "h3_6",
  progress = FALSE
) |>
  pivot_longer(
    -h3_6,
    names_to = "property",
    names_prefix = "mean.",
    values_to = "h3_6_value"
  )

zone_h3_5 <- exact_extract(
  soil,
  hex_5,
  "mean",
  append_cols = "h3_5",
  progress = FALSE
) |>
  pivot_longer(
    -h3_5,
    names_to = "property",
    names_prefix = "mean.",
    values_to = "h3_5_value"
  )

# Oblast mean, for Poltava and its neighbours (joined on the parcel's oblast)
zone_oblast <- exact_extract(
  soil,
  study_oblasts_soil,
  "mean",
  append_cols = "oblast_en",
  progress = FALSE
) |>
  rename(oblast = oblast_en) |>
  pivot_longer(
    -oblast,
    names_to = "property",
    names_prefix = "mean.",
    values_to = "oblast_value"
  )

# Fill ------------------------------------------------------------------------

soil_long <- soil_long |>
  left_join(zone_h3_6, by = c("h3_6", "property")) |>
  left_join(zone_h3_5, by = c("h3_5", "property")) |>
  left_join(zone_oblast, by = c("oblast", "property")) |>
  mutate(
    h3_6_value = if_else(is.nan(h3_6_value), NA, h3_6_value),
    h3_5_value = if_else(is.nan(h3_5_value), NA, h3_5_value),
    value = coalesce(value_raw, h3_6_value, h3_5_value, oblast_value),
    source = case_when(
      !is.na(value_raw) ~ "observed",
      !is.na(h3_6_value) ~ "h3_6",
      !is.na(h3_5_value) ~ "h3_5",
      !is.na(oblast_value) ~ "oblast"
    )
  )

if (anyNA(soil_long$value)) {
  cli_abort("Some soil values are still missing after the fill.")
}
if (nrow(soil_long) != 20 * nrow(parcels)) {
  cli_abort("Expected 20 soil rows per parcel, got {nrow(soil_long)} rows.")
}

# Counts by source and case
soil_long |> count(source, case) |> print()

# Save ------------------------------------------------------------------------

long_soil <- soil_long |> select(parcel_id, variable, value, source)

gc() # release memory-mapped files before overwriting (Windows)
arrow::write_parquet(long_soil, long_soil_path)

cli_inform(
  "Soil done: {n_distinct(long_soil$variable)} variables, {nrow(long_soil)} rows in {.path {long_soil_path}}."
)
