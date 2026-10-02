#' Plant a known effect into a raw intensity matrix
#'
#' Multiplies the *observed* values of `features` in class-1 samples by
#' `2^effect` (an `effect` log2 fold change). Missing values are left missing
#' and no new values are masked, so the missingness mask is identical before
#' and after planting.
#'
#' **Limits.** In real MNAR data a higher true abundance would also be less
#' likely to be missing; planting cannot undo values that were already
#' missing, so planted features keep their original (slightly higher)
#' missingness in class 1. That makes the audit conservative for positive
#' effects. Only upward shifts in class 1 are planted; downward shifts would
#' need extra synthetic dropout that depends on an assumed MNAR curve.
#'
#' @param X Raw (linear-scale) samples x features matrix.
#' @param y Binary outcome, 0/1.
#' @param features Column names or indices to plant into.
#' @param effect Log2 fold change to add in class 1.
#' @return `X` with the signal planted.
#' @export
plant_signal <- function(X, y, features, effect) {
  stopifnot(is.matrix(X), length(y) == nrow(X), all(y %in% c(0L, 1L)))
  X[y == 1L, features] <- X[y == 1L, features] * 2^effect
  X
}

#' Planted-signal audit and pipeline power curve
#'
#' Treats `pipeline` as a black box. The outcome is first **permuted**, so no
#' real signal remains, then a known effect is planted into randomly chosen
#' features (see [plant_signal()]) and the pipeline is run on the result. For
#' each effect size it records how many planted features the pipeline selects
#' (recall), how many of its selections are planted (precision) and its
#' reported performance. The effect at which mean recall first reaches
#' `target_recall` is the minimum detectable effect (MDE).
#'
#' Real noise and real missingness are kept; only the outcome is replaced.
#' This means the audit measures what *this pipeline* can detect *in this
#' dataset at this sample size*.
#'
#' @param pipeline Function `pipeline(X, y)` returning
#'   `list(selected = <character>, performance = <number>)`.
#' @param X Raw (linear-scale) samples x features matrix with column names.
#' @param y Binary outcome, 0/1 (only its class balance is used).
#' @param effects Log2 fold changes to test. Include `0` to measure the
#'   chance level.
#' @param n_plant Number of features planted per replicate. Default
#'   `max(1, round(0.1 * ncol(X)))`.
#' @param reps Replicates per effect size (each draws a new outcome
#'   permutation and a new set of planted features).
#' @param n_grid Optional sample sizes to subsample to (stratified). Needed
#'   for [samples_needed()]. Default: the full sample only.
#' @param target_recall Mean recall defining "detected".
#' @param quick If `TRUE`, use 3 replicates and a coarser effect grid.
#' @param cores Parallel workers (forked; ignored on Windows).
#' @param progress Show a progress bar.
#' @param seed Integer seed, recorded in the output. The caller's RNG state
#'   is left unchanged.
#' @return An object of class `audit_planted` with `results` (one row per
#'   replicate x effect x n), `summary` (means per effect x n), `mde` (per n),
#'   `params`, `seed` and the number of `failures` (pipeline errors).
#' @examples
#' sim <- simulate_omics(n = 60, p = 60, n_signal = 0, seed = 1)
#' top5 <- function(X, y) {
#'   t <- abs(apply(log2(X), 2, function(v) stats::t.test(v ~ y)$statistic))
#'   list(selected = names(sort(t, decreasing = TRUE))[1:5], performance = NA_real_)
#' }
#' a <- audit_planted(top5, sim$X, sim$y, quick = TRUE, seed = 1)
#' a
#' @export
audit_planted <- function(pipeline, X, y, effects = c(0, 0.25, 0.5, 0.75, 1, 1.5, 2),
                          n_plant = NULL, reps = 20, n_grid = NULL,
                          target_recall = 0.8, quick = FALSE, cores = 1,
                          progress = interactive(), seed = 1L) {
  stopifnot(is.function(pipeline), is.matrix(X), !is.null(colnames(X)),
            length(y) == nrow(X), all(y %in% c(0L, 1L)),
            target_recall > 0, target_recall <= 1)
  if (quick) { reps <- 3; effects <- c(0, 0.5, 1, 2) }
  p <- ncol(X); N <- nrow(X)
  if (is.null(n_plant)) n_plant <- max(1L, round(0.1 * p))
  stopifnot(n_plant >= 1, n_plant <= p)
  if (is.null(n_grid)) n_grid <- N
  stopifnot(all(n_grid >= 10), all(n_grid <= N))
  effects <- sort(unique(effects))

  jobs <- expand.grid(rep = seq_len(reps), n = n_grid)
  pb <- if (progress) utils::txtProgressBar(0, nrow(jobs), style = 3) else NULL

  one_job <- function(j) {
    rep <- jobs$rep[j]; n <- jobs$n[j]
    out <- with_seed(seed + 1000L * match(n, n_grid) + rep, {
      yp <- sample(y)                                  # destroy real signal
      idx <- if (n < N) stratified_subsample(yp, n) else seq_len(N)
      feats <- sample(colnames(X), n_plant)
      do.call(rbind, lapply(effects, function(e) {
        Xp <- plant_signal(X[idx, , drop = FALSE], yp[idx], feats, e)
        r <- tryCatch(pipeline(Xp, yp[idx]), error = function(err) NULL)
        sel <- if (is.null(r)) character() else as.character(r$selected)
        data.frame(rep = rep, n = n, effect = e,
                   recall = mean(feats %in% sel),
                   precision = if (length(sel)) mean(sel %in% feats) else NA_real_,
                   n_selected = length(sel),
                   performance = if (is.null(r)) NA_real_ else as.numeric(r$performance)[1],
                   failed = is.null(r))
      }))
    })
    if (!is.null(pb)) utils::setTxtProgressBar(pb, j)
    out
  }
  idx <- seq_len(nrow(jobs))
  res <- if (cores > 1 && .Platform$OS.type != "windows") {
    parallel::mclapply(idx, one_job, mc.cores = cores)
  } else lapply(idx, one_job)
  if (!is.null(pb)) close(pb)
  results <- do.call(rbind, res)

  summ <- stats::aggregate(
    cbind(recall, precision, n_selected, performance) ~ n + effect,
    data = results, FUN = function(v) mean(v, na.rm = TRUE), na.action = stats::na.pass)
  summ <- summ[order(summ$n, summ$effect), ]
  mde <- do.call(rbind, lapply(split(summ, summ$n), function(s) {
    data.frame(n = s$n[1], mde = find_mde(s$effect, s$recall, target_recall))
  }))
  rownames(mde) <- NULL
  mde$fold_change <- 2^mde$mde

  structure(list(
    results = results, summary = summ, mde = mde,
    chance_recall = results_chance(summ),
    failures = sum(results$failed),
    params = list(effects = effects, n_plant = n_plant, reps = reps,
                  n_grid = n_grid, target_recall = target_recall,
                  n_features = p, n_samples = N, quick = quick),
    seed = seed
  ), class = "audit_planted")
}

# Smallest effect whose mean recall reaches `target`, by linear interpolation.
# Returns NA if never reached; the smallest tested effect if reached at once.
find_mde <- function(effect, recall, target) {
  ok <- which(recall >= target)
  if (!length(ok)) return(NA_real_)
  i <- ok[1]
  if (i == 1) return(effect[1])
  effect[i - 1] + (target - recall[i - 1]) / (recall[i] - recall[i - 1]) *
    (effect[i] - effect[i - 1])
}

results_chance <- function(summ) {
  z <- summ[summ$effect == 0, ]
  if (nrow(z)) mean(z$recall) else NA_real_
}

stratified_subsample <- function(y, m) {
  idx <- unlist(lapply(unique(y), function(cl) {
    i <- which(y == cl)
    sample(i, max(2L, round(m * length(i) / length(y))))
  }))
  sort(idx)
}

#' Samples needed to detect a smaller effect
#'
#' Extrapolates the power curve to other sample sizes. Fits
#' `log(MDE) ~ log(n)` across the sample sizes tested with [audit_planted()]'s
#' `n_grid` (falling back to the textbook slope of -1/2 when there are fewer
#' than two usable sizes or the slope is not negative), then solves for the
#' `n` at which the MDE equals `effect`. This is an **extrapolation**, most
#' reliable close to the tested sizes.
#'
#' @param x An `audit_planted` object.
#' @param effect Target effect in log2 fold change.
#' @return Estimated number of samples (numeric), or `NA` if no MDE was found.
#' @export
samples_needed <- function(x, effect) {
  stopifnot(inherits(x, "audit_planted"), effect > 0)
  m <- x$mde[is.finite(x$mde$mde) & x$mde$mde > 0, ]
  if (!nrow(m)) return(NA_real_)
  slope <- -0.5
  if (nrow(m) >= 2) {
    s <- unname(stats::coef(stats::lm(log(mde) ~ log(n), m))[2])
    if (is.finite(s) && s < 0) slope <- s
  }
  ref <- m[which.max(m$n), ]
  ceiling(ref$n * (effect / ref$mde)^(1 / slope))
}

#' @export
print.audit_planted <- function(x, ...) {
  p <- x$params
  cat("<audit_planted> ", p$n_samples, " samples x ", p$n_features,
      " features; ", p$n_plant, " planted per replicate, ", p$reps,
      " replicates, seed ", x$seed, "\n", sep = "")
  cat("  chance recall (effect 0): ", sprintf("%.2f", x$chance_recall), "\n", sep = "")
  for (i in seq_len(nrow(x$mde))) {
    m <- x$mde[i, ]
    cat("  n = ", m$n, ": ", if (is.na(m$mde))
      sprintf("recall never reached %.0f%% (max effect tested %.2f log2FC)",
              100 * p$target_recall, max(p$effects)) else
      sprintf("minimum detectable effect %.2f log2FC (%.2fx fold change)",
              m$mde, m$fold_change), "\n", sep = "")
  }
  if (x$failures) cat("  WARNING: pipeline failed in ", x$failures, " runs\n", sep = "")
  invisible(x)
}

#' @export
plot.audit_planted <- function(x, ...) {
  s <- x$summary; ns <- sort(unique(s$n)); cols <- seq_along(ns) + 1L
  graphics::plot(range(s$effect), c(0, 1), type = "n",
                 xlab = "Planted effect (log2 fold change)",
                 ylab = "Recall of planted features", ...)
  graphics::abline(h = x$params$target_recall, lty = 2, col = "grey40")
  graphics::abline(h = x$chance_recall, lty = 3, col = "grey70")
  for (i in seq_along(ns)) {
    d <- s[s$n == ns[i], ]
    graphics::lines(d$effect, d$recall, type = "b", pch = 16, col = cols[i])
  }
  at <- pretty(range(s$effect))
  graphics::axis(3, at = at, labels = sprintf("%.1fx", 2^at))
  graphics::mtext("fold change", 3, 2.2, cex = 0.8)
  if (length(ns) > 1) graphics::legend("bottomright", paste("n =", ns),
                                       col = cols, pch = 16, bty = "n")
  invisible(x)
}
