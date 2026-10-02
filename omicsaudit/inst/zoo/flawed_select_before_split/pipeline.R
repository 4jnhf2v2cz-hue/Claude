# FLAW: the top features are chosen using ALL samples and labels, then the
# classifier is cross-validated on that pre-selected set. Test-fold labels have
# already shaped the feature list, so performance is optimistic even on pure
# noise. (Preprocessing is correctly fitted in-fold.)

pipeline <- function(X, y, k_folds = 5, n_select = 20, seed = 1) {
  X <- check_inputs(X, y)
  with_seed(seed, {
    Z <- prep_apply(prep_fit(X), X)
    keep <- top_features(Z, y, n_select)             # <-- uses every label
    folds <- stratified_folds(y, k_folds)
    perf <- cv_auc(X[, keep, drop = FALSE], y, folds, n_select)
    list(selected = colnames(X)[keep], performance = perf)
  })
}
