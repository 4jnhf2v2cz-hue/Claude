# Full audit and one-page report for the supplied proteomics file (values assumed
# log2). Run from the package root; writes data-raw/proteomics_audit.html.
suppressMessages(library(omicsaudit))
d <- read.csv("inst/extdata/targeted_proteomics.csv")
X <- 2^as.matrix(d[paste0("Prot", 1:10)]); rownames(X) <- d$PatientID
y <- d$Progress
pipe <- zoo_load("reference_nested_cv")$pipeline

aud <- audit_standard(pipe, X, y, batch = cut(d$Age, c(0, 50, 60, 100)),  # age band stands in for 'batch'
                      n_perm = 20, seed = 1)
print(aud)
pl <- audit_planted(pipe, X, y, effects = c(0, 0.25, 0.5, 1, 2), n_plant = 2,
                    reps = 10, n_grid = c(375, 750, 1500), seed = 1)
g <- variant_grid(variant_pipeline, norm = c("none", "median"), impute = c("min", "median"), k = c(3, 5))
va <- audit_variants(g$variants, X, y, design = g$design)
print(va)
audit_report(aud, pl, va, file = "data-raw/proteomics_audit.html",
             title = "Audit: targeted proteomics", pipeline_name = "reference_nested_cv")
