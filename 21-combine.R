# 21-combine.R
# In:  data/interim/long_distance.parquet, long_soil.parquet, long_relief.parquet, long_crop.parquet, long_crop_2025.parquet
# Out: output/tables/spatial_covariates.parquet, output/tables/spatial_covariates.csv
# Purpose: bind the five long tables into one table of 81 covariates per parcel and check it.

source("00-setup.R")

long_distance <- arrow::read_parquet(long_distance_path)
long_soil <- arrow::read_parquet(long_soil_path)
long_relief <- arrow::read_parquet(long_relief_path)
long_crop <- arrow::read_parquet(long_crop_path)
long_crop_2025 <- arrow::read_parquet(long_crop_2025_path)

covariates <- bind_rows(long_distance, long_soil, long_relief, long_crop, long_crop_2025) |>
  select(parcel_id, variable, value, source) |>
  arrange(parcel_id, variable)

# Checks ----------------------------------------------------------------------

n_duplicates <- covariates |> count(parcel_id, variable) |> filter(n > 1) |> nrow()
if (n_duplicates > 0) cli_abort("{n_duplicates} parcel x variable combinations appear more than once.")

if (anyNA(covariates)) cli_abort("The combined table has missing values.")

if (!all(covariates$source %in% c("observed", "h3_6", "h3_5", "oblast"))) cli_abort("{.field source} has values outside observed, h3_6, h3_5, oblast.")

variables_per_parcel <- covariates |> count(parcel_id)
if (any(variables_per_parcel$n != 81)) cli_abort("Not every parcel has 81 variables.")
if (n_distinct(covariates$variable) != 81) cli_abort("The table does not have 81 distinct variables.")

# Summary ---------------------------------------------------------------------

cli_inform("Parcels: {n_distinct(covariates$parcel_id)}")
cli_inform("Variables: {n_distinct(covariates$variable)}")
cli_inform("Rows: {nrow(covariates)}")
print(count(covariates, source))

# Write -----------------------------------------------------------------------

gc()
arrow::write_parquet(covariates, covariates_parquet_path)
write_csv(covariates, covariates_csv_path)

cli_inform("Wrote {nrow(covariates)} rows to {.path {covariates_parquet_path}} and {.path {covariates_csv_path}}.")
