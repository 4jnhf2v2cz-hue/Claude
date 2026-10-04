# =============================================================================
#  Reference analysis: descriptive statistics and biomarker prediction
#  ---------------------------------------------------------------------------
#  Answers the two questions in the project brief for a table with a 0/1
#  progression column, clinical variables and protein measurements:
#    PART 1  Descriptive analysis: variables, mean and spread, correlations,
#            univariate relationship with progression.
#    PART 2  Prediction and biomarkers: logistic regression, decision tree and
#            random forest, validated by repeated stratified cross-validation,
#            with every data-driven step (feature selection) done INSIDE the folds.
#
#  Use:   DATA_FILE <- "C:/path/to/targeted_proteomics.csv"
#         source("reference_analysis.R")
#  Output (folder OUT_DIR): tables as .csv, figures as .png, summary.txt.
#  Needs: base R + rpart (ships with R) + randomForest (installed if missing).
# =============================================================================

# ---- SETTINGS (define any of these before sourcing to override) -----------------
cfg <- function(name, default) if (exists(name, envir = globalenv())) get(name, envir = globalenv()) else default
DATA_FILE <- cfg("DATA_FILE", NULL)                   # NULL = choose a file in a window
OUTCOME   <- cfg("OUTCOME",   "Progress")             # 0/1 column (1 = progressed)
ID_COL    <- cfg("ID_COL",    "PatientID")            # id column, or NULL
CLINICAL  <- cfg("CLINICAL",  c("Age", "Sex", "WBC", "BMI"))
BINARY    <- cfg("BINARY",    "Sex")                  # clinical variables that are categories (0/1)
PROTEIN_PATTERN <- cfg("PROTEIN_PATTERN", "^Prot")    # regular expression for protein columns
N_REPEATS <- cfg("N_REPEATS", 10)                     # repeats of the cross-validation
N_FOLDS   <- cfg("N_FOLDS",   5)
TOP_K     <- cfg("TOP_K",     3)                      # proteins chosen in-fold for the 'selected' model
SEED      <- cfg("SEED",      1)
OUT_DIR   <- cfg("OUT_DIR",   "analysis_output")
# -----------------------------------------------------------------------------------

say <- function(...) cat(sprintf("\n=== %s ===\n", paste0(...)))
dir.create(OUT_DIR, showWarnings = FALSE)
out <- function(f) file.path(OUT_DIR, f)
if (!requireNamespace("randomForest", quietly = TRUE)) install.packages("randomForest")
suppressPackageStartupMessages({ library(rpart); library(randomForest) })
set.seed(SEED)

# ---- helper functions ----------------------------------------------------------------
auc <- function(score, y) {                    # rank-based AUC (Mann-Whitney)
  r <- rank(score); n1 <- sum(y == 1); n0 <- sum(y == 0)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
stratified_folds <- function(y, k) {           # folds keep the class balance
  f <- integer(length(y))
  for (cl in unique(y)) { i <- which(y == cl); f[i] <- sample(rep_len(seq_len(k), length(i))) }
  f
}
fmt_p <- function(p) ifelse(p < 0.001, "<0.001", sprintf("%.3f", p))

# ---- 0. Read and check the data ------------------------------------------------------
say("0. Reading the data")
if (is.null(DATA_FILE)) DATA_FILE <- file.choose()
raw <- read.csv(DATA_FILE, check.names = FALSE, stringsAsFactors = FALSE)
stopifnot(OUTCOME %in% names(raw), all(CLINICAL %in% names(raw)))
proteins <- grep(PROTEIN_PATTERN, names(raw), value = TRUE)
stopifnot(length(proteins) > 0)
dat <- raw[c(OUTCOME, CLINICAL, proteins)]
names(dat)[1] <- "progress"
stopifnot(all(dat$progress %in% c(0, 1)))
dat <- dat[complete.cases(dat), ]
y <- dat$progress
cat(sprintf("File: %s\n%d patients (%d progressed, %.1f%%), %d clinical variables, %d proteins\n",
            basename(DATA_FILE), nrow(dat), sum(y), 100 * mean(y), length(CLINICAL), length(proteins)))
cat(sprintf("Rows dropped for missing values: %d\n", nrow(raw) - nrow(dat)))
cat(sprintf("Events per variable (events / predictors): %.1f\n", sum(y) / (length(CLINICAL) + length(proteins))))
vars <- c(CLINICAL, proteins)
numeric_vars <- setdiff(vars, BINARY)

# =============================================================================
#  PART 1: DESCRIPTIVE ANALYSIS
# =============================================================================
say("PART 1. Descriptive analysis")

# 1a. mean and spread, overall and by progression group
describe <- function(v, x) data.frame(variable = v, n = length(x), mean = mean(x), sd = sd(x),
  median = median(x), q1 = quantile(x, .25, names = FALSE), q3 = quantile(x, .75, names = FALSE),
  min = min(x), max = max(x))
desc_all <- do.call(rbind, lapply(numeric_vars, function(v) describe(v, dat[[v]])))
write.csv(desc_all, out("1a_descriptive_overall.csv"), row.names = FALSE)
cat("\nMean and spread (all patients), first rows:\n"); print(head(transform(desc_all, mean = round(mean, 2), sd = round(sd, 2),
  median = round(median, 2), q1 = round(q1, 2), q3 = round(q3, 2)), 8), row.names = FALSE)
for (b in intersect(BINARY, vars)) cat(sprintf("\n%s: %s\n", b, paste(names(table(dat[[b]])), table(dat[[b]]),
  sep = " = ", collapse = ", ")))

# 1b. univariate relationship with progression
uni <- do.call(rbind, lapply(vars, function(v) {
  x <- dat[[v]]; is_bin <- v %in% BINARY
  g1 <- x[y == 1]; g0 <- x[y == 0]
  if (is_bin) {
    p <- fisher.test(table(x, y))$p.value
    m <- glm(y ~ x, family = binomial); cf <- summary(m)$coef["x", ]
    or <- exp(cf[1]); ci <- exp(cf[1] + c(-1.96, 1.96) * cf[2]); a <- NA
    data.frame(variable = v, type = "binary", progressed = sprintf("%.1f%% = 1", 100 * mean(g1)),
               not_progressed = sprintf("%.1f%% = 1", 100 * mean(g0)), difference = mean(g1) - mean(g0),
               auc = auc(x, y), odds_ratio = or, or_low = ci[1], or_high = ci[2], p_value = p)
  } else {
    p <- wilcox.test(g1, g0, exact = FALSE)$p.value
    xs <- as.numeric(scale(x)); m <- glm(y ~ xs, family = binomial); cf <- summary(m)$coef["xs", ]
    or <- exp(cf[1]); ci <- exp(cf[1] + c(-1.96, 1.96) * cf[2])
    data.frame(variable = v, type = "continuous",
               progressed = sprintf("%.2f (%.2f)", mean(g1), sd(g1)), not_progressed = sprintf("%.2f (%.2f)", mean(g0), sd(g0)),
               difference = mean(g1) - mean(g0), auc = auc(x, y), odds_ratio = or, or_low = ci[1], or_high = ci[2], p_value = p)
  }
}))
uni$p_adjusted_BH <- p.adjust(uni$p_value, method = "BH")
uni$auc_direction_free <- pmax(uni$auc, 1 - uni$auc)       # 0.5 = useless, 1 = perfect, ignoring direction
uni <- uni[order(-uni$auc_direction_free), ]
write.csv(uni, out("1b_univariate_vs_progression.csv"), row.names = FALSE)
cat("\nUnivariate relationship with progression (mean (SD) shown; OR per 1 SD for continuous; BH = Benjamini-Hochberg adjusted):\n")
print(data.frame(variable = uni$variable, progressed = uni$progressed, not_progressed = uni$not_progressed,
                 AUC = round(uni$auc_direction_free, 3), OR = round(uni$odds_ratio, 2), p = fmt_p(uni$p_value),
                 p_BH = fmt_p(uni$p_adjusted_BH)), row.names = FALSE)

# 1c. correlations
cm <- cor(dat[vars], method = "spearman")
write.csv(round(cm, 3), out("1c_correlation_matrix_spearman.csv"))
high <- which(abs(cm) > 0.7 & upper.tri(cm), arr.ind = TRUE)
if (nrow(high)) {
  hc <- data.frame(var1 = rownames(cm)[high[, 1]], var2 = colnames(cm)[high[, 2]], spearman_r = round(cm[high], 3))
  hc <- hc[order(-abs(hc$spearman_r)), ]; cat("\nStrongly correlated pairs (|r| > 0.7):\n"); print(hc, row.names = FALSE)
  write.csv(hc, out("1c_high_correlations.csv"), row.names = FALSE)
} else cat("\nNo pairs with |Spearman r| > 0.7.\n")
cat("\nLargest correlations of each variable with Age:\n")
age_cor <- sort(cm["Age", setdiff(vars, "Age")], decreasing = TRUE); print(round(c(head(age_cor, 2), tail(age_cor, 2)), 2))

# 1d. figures
png(out("1d_distributions_by_progression.png"), width = 1400, height = 900, res = 130)
op <- par(mfrow = c(ceiling(length(numeric_vars) / 5), 5), mar = c(3, 3, 2, 0.5)); 
for (v in numeric_vars) boxplot(dat[[v]] ~ factor(y, labels = c("no", "yes")), main = v, xlab = "", ylab = "",
                                col = c("grey85", "tomato"), outpch = 20, outcex = 0.4)
par(op); dev.off()
png(out("1d_correlation_heatmap.png"), width = 1000, height = 900, res = 130)
op <- par(mar = c(6, 6, 2, 1))
image(seq_along(vars), seq_along(vars), cm[, rev(seq_along(vars))], zlim = c(-1, 1), axes = FALSE, xlab = "", ylab = "",
      col = hcl.colors(41, "Blue-Red 3"), main = "Spearman correlation")
axis(1, seq_along(vars), vars, las = 2, cex.axis = 0.7); axis(2, seq_along(vars), rev(vars), las = 1, cex.axis = 0.7); box()
par(op); dev.off()
png(out("1d_univariate_auc.png"), width = 1000, height = 700, res = 130)
op <- par(mar = c(4, 7, 2, 1)); barplot(rev(uni$auc_direction_free), names.arg = rev(uni$variable), horiz = TRUE, las = 1,
        xlim = c(0.4, 1), xpd = FALSE, col = "steelblue", xlab = "single-variable AUC (direction ignored)", main = "Univariate discrimination")
abline(v = 0.5, lty = 2); par(op); dev.off()

# =============================================================================
#  PART 2: PREDICTION AND BIOMARKERS
# =============================================================================
say("PART 2. Prediction and biomarker analysis")
cat(sprintf("Validation: %d x repeated stratified %d-fold cross-validation. Every model is fitted on the\ntraining folds only; protein selection for the 'selected' model also happens inside each training fold.\n", N_REPEATS, N_FOLDS))

fit_predict <- function(model, tr, te, feats) {
  d_tr <- dat[tr, c("progress", feats), drop = FALSE]; d_te <- dat[te, feats, drop = FALSE]
  switch(model,
    logistic = { m <- suppressWarnings(glm(progress ~ ., data = d_tr, family = binomial)); suppressWarnings(predict(m, d_te, type = "response")) },
    tree     = { m <- rpart(factor(progress) ~ ., data = d_tr, method = "class", control = rpart.control(cp = 0.01, minsplit = 20))
                 predict(m, d_te, type = "prob")[, "1"] },
    forest   = { m <- randomForest(x = d_tr[feats], y = factor(d_tr$progress), ntree = 500); predict(m, d_te, type = "prob")[, "1"] })
}
select_top <- function(tr, k) {                # in-fold: top k proteins by univariate Wilcoxon p, training rows only
  p <- vapply(proteins, function(v) wilcox.test(dat[[v]][tr & y == 1], dat[[v]][tr & y == 0], exact = FALSE)$p.value, numeric(1))
  names(sort(p))[seq_len(k)]
}
specs <- list(
  list(name = "Clinical only",              model = "logistic", set = "clinical"),
  list(name = "Proteins only",              model = "logistic", set = "proteins"),
  list(name = "Clinical + all proteins",    model = "logistic", set = "all"),
  list(name = sprintf("Clinical + top %d proteins (selected in-fold)", TOP_K), model = "logistic", set = "selected"),
  list(name = "Decision tree (clinical + proteins)", model = "tree",   set = "all"),
  list(name = "Random forest (clinical only)",       model = "forest", set = "clinical"),
  list(name = "Random forest (proteins only)",       model = "forest", set = "proteins"),
  list(name = "Random forest (clinical + proteins)", model = "forest", set = "all"))
feats_of <- c(clinical = list(CLINICAL), proteins = list(proteins), all = list(vars))

oof <- array(NA_real_, c(nrow(dat), N_REPEATS, length(specs)), dimnames = list(NULL, NULL, vapply(specs, `[[`, "", "name")))
selected_log <- list()
t0 <- Sys.time()
for (r in seq_len(N_REPEATS)) {
  folds <- stratified_folds(y, N_FOLDS)
  for (f in seq_len(N_FOLDS)) {
    te <- folds == f; tr <- !te
    top <- select_top(tr, TOP_K); selected_log[[length(selected_log) + 1]] <- top
    for (s in seq_along(specs)) {
      feats <- if (specs[[s]]$set == "selected") c(CLINICAL, top) else feats_of[[specs[[s]]$set]]
      oof[te, r, s] <- fit_predict(specs[[s]]$model, tr, te, feats)
    }
  }
  cat(sprintf("\r  repeat %d of %d (%.0f s)", r, N_REPEATS, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}
cat("\n")
aucs <- apply(oof, c(2, 3), function(p) auc(p, y))                  # repeats x models
res <- data.frame(model = colnames(aucs), mean_auc = colMeans(aucs), sd_across_repeats = apply(aucs, 2, sd),
                  min_auc = apply(aucs, 2, min), max_auc = apply(aucs, 2, max), row.names = NULL)
res <- res[order(-res$mean_auc), ]
write.csv(res, out("2a_model_comparison_cv_auc.csv"), row.names = FALSE)
cat("\nCross-validated AUC (mean over repeats; 0.5 = chance, 1 = perfect):\n")
print(transform(res, mean_auc = round(mean_auc, 3), sd_across_repeats = round(sd_across_repeats, 3),
                min_auc = round(min_auc, 3), max_auc = round(max_auc, 3)), row.names = FALSE)

# 2b. Do the proteins add anything beyond the clinical variables?
cat("\nAdded value of proteins over clinical variables (paired over the same folds and repeats):\n")
base <- aucs[, "Clinical only"]
for (nm in setdiff(colnames(aucs), "Clinical only")) {
  dlt <- aucs[, nm] - base
  cat(sprintf("  %-52s AUC difference vs clinical only: %+.3f (range %+.3f to %+.3f)\n", nm, mean(dlt), min(dlt), max(dlt)))
}
m_clin <- glm(progress ~ ., data = dat[c("progress", CLINICAL)], family = binomial)
m_full <- glm(progress ~ ., data = dat[c("progress", vars)], family = binomial)
lr <- anova(m_clin, m_full, test = "Chisq")
cat(sprintf("\nLikelihood-ratio test, all proteins added to clinical model (full data): chi-square = %.1f on %d df, p %s\n",
            lr$Deviance[2], lr$Df[2], fmt_p(lr$`Pr(>Chi)`[2])))

# 2c. Which proteins are chosen, and how stable is that?
sel_tab <- sort(table(unlist(selected_log)) / length(selected_log), decreasing = TRUE)
write.csv(data.frame(protein = names(sel_tab), share_of_folds_selected = as.numeric(sel_tab)), out("2c_selection_frequency.csv"), row.names = FALSE)
cat(sprintf("\nProteins selected in-fold (share of the %d training folds): %s\n", length(selected_log),
            paste(sprintf("%s %.0f%%", names(sel_tab), 100 * sel_tab), collapse = ", ")))

# 2d. Final logistic model on all data: coefficients (odds ratio per 1 SD)
sc <- dat; sc[numeric_vars] <- lapply(dat[numeric_vars], function(v) as.numeric(scale(v)))
m_final <- glm(progress ~ ., data = sc[c("progress", vars)], family = binomial)
cf <- summary(m_final)$coef[-1, , drop = FALSE]
coef_tab <- data.frame(variable = rownames(cf), odds_ratio_per_SD = exp(cf[, 1]), ci_low = exp(cf[, 1] - 1.96 * cf[, 2]),
                       ci_high = exp(cf[, 1] + 1.96 * cf[, 2]), p_value = cf[, 4], row.names = NULL)
coef_tab <- coef_tab[order(coef_tab$p_value), ]
write.csv(coef_tab, out("2d_final_logistic_coefficients.csv"), row.names = FALSE)
uni_or <- setNames(uni$odds_ratio, uni$variable)
flips <- coef_tab$variable[(coef_tab$odds_ratio_per_SD > 1) != (uni_or[coef_tab$variable] > 1) &
                           (coef_tab$p_value < 0.1 | uni$p_value[match(coef_tab$variable, uni$variable)] < 0.05)]
if (length(flips)) cat(sprintf("\nNote: for %s the effect points the opposite way in the full model than on its own. This usually means collinearity with other variables (see the correlated pairs above).\n", paste(flips, collapse = ", ")))
cat("\nFinal logistic model (all variables, fitted on all patients; odds ratios per 1 SD; this is descriptive, not a validation):\n")
print(transform(coef_tab, odds_ratio_per_SD = round(odds_ratio_per_SD, 2), ci_low = round(ci_low, 2), ci_high = round(ci_high, 2),
                p_value = fmt_p(p_value)), row.names = FALSE)

# 2e. Random-forest importance
rf <- randomForest(x = dat[vars], y = factor(y), ntree = 1000, importance = TRUE)
imp <- importance(rf, type = 1)[, 1]; imp <- sort(imp, decreasing = TRUE)
write.csv(data.frame(variable = names(imp), mean_decrease_accuracy = as.numeric(imp)), out("2e_random_forest_importance.csv"), row.names = FALSE)
cat("\nRandom-forest importance (mean decrease in accuracy), top 6:\n"); print(round(head(imp, 6), 2))

# 2f. Threshold performance of the best simple model, from out-of-fold predictions
best <- res$model[1]; sp <- which(colnames(aucs) == best)
pr <- rowMeans(oof[, , sp])                              # average out-of-fold risk over repeats
ths <- sort(unique(pr)); sens <- sapply(ths, function(t) mean(pr[y == 1] >= t)); spec <- sapply(ths, function(t) mean(pr[y == 0] < t))
j <- which.max(sens + spec - 1)
cat(sprintf("\nBest model: %s\n  Youden-optimal cut-off on out-of-fold risk: sensitivity %.0f%%, specificity %.0f%%\n  (cut-off chosen on the same predictions, so these two figures are mildly optimistic)\n",
            best, 100 * sens[j], 100 * spec[j]))

# 2g. Figures
png(out("2g_roc_curves.png"), width = 1000, height = 900, res = 130)
plot(0:1, 0:1, type = "n", xlab = "1 - specificity", ylab = "sensitivity", main = "Out-of-fold ROC (averaged over repeats)")
abline(0, 1, lty = 2, col = "grey60"); cols <- hcl.colors(length(specs), "Dark 3")
for (s in seq_along(specs)) { p <- rowMeans(oof[, , s]); th <- sort(unique(p), decreasing = TRUE)
  lines(c(0, sapply(th, function(t) mean(p[y == 0] >= t)), 1), c(0, sapply(th, function(t) mean(p[y == 1] >= t)), 1), col = cols[s], lwd = 2) }
legend("bottomright", sprintf("%s (%.2f)", colnames(aucs), colMeans(aucs)), col = cols, lwd = 2, cex = 0.6, bty = "n"); dev.off()
png(out("2g_model_auc_comparison.png"), width = 1100, height = 700, res = 130)
op <- par(mar = c(4, 17, 2, 1)); o <- order(colMeans(aucs))
boxplot(aucs[, o], horizontal = TRUE, las = 1, col = "steelblue", xlab = "cross-validated AUC (spread over repeats)", main = "Model comparison")
par(op); dev.off()

# ---- summary ----------------------------------------------------------------------------
say("Summary")
top3 <- uni$variable[1:3]
lines <- c(
  sprintf("Data: %d patients, %d progressed (%.1f%%); %d clinical variables and %d proteins.", nrow(dat), sum(y), 100 * mean(y), length(CLINICAL), length(proteins)),
  sprintf("Strongest single variables by AUC: %s.", paste(sprintf("%s (%.2f)", top3, uni$auc_direction_free[1:3]), collapse = ", ")),
  sprintf("Best cross-validated model: %s, AUC %.3f (clinical only: %.3f).", best, res$mean_auc[1], mean(base)),
  sprintf("Proteins %s to the clinical model (likelihood-ratio test p %s).", if (lr$`Pr(>Chi)`[2] < 0.05) "add" else "do not clearly add", fmt_p(lr$`Pr(>Chi)`[2])),
  if (length(flips)) sprintf("Direction of effect reverses once other variables are included for: %s (collinearity; do not interpret these coefficients on their own).", paste(flips, collapse = ", ")),
  if (nrow(high)) sprintf("Note: %d strongly correlated pair(s); check %s.", nrow(high), paste(unique(c(hc$var1, hc$var2))[1:min(4, length(unique(c(hc$var1, hc$var2))))], collapse = ", ")),
  "Limits: a single dataset with no independent validation; cut-offs are optimistic; the sign and size of effects depend on the units of the measurements.")
writeLines(lines, out("summary.txt")); cat(paste0(" - ", lines), sep = "\n")
cat(sprintf("\nAll tables and figures are in: %s\n", normalizePath(OUT_DIR)))
