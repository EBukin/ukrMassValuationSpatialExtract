# _language-switch.R
# In:  ../docs/en/*.html, ../docs/uk/*.html (just rendered)
# Out: the same files, with the navbar language link pointing at the same page in the other language
# Purpose: post-render step; the navbar is shared by all pages of a language, so its link goes to index.html.

pages <- c("index.html", "data.html", "pipeline.html", "reference.html", "distance.html",
           "soil.html", "relief.html", "crop.html", "output.html")

for (page in pages) {
  # English page: "Українська" link to ../uk/<page>
  file <- file.path("..", "docs", "en", page)
  if (file.exists(file)) {
    html <- readChar(file, file.size(file), useBytes = TRUE)
    html <- gsub('href="../uk/index.html"', paste0('href="../uk/', page, '"'), html, fixed = TRUE, useBytes = TRUE)
    writeBin(charToRaw(html), file)
  }
  # Ukrainian page: "English" link to ../en/<page>
  file <- file.path("..", "docs", "uk", page)
  if (file.exists(file)) {
    html <- readChar(file, file.size(file), useBytes = TRUE)
    html <- gsub('href="../en/index.html"', paste0('href="../en/', page, '"'), html, fixed = TRUE, useBytes = TRUE)
    writeBin(charToRaw(html), file)
  }
}
