# 06-crop.R
# In:  data/clean/reference/parcels.parquet, crop maps crop_2019 ... crop_2024, crop_groups (from 00-setup.R)
# Out: data/interim/long_crop.parquet
# Purpose: share of each parcel in 7 crop groups, one explicit block per year 2019-2024.

source("00-setup.R")

parcels <- arrow::read_parquet(parcels_path, as_data_frame = FALSE) |> st_as_sf()

# "frac" is the share of the parcel's classified (non-NoData) area in each code.
# 0 is NoData in every year. A parcel entirely on NoData gets 0 for all groups;
# the number of such parcels is printed for each year.

# 2019 ------------------------------------------------------------------------

r <- rast(crop_2019)
NAflag(r) <- 0
p <- st_transform(parcels, crs(r))

crop_long_2019 <- exact_extract(r, p, "frac", append_cols = "parcel_id", progress = FALSE) |>
  pivot_longer(starts_with("frac_"), names_to = "code", names_prefix = "frac_",
               names_transform = as.integer, values_to = "share", values_drop_na = TRUE) |>
  left_join(crop_groups, by = "code") |>
  mutate(group = coalesce(group, "other")) |>
  summarise(value = sum(share), .by = c(parcel_id, group)) |>
  complete(parcel_id = parcels$parcel_id,
           group = c("built", "ag", "forest", "grass", "bare", "water", "other"),
           fill = list(value = 0)) |>
  mutate(variable = str_c("crop_", group, "_2019"))

n_empty_2019 <- crop_long_2019 |> summarise(total = sum(value), .by = parcel_id) |> filter(total == 0) |> nrow()
cli_inform("2019: {n_empty_2019} parcel{?s} entirely on NoData.")

# 2020 ------------------------------------------------------------------------

r <- rast(crop_2020)
NAflag(r) <- 0
p <- st_transform(parcels, crs(r))

crop_long_2020 <- exact_extract(r, p, "frac", append_cols = "parcel_id", progress = FALSE) |>
  pivot_longer(starts_with("frac_"), names_to = "code", names_prefix = "frac_",
               names_transform = as.integer, values_to = "share", values_drop_na = TRUE) |>
  left_join(crop_groups, by = "code") |>
  mutate(group = coalesce(group, "other")) |>
  summarise(value = sum(share), .by = c(parcel_id, group)) |>
  complete(parcel_id = parcels$parcel_id,
           group = c("built", "ag", "forest", "grass", "bare", "water", "other"),
           fill = list(value = 0)) |>
  mutate(variable = str_c("crop_", group, "_2020"))

n_empty_2020 <- crop_long_2020 |> summarise(total = sum(value), .by = parcel_id) |> filter(total == 0) |> nrow()
cli_inform("2020: {n_empty_2020} parcel{?s} entirely on NoData.")

# 2021 ------------------------------------------------------------------------

r <- rast(crop_2021)
NAflag(r) <- 0
p <- st_transform(parcels, crs(r))

crop_long_2021 <- exact_extract(r, p, "frac", append_cols = "parcel_id", progress = FALSE) |>
  pivot_longer(starts_with("frac_"), names_to = "code", names_prefix = "frac_",
               names_transform = as.integer, values_to = "share", values_drop_na = TRUE) |>
  left_join(crop_groups, by = "code") |>
  mutate(group = coalesce(group, "other")) |>
  summarise(value = sum(share), .by = c(parcel_id, group)) |>
  complete(parcel_id = parcels$parcel_id,
           group = c("built", "ag", "forest", "grass", "bare", "water", "other"),
           fill = list(value = 0)) |>
  mutate(variable = str_c("crop_", group, "_2021"))

n_empty_2021 <- crop_long_2021 |> summarise(total = sum(value), .by = parcel_id) |> filter(total == 0) |> nrow()
cli_inform("2021: {n_empty_2021} parcel{?s} entirely on NoData.")

# 2022 ------------------------------------------------------------------------

r <- rast(crop_2022)
NAflag(r) <- 0
p <- st_transform(parcels, crs(r))

crop_long_2022 <- exact_extract(r, p, "frac", append_cols = "parcel_id", progress = FALSE) |>
  pivot_longer(starts_with("frac_"), names_to = "code", names_prefix = "frac_",
               names_transform = as.integer, values_to = "share", values_drop_na = TRUE) |>
  left_join(crop_groups, by = "code") |>
  mutate(group = coalesce(group, "other")) |>
  summarise(value = sum(share), .by = c(parcel_id, group)) |>
  complete(parcel_id = parcels$parcel_id,
           group = c("built", "ag", "forest", "grass", "bare", "water", "other"),
           fill = list(value = 0)) |>
  mutate(variable = str_c("crop_", group, "_2022"))

n_empty_2022 <- crop_long_2022 |> summarise(total = sum(value), .by = parcel_id) |> filter(total == 0) |> nrow()
cli_inform("2022: {n_empty_2022} parcel{?s} entirely on NoData.")

# 2023 ------------------------------------------------------------------------

r <- rast(crop_2023)
NAflag(r) <- 0
p <- st_transform(parcels, crs(r))

crop_long_2023 <- exact_extract(r, p, "frac", append_cols = "parcel_id", progress = FALSE) |>
  pivot_longer(starts_with("frac_"), names_to = "code", names_prefix = "frac_",
               names_transform = as.integer, values_to = "share", values_drop_na = TRUE) |>
  left_join(crop_groups, by = "code") |>
  mutate(group = coalesce(group, "other")) |>
  summarise(value = sum(share), .by = c(parcel_id, group)) |>
  complete(parcel_id = parcels$parcel_id,
           group = c("built", "ag", "forest", "grass", "bare", "water", "other"),
           fill = list(value = 0)) |>
  mutate(variable = str_c("crop_", group, "_2023"))

n_empty_2023 <- crop_long_2023 |> summarise(total = sum(value), .by = parcel_id) |> filter(total == 0) |> nrow()
cli_inform("2023: {n_empty_2023} parcel{?s} entirely on NoData.")

# 2024 ------------------------------------------------------------------------

r <- rast(crop_2024)
NAflag(r) <- 0
p <- st_transform(parcels, crs(r))

crop_long_2024 <- exact_extract(r, p, "frac", append_cols = "parcel_id", progress = FALSE) |>
  pivot_longer(starts_with("frac_"), names_to = "code", names_prefix = "frac_",
               names_transform = as.integer, values_to = "share", values_drop_na = TRUE) |>
  left_join(crop_groups, by = "code") |>
  mutate(group = coalesce(group, "other")) |>
  summarise(value = sum(share), .by = c(parcel_id, group)) |>
  complete(parcel_id = parcels$parcel_id,
           group = c("built", "ag", "forest", "grass", "bare", "water", "other"),
           fill = list(value = 0)) |>
  mutate(variable = str_c("crop_", group, "_2024"))

n_empty_2024 <- crop_long_2024 |> summarise(total = sum(value), .by = parcel_id) |> filter(total == 0) |> nrow()
cli_inform("2024: {n_empty_2024} parcel{?s} entirely on NoData.")

# Long table ------------------------------------------------------------------

long_crop <- bind_rows(crop_long_2019, crop_long_2020, crop_long_2021,
                       crop_long_2022, crop_long_2023, crop_long_2024) |>
  mutate(source = "observed") |>
  select(parcel_id, variable, value, source)

arrow::write_parquet(long_crop, long_crop_path)
cli_inform("Wrote {nrow(long_crop)} rows to {.path {long_crop_path}}.")
