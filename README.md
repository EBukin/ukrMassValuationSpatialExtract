# ukrMassValuationSpatialExtract

## Objective

Set a baseline for how to compute spatial covariates for the mass valuation of agricultural land in Ukraine.

The project builds a reference dataset of spatial variables from a controlled set of inputs. Other implementations (different software, tools or teams) can compare their results against it.

## Data sources

1. **Oblast boundaries (real).** Oblast-level administrative maps of Ukraine. They limit the area where spatial data is extracted.
2. **Synthetic parcels (fictional).** Agricultural land parcels of different sizes, placed in different parts of Ukraine: on borders between oblasts, near cities, and elsewhere. These parcels are the gold standard for checking that extraction is done the same way every time.
3. **Synthetic roads and points (fictional).** Made-up road lines and point features. They are used to compute distances from parcels to these objects, taking the spherical shape of the Earth into account.
4. **Soil raster (real).** Real soil raster data.
5. **Crop cover raster (real).** Real crop cover raster data.

## Methods covered

- **Distance covariates.** Distances from parcels to roads and points, computed on the sphere (or ellipsoid) rather than on a flat projection.
- **Raster extraction.** Summary values from the intersection of parcel polygons with raster cells. The extraction accounts for the shape and alignment of raster cells, so partial cell coverage is handled without losing precision.

## Output

A single dataset with one row per synthetic parcel and all computed spatial covariates. It is the reference for comparing against the same calculations done by other means.
