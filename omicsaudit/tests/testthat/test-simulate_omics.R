test_that("output has the documented structure and dimensions", {
  sim <- simulate_omics(n = 60, p = 120, n_signal = 10, seed = 1)
  expect_s3_class(sim, "omics_sim")
  expect_equal(dim(sim$X), c(60, 120))
  expect_true(all(sim$X > 0, na.rm = TRUE))
  expect_setequal(sim$y, c(0L, 1L))
  expect_equal(length(sim$batch), 60)
  expect_length(sim$truth$signal_features, 10)
  expect_true(all(sim$truth$signal_features %in% colnames(sim$X)))
  expect_equal(sim$params$seed, 1)
  expect_output(print(sim), "omics_sim")
})

test_that("same seed reproduces, different seed differs, caller RNG untouched", {
  a <- simulate_omics(n = 40, p = 50, seed = 7)
  b <- simulate_omics(n = 40, p = 50, seed = 7)
  c <- simulate_omics(n = 40, p = 50, seed = 8)
  expect_identical(a$X, b$X)
  expect_false(identical(a$X, c$X))

  set.seed(99); r1 <- runif(1)
  set.seed(99); invisible(simulate_omics(n = 40, p = 50, seed = 7)); r2 <- runif(1)
  expect_equal(r1, r2)
})

test_that("planted features differ between classes by about the planted effect", {
  sim <- simulate_omics(n = 400, p = 200, n_signal = 20, effect = 1.5,
                        batch_effect = 0, missing_rate = 0, seed = 2)
  L <- sim$log2_complete
  d <- colMeans(L[sim$y == 1, ]) - colMeans(L[sim$y == 0, ])
  sig <- sim$truth$signal_features
  expect_equal(unname(d[sig]), unname(sim$truth$effect), tolerance = 0.25)
  expect_lt(max(abs(d[setdiff(colnames(L), sig)])), 0.4)
  expect_true(all(sign(d[sig]) == sign(sim$truth$effect)))
})

test_that("planted effect is zero when n_signal = 0 or effect = 0", {
  sim <- simulate_omics(n = 300, p = 100, n_signal = 0, batch_effect = 0,
                        missing_rate = 0, seed = 3)
  d <- colMeans(sim$log2_complete[sim$y == 1, ]) -
    colMeans(sim$log2_complete[sim$y == 0, ])
  expect_lt(max(abs(d)), 0.5)
  expect_length(sim$truth$signal_features, 0)
})

test_that("batch effect is present, and absent when batch_effect = 0", {
  batch_sd <- function(be) {
    sim <- simulate_omics(n = 300, p = 200, n_signal = 0, batch_effect = be,
                          missing_rate = 0, seed = 4)
    L <- sim$log2_complete
    d <- colMeans(L[sim$batch == 2, ]) - colMeans(L[sim$batch == 1, ])
    sd(d)
  }
  expect_gt(batch_sd(1), 0.8)
  expect_lt(batch_sd(0), 0.2)
})

test_that("batch_confound controls the batch-outcome association", {
  tab_cor <- function(bc) {
    sim <- simulate_omics(n = 400, p = 20, n_signal = 5, batch_confound = bc, seed = 5)
    abs(cor(sim$y, as.integer(sim$batch)))
  }
  expect_lt(tab_cor(0), 0.2)
  expect_gt(tab_cor(1), 0.99)
  expect_gt(tab_cor(0.5), tab_cor(0))
})

test_that("overall missing rate hits the target", {
  for (r in c(0.1, 0.3)) {
    sim <- simulate_omics(n = 100, p = 300, missing_rate = r, seed = 6)
    expect_equal(mean(is.na(sim$X)), r, tolerance = 0.1)
    expect_identical(is.na(sim$X), sim$missing)
  }
  sim0 <- simulate_omics(n = 50, p = 50, missing_rate = 0, seed = 6)
  expect_false(anyNA(sim0$X))
})

test_that("missingness is MNAR: low-abundance values go missing more often", {
  sim <- simulate_omics(n = 100, p = 300, missing_rate = 0.25,
                        mnar_slope = 1, seed = 8)
  L <- sim$log2_complete
  expect_lt(mean(L[sim$missing]), mean(L[!sim$missing]) - 1)

  # missing rate falls monotonically across abundance quartiles
  q <- cut(L, quantile(L, 0:4 / 4), include.lowest = TRUE)
  rate <- tapply(sim$missing, q, mean)
  expect_true(all(diff(rate) < 0))
})

test_that("mnar_slope = 0 gives MCAR", {
  sim <- simulate_omics(n = 100, p = 300, missing_rate = 0.25,
                        mnar_slope = 0, seed = 9)
  L <- sim$log2_complete
  expect_lt(abs(mean(L[sim$missing]) - mean(L[!sim$missing])), 0.1)
})

test_that("missingness depends on abundance, not on the class label", {
  sim <- simulate_omics(n = 300, p = 200, n_signal = 0, missing_rate = 0.2,
                        seed = 10)
  r1 <- mean(sim$missing[sim$y == 1, ])
  r0 <- mean(sim$missing[sim$y == 0, ])
  expect_lt(abs(r1 - r0), 0.02)
})

test_that("invalid arguments are rejected", {
  expect_error(simulate_omics(n_signal = 1000, p = 10))
  expect_error(simulate_omics(missing_rate = 1))
  expect_error(simulate_omics(batch_confound = 2))
})
