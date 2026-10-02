#' Standard black-box audit
#'
#' Runs the checks that apply to the supplied inputs: [audit_null()] always,
#' [audit_confound()] when `batch` is given, [audit_stability()] as evidence.
#' The audit is flagged if the null test or the confounding check is flagged;
#' stability is reported but does not drive the flag, because instability is
#' not itself a flaw in the estimate.
#'
#' This is the default `audit_fn` for [zoo_score()]. Any function with the
#' same signature that returns something with a logical `flagged` can be
#' benchmarked instead.
#'
#' @inheritParams audit_planted
#' @param batch Optional batch/site/run vector.
#' @param groups Optional subject ids for grouped permutation.
#' @param stability Also run [audit_stability()].
#' @param ... Passed to [audit_null()].
#' @return Object of class `audit_standard` with `checks` (a table), `flagged`,
#'   the individual check objects and `seed`.
#' @export
audit_standard <- function(pipeline, X, y, batch = NULL, groups = NULL,
                           quick = FALSE, stability = TRUE, cores = 1, seed = 1L, ...) {
  check_omics_input(X, y)
  parts <- list(null = audit_null(pipeline, X, y, groups = groups, quick = quick,
                                  cores = cores, seed = seed, ...))
  if (!is.null(batch)) parts$confound <- audit_confound(X, y, batch, seed = seed)
  if (stability) parts$stability <- audit_stability(pipeline, X, y, groups = groups, quick = quick,
                                                    cores = cores, seed = seed)
  checks <- data.frame(
    check = names(parts),
    flagged = vapply(parts, function(p) p$flagged, logical(1)),
    drives_verdict = names(parts) != "stability",
    evidence = vapply(parts, function(p) p$evidence, character(1)),
    row.names = NULL)
  structure(c(parts, list(checks = checks,
                          flagged = any(checks$flagged[checks$drives_verdict]),
                          seed = seed)), class = "audit_standard")
}

#' @export
print.audit_standard <- function(x, ...) {
  cat("<audit_standard> verdict: ", if (x$flagged) "FLAGGED" else "no problem found",
      " (seed ", x$seed, ")\n", sep = "")
  for (i in seq_len(nrow(x$checks)))
    cat(sprintf("  [%s] %-9s %s\n", if (x$checks$flagged[i]) "FLAG" else " ok ",
                x$checks$check[i], x$checks$evidence[i]))
  invisible(x)
}

#' @export
plot.audit_standard <- function(x, ...) {
  op <- graphics::par(mfrow = c(1, length(x$checks$check))); on.exit(graphics::par(op))
  for (nm in x$checks$check) plot(x[[nm]], ...)
  invisible(x)
}
