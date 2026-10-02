#' Example variant pipeline (normalisation / imputation / filtering choices)
#'
#' A small, fully transparent pipeline used to demonstrate [audit_variants()]:
#' log2, optional sample normalisation, filtering on missingness, imputation,
#' then top-`k` features by |t|; performance is the cross-validated AUC of a
#' diagonal-LDA classifier with preprocessing fitted in-fold.
#'
#' @param norm `"none"` or `"median"` (per-sample median centring).
#' @param impute `"min"` (left-censored, feature minimum) or `"median"`.
#' @param max_missing Drop features with a higher missing fraction.
#' @param k Number of features to select.
#' @return A function `pipeline(X, y)`.
#' @export
variant_pipeline <- function(norm = c("none", "median"), impute = c("min", "median"),
                             max_missing = 1, k = 10) {
  norm <- match.arg(norm); impute <- match.arg(impute)
  function(X, y) {
    keep <- colMeans(is.na(X)) <= max_missing
    L <- log2(X[, keep, drop = FALSE])
    if (norm == "median") L <- sweep(L, 1, apply(L, 1, stats::median, na.rm = TRUE), "-")
    fill <- apply(L, 2, function(v) if (impute == "min") min(v, na.rm = TRUE) else stats::median(v, na.rm = TRUE))
    fill[!is.finite(fill)] <- 0
    idx <- which(is.na(L), arr.ind = TRUE)
    L[idx] <- fill[idx[, 2]]
    sd_j <- pmax(apply(L, 2, stats::sd), 1e-8)
    Z <- sweep(sweep(L, 2, colMeans(L), "-"), 2, sd_j, "/")
    h <- zoo_helpers()
    sel <- h$top_features(Z, y, k)
    perf <- with_seed(1, h$cv_auc(Z, y, stratified_folds(y, 5), k, prep = FALSE))
    list(selected = colnames(Z)[sel], performance = perf)
  }
}

#' Decision attribution across defensible pipeline variants
#'
#' Runs every variant on the same data and reports (a) the share of variants
#' that select each feature and (b) which analysis decision changes the
#' selected set most. Attribution compares pairs of variants that differ in
#' exactly one decision (other decisions equal) and averages
#' `1 - Jaccard` of their selected sets and the absolute change in performance.
#'
#' @param variants Named list of pipeline functions.
#' @param X,y Data as in [audit_planted()].
#' @param design Data frame with one row per variant (same order) and one
#'   column per decision, e.g. from [variant_grid()]. Without it, only the
#'   selection shares are computed.
#' @param stable_share Share above which a feature counts as "robust".
#' @param cores Parallel workers (forked; ignored on Windows).
#' @param seed Recorded in the output.
#' @return Object of class `audit_variants`.
#' @export
audit_variants <- function(variants, X, y, design = NULL, stable_share = 0.8,
                           cores = 1, seed = 1L) {
  stopifnot(is.list(variants), length(variants) >= 2, is.matrix(X))
  if (is.null(names(variants))) names(variants) <- paste0("v", seq_along(variants))
  if (!is.null(design)) stopifnot(nrow(design) == length(variants))
  res <- par_lapply(variants, function(f) with_seed(seed, f(X, y)), cores)
  sel <- lapply(res, function(r) as.character(r$selected))
  perf <- vapply(res, function(r) as.numeric(r$performance)[1], numeric(1))
  all_f <- sort(unique(unlist(sel)))
  share <- vapply(all_f, function(f) mean(vapply(sel, function(s) f %in% s, logical(1))), numeric(1))
  share <- sort(share, decreasing = TRUE)
  jac <- function(a, b) length(intersect(a, b)) / max(1, length(union(a, b)))
  attribution <- NULL
  if (!is.null(design)) {
    dec <- names(design)
    attribution <- do.call(rbind, lapply(dec, function(d) {
      others <- setdiff(dec, d); dj <- c(); dp <- c()
      for (i in seq_len(nrow(design))) for (j in seq_len(nrow(design))) {
        if (i < j && design[i, d] != design[j, d] &&
            all(unlist(design[i, others]) == unlist(design[j, others]))) {
          dj <- c(dj, 1 - jac(sel[[i]], sel[[j]])); dp <- c(dp, abs(perf[i] - perf[j]))
        }
      }
      data.frame(decision = d,
                 mean_selection_change = if (length(dj)) mean(dj) else NA_real_,
                 mean_performance_change = if (length(dp)) mean(dp) else NA_real_,
                 n_pairs = length(dj))
    }))
    attribution <- attribution[order(-attribution$mean_selection_change, na.last = TRUE), ]
    rownames(attribution) <- NULL
  }
  structure(list(
    selection_share = share, performance = perf, selected = sel,
    robust = names(share)[share >= stable_share], attribution = attribution,
    design = design,
    evidence = sprintf("%d variants; %d features selected by >= %.0f%% of variants%s; performance ranged %.2f to %.2f.",
                       length(variants), sum(share >= stable_share), 100 * stable_share,
                       if (!is.null(attribution) && nrow(attribution)) sprintf("; the decision that most changes the selected set is '%s'", attribution$decision[1]) else "",
                       min(perf, na.rm = TRUE), max(perf, na.rm = TRUE)),
    seed = seed), class = "audit_variants")
}

#' Build all combinations of decisions for a pipeline factory
#'
#' @param factory Function taking the decisions as named arguments and
#'   returning a pipeline, e.g. [variant_pipeline()].
#' @param ... Named vectors of options for each decision.
#' @return List with `variants` (named list of pipelines) and `design`
#'   (data frame of decisions), ready for [audit_variants()].
#' @export
variant_grid <- function(factory, ...) {
  design <- expand.grid(..., stringsAsFactors = FALSE)
  variants <- lapply(seq_len(nrow(design)), function(i) do.call(factory, as.list(design[i, , drop = FALSE])))
  names(variants) <- apply(design, 1, function(r) paste(names(design), r, sep = "=", collapse = ","))
  list(variants = variants, design = design)
}

#' @export
print.audit_variants <- function(x, ...) {
  cat("<audit_variants> (seed ", x$seed, ")\n  ", x$evidence, "\n", sep = "")
  if (!is.null(x$attribution)) { cat("\n"); print(x$attribution, row.names = FALSE) }
  invisible(x)
}

#' @export
plot.audit_variants <- function(x, ...) {
  f <- utils::head(x$selection_share, 20)
  graphics::barplot(rev(as.numeric(f)), names.arg = rev(names(f)), horiz = TRUE, las = 1,
                    xlim = c(0, 1), xlab = "share of variants selecting feature",
                    main = "Robustness to analysis decisions", ...)
  invisible(x)
}
