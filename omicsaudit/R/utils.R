# Internal helpers ---------------------------------------------------------

#' Run code with a fixed RNG seed, restoring the caller's RNG state afterwards
#' @param seed Integer seed, or `NULL` to leave the RNG untouched.
#' @param expr Expression to evaluate.
#' @noRd
with_seed <- function(seed, expr) {
  if (is.null(seed)) return(expr)
  had_seed <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (had_seed) old <- get(".Random.seed", envir = globalenv())
  on.exit({
    if (had_seed) {
      assign(".Random.seed", old, envir = globalenv())
    } else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      rm(".Random.seed", envir = globalenv())
    }
  }, add = TRUE)
  set.seed(seed)
  expr
}

#' Rank-based (Mann-Whitney) AUC
#' @param score Numeric scores; higher means more likely class 1.
#' @param y Binary outcome coded 0/1.
#' @return AUC, or `NA` if only one class is present.
#' @noRd
auc <- function(score, y) {
  y <- as.integer(y)
  n1 <- sum(y == 1L)
  n0 <- sum(y == 0L)
  if (n1 == 0L || n0 == 0L) return(NA_real_)
  r <- rank(score)
  (sum(r[y == 1L]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

#' Stratified k-fold assignment
#' @return Integer vector of fold ids (1..k), balanced within each class.
#' @noRd
stratified_folds <- function(y, k) {
  folds <- integer(length(y))
  for (cl in unique(y)) {
    idx <- which(y == cl)
    folds[idx] <- sample(rep_len(seq_len(k), length(idx)))
  }
  folds
}

# Helper functions shared with the zoo (prep, classifier, CV), loaded once.
.omicsaudit_cache <- new.env(parent = emptyenv())
zoo_helpers <- function() {
  if (is.null(.omicsaudit_cache$helpers)) {
    env <- new.env(parent = asNamespace("omicsaudit"))
    sys.source(file.path(zoo_path(), "_common.R"), envir = env)
    .omicsaudit_cache$helpers <- env
  }
  .omicsaudit_cache$helpers
}

# Permute labels, optionally at group level (all members of a group keep one label)
permute_labels <- function(y, groups = NULL) {
  if (is.null(groups)) return(sample(y))
  g <- unique(groups)
  gy <- sample(y[match(g, groups)])
  gy[match(groups, g)]
}

# Run in parallel (forked, not on Windows) or serially
par_lapply <- function(X, FUN, cores = 1) {
  if (cores > 1 && .Platform$OS.type != "windows")
    parallel::mclapply(X, FUN, mc.cores = cores) else lapply(X, FUN)
}
