# Planted-signal audit of the zoo reference pipeline on the supplied proteomics
# file (values assumed log2). Run from the package root.
suppressMessages(library(omicsaudit))
d <- read.csv("inst/extdata/targeted_proteomics.csv")
X <- 2^as.matrix(d[paste0("Prot", 1:10)]); rownames(X) <- d$PatientID
y <- d$Progress

p <- zoo_load("reference_nested_cv")$pipeline
a <- audit_planted(p, X, y, effects = c(0, 0.25, 0.5, 0.75, 1, 1.5, 2),
                   n_plant = 2, reps = 20, n_grid = c(300, 750, 1500), seed = 1)
print(a)
print(a$summary[a$summary$n == 1500, c("effect", "recall", "precision", "n_selected")])
cat("\nSamples needed to detect a 0.25 log2FC (1.19x) effect:",
    samples_needed(a, 0.25), "\n")
plot(a)
