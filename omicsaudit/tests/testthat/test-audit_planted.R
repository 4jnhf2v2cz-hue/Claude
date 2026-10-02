# A cheap black-box pipeline: top-k features by |t| on log2 data
top_k <- function(k = 5) function(X, y) {
  t <- abs(apply(log2(X), 2, function(v) {
    v1 <- v[y == 1]; v0 <- v[y == 0]
    (mean(v1, na.rm = TRUE) - mean(v0, na.rm = TRUE)) /
      sqrt(var(v1, na.rm = TRUE) / sum(!is.na(v1)) + var(v0, na.rm = TRUE) / sum(!is.na(v0)))
  }))
  list(selected = names(sort(t, decreasing = TRUE))[seq_len(k)], performance = NA_real_)
}
sim <- simulate_omics(n = 80, p = 60, n_signal = 0, seed = 1)

test_that("plant_signal shifts only class-1 observed cells of planted features", {
  f <- colnames(sim$X)[1:3]
  Xp <- plant_signal(sim$X, sim$y, f, 1)
  # missingness mask identical: nothing masked or unmasked
  expect_identical(is.na(Xp), is.na(sim$X))
  # unplanted columns and class-0 rows untouched
  expect_identical(Xp[, -(1:3)], sim$X[, -(1:3)])
  expect_identical(Xp[sim$y == 0, ], sim$X[sim$y == 0, ])
  # planted cells are exactly doubled (effect 1 = one doubling)
  expect_equal(Xp[sim$y == 1, f], sim$X[sim$y == 1, f] * 2)
})

test_that("planting does not distort the missingness pattern of the data", {
  f <- colnames(sim$X)[1:10]
  Xp <- plant_signal(sim$X, sim$y, f, 2)
  expect_equal(colMeans(is.na(Xp)), colMeans(is.na(sim$X)))
  expect_equal(mean(is.na(Xp[sim$y == 1, f])), mean(is.na(sim$X[sim$y == 1, f])))
})

test_that("recall rises with effect size and an MDE is found", {
  a <- audit_planted(top_k(5), sim$X, sim$y, effects = c(0, 0.5, 1, 2, 3),
                     n_plant = 3, reps = 15, progress = FALSE, seed = 2)
  expect_s3_class(a, "audit_planted")
  r <- a$summary$recall
  expect_lt(r[1], 0.3)                  # chance level
  expect_gt(r[length(r)], 0.9)          # huge effect is found
  expect_true(all(diff(r) > -0.1))      # roughly monotone
  expect_true(is.finite(a$mde$mde))
  expect_equal(a$mde$fold_change, 2^a$mde$mde)
  expect_output(print(a), "minimum detectable effect")
})

test_that("recall at effect 0 is near chance", {
  a <- audit_planted(top_k(6), sim$X, sim$y, effects = 0, n_plant = 3,
                     reps = 60, progress = FALSE, seed = 3)
  # chance recall = k / p = 6 / 60
  expect_lt(abs(a$chance_recall - 0.1), 0.08)
})

test_that("seed is recorded, reproducible, and caller RNG untouched", {
  args <- list(top_k(5), sim$X, sim$y, quick = TRUE, progress = FALSE, seed = 4)
  a <- do.call(audit_planted, args); b <- do.call(audit_planted, args)
  expect_equal(a$seed, 4)
  expect_identical(a$results, b$results)
  set.seed(1); r1 <- runif(1)
  set.seed(1); do.call(audit_planted, args); r2 <- runif(1)
  expect_equal(r1, r2)
})

test_that("a pipeline that ignores the data is flagged as never detecting", {
  blind <- function(X, y) list(selected = colnames(X)[1:3], performance = 0.5)
  a <- audit_planted(blind, sim$X, sim$y, effects = c(0, 1, 3), n_plant = 3,
                     reps = 10, progress = FALSE, seed = 5)
  expect_true(is.na(a$mde$mde))
  expect_output(print(a), "never reached")
})

test_that("pipeline errors are counted, not fatal", {
  bad <- function(X, y) stop("boom")
  a <- audit_planted(bad, sim$X, sim$y, effects = c(0, 1), reps = 2,
                     progress = FALSE, seed = 6)
  expect_equal(a$failures, nrow(a$results))
})

test_that("find_mde interpolates, and handles never/always", {
  expect_equal(find_mde(c(0, 1, 2), c(0, 0.5, 1), 0.75), 1.5)
  expect_true(is.na(find_mde(c(0, 1), c(0, 0.2), 0.8)))
  expect_equal(find_mde(c(0.5, 1), c(0.9, 1), 0.8), 0.5)
})

test_that("n_grid gives a curve per n; larger n detects smaller effects", {
  big <- simulate_omics(n = 160, p = 60, n_signal = 0, seed = 7)
  a <- audit_planted(top_k(5), big$X, big$y, effects = c(0, 0.5, 1, 1.5, 2, 3),
                     n_plant = 3, reps = 15, n_grid = c(40, 160),
                     progress = FALSE, seed = 7)
  expect_equal(nrow(a$mde), 2)
  expect_lt(a$mde$mde[a$mde$n == 160], a$mde$mde[a$mde$n == 40])
  need <- samples_needed(a, effect = a$mde$mde[a$mde$n == 160] / 2)
  expect_gt(need, 160)                  # detecting a smaller effect needs more n
  expect_error(samples_needed(a, -1))
})

test_that("works with a zoo pipeline", {
  skip_if_not_installed("yaml")
  small <- simulate_omics(n = 60, p = 30, n_signal = 0, seed = 8)
  p <- zoo_load("reference_nested_cv")$pipeline
  a <- audit_planted(p, small$X, small$y, effects = c(0, 2), n_plant = 3,
                     reps = 2, progress = FALSE, seed = 8)
  expect_equal(a$failures, 0)
  expect_true(all(a$results$performance >= 0 & a$results$performance <= 1))
})
