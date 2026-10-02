# Helpers for pulling a public proteomics dataset from PRIDE into data-raw/.
# No data is committed; downloaded files go to data-raw/pride/<accession>/.
# Usage:
#   source("data-raw/pride_download.R")
#   pride_files("PXD017710")                       # list the files of a project
#   pride_download("PXD017710", "sdrf-tmt.tsv")    # fetch one file
# A project is only usable for omicsaudit if it ships a protein quantification
# table AND per-sample outcome labels (e.g. an SDRF or supplementary table).
# Raw instrument files are not usable here. Choosing a suitable project is left
# to the analyst; none is selected yet.

pride_files <- function(accession, page_size = 500) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
  u <- sprintf("https://www.ebi.ac.uk/pride/ws/archive/v2/projects/%s/files?pageSize=%d", accession, page_size)
  d <- jsonlite::fromJSON(u)
  data.frame(file = d$fileName, category = d$fileCategory$value,
             size_mb = round(d$fileSizeBytes / 1e6, 1))
}

pride_download <- function(accession, file, dest = file.path("data-raw", "pride", accession)) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  u <- sprintf("https://www.ebi.ac.uk/pride/ws/archive/v2/projects/%s/files?pageSize=500", accession)
  d <- jsonlite::fromJSON(u)
  i <- match(file, d$fileName)
  if (is.na(i)) stop("file not found in project: ", file)
  link <- d$publicFileLocations[[i]]
  link <- sub("^ftp://", "https://", link$value[grepl("^(https|ftp)", link$value)][1])
  out <- file.path(dest, file)
  utils::download.file(link, out, mode = "wb")
  out
}
