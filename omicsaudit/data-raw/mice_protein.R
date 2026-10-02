# Audit on a real, public proteomics dataset: Mice Protein Expression
# (Higuera, Gardiner & Cios 2015, PLoS ONE; UCI ML Repository, CC BY 4.0).
# 77 proteins, 1080 samples from 72 mice (15 repeated measurements each).
# Outcome here: Genotype (Control vs Ts65Dn). Nothing is committed: the file is
# downloaded to data-raw/mice/ (gitignored). Run from the package root.
suppressMessages(library(omicsaudit))
dir.create("data-raw/mice", showWarnings = FALSE)
xls <- "data-raw/mice/Data_Cortex_Nuclear.xls"
if (!file.exists(xls)) {
  zip <- tempfile(fileext = ".zip")
  download.file("https://archive.ics.uci.edu/static/public/342/mice+protein+expression.zip", zip, mode = "wb")
  unzip(zip, files = "Data_Cortex_Nuclear.xls", exdir = "data-raw/mice")
}
raw <- as.data.frame(readxl::read_excel(xls))
# Row names "309_1" -> "309_r1" so subject-aware pipelines can group by mouse.
raw$MouseID <- sub("_([0-9]+)$", "_r\\1", raw$MouseID)
d <- read_omics(raw[c("MouseID", grep("_N$", names(raw), value = TRUE), "Genotype")],
                outcome = "Genotype", id = "MouseID", positive_label = "Ts65Dn", scale = "linear")
print(d)
mouse <- sub("_r[0-9]+$", "", rownames(d$X))
stopifnot(all(tapply(d$y, mouse, function(v) length(unique(v))) == 1))   # outcome is per mouse

random_cv  <- zoo_load("flawed_repeated_measures")$pipeline    # ignores mouse
grouped_cv <- zoo_load("reference_grouped_cv")$pipeline        # keeps each mouse in one fold
cat("\nHonest (mouse-grouped) AUC:", round(grouped_cv(d$X, d$y)$performance, 3), "\n")
cat("Naive (random-row) AUC:    ", round(random_cv(d$X, d$y)$performance, 3), "\n\n")

for (nm in c("random_cv", "grouped_cv")) {
  a <- audit_null(get(nm), d$X, d$y, groups = mouse, n_perm = 20, seed = 1)
  cat(nm, ": "); print(a)
}
