#' Stability of the selected features under resampling
#'
#' Repeatedly drops a fraction of the samples (stratified), reruns the
#' pipeline, and measures the agreement of `selected` between runs as the mean
#' pairwise Jaccard index. Low agreement means the feature list is not
#' reproducible; it does not by itself indicate leakage, so it is reported
#' as evidence but does not drive the standard flag.
#'
#' @inheritParams audit_planted
#' @param n_runs Number of subsamples (4 in quick mode).
#' @param keep Fraction of samples kept in each run.
#' @param min_jaccard Mean Jaccard below which the check is flagged.
#' @return Object of class `audit_stability` with `jaccard` (mean),
#'   `pairwise`, `frequency` (selection frequency per feature), `flagged`.
#' @export
audit_stability <- function(pipeline, X, y, n_runs = 10, keep = 0.8,
                            min_jaccard = 0.5, quick = FALSE, cores = 1,
                            seed = 1L) {
  stopifnot(is.function(pipeline), is.matrix(X), length(y) == nrow(X))
  if (quick) n_runs <- 4
  sels <- par_lapply(seq_len(n_runs), function(i) with_seed(seed + i, {
    idx <- stratified_subsample(y, max(10L, round(keep * length(y))))
    tryCatch(as.character(pipeline(X[idx, , drop = FALSE], y[idx])$selected),
             error = function(e) character())
  }), cores)
  jac <- function(a, b) if (!length(a) && !length(b)) NA_real_ else
    length(intersect(a, b)) / length(union(a, b))
  pw <- utils::combn(seq_along(sels), 2, function(ij) jac(sels[[ij[1]]], sels[[ij[2]]]))
  j <- mean(pw, na.rm = TRUE)
  freq <- sort(table(factor(unlist(sels), levels = colnames(X))) / n_runs, decreasing = TRUE)
  freq <- freq[freq > 0]
  structure(list(
    jaccard = j, pairwise = pw, frequency = freq,
    flagged = is.finite(j) && j < min_jaccard,
    evidence = sprintf("Mean Jaccard agreement of selected features across %d resamples (%.0f%% of samples kept): %.2f.",
                       n_runs, 100 * keep, j),
    params = list(n_runs = n_runs, keep = keep, min_jaccard = min_jaccard),
    seed = seed), class = "audit_stability")
}

#' @export
print.audit_stability <- function(x, ...) {
  cat("<audit_stability> ", if (x$flagged) "FLAGGED" else "pass", " (seed ", x$seed, ")\n  ",
      x$evidence, "\n", sep = "")
  invisible(x)
}

#' @export
plot.audit_stability <- function(x, ...) {
  f <- utils::head(x$frequency, 20)
  graphics::barplot(rev(as.numeric(f)), names.arg = rev(names(f)), horiz = TRUE, las = 1,
                    xlim = c(0, 1), xlab = "selection frequency", main = "Feature stability", ...)
  invisible(x)
}
