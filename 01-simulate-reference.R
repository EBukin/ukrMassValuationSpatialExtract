# 01-simulate-reference.R
# In:  data/interim/oblasts.gpkg, clay_0-5cm_mean.tif (soil NoData cells), crop_2024 (only to check towns and water)
# Out: data/clean/reference/parcels.parquet, elevators.parquet, roads.parquet (GeoParquet, EPSG:4326)
# Purpose: simulate the fixed reference parcels, elevators and roads in Poltava oblast.
# This script ran once to create the committed reference inputs. It is not part of the normal run.

source("00-setup.R")

if (file.exists(parcels_path)) cli_abort("Reference inputs already exist. They are fixed: do not regenerate.")

set.seed(20261110)

# Study oblast and its neighbours, in metres ----------------------------------

oblasts <- st_read(oblasts_path, quiet = TRUE) |> st_transform(crs_work)
poltava <- oblasts |> filter(oblast_en == study_oblast_en)
neighbours <- oblasts |> filter(lengths(st_touches(oblasts, poltava)) > 0)
poltava_inner <- st_buffer(poltava, -1000)   # Poltava shrunk by 1 km

cli_inform("{study_oblast_en} has {nrow(neighbours)} neighbouring oblasts.")

# Parcel centres --------------------------------------------------------------

# interior: random points more than 1 km from Poltava's boundary
interior <- st_sample(poltava, 900) |>
  st_as_sf() |>
  st_filter(poltava_inner) |>
  slice_head(n = 700) |>
  mutate(case = "interior")

# border: random points on the boundary Poltava shares with its neighbours
shared_boundary <- st_intersection(st_boundary(st_geometry(poltava)), st_union(neighbours)) |>
  st_line_merge()   # one line, so that st_sample() spreads the points along its whole length
border <- st_sample(shared_boundary, 150, type = "random", exact = TRUE) |>
  st_as_sf() |>
  st_cast("POINT") |>
  slice_head(n = 150) |>
  mutate(case = "border")

# nodata: random soil NoData cells (towns, rivers, reservoir) inside Poltava shrunk by 1 km
clay <- rast(file.path(soil_dir, "clay_0-5cm_mean.tif"))
clay_crop <- crop(clay, st_transform(poltava_inner, crs(clay)))
soil_na_cells <- ifel(is.na(clay_crop), 1, NA)   # 1 on soil NoData, NA elsewhere

nodata_cells <- spatSample(soil_na_cells, size = 5000, method = "random", na.rm = TRUE, as.points = TRUE) |>
  st_as_sf() |>
  st_transform(crs_work) |>
  st_filter(poltava_inner) |>
  slice_sample(n = 150)

# shift each nodata centre by at most 100 m in a random direction
shift_m <- runif(150, 0, 100)
shift_angle <- runif(150, 0, 2 * pi)
nodata_xy <- st_coordinates(nodata_cells)
nodata <- tibble(
  case = "nodata",
  x = nodata_xy[, "X"] + shift_m * cos(shift_angle),
  y = nodata_xy[, "Y"] + shift_m * sin(shift_angle)
) |>
  st_as_sf(coords = c("x", "y"), crs = crs_work)

centres <- bind_rows(
  interior |> st_set_geometry("geometry"),
  border |> st_set_geometry("geometry"),
  nodata
)
centres_xy <- st_coordinates(centres)

# Parcel shapes: unit square -> scale -> shear -> rotate -> translate ---------

shapes <- tibble(
  case = centres$case,
  x = centres_xy[, "X"],
  y = centres_xy[, "Y"]
) |>
  mutate(
    area_target = pmin(pmax(rlnorm(n(), log(3), 0.25), 1), 10),   # hectares
    ratio = runif(n(), 1.5, 6),
    angle = runif(n(), 0, pi),
    shear = if_else(runif(n()) < 0.5, 0, runif(n(), 0.2, 0.5))
  )

shapes$geometry <- pmap(
  list(shapes$x, shapes$y, shapes$area_target, shapes$ratio, shapes$angle, shapes$shear),
  \(x, y, area_target, ratio, angle, shear) {
    square <- matrix(c(-0.5, -0.5, 0.5, -0.5, 0.5, 0.5, -0.5, 0.5, -0.5, -0.5), ncol = 2, byrow = TRUE)
    width <- sqrt(area_target * 10000 / ratio)
    scaled <- square %*% diag(c(width * ratio, width))
    sheared <- scaled %*% matrix(c(1, 0, shear, 1), ncol = 2)   # y + shear * x keeps the area
    rotated <- sheared %*% matrix(c(cos(angle), -sin(angle), sin(angle), cos(angle)), ncol = 2)
    st_polygon(list(sweep(rotated, 2, c(x, y), "+")))
  }
) |>
  st_sfc(crs = crs_work)

parcels <- shapes |>
  st_as_sf() |>
  mutate(
    parcel_id = sprintf("P%05d", row_number()),
    area_ha = as.numeric(st_area(geometry)) / 10000
  ) |>
  select(parcel_id, case, area_ha)

# Oblast with the largest overlap
parcel_oblast <- st_intersection(parcels, select(oblasts, oblast_en)) |>
  mutate(overlap = as.numeric(st_area(geometry))) |>
  st_drop_geometry() |>
  group_by(parcel_id) |>
  slice_max(overlap, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(parcel_id, oblast = oblast_en)

parcels <- parcels |> left_join(parcel_oblast, by = "parcel_id")

# H3 cells of the WGS84 centroid
parcels_4326 <- st_transform(parcels, 4326)
centroids_4326 <- st_centroid(st_geometry(parcels_4326))
parcels_4326 <- parcels_4326 |>
  mutate(
    h3_6 = h3o::h3_from_points(centroids_4326, 6) |> as.character(),
    h3_5 = h3o::h3_from_points(centroids_4326, 5) |> as.character()
  ) |>
  select(parcel_id, case, area_ha, oblast, h3_6, h3_5)

# Elevators -------------------------------------------------------------------

elevators <- st_sample(poltava, 30) |>
  st_as_sf() |>
  st_set_geometry("geometry") |>
  mutate(elevator_id = sprintf("E%03d", row_number())) |>
  select(elevator_id)

# Roads -----------------------------------------------------------------------

# main: 40 candidate straight lines between random points on Poltava's boundary.
# After clipping to Poltava, the 4 longest are kept, so every main road crosses Poltava.
main_ends <- st_sample(st_line_merge(st_boundary(st_geometry(poltava))), 80, type = "random", exact = TRUE) |>
  st_cast("POINT") |>
  st_coordinates()
main_roads <- tibble(
  road_id = rep(sprintf("C%02d", 1:40), each = 2),
  type = "main",
  x = main_ends[1:80, "X"],
  y = main_ends[1:80, "Y"]
) |>
  st_as_sf(coords = c("x", "y"), crs = crs_work) |>
  group_by(road_id, type) |>
  summarise(do_union = FALSE, .groups = "drop") |>
  st_cast("LINESTRING") |>
  st_intersection(st_geometry(poltava)) |>   # a road that leaves Poltava and comes back becomes a MULTILINESTRING
  st_collection_extract("LINESTRING") |>     # drop stray points from the clipping
  mutate(length_m = as.numeric(st_length(geometry))) |>
  slice_max(length_m, n = 4, with_ties = FALSE) |>
  mutate(road_id = sprintf("M%02d", row_number()))

# local: 50 lines of 5-20 km from random points inside Poltava, in a random direction
local_starts <- st_coordinates(st_sample(poltava, 50))
local_length <- runif(50, 5000, 20000)
local_angle <- runif(50, 0, 2 * pi)
local_roads <- bind_rows(
  tibble(road_id = sprintf("L%02d", 1:50), x = local_starts[, "X"], y = local_starts[, "Y"]),
  tibble(
    road_id = sprintf("L%02d", 1:50),
    x = local_starts[, "X"] + local_length * cos(local_angle),
    y = local_starts[, "Y"] + local_length * sin(local_angle)
  )
) |>
  arrange(road_id) |>
  mutate(type = "local") |>
  st_as_sf(coords = c("x", "y"), crs = crs_work) |>
  group_by(road_id, type) |>
  summarise(do_union = FALSE, .groups = "drop") |>
  st_cast("LINESTRING") |>
  st_intersection(st_geometry(poltava))

# densify to 950 m here, so that segments stay under 1 km on the sphere too
roads <- bind_rows(main_roads, local_roads) |>
  st_segmentize(dfMaxLength = 950) |>
  select(road_id, type)

# Summaries -------------------------------------------------------------------

print(count(st_drop_geometry(parcels_4326), case))
print(summary(parcels_4326$area_ha))
print(count(st_drop_geometry(roads), type))

# Checks ----------------------------------------------------------------------

share_2_4_ha <- mean(parcels_4326$area_ha >= 2 & parcels_4326$area_ha <= 4)
cli_inform("{round(100 * share_2_4_ha, 1)}% of parcels are 2-4 ha (75% or more expected).")
if (share_2_4_ha < 0.75) cli_abort("Too few parcels of 2-4 ha.")
if (any(parcels_4326$area_ha < 1 | parcels_4326$area_ha > 10)) cli_abort("Parcel areas must be 1-10 ha.")
if (n_distinct(parcels_4326$parcel_id) != n_parcels) cli_abort("Parcel IDs are not unique.")
if (!all(st_is_valid(parcels_4326))) cli_abort("Some parcel geometries are invalid.")

border_parcels <- parcels |> filter(case == "border")
border_in_poltava <- lengths(st_intersects(border_parcels, poltava)) > 0
border_in_neighbour <- lengths(st_intersects(border_parcels, neighbours)) > 0
cli_inform("{sum(border_in_poltava & border_in_neighbour)} of {nrow(border_parcels)} border parcels cross into a neighbouring oblast.")
if (!all(border_in_poltava & border_in_neighbour)) cli_abort("Every border parcel must touch Poltava and a neighbour.")

# Share of each nodata parcel on soil NoData
nodata_parcels <- parcels |> filter(case == "nodata")
soil_na_share <- exact_extract(is.na(clay_crop), st_transform(nodata_parcels, crs(clay)), "mean", progress = FALSE)
share_mostly_na <- mean(soil_na_share > 0.5)
cli_inform("{round(100 * share_mostly_na, 1)}% of nodata parcels are more than half on soil NoData (70% or more expected).")
if (share_mostly_na < 0.7) cli_abort("Too few nodata parcels on soil NoData.")

# Towns and water around nodata parcels, from the 2024 crop map
crop24 <- rast(crop_2024)
nodata_crop <- st_transform(nodata_parcels, crs(crop24))
crop_majority <- exact_extract(crop24, nodata_crop, "mode", progress = FALSE)
crop_near <- exact_extract(crop24, st_buffer(nodata_crop, 500), "frac", progress = FALSE)
n_town <- sum(crop_majority == 1, na.rm = TRUE)
n_water <- sum(crop_near$frac_13 + crop_near$frac_14 > 0, na.rm = TRUE)
cli_inform("{n_town} nodata parcels are mostly built (code 1) in 2024; {n_water} have water within 500 m (30 or more each expected).")
if (n_town < 30) cli_abort("Fewer than 30 nodata parcels near a town.")
if (n_water < 30) cli_abort("Fewer than 30 nodata parcels near water.")

if (!all(st_within(elevators, poltava, sparse = FALSE))) cli_abort("Some elevators lie outside Poltava.")
if (!all(st_covered_by(roads, st_buffer(poltava, 1), sparse = FALSE))) cli_abort("Some roads lie outside Poltava.")
if (!all(st_geometry_type(roads) %in% c("LINESTRING", "MULTILINESTRING"))) cli_abort("Some roads are not lines.")
if (any(main_roads$length_m < 50000)) cli_abort("Some main roads are shorter than 50 km.")

# Write in EPSG:4326 ----------------------------------------------------------

arrow::write_parquet(parcels_4326, parcels_path)
arrow::write_parquet(st_transform(elevators, 4326), elevators_path)
arrow::write_parquet(st_transform(roads, 4326), roads_path)
cli_inform("Wrote {.path {parcels_path}}, {.path {elevators_path}} and {.path {roads_path}}.")
