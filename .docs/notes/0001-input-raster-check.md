# Input raster check and environment (plan 0001, T01)

- **Date:** 2026-11-10
- **Author:** Eduard Bukin (T01 writer agent, Claude)
- **Summary:** packages installed and locked; GeoParquet via geoarrow + arrow; H3 via h3o; SSL with `ssl_options = 2`; 28 soil layers share one grid (Homolosine, 250 m); crop and 2025 grids recorded.

## Instruction (verbatim)

> Write `.docs/notes/0001-input-raster-check.md` (template `.docs/_templates/note.md`) with all findings, including the chosen GeoParquet pair and the SSL method.

(Plan 0001, task T01, step 6.)

## Note

### Environment

- R 4.6.1, renv, `snapshot.type = "all"` (in `renv/settings.json`).
- Installed into the project library: `tidyverse` 2.0.0, `sf` 1.1-3, `terra` 1.9-50, `exactextractr` 0.10.1, `arrow` 26.0.1, `geoarrow` 0.4.4, `h3o` 0.3.0, `curl` 8.1.0, `cli` 3.6.6, `lwgeom` 0.2-17, `osmextract` 0.6.0, `knitr` 1.52, `rmarkdown` 2.32, plus dependencies (135 packages in `renv.lock`). No `h3jsr`, no V8.
- sf links GEOS 3.14.1, GDAL 3.12.1, PROJ 9.7.1. `renv::status()`: "No issues found".
- `arrow` warns on load that it was built under R 4.6.2. This is harmless.
- `library(terra)` masks `arrow::buffer`. Neither is used by name in the plan.

### GeoParquet read/write pair (binding for all scripts)

GDAL's `Parquet` driver is **not** available in this sf build (`"Parquet" %in% st_drivers()$name` is `FALSE`). Use geoarrow with arrow. `library(geoarrow)` must be loaded (in `00-setup.R`).

```r
arrow::write_parquet(x, path)                                     # write an sf object
x <- arrow::read_parquet(path, as_data_frame = FALSE) |> st_as_sf()  # read it back as sf
```

- Round trip tested with polygons, points and lines, in EPSG:4326 and EPSG:3035: attributes, coordinates and CRS come back identical.
- `as_data_frame = FALSE` is required. A plain `read_parquet(path) |> st_as_sf()` returns an object of class `sf` whose geometry column is still a `geoarrow_vctr`, and printing it fails.
- A column that mixes `LINESTRING` and `MULTILINESTRING` comes back as `MULTILINESTRING` everywhere. Harmless for distances.
- The geometry type and CRS are stored as geoarrow extension metadata on the column. The file has no GeoParquet `geo` key, so other tools may read the geometry as WKB/struct without CRS.
- Windows gotcha: the read memory-maps the file. Overwriting or deleting a file that was read earlier in the same session can fail with `Windows error 1224`. Fix: `gc()` before overwriting, or read with `mmap = FALSE`. This only matters while developing (for example, T04 regenerating the reference files).
- Plain (non-spatial) tables: `arrow::write_parquet()` / `arrow::read_parquet()`.

### H3 route (h3o works)

```r
h3_6 <- h3o::h3_from_points(st_geometry(points_wgs84), 6) |> as.character()   # res-6 cell IDs
h3_5 <- h3o::h3_from_points(st_geometry(points_wgs84), 5) |> as.character()   # res-5 cell IDs
hex  <- h3o::h3_from_strings(h3_6) |> st_as_sfc()                             # hexagon polygons, EPSG:4326
```

- `h3_from_points()` needs an `sfc_POINT` (use `st_geometry()`), not an `sf` data frame, in EPSG:4326.
- `h3o::sfc()` does not exist in h3o 0.3.0. Use `st_as_sfc()` on the `H3` vector.
- Test with 3 points in Poltava oblast (Poltava, Kremenchuk, Lubny): res-6 IDs `861e69537ffffff`, `861e6bd87ffffff`, `861e68c37ffffff`; res-5 `851e6953fffffff`, `851e6bdbfffffff`, `851e68c3fffffff`. Each hexagon contains its point. Areas: about 34 km² (res 6) and 240 km² (res 5).
- `h3r` was not needed.

### SSL / downloads

- `curl::curl_fetch_memory("https://data.humdata.org/api/3/action/package_show?id=cod-ab-ukr", handle = curl::new_handle(ssl_options = 2))` returned HTTP 200. **Method: `curl::new_handle(ssl_options = 2)`** (no revocation check). The `CURL_SSL_BACKEND = "openssl"` fallback was not needed.
- The same request without `ssl_options` also returned 200 in this session (curl 8.1.0, `(OpenSSL/3.5.8) Schannel`). Base R `url()` / `download.file()` with libcurl fails on HDX and AWS with "SSL connect error". So always use the curl package, with the handle above.
- Copernicus GLO-30 tile `Copernicus_DSM_COG_10_N49_00_E034_00_DEM` on `https://copernicus-dem-30m.s3.amazonaws.com`: HEAD returns 200, with and without `ssl_options = 2`.

### COD-AB (for T03)

- HDX resources (modified 2026-01-26):

  | Resource | Size |
  |---|---|
  | `ukr_admin_boundaries.gdb.zip` | 41.4 MB |
  | `ukr_admin_boundaries.shp.zip` | 81.5 MB |
  | `ukr_admin_boundaries.geojson.zip` | 84.0 MB |
  | `ukr_admin_boundaries.xlsx` | 6.3 MB (attributes only) |

  Download URL pattern: `https://data.humdata.org/dataset/d23f529f-31e4-4021-a65b-13987e5cfb42/resource/<id>/download/<name>`. The shp zip is `resource/2b38131d-5dd6-4b0f-b4c6-4aecc67f179d`, the geojson zip is `resource/681beb86-391b-4a08-8140-ca52e80fcdce`.
- Layers (from the xlsx): `ukr_admin0` … `ukr_admin4`, `ukr_admincapitals`, `ukr_adminlines`, `ukr_adminpoints`. ADM1 has **27** rows.
- ADM1 fields (lowercase): `adm1_name` (English), `adm1_name1` (Ukrainian), `adm1_pcode`, plus `adm0_*`, `valid_on`, `valid_to`, `area_sqkm`, `version`, `lang`, `lang1`, `center_lat`, `center_lon`. Mapping: `adm1_pcode` → `oblast_pcode`, `adm1_name1` → `oblast_ua`, `adm1_name` → `oblast_en`.
- **Poltava's English name in COD-AB is `"Poltavska"`** (P-code `UA53`, Ukrainian `Полтавська`), not `"Poltava"`. All English names use the adjectival form (`Kharkivska`, `Sumska`, ...). With `study_oblast_en <- "Poltava"` the lookup `oblast_en == study_oblast_en` matches nothing. T02/T03 must use `"Poltavska"`, or the orchestrator must decide otherwise.
- The shapefile and geojson variants were not opened in T01. Shapefile field names are cut at 10 characters, but all ADM1 names above are 10 characters or fewer.

### Soil rasters (28 files used in T07)

- Folder: `C:/Users/wb532966/OneDrive - WBG/DEC/data-EB/ukrSoilgridsData/data-raw/ukr`. All 28 files exist: `{bdod,cec,cfvo,clay,nitrogen,ocd,phh2o,sand,silt}_{0-5cm,5-15cm,15-30cm}_mean.tif` and `ocs_0-30cm_mean.tif`. The folder also has 30–60, 60–100 and 100–200 cm layers, which are not used.
- **One grid: `compareGeom()` is TRUE for all 28.**
- CRS: **Interrupted Goode Homolosine** on WGS 84 (WKT name `unknown`, no EPSG code). `st_transform(x, crs(r))` to it works.
- Resolution 250 × 250 m; 3467 rows × 5661 columns; extent x 2719250–4134500, y 4926750–5793500.
- Float32; NoData = `-3.4e+38` (declared, so terra reads it as NA).
- Values are in **SoilGrids mapped units** (integers stored as float). Units from `ukrSoilgridsData/README.md`:

  | Property | Mapped unit | Divide by | Conventional unit |
  |---|---|---|---|
  | bdod | cg/cm³ | 100 | kg/dm³ |
  | cec | mmol(c)/kg | 10 | cmol(c)/kg |
  | cfvo | cm³/dm³ (vol‰) | 10 | vol % |
  | clay | g/kg | 10 | % |
  | nitrogen | cg/kg | 100 | g/kg |
  | ocd | hg/m³ | 10 | kg/m³ |
  | ocs | t/ha | 10 | kg/m² |
  | phh2o | pH × 10 | 10 | pH |
  | sand | g/kg | 10 | % |
  | silt | g/kg | 10 | % |

- Sanity check at rural points in Poltava oblast: bdod 111–135, clay 230–392, phh2o 62–71, ocs 56–70. The centres of Poltava, Kremenchuk and Lubny are NA in every layer (soil NoData over towns, as expected).

### Crop rasters (8 files)

All are EPSG:32636 (UTM 36N), 10 m, Byte.

| File | Rows × cols | xmin | xmax | ymin | ymax | Declared NoData |
|---|---|---|---|---|---|---|
| `GEE_15102019.tif` | 90772 × 134691 | -312941.832 | 1033968.168 | 4905043.346 | 5812763.346 | 0 |
| `ukr_2020.tif` | 88823 × 132874 | -303027.846 | 1025712.154 | 4915095.861 | 5803325.861 | none |
| `Ukr_October2021.tif` | 88823 × 132874 | -303027.846 | 1025712.154 | 4915095.861 | 5803325.861 | none |
| `Ukraine_August2022_corr.tif` | 88823 × 132874 | -303027.846 | 1025712.154 | 4915095.861 | 5803325.861 | none |
| `Ukraine_2023_01_September.tif` | 88823 × 132874 | -303027.846 | 1025712.154 | 4915095.861 | 5803325.861 | none |
| `Ukraine_september_2024.tif` | 88823 × 132874 | -303027.846 | 1025712.154 | 4915095.861 | 5803325.861 | none |
| `SummerMap_Ukraine_2025_WB.tif` | 88823 × 132874 | -303030.228 | 1025709.772 | 4915095.668 | 5803325.668 | none |
| `Winter2025_Rape_Cereal.tif` | 88823 × 132874 | -303028.259 | 1025711.741 | 4915094.689 | 5803324.689 | none |

- 2020–2024 share one grid. 2019 has a larger extent. The 2025 maps have the same dimensions as 2020–2024, but their origins are shifted by about 2 m.
- **2025 winter vs summer origin:** `xmin(winter) - xmin(summer)` = **+1.969 m**; `ymax(winter) - ymax(summer)` = **−0.980 m**. Same dimensions; `compareGeom()` is FALSE only because of this shift. The shift is below T10's 5 m guard, so `ext(winter) <- ext(summer)` is a sub-pixel (< 0.2 pixel) alignment.
- The crop folder also has a `2025/` subfolder (source zips, reports, confusion matrices, damage shapefiles) and `.qml` styles. None is used.
