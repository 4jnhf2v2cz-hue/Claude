# REFERENCE (correct): preprocessing is fitted on training rows only, and
# the number of selected features is tuned by an inner CV that sees only the
# outer training rows. The outer CV AUC is therefore an honest estimate.
# `selected` comes from a final fit on all samples (inner-CV-tuned size),
# which is legitimate: it is the model you would report, and `performance`
# does not depend on it.

pipeline <- function(X, y, k_outer = 5, k_inner = 3,
                     grid = c(5, 20, 50), seed = 1) {
  X <- check_inputs(X, y)
  # never tune over more features than exist, otherwise 'select' = 'keep all'
  grid <- unique(pmin(grid, max(1L, floor(ncol(X) / 2))))
  tune <- function(Xt, yt) {
    inner <- stratified_folds(yt, k_inner)
    aucs <- vapply(grid, function(k) cv_auc(Xt, yt, inner, k), numeric(1))
    grid[which.max(aucs)]
  }
  with_seed(seed, {
    outer <- stratified_folds(y, k_outer)
    score <- numeric(length(y))
    for (f in sort(unique(outer))) {
      tr <- outer != f
      k <- tune(X[tr, , drop = FALSE], y[tr])
      fit <- prep_fit(X[tr, , drop = FALSE])
      Ztr <- prep_apply(fit, X[tr, , drop = FALSE])
      Zte <- prep_apply(fit, X[!tr, , drop = FALSE])
      sel <- top_features(Ztr, y[tr], k)
      score[!tr] <- dlda_fit(Ztr, y[tr], sel)(Zte)
    }
    # Final model on all samples (not used for `performance`)
    k <- tune(X, y)
    fit <- prep_fit(X)
    Z <- prep_apply(fit, X)
    list(selected = colnames(X)[top_features(Z, y, k)],
         performance = auc(score, y))
  })
}
