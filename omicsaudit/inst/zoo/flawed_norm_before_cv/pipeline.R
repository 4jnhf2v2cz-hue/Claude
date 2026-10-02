# FLAW: imputation floor and feature z-scoring are fitted on ALL samples
# before cross-validation, so every test fold has contributed to the
# preprocessing parameters that its own training data were transformed with.
# Feature selection and the classifier are (correctly) refit inside each fold,
# so this is the only flaw in the pipeline.

pipeline <- function(X, y, k_folds = 5, n_select = 20, seed = 1) {
  X <- check_inputs(X, y)
  with_seed(seed, {
    fit <- prep_fit(X)                      # <-- all samples
    Z <- prep_apply(fit, X)
    folds <- stratified_folds(y, k_folds)
    perf <- cv_auc(Z, y, folds, n_select, prep = FALSE)
    selected <- colnames(X)[top_features(Z, y, n_select)]
    list(selected = selected, performance = perf)
  })
}
