#' Simulate an omics dataset with known ground truth
#'
#' Generates a raw (linear-scale, pre-preprocessing) samples x features
#' intensity matrix with three controlled ingredients:
#'
#' * **Planted signal**: `n_signal` features shift by `effect` (log2 fold
#'   change) between class 1 and class 0, with random direction.
#' * **Batch effect**: each feature gets a batch-specific log2 shift drawn
#'   from `N(0, batch_effect^2)`, plus a per-sample size factor that
#'   normalisation is supposed to remove. `batch_confound` controls how
#'   strongly batch is tied to the outcome.
#' * **MNAR missingness**: the probability that a value is missing falls
#'   with its (log2) abundance via a logistic curve, so low-abundance values
#'   go missing more often. The intercept is calibrated so the overall
#'   missing fraction equals `missing_rate`.
#'
#' Missingness is applied *after* signal and batch effects, i.e. it depends
#' on the final observed abundance, not on the class label.
#'
#' @param n Number of samples.
#' @param p Number of features.
#' @param n_signal Number of planted (truly differential) features.
#' @param effect Planted effect size in log2 fold change (class 1 vs 0).
#' @param prevalence Fraction of samples in class 1.
#' @param n_batches Number of batches.
#' @param batch_effect SD (log2 units) of the per-feature batch shift.
#'   `0` removes the batch effect.
#' @param batch_confound Value in `[0, 1]`. `0`: batch independent of outcome.
#'   `1`: batch fully determined by outcome (only meaningful for
#'   `n_batches = 2`; for more batches, class 1 samples are weighted towards
#'   the higher-numbered batches).
#' @param noise_sd Residual SD (log2 units); a single value or a range
#'   `c(min, max)` from which per-feature SDs are drawn uniformly.
#' @param missing_rate Target overall fraction of missing values.
#' @param mnar_slope Steepness of the missingness curve per log2 unit
#'   (larger = more strongly abundance-dependent). `0` gives MCAR.
#' @param seed Integer seed. Recorded in the output. The caller's RNG state
#'   is left unchanged.
#'
#' @return An object of class `omics_sim`, a list with
#' \describe{
#'   \item{`X`}{Raw intensities, samples x features, with `NA` for missing.}
#'   \item{`y`}{Integer outcome, 0/1.}
#'   \item{`batch`}{Factor of batch labels.}
#'   \item{`truth`}{List: `signal_features` (character), `effect`
#'     (named signed log2FC per signal feature).}
#'   \item{`log2_complete`}{log2 intensities before missingness was applied.}
#'   \item{`missing`}{Logical matrix of the missingness mask.}
#'   \item{`params`}{All arguments, including `seed`.}
#' }
#' @examples
#' sim <- simulate_omics(n = 60, p = 100, n_signal = 10, seed = 1)
#' sim
#' @export
simulate_omics <- function(n = 100, p = 500, n_signal = 25, effect = 1,
                           prevalence = 0.5, n_batches = 2,
                           batch_effect = 0.5, batch_confound = 0,
                           noise_sd = c(0.3, 0.8), missing_rate = 0.2,
                           mnar_slope = 1, seed = 1L) {
  stopifnot(
    n >= 4, p >= 1, n_signal >= 0, n_signal <= p,
    prevalence > 0, prevalence < 1,
    n_batches >= 1, batch_effect >= 0,
    batch_confound >= 0, batch_confound <= 1,
    all(noise_sd > 0), length(noise_sd) %in% 1:2,
    missing_rate >= 0, missing_rate < 1, mnar_slope >= 0
  )
  params <- as.list(environment())

  with_seed(seed, {
    feat <- sprintf("feat%0*d", nchar(p), seq_len(p))
    samp <- sprintf("samp%0*d", nchar(n), seq_len(n))

    # Outcome: fixed class counts so prevalence is exact
    n1 <- max(1L, min(n - 1L, round(n * prevalence)))
    y <- sample(rep(c(0L, 1L), c(n - n1, n1)))

    # Batch: with probability batch_confound the batch is set by the outcome,
    # otherwise it is drawn uniformly
    batch_free <- sample.int(n_batches, n, replace = TRUE)
    batch_from_y <- if (n_batches == 1) rep(1L, n) else
      ifelse(y == 1L, n_batches, 1L)
    use_y <- stats::runif(n) < batch_confound
    batch <- factor(ifelse(use_y, batch_from_y, batch_free),
                    levels = seq_len(n_batches))

    # Feature means (log2 scale) and per-feature noise
    mu <- stats::rnorm(p, mean = 22, sd = 2)
    sd_j <- if (length(noise_sd) == 1) rep(noise_sd, p) else
      stats::runif(p, noise_sd[1], noise_sd[2])

    # Planted signal
    signal_idx <- sort(sample.int(p, n_signal))
    delta <- numeric(p)
    delta[signal_idx] <- effect * sample(c(-1, 1), n_signal, replace = TRUE)

    # Batch shifts (per batch x feature) and per-sample size factors
    batch_shift <- matrix(stats::rnorm(n_batches * p, 0, batch_effect),
                          n_batches, p)
    size_factor <- stats::rnorm(n, 0, 0.5)

    L <- matrix(mu, n, p, byrow = TRUE) +
      outer(y, delta) +
      batch_shift[as.integer(batch), , drop = FALSE] +
      matrix(size_factor, n, p) +
      matrix(stats::rnorm(n * p), n, p) * matrix(sd_j, n, p, byrow = TRUE)
    dimnames(L) <- list(samp, feat)

    # MNAR mask: P(missing) = plogis(a - slope * (L - median(L))),
    # with `a` calibrated to hit the target overall rate
    miss <- matrix(FALSE, n, p, dimnames = dimnames(L))
    if (missing_rate > 0) {
      z <- L - stats::median(L)
      a <- if (mnar_slope == 0) stats::qlogis(missing_rate) else
        stats::uniroot(function(a) mean(stats::plogis(a - mnar_slope * z)) -
                         missing_rate, c(-50, 50))$root
      pm <- stats::plogis(a - mnar_slope * z)
      miss[] <- matrix(stats::runif(n * p), n, p) < pm
    }

    X <- 2^L
    X[miss] <- NA_real_

    structure(
      list(
        X = X, y = y, batch = batch,
        truth = list(
          signal_features = feat[signal_idx],
          effect = stats::setNames(delta[signal_idx], feat[signal_idx])
        ),
        log2_complete = L, missing = miss,
        params = params
      ),
      class = "omics_sim"
    )
  })
}

#' @export
print.omics_sim <- function(x, ...) {
  p <- x$params
  cat("<omics_sim> ", nrow(x$X), " samples x ", ncol(x$X), " features\n", sep = "")
  cat("  outcome : ", sum(x$y == 1L), " class 1 / ", sum(x$y == 0L),
      " class 0\n", sep = "")
  cat("  signal  : ", length(x$truth$signal_features), " planted features, ",
      "|log2FC| = ", format(p$effect), "\n", sep = "")
  cat("  batch   : ", nlevels(x$batch), " batches, shift SD ",
      format(p$batch_effect), ", confound ", format(p$batch_confound), "\n",
      sep = "")
  cat("  missing : ", sprintf("%.1f%%", 100 * mean(x$missing)),
      " (MNAR slope ", format(p$mnar_slope), ")\n", sep = "")
  cat("  seed    : ", format(p$seed), "\n", sep = "")
  invisible(x)
}

#' @export
plot.omics_sim <- function(x, ...) {
  op <- graphics::par(mfrow = c(1, 2))
  on.exit(graphics::par(op))
  obs <- x$log2_complete[!x$missing]
  mis <- x$log2_complete[x$missing]
  graphics::plot(stats::density(obs), main = "Abundance by missingness",
                 xlab = "log2 intensity (complete data)", ...)
  graphics::lines(stats::density(mis), lty = 2)
  graphics::legend("topright", c("observed", "missing"), lty = 1:2, bty = "n")
  pc <- stats::prcomp(x$log2_complete, scale. = TRUE)$x[, 1:2]
  graphics::plot(pc, col = as.integer(x$batch) + 1L, pch = 1 + x$y,
                 main = "PCA: colour = batch, shape = outcome")
  invisible(x)
}
