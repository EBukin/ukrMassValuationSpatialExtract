# 03-distance.R
# In:  data/clean/reference/parcels.parquet, elevators.parquet, roads.parquet (EPSG:4326)
# Out: data/interim/long_distance.parquet, output/tables/distance_sphere_vs_ellipsoid.csv
# Purpose: distance in metres from each parcel (centroid and edge) to the nearest elevator, main road and local road.

source("00-setup.R")

parcels <- arrow::read_parquet(parcels_path, as_data_frame = FALSE) |>
  st_as_sf()
elevators <- arrow::read_parquet(elevators_path, as_data_frame = FALSE) |>
  st_as_sf()
roads <- arrow::read_parquet(roads_path, as_data_frame = FALSE) |> st_as_sf()

roads_main <- roads |> filter(type == "main")
roads_local <- roads |> filter(type == "local")

# Centroids on the sphere (s2). "Edge" is the parcel polygon itself:
# its distance is 0 when a feature touches or crosses the parcel.
centroids <- st_centroid(st_geometry(parcels))
edges <- st_geometry(parcels)

# Distances on the sphere (s2) --------------------------------------------------

# Distance from each "from" geometry to its nearest feature in "to", in metres
nearest_dist <- function(from, to) {
  as.numeric(st_distance(
    from,
    to[st_nearest_feature(from, to), ],
    by_element = TRUE
  ))
}

distance_wide <- tibble(
  parcel_id = parcels$parcel_id,
  dist_elevator_centroid = nearest_dist(centroids, elevators),
  dist_elevator_edge = nearest_dist(edges, elevators),
  dist_road_main_centroid = nearest_dist(centroids, roads_main),
  dist_road_main_edge = nearest_dist(edges, roads_main),
  dist_road_local_centroid = nearest_dist(centroids, roads_local),
  dist_road_local_edge = nearest_dist(edges, roads_local)
)

distance_long <- distance_wide |>
  pivot_longer(-parcel_id, names_to = "variable", values_to = "value") |>
  mutate(value = as.numeric(value), source = "observed") |>
  select(parcel_id, variable, value, source)

# Checks ----------------------------------------------------------------------

if (nrow(distance_long) != 6 * nrow(parcels)) {
  cli_abort("Expected 6 rows per parcel.")
}
if (anyNA(distance_long$value)) {
  cli_abort("Some distances are NA.")
}
if (
  any(distance_wide$dist_elevator_edge > distance_wide$dist_elevator_centroid)
) {
  cli_abort("Elevator: edge distance above centroid distance.")
}
if (
  any(distance_wide$dist_road_main_edge > distance_wide$dist_road_main_centroid)
) {
  cli_abort("Main road: edge distance above centroid distance.")
}
if (
  any(
    distance_wide$dist_road_local_edge > distance_wide$dist_road_local_centroid
  )
) {
  cli_abort("Local road: edge distance above centroid distance.")
}

# Spot check: 3 parcels (one per case) against ALL features, minimum by brute force
spot <- c(
  which(parcels$case == "interior")[1],
  which(parcels$case == "border")[1],
  which(parcels$case == "nodata")[1]
)

spot_check <- tibble(
  parcel_id = parcels$parcel_id[spot],
  dist_elevator_centroid = apply(
    st_distance(centroids[spot], elevators),
    1,
    min
  ),
  dist_elevator_edge = apply(st_distance(edges[spot], elevators), 1, min),
  dist_road_main_centroid = apply(
    st_distance(centroids[spot], roads_main),
    1,
    min
  ),
  dist_road_main_edge = apply(st_distance(edges[spot], roads_main), 1, min),
  dist_road_local_centroid = apply(
    st_distance(centroids[spot], roads_local),
    1,
    min
  ),
  dist_road_local_edge = apply(st_distance(edges[spot], roads_local), 1, min)
)

spot_gap <- abs(
  as.matrix(spot_check[, -1]) - as.matrix(distance_wide[spot, -1])
)
if (max(spot_gap) > 0.001) {
  cli_abort(
    "Spot check failed: brute-force minimum differs by {round(max(spot_gap), 3)} m."
  )
}
cli_inform(
  "Spot check passed for parcels {spot_check$parcel_id} (max gap {signif(max(spot_gap), 3)} m)."
)

# Sphere vs ellipsoid -----------------------------------------------------------

# The same pairs (same nearest feature), measured on the WGS84 ellipsoid (lwgeom)
idx_elevator_centroid <- st_nearest_feature(centroids, elevators)
idx_elevator_edge <- st_nearest_feature(edges, elevators)
idx_road_main_centroid <- st_nearest_feature(centroids, roads_main)
idx_road_main_edge <- st_nearest_feature(edges, roads_main)
idx_road_local_centroid <- st_nearest_feature(centroids, roads_local)
idx_road_local_edge <- st_nearest_feature(edges, roads_local)

sf_use_s2(FALSE)

ellipsoid_wide <- tibble(
  parcel_id = parcels$parcel_id,
  dist_elevator_centroid = as.numeric(st_distance(
    centroids,
    elevators[idx_elevator_centroid, ],
    by_element = TRUE
  )),
  dist_elevator_edge = as.numeric(st_distance(
    edges,
    elevators[idx_elevator_edge, ],
    by_element = TRUE
  )),
  dist_road_main_centroid = as.numeric(st_distance(
    centroids,
    roads_main[idx_road_main_centroid, ],
    by_element = TRUE
  )),
  dist_road_main_edge = as.numeric(st_distance(
    edges,
    roads_main[idx_road_main_edge, ],
    by_element = TRUE
  )),
  dist_road_local_centroid = as.numeric(st_distance(
    centroids,
    roads_local[idx_road_local_centroid, ],
    by_element = TRUE
  )),
  dist_road_local_edge = as.numeric(st_distance(
    edges,
    roads_local[idx_road_local_edge, ],
    by_element = TRUE
  ))
)

sf_use_s2(TRUE)

ellipsoid_long <- ellipsoid_wide |>
  pivot_longer(-parcel_id, names_to = "variable", values_to = "value_ellipsoid")

# Relative gap only where the ellipsoidal distance is above 0 (edge distances can be 0)
distance_check <- distance_long |>
  left_join(ellipsoid_long, by = c("parcel_id", "variable")) |>
  mutate(
    gap_m = abs(value - value_ellipsoid),
    gap_pct = if_else(value_ellipsoid > 0, 100 * gap_m / value_ellipsoid, NA)
  ) |>
  summarise(
    mean_gap_m = mean(gap_m),
    max_gap_m = max(gap_m),
    mean_gap_pct = mean(gap_pct, na.rm = TRUE),
    .by = variable
  )

print(distance_check)
if (any(distance_check$mean_gap_pct >= 0.5)) {
  cli_abort("Mean relative sphere vs ellipsoid gap is 0.5 % or more.")
}

# Write -----------------------------------------------------------------------

gc()
arrow::write_parquet(distance_long, long_distance_path)
write_csv(distance_check, distance_check_path)

cli_inform(
  "Wrote {nrow(distance_long)} rows to {.path {long_distance_path}} and the check table to {.path {distance_check_path}}."
)
