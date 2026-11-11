# 07-crop-2025.R
# In:  data/clean/reference/parcels.parquet, crop maps crop_2025_summer and crop_2025_winter, crop_groups (from 00-setup.R)
# Out: data/interim/long_crop_2025.parquet
# Purpose: share of each parcel in 7 crop groups in 2025, with winter crops taking precedence over the summer map.

source("00-setup.R")

parcels <- arrow::read_parquet(parcels_path, as_data_frame = FALSE) |>
  st_as_sf()

# Rule for 2025:
# - the winter map marks winter cereal (2) and winter rapeseed (3);
# - inside each parcel, a pixel takes the winter code where winter is 2 or 3,
#   otherwise the summer code;
# - winter non-crop and NoData never overwrite summer;
# - this is applied per pixel inside parcels, never on the whole raster.
# 0 is NoData in both maps. Shares are of the parcel's classified (non-NoData) area;
# a parcel entirely on NoData gets 0 for all groups, and the count is printed.

summer <- rast(crop_2025_summer)
names(summer) <- "summer"
NAflag(summer) <- 0

winter <- rast(crop_2025_winter)
names(winter) <- "winter"
NAflag(winter) <- 0

if (any(dim(winter) != dim(summer))) {
  cli_abort("The 2025 winter and summer maps have different dimensions.")
}
if (max(abs(c(xmin(winter) - xmin(summer), ymax(winter) - ymax(summer)))) > 5) {
  cli_abort("The 2025 winter and summer map origins differ by more than 5 m.")
}

# The winter origin is shifted by about 2 m (less than a quarter of a pixel).
# Giving it the summer extent matches each winter pixel to its nearest summer pixel.
ext(winter) <- ext(summer)

p <- st_transform(parcels, crs(summer))

pixels <- exact_extract(
  c(summer, winter),
  p,
  include_cols = "parcel_id",
  progress = FALSE
) |>
  bind_rows()

crop_long_2025 <- pixels |>
  mutate(code = if_else(winter %in% c(2, 3), winter, summer)) |>
  filter(!is.na(code)) |>
  left_join(crop_groups, by = "code") |>
  mutate(group = coalesce(group, "other")) |>
  summarise(value = sum(coverage_fraction), .by = c(parcel_id, group)) |>
  mutate(value = value / sum(value), .by = parcel_id) |>
  complete(
    parcel_id = parcels$parcel_id,
    group = c("built", "ag", "forest", "grass", "bare", "water", "other"),
    fill = list(value = 0)
  ) |>
  mutate(variable = str_c("crop_", group, "_2025"))

n_empty_2025 <- crop_long_2025 |>
  summarise(total = sum(value), .by = parcel_id) |>
  filter(total == 0) |>
  nrow()
cli_inform("2025: {n_empty_2025} parcel{?s} entirely on NoData.")

# Long table ------------------------------------------------------------------

long_crop_2025 <- crop_long_2025 |>
  mutate(source = "observed") |>
  select(parcel_id, variable, value, source)

arrow::write_parquet(long_crop_2025, long_crop_2025_path)
cli_inform(
  "Wrote {nrow(long_crop_2025)} rows to {.path {long_crop_2025_path}}."
)
