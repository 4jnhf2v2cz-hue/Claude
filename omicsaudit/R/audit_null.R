#' Shuffled-label (null) test through the whole pipeline
#'
#' Runs `pipeline` on the real data and on `n_perm` copies with the outcome
#' permuted. A leak-free pipeline scores at chance on permuted labels; a
#' pipeline whose estimate is optimistic on noise (selection before splitting,
#' tuning on test folds, subject leakage, ...) scores above chance.
#' With `groups`, labels are permuted at group level (e.g. per subject), which
#' is what exposes repeated-measures leakage.
#'
#' The audit is flagged when the mean permuted performance is above `chance`
#' by more than `tol` **and** the lower end of its one-sided 99% confidence
#' interval is also above `chance`.
#'
#' This is a thin wrapper. `bioLeak` offers label-permutation diagnostics for
#' pipelines built in its own format; `audit_null` works with any black-box
#' function but is not a replacement for it. (No `bioLeak` call is wired in yet.)
#'
#' @inheritParams audit_planted
#' @param groups Optional vector of group ids (e.g. subject) for grouped
#'   permutation.
#' @param n_perm Number of permutations (5 in quick mode).
#' @param chance Performance expected from a useless model (0.5 for AUC).
#' @param tol Minimum excess over `chance` to flag.
#' @return Object of class `audit_null` with `observed`, `null` (vector),
#'   `p_value`, `flagged`, `evidence` and `seed`.
#' @export
audit_null <- function(pipeline, X, y, groups = NULL, n_perm = 20, chance = 0.5,
                       tol = 0.05, quick = FALSE, cores = 1,
                       progress = FALSE, seed = 1L) {
  stopifnot(is.function(pipeline), is.matrix(X), length(y) == nrow(X))
  if (quick) n_perm <- 5
  obs <- as.numeric(pipeline(X, y)$performance)[1]
  pb <- if (progress) utils::txtProgressBar(0, n_perm, style = 3) else NULL
  nul <- unlist(par_lapply(seq_len(n_perm), function(i) {
    v <- with_seed(seed + i, {
      yp <- permute_labels(y, groups)
      tryCatch(as.numeric(pipeline(X, yp)$performance)[1], error = function(e) NA_real_)
    })
    if (!is.null(pb)) utils::setTxtProgressBar(pb, i)
    v
  }, cores))
  if (!is.null(pb)) close(pb)
  ok <- nul[!is.na(nul)]
  m <- mean(ok); se <- stats::sd(ok) / sqrt(length(ok))
  lower <- m - stats::qt(0.99, max(1, length(ok) - 1)) * se
  flagged <- length(ok) >= 3 && (m - chance) > tol && lower > chance
  structure(list(
    observed = obs, null = nul, null_mean = m, null_sd = stats::sd(ok),
    p_value = (1 + sum(ok >= obs)) / (1 + length(ok)),
    flagged = flagged,
    evidence = sprintf(
      "Mean performance with shuffled labels was %.3f (chance %.2f); real labels gave %.3f.%s",
      m, chance, obs,
      if (flagged) " Performance on pure noise is above chance: the pipeline's estimate is optimistic (leakage or selection on evaluation data)." else ""),
    params = list(n_perm = n_perm, chance = chance, tol = tol, grouped = !is.null(groups)),
    seed = seed), class = "audit_null")
}

#' @export
print.audit_null <- function(x, ...) {
  cat("<audit_null> ", if (x$flagged) "FLAGGED" else "pass", " (seed ", x$seed, ")\n  ",
      x$evidence, "\n", sep = "")
  invisible(x)
}

#' @export
plot.audit_null <- function(x, ...) {
  graphics::hist(x$null, main = "Performance with shuffled labels",
                 xlab = "performance", xlim = range(c(x$null, x$observed, x$params$chance), na.rm = TRUE), ...)
  graphics::abline(v = x$observed, col = 2, lwd = 2)
  graphics::abline(v = x$params$chance, lty = 2)
  graphics::legend("topright", c("real labels", "chance"), col = c(2, 1), lty = c(1, 2), bty = "n")
  invisible(x)
}
