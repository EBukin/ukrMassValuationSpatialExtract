# 02-diagnostics.R
# In:  data/interim/oblasts.gpkg, data/clean/reference/*.parquet, clay_0-5cm_mean.tif (soil NoData area)
# Out: output/figures/parcels-map.png, output/figures/parcels-zoom.png
# Purpose: map the reference inputs and print parcel counts and areas by case and oblast.

source("00-setup.R")

# Inputs, in metres ------------------------------------------------------------

oblasts <- st_read(oblasts_path, quiet = TRUE) |>
  st_transform(crs_work) |>
  st_set_agr("constant") # attributes hold for every part of a shape
poltava <- oblasts |> filter(oblast_en == study_oblast_en)
neighbours <- oblasts |> filter(lengths(st_touches(oblasts, poltava)) > 0)

parcels <- arrow::read_parquet(parcels_path, as_data_frame = FALSE) |>
  st_as_sf() |>
  st_transform(crs_work) |>
  st_set_agr("constant")
elevators <- arrow::read_parquet(elevators_path, as_data_frame = FALSE) |>
  st_as_sf() |>
  st_transform(crs_work)
roads <- arrow::read_parquet(roads_path, as_data_frame = FALSE) |>
  st_as_sf() |>
  st_transform(crs_work)

# Map window: Poltava plus 20 km
map_box <- st_bbox(st_buffer(poltava, 20000))
map_window <- st_as_sfc(map_box)

# Soil NoData area -------------------------------------------------------------

# The raster stays in its own CRS: NoData cells become polygons, and only those vectors are transformed
clay <- rast(file.path(soil_dir, "clay_0-5cm_mean.tif"))
clay_crop <- crop(clay, st_transform(map_window, crs(clay)))
soil_na <- ifel(is.na(clay_crop), 1, NA) |> # 1 on soil NoData, NA elsewhere
  as.polygons() |>
  st_as_sf() |>
  st_transform(crs_work) |>
  st_make_valid()

# Counts and areas by case and oblast ------------------------------------------

parcel_table <- parcels |>
  st_drop_geometry() |>
  group_by(case, oblast) |>
  summarise(
    n_parcels = n(),
    area_ha_total = round(sum(area_ha), 1),
    area_ha_mean = round(mean(area_ha), 2),
    area_ha_min = round(min(area_ha), 2),
    area_ha_max = round(max(area_ha), 2),
    .groups = "drop"
  ) |>
  arrange(case, desc(n_parcels))

print(parcel_table, n = Inf)

# Colours ----------------------------------------------------------------------

case_colours <- c(interior = "#2a78d6", border = "#eb6834", nodata = "#1baf7a")
nodata_fill <- "#d3d1c8"
ink <- "#0b0b0b"
ink_secondary <- "#52514e"
ink_muted <- "#898781"

# Overview map -----------------------------------------------------------------

# At this scale a 3 ha parcel is about 2 pixels wide, so parcels are drawn as centroid points
parcel_points <- st_centroid(parcels)
neighbour_labels <- st_intersection(neighbours, map_window) |>
  st_set_agr("constant") |>
  st_point_on_surface()

parcels_map <- ggplot() +
  geom_sf(
    data = neighbours,
    fill = "#f4f3ef",
    colour = ink_muted,
    linewidth = 0.3
  ) +
  geom_sf(
    data = poltava,
    fill = "#fcfcfb",
    colour = ink_secondary,
    linewidth = 0.6
  ) +
  geom_sf(
    data = soil_na,
    aes(fill = "Soil NoData (towns, water)"),
    colour = NA
  ) +
  geom_sf(data = roads, aes(linewidth = type), colour = ink_secondary) +
  geom_sf(data = parcel_points, aes(colour = case), size = 1.1) +
  geom_sf(
    data = elevators,
    aes(shape = "Elevator"),
    fill = ink,
    colour = "white",
    size = 2.6,
    stroke = 0.4
  ) +
  geom_sf_text(
    data = neighbour_labels,
    aes(label = oblast_en),
    colour = ink_muted,
    size = 3.2,
    fontface = "italic"
  ) +
  scale_colour_manual(values = case_colours, name = "Parcel case") +
  scale_fill_manual(values = nodata_fill, name = NULL) +
  scale_linewidth_manual(values = c(main = 0.8, local = 0.3), name = "Road") +
  scale_shape_manual(values = 24, name = NULL) +
  guides(colour = guide_legend(override.aes = list(size = 3), order = 1)) +
  coord_sf(
    xlim = map_box[c("xmin", "xmax")],
    ylim = map_box[c("ymin", "ymax")],
    expand = FALSE
  ) +
  labs(
    title = str_c("Reference inputs in ", study_oblast_en, " oblast"),
    subtitle = str_c(
      nrow(parcels),
      " simulated parcels (centroids), ",
      nrow(elevators),
      " elevators, ",
      nrow(roads),
      " roads"
    ),
    caption = "Grey shading: SoilGrids clay 0-5 cm NoData. Outlines: oblasts (COD-AB). EPSG:3035."
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.background = element_rect(fill = "#fcfcfb", colour = NA),
    panel.grid = element_line(colour = "#e1e0d9", linewidth = 0.2),
    axis.text = element_text(colour = ink_muted, size = 8),
    axis.title = element_blank(),
    plot.title = element_text(colour = ink, face = "bold"),
    plot.subtitle = element_text(colour = ink_secondary),
    plot.caption = element_text(colour = ink_muted, hjust = 0),
    legend.position = "right"
  )

ggsave(
  parcels_map_path,
  parcels_map,
  width = 10,
  height = 7.5,
  dpi = 300,
  bg = "white"
)
cli_inform("Wrote {.path {parcels_map_path}}.")

# Zoom: one parcel of each case ------------------------------------------------

# Layers shared by the three panels
zoom_layers <- list(
  geom_sf(data = soil_na, fill = nodata_fill, colour = NA),
  geom_sf(
    data = st_boundary(oblasts),
    colour = ink,
    linewidth = 0.6,
    linetype = "dashed"
  ),
  geom_sf(
    data = roads,
    aes(linewidth = type),
    colour = ink_secondary,
    show.legend = FALSE
  ),
  scale_linewidth_manual(values = c(main = 1.2, local = 0.6)),
  theme_minimal(base_size = 11),
  theme(
    panel.background = element_rect(fill = "#fcfcfb", colour = NA),
    panel.border = element_rect(fill = NA, colour = "#c3c2b7", linewidth = 0.4),
    panel.grid = element_blank(),
    axis.text = element_blank(),
    axis.title = element_blank(),
    plot.title = element_text(colour = ink, face = "bold", size = 11),
    plot.subtitle = element_text(colour = ink_secondary, size = 9)
  )
)

# First parcel of each case, in a 2 km x 2 km window around its centroid
zoom_interior <- parcels |>
  filter(case == "interior") |>
  arrange(parcel_id) |>
  slice_head(n = 1)
zoom_border <- parcels |>
  filter(case == "border") |>
  arrange(parcel_id) |>
  slice_head(n = 1)
zoom_nodata <- parcels |>
  filter(case == "nodata") |>
  arrange(parcel_id) |>
  slice_head(n = 1)

box_interior <- st_bbox(st_buffer(
  st_centroid(st_geometry(zoom_interior)),
  1000
))
box_border <- st_bbox(st_buffer(st_centroid(st_geometry(zoom_border)), 1000))
box_nodata <- st_bbox(st_buffer(st_centroid(st_geometry(zoom_nodata)), 1000))

plot_interior <- ggplot() +
  zoom_layers +
  geom_sf(
    data = zoom_interior,
    fill = case_colours["interior"],
    colour = ink,
    linewidth = 0.4,
    alpha = 0.85
  ) +
  coord_sf(
    xlim = box_interior[c("xmin", "xmax")],
    ylim = box_interior[c("ymin", "ymax")],
    expand = FALSE
  ) +
  labs(
    title = "interior",
    subtitle = str_c(
      zoom_interior$parcel_id,
      ", ",
      round(zoom_interior$area_ha, 1),
      " ha, ",
      zoom_interior$oblast
    )
  )

plot_border <- ggplot() +
  zoom_layers +
  geom_sf(
    data = zoom_border,
    fill = case_colours["border"],
    colour = ink,
    linewidth = 0.4,
    alpha = 0.85
  ) +
  coord_sf(
    xlim = box_border[c("xmin", "xmax")],
    ylim = box_border[c("ymin", "ymax")],
    expand = FALSE
  ) +
  labs(
    title = "border",
    subtitle = str_c(
      zoom_border$parcel_id,
      ", ",
      round(zoom_border$area_ha, 1),
      " ha, mostly in ",
      zoom_border$oblast
    )
  )

plot_nodata <- ggplot() +
  zoom_layers +
  geom_sf(
    data = zoom_nodata,
    fill = case_colours["nodata"],
    colour = ink,
    linewidth = 0.4,
    alpha = 0.85
  ) +
  coord_sf(
    xlim = box_nodata[c("xmin", "xmax")],
    ylim = box_nodata[c("ymin", "ymax")],
    expand = FALSE
  ) +
  labs(
    title = "nodata",
    subtitle = str_c(
      zoom_nodata$parcel_id,
      ", ",
      round(zoom_nodata$area_ha, 1),
      " ha, ",
      zoom_nodata$oblast
    )
  )

# Three panels side by side, with grid viewports
png(
  parcels_zoom_path,
  width = 13,
  height = 5.2,
  units = "in",
  res = 300,
  bg = "white"
)
grid::grid.newpage()
grid::pushViewport(grid::viewport(
  layout = grid::grid.layout(
    nrow = 2,
    ncol = 3,
    heights = grid::unit(c(1, 0.08), "null")
  )
))
print(
  plot_interior,
  vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1)
)
print(plot_border, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
print(plot_nodata, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 3))
grid::grid.text(
  "Each window is 2 km x 2 km around the parcel centroid (EPSG:3035). Grey: soil NoData (250 m cells). Dashed: oblast boundary. Lines: roads.",
  x = 0.01,
  hjust = 0,
  gp = grid::gpar(col = ink_muted, fontsize = 9),
  vp = grid::viewport(layout.pos.row = 2, layout.pos.col = 1:3)
)
invisible(dev.off())
cli_inform("Wrote {.path {parcels_zoom_path}}.")
