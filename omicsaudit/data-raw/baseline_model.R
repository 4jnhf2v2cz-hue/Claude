# Prototype baseline on the supplied targeted proteomics file (public).
# Values appear to be log2 (estimated, unconfirmed). Run from package root.
suppressMessages(library(omicsaudit))
d <- read.csv("inst/extdata/targeted_proteomics.csv")
prot <- paste0("Prot", 1:10)
y <- d$Progress
X <- 2^as.matrix(d[prot]); rownames(X) <- d$PatientID   # back to linear scale

# 1. Zoo reference pipeline (nested CV, DLDA, proteins only)
ref <- zoo_load("reference_nested_cv")$pipeline
r <- ref(X, y)
cat("Reference nested-CV pipeline: AUC", round(r$performance, 3),
    "| selected:", paste(r$selected, collapse = ", "), "\n\n")

# 2. Repeated stratified 5-fold CV of logistic regression, several feature sets
auc <- function(s, y) { r <- rank(s); n1 <- sum(y); n0 <- sum(!y)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
cv_logit <- function(vars, reps = 10, k = 5) {
  mean(sapply(seq_len(reps), function(s) {
    set.seed(s); f <- integer(nrow(d))
    for (cl in 0:1) { i <- which(y == cl); f[i] <- sample(rep_len(1:k, length(i))) }
    sc <- numeric(nrow(d))
    for (j in 1:k) {
      m <- suppressWarnings(glm(reformulate(vars, "Progress"), binomial, d[f != j, ]))
      sc[f == j] <- predict(m, d[f == j, ])
    }
    auc(sc, y)
  }))
}
sets <- list(
  "Age+WBC only (no proteins)"        = c("Age", "WBC"),
  "All proteins"                      = prot,
  "All proteins, minus age surrogates (Prot2, Prot8)" = setdiff(prot, c("Prot2", "Prot8")),
  "Proteins + Age + WBC + Sex + BMI"  = c(prot, "Age", "WBC", "Sex", "BMI"),
  "Prot3, 6, 10 + Age + WBC"          = c("Prot3", "Prot6", "Prot10", "Age", "WBC"),
  "Prot6 + Prot10 + WBC"              = c("Prot6", "Prot10", "WBC")
)
res <- data.frame(model = names(sets), cv_auc = round(sapply(sets, cv_logit), 3), row.names = NULL)
print(res)

# 3. Is Prot2 / Prot8 signal independent of Age?
cat("\nProt2 ~ Age R^2:", round(summary(lm(Prot2 ~ Age, d))$r.squared, 3),
    "| Prot8 ~ Age R^2:", round(summary(lm(Prot8 ~ Age, d))$r.squared, 3), "\n")
print(round(summary(glm(Progress ~ Prot2 + Prot8 + Age, binomial, d))$coef[, c(1, 4)], 3))
