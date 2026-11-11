# 22-descriptives.R
# In:  output/tables/spatial_covariates.parquet, data/clean/reference/parcels.parquet
# Out: output/tables/soil_centroid_vs_polygon.csv, crop_by_year.csv, distance_summary.csv, relief_summary.csv,
#      soil_source_by_case.csv; output/figures/soil_centroid_vs_polygon.png
# Purpose: descriptive statistics of the covariates, printed and saved.

source("00-setup.R")

covariates <- arrow::read_parquet(covariates_parquet_path)
parcels <- arrow::read_parquet(parcels_path, col_select = c(parcel_id, case)) # attributes only, no geometry

# Soil: centroid value vs polygon mean -----------------------------------------

# Units are SoilGrids mapped units (see 04-soil.R)
soil_pairs <- tribble(
  ~property  , ~mean_var                   , ~centroid_var                   , ~label             ,
  "bdod"     , "soil_bdod_0_30cm_mean"     , "soil_bdod_0_30cm_centroid"     , "bdod (cg/cm³)"    ,
  "cec"      , "soil_cec_0_30cm_mean"      , "soil_cec_0_30cm_centroid"      , "cec (mmol(c)/kg)" ,
  "cfvo"     , "soil_cfvo_0_30cm_mean"     , "soil_cfvo_0_30cm_centroid"     , "cfvo (cm³/dm³)"   ,
  "clay"     , "soil_clay_0_30cm_mean"     , "soil_clay_0_30cm_centroid"     , "clay (g/kg)"      ,
  "nitrogen" , "soil_nitrogen_0_30cm_mean" , "soil_nitrogen_0_30cm_centroid" , "nitrogen (cg/kg)" ,
  "ocd"      , "soil_ocd_0_30cm_mean"      , "soil_ocd_0_30cm_centroid"      , "ocd (hg/m³)"      ,
  "ocs"      , "soil_ocs_0_30cm_mean"      , "soil_ocs_0_30cm_centroid"      , "ocs (t/ha)"       ,
  "phh2o"    , "soil_phh2o_0_30cm_mean"    , "soil_phh2o_0_30cm_centroid"    , "phh2o (pH × 10)"  ,
  "sand"     , "soil_sand_0_30cm_mean"     , "soil_sand_0_30cm_centroid"     , "sand (g/kg)"      ,
  "silt"     , "soil_silt_0_30cm_mean"     , "soil_silt_0_30cm_centroid"     , "silt (g/kg)"
)

soil_mean <- covariates |>
  inner_join(soil_pairs, by = c("variable" = "mean_var")) |>
  select(parcel_id, property, label, mean_value = value, mean_source = source)

soil_centroid <- covariates |>
  inner_join(soil_pairs, by = c("variable" = "centroid_var")) |>
  select(parcel_id, property, centroid_value = value, centroid_source = source)

soil_compare <- soil_mean |>
  inner_join(soil_centroid, by = c("parcel_id", "property")) |>
  mutate(observed = mean_source == "observed" & centroid_source == "observed")

if (nrow(soil_compare) != 10 * n_distinct(covariates$parcel_id)) {
  cli_abort("Soil pairs do not cover 10 properties for every parcel.")
}

soil_stats_observed <- soil_compare |>
  filter(observed) |>
  group_by(property, label) |>
  summarise(
    rows = "observed",
    pearson = cor(mean_value, centroid_value),
    spearman = cor(mean_value, centroid_value, method = "spearman"),
    mean_abs_diff = mean(abs(centroid_value - mean_value)),
    n = n(),
    .groups = "drop"
  )

soil_stats_all <- soil_compare |>
  group_by(property, label) |>
  summarise(
    rows = "all",
    pearson = cor(mean_value, centroid_value),
    spearman = cor(mean_value, centroid_value, method = "spearman"),
    mean_abs_diff = mean(abs(centroid_value - mean_value)),
    n = n(),
    .groups = "drop"
  )

soil_stats <- bind_rows(soil_stats_observed, soil_stats_all) |>
  arrange(property, desc(rows))

if (anyNA(soil_stats$pearson) || anyNA(soil_stats$spearman)) {
  cli_abort("Some soil correlations are missing.")
}
if (any(abs(soil_stats$pearson) > 1) || any(abs(soil_stats$spearman) > 1)) {
  cli_abort("Soil correlations outside [-1, 1].")
}

print(soil_stats, n = Inf)
write_csv(soil_stats, soil_centroid_vs_polygon_path)

# Scatter plot, one facet per property. geom_blank() with x and y swapped gives
# each facet the same range on both axes, so the 45° line is a true diagonal.
soil_plot_data <- soil_compare |>
  mutate(fill = if_else(observed, "Observed", "Filled (H3 or oblast mean)"))

soil_plot <- ggplot(soil_plot_data, aes(x = mean_value, y = centroid_value)) +
  geom_blank(aes(x = centroid_value, y = mean_value)) +
  geom_abline(
    slope = 1,
    intercept = 0,
    colour = "#52514e",
    linewidth = 0.4,
    linetype = "dashed"
  ) +
  geom_point(aes(colour = fill), size = 0.9, alpha = 0.5) +
  facet_wrap(vars(label), ncol = 5, scales = "free") +
  scale_colour_manual(
    values = c(
      "Observed" = "#2a78d6",
      "Filled (H3 or oblast mean)" = "#eb6834"
    ),
    breaks = c("Observed", "Filled (H3 or oblast mean)")
  ) +
  guides(colour = guide_legend(override.aes = list(size = 2.5, alpha = 1))) +
  labs(
    title = "Soil 0–30 cm: value at the parcel centroid vs mean over the parcel polygon",
    subtitle = "One point per parcel; dashed line: centroid = polygon mean. SoilGrids mapped units.",
    x = "Polygon mean",
    y = "Centroid value",
    colour = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "top",
    legend.justification = "left",
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold", hjust = 0),
    plot.background = element_rect(fill = "white", colour = NA)
  )

ggsave(
  soil_centroid_vs_polygon_png_path,
  soil_plot,
  width = 12,
  height = 6,
  dpi = 200,
  bg = "white"
)

# Crop share by group and year ---------------------------------------------------

# Variable names look like crop_ag_2019: split them at "_" into group and year
crop_by_year <- covariates |>
  filter(startsWith(variable, "crop_")) |>
  separate_wider_delim(variable, delim = "_", names = c(NA, "group", "year")) |>
  group_by(year, group) |>
  summarise(
    mean_share = mean(value),
    median_share = median(value),
    share_parcels_above_half = mean(value > 0.5), # for ag: share of parcels with crop_ag > 0.5
    n = n(),
    .groups = "drop"
  ) |>
  arrange(year, group)

print(crop_by_year, n = Inf)
cli_inform("Share of parcels with {.field crop_ag} > 0.5, by year:")
print(
  filter(crop_by_year, group == "ag") |> select(year, share_parcels_above_half)
)
write_csv(crop_by_year, crop_by_year_path)

# Distance quantiles (metres) ----------------------------------------------------

distance_vars <- c(
  "dist_elevator_centroid",
  "dist_elevator_edge",
  "dist_road_main_centroid",
  "dist_road_main_edge",
  "dist_road_local_centroid",
  "dist_road_local_edge"
)

distance_summary <- covariates |>
  filter(variable %in% distance_vars) |>
  group_by(variable) |>
  summarise(
    unit = "m",
    n = n(),
    min = min(value),
    p05 = quantile(value, 0.05),
    p25 = quantile(value, 0.25),
    median = median(value),
    mean = mean(value),
    p75 = quantile(value, 0.75),
    p95 = quantile(value, 0.95),
    max = max(value)
  )

print(distance_summary, width = Inf)
write_csv(distance_summary, distance_summary_path)

# Relief quantiles -----------------------------------------------------------------

relief_units <- tribble(
  ~variable             , ~unit           ,
  "relief_elev_mean"    , "m"             ,
  "relief_elev_range"   , "m"             ,
  "relief_slope_mean"   , "degrees"       ,
  "relief_slope_max"    , "degrees"       ,
  "relief_aspect_south" , "index -1 to 1" ,
  "relief_aspect_east"  , "index -1 to 1"
)

relief_summary <- covariates |>
  inner_join(relief_units, by = "variable") |>
  group_by(variable, unit) |>
  summarise(
    n = n(),
    min = min(value),
    p05 = quantile(value, 0.05),
    p25 = quantile(value, 0.25),
    median = median(value),
    mean = mean(value),
    p75 = quantile(value, 0.75),
    p95 = quantile(value, 0.95),
    max = max(value),
    .groups = "drop"
  )

print(relief_summary, width = Inf)
write_csv(relief_summary, relief_summary_path)

# Soil source by parcel case ---------------------------------------------------------

# Counts soil rows (parcel x soil variable), 20 per parcel
soil_source_by_case <- covariates |>
  filter(variable %in% c(soil_pairs$mean_var, soil_pairs$centroid_var)) |>
  inner_join(parcels, by = "parcel_id") |>
  mutate(
    source = factor(source, levels = c("observed", "h3_6", "h3_5", "oblast"))
  ) |>
  count(case, source, .drop = FALSE) |>
  pivot_wider(names_from = source, values_from = n) |>
  mutate(total = observed + h3_6 + h3_5 + oblast)

print(soil_source_by_case)
write_csv(soil_source_by_case, soil_source_by_case_path)

cli_inform(
  "Descriptives written to {.path {tables_dir}} and {.path {soil_centroid_vs_polygon_png_path}}."
)
