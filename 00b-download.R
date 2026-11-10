# 00b-download.R
# In:  internet only
#      - OCHA COD-AB Ukraine admin boundaries, shapefile zip (81.5 MB), licence CC BY-IGO
#        https://data.humdata.org/dataset/cod-ab-ukr
#        -> data/raw/cod-ab/ukr_admin_boundaries.shp.zip (ADM1 files unzipped next to it)
#      - Copernicus DEM GLO-30 (or GLO-90), tiles over Poltava oblast plus 10 km (about 12 tiles, 20-40 MB each for GLO-30)
#        licence: Copernicus DEM licence (free use, attribution "produced using Copernicus WorldDEM-30 (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH 2014-2018")
#        https://copernicus-dem-30m.s3.amazonaws.com (GLO-30), https://copernicus-dem-90m.s3.amazonaws.com (GLO-90)
#        -> data/raw/dem/GLO-30/<tile id>.tif
# Out: data/interim/oblasts.gpkg (all oblasts), data/interim/dem.vrt (virtual mosaic of the DEM tiles)
# Purpose: download the public inputs once; existing files are skipped.

source("00-setup.R")

dir.create(codab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(dem_dir, dem_product), recursive = TRUE, showWarnings = FALSE)

h <- curl::new_handle(ssl_options = 2)  # this network cannot check certificate revocation

# COD-AB oblast boundaries (ADM1) ---------------------------------------------

codab_url <- "https://data.humdata.org/dataset/d23f529f-31e4-4021-a65b-13987e5cfb42/resource/2b38131d-5dd6-4b0f-b4c6-4aecc67f179d/download/ukr_admin_boundaries.shp.zip"
codab_zip <- file.path(codab_dir, "ukr_admin_boundaries.shp.zip")
codab_shp <- file.path(codab_dir, "ukr_admin1.shp")

if (!file.exists(codab_zip)) curl::curl_download(codab_url, codab_zip, handle = h)
if (!file.exists(codab_shp)) {
  unzip(
    codab_zip,
    files = c("ukr_admin1.shp", "ukr_admin1.shx", "ukr_admin1.dbf", "ukr_admin1.prj", "ukr_admin1.cpg"),
    exdir = codab_dir
  )
}

oblasts_raw <- st_read(codab_shp, quiet = TRUE)
cli_inform("COD-AB ADM1 fields: {.field {names(oblasts_raw)}}")

oblasts <- oblasts_raw |>
  select(oblast_pcode = adm1_pcode, oblast_ua = adm1_name1, oblast_en = adm1_name) |>
  st_transform(4326)

cli_inform("Renamed {.field adm1_pcode}, {.field adm1_name1}, {.field adm1_name} to {.field oblast_pcode}, {.field oblast_ua}, {.field oblast_en}.")
cli_inform("{nrow(oblasts)} oblasts read (27 expected).")

study_oblast <- oblasts |> filter(oblast_en == study_oblast_en)
if (nrow(study_oblast) != 1) cli_abort("Study oblast {study_oblast_en} not found in COD-AB.")

st_write(oblasts, oblasts_path, delete_dsn = TRUE, quiet = TRUE)
cli_inform("Wrote {.path {oblasts_path}}.")

# Copernicus DEM tiles --------------------------------------------------------

dem_products <- tribble(
  ~product, ~bucket,                                         ~code,
  "GLO-30", "https://copernicus-dem-30m.s3.amazonaws.com",  "10",
  "GLO-90", "https://copernicus-dem-90m.s3.amazonaws.com",  "30"
) |> filter(product == dem_product)

# 1 x 1 degree tile boxes over Ukraine, kept where they touch Poltava plus 10 km
study_buffer <- st_buffer(study_oblast, 10000)
tiles <- st_make_grid(cellsize = 1, offset = c(22, 44), n = c(19, 9), crs = 4326)
tiles <- tiles[lengths(st_intersects(tiles, study_buffer)) > 0]

# Lower-left corner of each tile, from its centre
tile_centres <- st_coordinates(st_centroid(tiles))
lon <- round(tile_centres[, "X"] - 0.5)
lat <- round(tile_centres[, "Y"] - 0.5)

dem_tiles <- tibble(
  id = str_c("Copernicus_DSM_COG_", dem_products$code, "_N", lat, "_00_E", sprintf("%03d", lon), "_00_DEM"),
  url = str_c(dem_products$bucket, "/", id, "/", id, ".tif"),
  dest = file.path(dem_dir, dem_product, str_c(id, ".tif"))
)
cli_inform("{nrow(dem_tiles)} {dem_product} tiles intersect {study_oblast_en} plus 10 km.")

# Download only the tiles not on disk yet (multi_download takes handle options, not a handle)
to_get <- dem_tiles |> filter(!file.exists(dest))
cli_inform("{nrow(to_get)} tiles to download.")
res <- curl::multi_download(to_get$url, to_get$dest, progress = FALSE, ssl_options = 2)

# A failed request (e.g. 404 for a sea tile) leaves an error page on disk: remove it
failed <- res |> filter(status_code != 200)
file.remove(failed$destfile[file.exists(failed$destfile)])
if (nrow(failed) > 0) cli_warn("{nrow(failed)} tile{?s} not downloaded: {.url {failed$url}}")

files_ok <- dem_tiles$dest[file.exists(dem_tiles$dest)]
cli_inform("{length(files_ok)} of {nrow(dem_tiles)} tiles on disk.")

# The mosaic uses the finest tile grid (1 arc-second). Tiles north of 50 N have coarser
# longitude spacing; GDAL repeats their pixels on that grid on the fly (nearest neighbour)
dem <- vrt(files_ok, filename = dem_vrt_path, options = c("-resolution", "highest"), overwrite = TRUE)
cli_inform("Wrote {.path {dem_vrt_path}}.")

# Optional: real OSM roads instead of the simulated ones ----------------------
# osm_lines <- osmextract::oe_get("Ukraine", layer = "lines", download_directory = "data/raw/osm")
# osm_main  <- osm_lines |> filter(highway %in% c("motorway", "trunk", "primary"))
# osm_local <- osm_lines |> filter(highway %in% c("secondary", "tertiary"))
