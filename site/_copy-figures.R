# _copy-figures.R
# In:  ../output/figures/parcels-map.png, parcels-zoom.png, soil_centroid_vs_polygon.png
# Out: site/figures/ (copies, so that Quarto puts them in docs/figures/)
# Purpose: pre-render step; Quarto only publishes files inside the site folder.

dir.create("figures", showWarnings = FALSE)
file.copy("../output/figures/parcels-map.png", "figures/parcels-map.png", overwrite = TRUE)
file.copy("../output/figures/parcels-zoom.png", "figures/parcels-zoom.png", overwrite = TRUE)
file.copy("../output/figures/soil_centroid_vs_polygon.png", "figures/soil_centroid_vs_polygon.png", overwrite = TRUE)
