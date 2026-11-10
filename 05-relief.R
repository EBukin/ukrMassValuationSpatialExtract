# 05-relief.R
# In:  data/clean/reference/parcels.parquet, data/interim/dem.vrt
# Out: data/interim/long_relief.parquet
# Purpose: relief per parcel (elevation, slope, aspect exposure) from the whole parcel polygon.
#
# The DEM is cropped only, never resampled or reprojected (EPSG:4326, elevation in metres).
# Slope and aspect come from terra::terrain() on the lon/lat grid. terra's help page (?terra::terrain)
# says: "Distances (needed for slope and aspect) for longitude/latitude data are computed on the
# WGS84 ellipsoid with Karney's algorithm." So no degrees are treated as metres.
# Aspect is clockwise from north, in degrees. A flat pixel (slope < flat_slope_deg) gets 0 for
# both exposure variables: south = -cos(aspect), east = sin(aspect).
# Statistics use exact_extract(): "mean" weights each pixel by the share of it inside the parcel;
# "max" and "min" use every pixel the parcel touches, so a parcel smaller than one pixel still gets values.

source("00-setup.R")

# Parcels and DEM -------------------------------------------------------------

parcels <- arrow::read_parquet(parcels_path, as_data_frame = FALSE) |> st_as_sf()

# Parcels' extent plus 0.02 degrees, so terrain() has neighbours at the edge of every parcel
parcels_box <- ext(vect(parcels)) + 0.02

elev <- crop(rast(dem_vrt_path), parcels_box)
names(elev) <- "elev"

# Slope, aspect and exposure --------------------------------------------------

slope_aspect <- terrain(elev, c("slope", "aspect"), unit = "degrees")
slope <- slope_aspect[["slope"]]
aspect <- slope_aspect[["aspect"]]

south <- ifel(slope < flat_slope_deg, 0, -cos(aspect * pi / 180))
east <- ifel(slope < flat_slope_deg, 0, sin(aspect * pi / 180))

relief <- c(elev, slope, south, east)
names(relief) <- c("elev", "slope", "south", "east")

# Parcel values ---------------------------------------------------------------

relief_stats <- exact_extract(relief, parcels, c("mean", "max", "min"), append_cols = "parcel_id", progress = FALSE)

relief_wide <- relief_stats |>
  transmute(
    parcel_id,
    relief_elev_mean = mean.elev,
    relief_slope_mean = mean.slope,
    relief_slope_max = max.slope,
    relief_elev_range = max.elev - min.elev,
    relief_aspect_south = mean.south,
    relief_aspect_east = mean.east
  )

long_relief <- relief_wide |>
  pivot_longer(-parcel_id, names_to = "variable", values_to = "value") |>
  mutate(source = "observed")

if (anyNA(long_relief$value)) cli_abort("Some relief values are missing.")
if (nrow(long_relief) != 6 * nrow(parcels)) cli_abort("Expected 6 relief rows per parcel, got {nrow(long_relief)} rows.")

# Range of each variable
long_relief |>
  group_by(variable) |>
  summarise(min = min(value), max = max(value)) |>
  print()

# Save ------------------------------------------------------------------------

gc()   # release memory-mapped files before overwriting (Windows)
arrow::write_parquet(long_relief, long_relief_path)

cli_inform("Relief done: {n_distinct(long_relief$variable)} variables, {nrow(long_relief)} rows in {.path {long_relief_path}}.")
