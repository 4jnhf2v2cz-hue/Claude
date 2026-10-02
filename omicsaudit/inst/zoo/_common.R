# Shared building blocks for zoo pipelines. zoo_load() sources this file
# into the pipeline's environment before pipeline.R. Everything here uses
# base R + stats only.

# Preprocessing --------------------------------------------------------------
# Steps: log2 -> per-sample median centring -> left-censored imputation
# (feature minimum among the rows used for fitting) -> feature z-scoring.
# The *fitted* parts (imputation floor, feature mean/sd) are the only places
# where one sample's values can influence another's, which is where the
# "preprocess before cross-validation" flaw leaks.

prep_fit <- function(X) {
  L <- log2(X)
  L <- sweep(L, 1, apply(L, 1, stats::median, na.rm = TRUE), "-")
  floor_j <- apply(L, 2, function(v) if (all(is.na(v))) NA_real_ else min(v, na.rm = TRUE))
  floor_j[is.na(floor_j)] <- min(L, na.rm = TRUE)
  L <- impute_floor(L, floor_j)
  list(floor = floor_j, mean = colMeans(L),
       sd = pmax(apply(L, 2, stats::sd), 1e-8))
}

prep_apply <- function(fit, X) {
  L <- log2(X)
  L <- sweep(L, 1, apply(L, 1, stats::median, na.rm = TRUE), "-")
  L <- impute_floor(L, fit$floor)
  sweep(sweep(L, 2, fit$mean, "-"), 2, fit$sd, "/")
}

impute_floor <- function(L, floor_j) {
  idx <- which(is.na(L), arr.ind = TRUE)
  L[idx] <- floor_j[idx[, 2]]
  L
}

# Feature selection and classifier --------------------------------------------

top_features <- function(Z, y, k) {
  g1 <- Z[y == 1L, , drop = FALSE]
  g0 <- Z[y == 0L, , drop = FALSE]
  v1 <- apply(g1, 2, stats::var)
  v0 <- apply(g0, 2, stats::var)
  t <- (colMeans(g1) - colMeans(g0)) /
    sqrt(v1 / nrow(g1) + v0 / nrow(g0) + 1e-12)
  order(abs(t), decreasing = TRUE)[seq_len(min(k, ncol(Z)))]
}

# Diagonal LDA on the selected columns; returns a scoring function.
dlda_fit <- function(Z, y, sel) {
  m1 <- colMeans(Z[y == 1L, sel, drop = FALSE])
  m0 <- colMeans(Z[y == 0L, sel, drop = FALSE])
  r <- Z[, sel, drop = FALSE] - ifelse(y == 1L, 1, 0) %o% (m1 - m0) -
    matrix(m0, nrow(Z), length(sel), byrow = TRUE)
  s2 <- pmax(colSums(r^2) / (nrow(Z) - 2L), 1e-8)
  w <- (m1 - m0) / s2
  mid <- (m1 + m0) / 2
  function(Znew) as.numeric((Znew[, sel, drop = FALSE] -
                               matrix(mid, nrow(Znew), length(sel), byrow = TRUE)) %*% w)
}

# Cross-validation ------------------------------------------------------------
# prep = TRUE : preprocessing is fitted on each fold's training rows only.
# prep = FALSE: X is assumed to be already preprocessed (z-scored, imputed).

cv_auc <- function(X, y, folds, n_select, prep = TRUE) {
  score <- numeric(length(y))
  for (f in sort(unique(folds))) {
    tr <- folds != f
    if (prep) {
      fit <- prep_fit(X[tr, , drop = FALSE])
      Ztr <- prep_apply(fit, X[tr, , drop = FALSE])
      Zte <- prep_apply(fit, X[!tr, , drop = FALSE])
    } else {
      Ztr <- X[tr, , drop = FALSE]
      Zte <- X[!tr, , drop = FALSE]
    }
    sel <- top_features(Ztr, y[tr], n_select)
    score[!tr] <- dlda_fit(Ztr, y[tr], sel)(Zte)
  }
  auc(score, y)
}

check_inputs <- function(X, y) {
  stopifnot(is.matrix(X), is.numeric(X), nrow(X) == length(y),
            all(y %in% c(0L, 1L)), all(X > 0, na.rm = TRUE))
  if (is.null(colnames(X))) colnames(X) <- sprintf("V%d", seq_len(ncol(X)))
  X
}

with_seed <- function(seed, expr) {
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (had) old <- get(".Random.seed", envir = globalenv())
  on.exit(if (had) assign(".Random.seed", old, envir = globalenv()), add = TRUE)
  set.seed(seed)
  expr
}

# Folds ------------------------------------------------------------------------
# With `groups`, all samples of a group (e.g. one subject) share a fold.
make_folds <- function(y, k, groups = NULL) {
  if (is.null(groups)) return(stratified_folds(y, k))
  g <- unique(groups)
  gy <- y[match(g, groups)]
  gf <- stratified_folds(gy, min(k, length(g)))
  gf[match(groups, g)]
}

subject_ids <- function(X) sub("_r[0-9]+$", "", rownames(X))

# Reference pipeline body (correct nested CV); reused by several zoo entries.
# `grouped = TRUE` keeps all samples of a subject (row names `<subject>_r<n>`)
# in the same fold, at both CV levels.
nested_cv_pipeline <- function(X, y, k_outer = 5, k_inner = 3,
                               grid = c(5, 20, 50), grouped = FALSE, seed = 1) {
  X <- check_inputs(X, y)
  # never tune over more features than exist, otherwise 'select' = 'keep all'
  grid <- unique(pmin(grid, max(1L, floor(ncol(X) / 2))))
  groups <- if (grouped) subject_ids(X) else NULL
  tune <- function(Xt, yt, gt) {
    inner <- make_folds(yt, k_inner, gt)
    aucs <- vapply(grid, function(k) cv_auc(Xt, yt, inner, k), numeric(1))
    grid[which.max(aucs)]
  }
  with_seed(seed, {
    outer <- make_folds(y, k_outer, groups)
    score <- numeric(length(y))
    for (f in sort(unique(outer))) {
      tr <- outer != f
      k <- tune(X[tr, , drop = FALSE], y[tr], groups[tr])
      fit <- prep_fit(X[tr, , drop = FALSE])
      Ztr <- prep_apply(fit, X[tr, , drop = FALSE])
      Zte <- prep_apply(fit, X[!tr, , drop = FALSE])
      sel <- top_features(Ztr, y[tr], k)
      score[!tr] <- dlda_fit(Ztr, y[tr], sel)(Zte)
    }
    # Final model on all samples (not used for `performance`)
    k <- tune(X, y, groups)
    fit <- prep_fit(X)
    Z <- prep_apply(fit, X)
    list(selected = colnames(X)[top_features(Z, y, k)],
         performance = auc(score, y))
  })
}
