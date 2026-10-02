sim_small <- function(seed, ...) {
  simulate_omics(n = 80, p = 150, n_signal = 15, effect = 1.5, seed = seed, ...)
}

test_that("zoo lists and loads the first two entries", {
  skip_if_not_installed("yaml")
  expect_true(all(c("flawed_norm_before_cv", "reference_nested_cv") %in% zoo_list()))
  fl <- zoo_load("flawed_norm_before_cv")
  rf <- zoo_load("reference_nested_cv")
  expect_true(is.function(fl$pipeline))
  expect_false(fl$meta$is_reference)
  expect_true(rf$meta$is_reference)
  expect_true(fl$meta$expected_audit_outcome$flagged)
  expect_false(rf$meta$expected_audit_outcome$flagged)
  expect_error(zoo_load("nope"), "No zoo entry")
})

test_that("pipelines satisfy the black-box contract", {
  skip_if_not_installed("yaml")
  sim <- sim_small(1)
  for (nm in c("flawed_norm_before_cv", "reference_nested_cv")) {
    res <- zoo_load(nm)$pipeline(sim$X, sim$y)
    expect_named(res, c("selected", "performance"), ignore.order = TRUE)
    expect_type(res$selected, "character")
    expect_true(all(res$selected %in% colnames(sim$X)))
    expect_length(res$performance, 1)
    expect_gte(res$performance, 0); expect_lte(res$performance, 1)
  }
})

test_that("pipelines are deterministic given a seed and record no hidden state", {
  skip_if_not_installed("yaml")
  sim <- sim_small(2)
  p <- zoo_load("reference_nested_cv")$pipeline
  expect_identical(p(sim$X, sim$y, seed = 3), p(sim$X, sim$y, seed = 3))
})

test_that("flawed pipeline fits preprocessing on ALL rows; reference never does in CV", {
  skip_if_not_installed("yaml")
  sim <- sim_small(3)
  n <- nrow(sim$X)

  trace_prep <- function(name) {
    e <- zoo_load(name)
    calls <- integer()
    orig <- e$env$prep_fit
    assign("prep_fit", function(X) { calls <<- c(calls, nrow(X)); orig(X) },
           envir = e$env)
    e$pipeline(sim$X, sim$y)
    calls
  }

  fl <- trace_prep("flawed_norm_before_cv")
  expect_equal(fl, n)                       # one fit, on every sample

  rf <- trace_prep("reference_nested_cv")
  # all fits inside the performance estimate use strictly fewer rows;
  # only the last (final model for `selected`) sees all samples
  expect_true(all(head(rf, -1) < n))
  expect_equal(tail(rf, 1), n)
})

test_that("both pipelines select planted features and score high when signal is strong", {
  skip_if_not_installed("yaml")
  sim <- sim_small(4)
  for (nm in c("flawed_norm_before_cv", "reference_nested_cv")) {
    res <- zoo_load(nm)$pipeline(sim$X, sim$y)
    expect_gt(res$performance, 0.85)
    # The reference may pick a small, parsimonious set when inner-CV AUC
    # saturates, and the flawed one always picks 20 for 15 true features, so
    # score hits against the best achievable number rather than recall/precision.
    hits <- sum(res$selected %in% sim$truth$signal_features)
    expect_gt(hits / min(length(res$selected), 15), 0.9)
  }
})

test_that("reference pipeline is honest on null data (AUC ~ 0.5)", {
  skip_if_not_installed("yaml")
  skip_on_cran()
  p <- zoo_load("reference_nested_cv")$pipeline
  aucs <- vapply(1:12, function(s) {
    sim <- simulate_omics(n = 60, p = 200, n_signal = 0, seed = 100 + s)
    p(sim$X, sim$y)$performance
  }, numeric(1))
  expect_lt(abs(mean(aucs) - 0.5), 0.07)
})

test_that("reference pipeline survives a batch effect that is not confounded", {
  skip_if_not_installed("yaml")
  sim <- sim_small(5, batch_effect = 1)
  res <- zoo_load("reference_nested_cv")$pipeline(sim$X, sim$y)
  expect_gt(res$performance, 0.8)
})

test_that("median normalisation is skipped for small panels and applied for large ones", {
  skip_if_not_installed("yaml")
  h <- zoo_load("reference_nested_cv")$env
  small <- simulate_omics(n = 40, p = 10, n_signal = 2, seed = 1)$X
  large <- simulate_omics(n = 40, p = 150, n_signal = 2, seed = 1)$X
  expect_equal(h$prep_fit(small)$norm, "none")
  expect_equal(h$prep_fit(large)$norm, "median")
  expect_equal(h$prep_fit(small, norm = "median")$norm, "median")
})

test_that("a constant feature is not selected on a small panel", {
  skip_if_not_installed("yaml")
  sim <- simulate_omics(n = 120, p = 10, n_signal = 4, effect = 1.5, seed = 2)
  X <- sim$X; X[, c(1, 2)] <- 10
  res <- zoo_load("reference_nested_cv")$pipeline(X, sim$y)
  expect_false(any(colnames(X)[1:2] %in% res$selected))
})
