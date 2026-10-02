#' Can batch (or site, run date) be predicted as well as the outcome?
#'
#' Two complementary checks on the data (the pipeline is not needed):
#'
#' 1. **Design confounding**: association between batch and outcome
#'    (Cramer's V from a chi-squared test; Fisher p-value). Flagged when
#'    `V >= v_threshold` and `p < 0.01`. This is what makes batch
#'    and biology impossible to separate, whatever the pipeline does.
#' 2. **Predictability**: cross-validated AUC for predicting the outcome from
#'    the features, and for predicting batch from the features
#'    (one-vs-rest mean AUC if more than two batches). Reported as evidence;
#'    a visible batch effect alone does not raise the flag, because a batch
#'    that is balanced across outcome groups can be corrected for.
#'
#' @param X Raw samples x features matrix.
#' @param y Binary outcome, 0/1.
#' @param batch Factor/character of batch, site or run date.
#' @param v_threshold Cramer's V above which confounding is flagged.
#' @param k_folds,n_select CV folds and features used by the internal
#'   diagonal-LDA predictor.
#' @param seed Integer seed, recorded in the output.
#' @return Object of class `audit_confound`.
#' @export
audit_confound <- function(X, y, batch, v_threshold = 0.3, k_folds = 5,
                           n_select = 20, seed = 1L) {
  stopifnot(is.matrix(X), length(y) == nrow(X), length(batch) == nrow(X))
  batch <- factor(batch)
  tab <- table(batch, y)
  ct <- suppressWarnings(stats::chisq.test(tab, correct = FALSE))
  v <- sqrt(unname(ct$statistic) / (sum(tab) * (min(dim(tab)) - 1)))
  v <- if (is.finite(v)) v else 0
  p <- tryCatch(stats::fisher.test(tab, simulate.p.value = nlevels(batch) > 2,
                                   B = 2000)$p.value, error = function(e) ct$p.value)
  h <- zoo_helpers()
  predict_auc <- function(target) {
    if (length(unique(target)) < 2) return(NA_real_)
    with_seed(seed, {
      folds <- stratified_folds(target, k_folds)
      h$cv_auc(X, target, folds, min(n_select, ncol(X)))
    })
  }
  auc_y <- predict_auc(as.integer(y))
  auc_b <- if (nlevels(batch) < 2) NA_real_ else mean(vapply(levels(batch), function(l)
    predict_auc(as.integer(batch == l)), numeric(1)), na.rm = TRUE)
  flagged <- nlevels(batch) >= 2 && v >= v_threshold && p < 0.01
  structure(list(
    cramers_v = v, p_value = p, table = tab,
    auc_outcome = auc_y, auc_batch = auc_b, flagged = flagged,
    evidence = sprintf(
      "Batch and outcome association: Cramer's V = %.2f (p = %.3g). Features predict outcome with AUC %.2f and batch with AUC %.2f.%s",
      v, p, auc_y, auc_b,
      if (flagged) " Batch is confounded with the outcome: any apparent signal may be batch." else ""),
    params = list(v_threshold = v_threshold), seed = seed), class = "audit_confound")
}

#' @export
print.audit_confound <- function(x, ...) {
  cat("<audit_confound> ", if (x$flagged) "FLAGGED" else "pass", " (seed ", x$seed, ")\n  ",
      x$evidence, "\n", sep = "")
  invisible(x)
}

#' @export
plot.audit_confound <- function(x, ...) {
  graphics::barplot(t(prop.table(x$table, 1)), beside = FALSE, legend.text = c("class 0", "class 1"),
                    xlab = "batch", ylab = "share of samples",
                    main = sprintf("Outcome by batch (V = %.2f)", x$cramers_v), ...)
  invisible(x)
}
