# FLAW: the number of selected features is tuned on the outer TEST fold, i.e.
# for each fold the k that scores best on that fold's own test samples is kept.
# Taking the maximum over a grid of k on the evaluation data inflates AUC.

pipeline <- function(X, y, k_folds = 5,
                     grid = c(1, 2, 3, 5, 8, 12, 20, 30, 50, 80), seed = 1) {
  X <- check_inputs(X, y)
  grid <- unique(pmin(grid, max(1L, floor(ncol(X) / 2))))
  with_seed(seed, {
    folds <- stratified_folds(y, k_folds)
    score <- numeric(length(y)); chosen <- integer()
    for (f in sort(unique(folds))) {
      tr <- folds != f
      fit <- prep_fit(X[tr, , drop = FALSE])
      Ztr <- prep_apply(fit, X[tr, , drop = FALSE])
      Zte <- prep_apply(fit, X[!tr, , drop = FALSE])
      s <- lapply(grid, function(k) dlda_fit(Ztr, y[tr], top_features(Ztr, y[tr], k))(Zte))
      a <- vapply(s, function(v) auc(v, y[!tr]), numeric(1))   # <-- test labels
      best <- which.max(replace(a, is.na(a), -Inf))
      score[!tr] <- s[[best]]; chosen <- c(chosen, grid[best])
    }
    Z <- prep_apply(prep_fit(X), X)
    list(selected = colnames(X)[top_features(Z, y, stats::median(chosen))],
         performance = auc(score, y))
  })
}
