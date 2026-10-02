top_k <- function(k = 5) function(X, y) {
  L <- log2(X); L[is.na(L)] <- min(L, na.rm = TRUE)
  t <- abs(apply(L, 2, function(v) (mean(v[y == 1]) - mean(v[y == 0])) /
                   sqrt(var(v[y == 1]) / sum(y == 1) + var(v[y == 0]) / sum(y == 0))))
  list(selected = names(sort(t, decreasing = TRUE))[seq_len(k)], performance = 0.5)
}

# audit_null ------------------------------------------------------------------
test_that("audit_null flags a pipeline that scores above chance on shuffled labels", {
  leaky <- function(X, y) list(selected = "a", performance = 0.5 + runif(1, 0.15, 0.25))
  a <- audit_null(leaky, matrix(1, 20, 3), rep(0:1, 10), n_perm = 10, seed = 1)
  expect_true(a$flagged)
  expect_output(print(a), "FLAGGED")
})

test_that("audit_null passes a pipeline at chance", {
  fair <- function(X, y) list(selected = "a", performance = 0.5 + rnorm(1, 0, 0.03))
  a <- audit_null(fair, matrix(1, 20, 3), rep(0:1, 10), n_perm = 15, seed = 2)
  expect_false(a$flagged)
  expect_equal(a$seed, 2)
})

test_that("audit_null permutes at group level when groups are given", {
  seen <- list()
  spy <- function(X, y) { seen[[length(seen) + 1]] <<- y; list(selected = "a", performance = 0.5) }
  g <- rep(1:6, each = 4); y <- rep(c(0, 1), 12)[0]; y <- rep(c(0, 1, 0, 1, 0, 1), each = 4)
  audit_null(spy, matrix(1, 24, 2), y, groups = g, n_perm = 5, seed = 3)
  expect_true(all(vapply(seen[-1], function(v) all(tapply(v, g, function(z) length(unique(z))) == 1), logical(1))))
})

test_that("audit_null is reproducible", {
  s <- simulate_omics(n = 40, p = 30, seed = 1)
  a <- audit_null(top_k(), s$X, s$y, n_perm = 5, seed = 4)
  b <- audit_null(top_k(), s$X, s$y, n_perm = 5, seed = 4)
  expect_identical(a$null, b$null)
})

# audit_confound --------------------------------------------------------------
test_that("audit_confound flags confounded batch, not merely visible batch", {
  conf <- simulate_omics(n = 80, p = 60, n_signal = 0, batch_effect = 1.5, batch_confound = 1, seed = 1)
  free <- simulate_omics(n = 80, p = 60, n_signal = 5, batch_effect = 1.5, batch_confound = 0, seed = 1)
  a <- audit_confound(conf$X, conf$y, conf$batch)
  b <- audit_confound(free$X, free$y, free$batch)
  expect_true(a$flagged)
  expect_gt(a$cramers_v, 0.9)
  expect_false(b$flagged)
  expect_gt(b$auc_batch, 0.9)     # batch is plainly visible in the features...
  expect_lt(b$cramers_v, 0.3)     # ...but is not tied to the outcome
  expect_output(print(a), "confounded")
})

test_that("audit_confound handles a single batch and multi-level batches", {
  s <- simulate_omics(n = 60, p = 30, n_batches = 1, seed = 2)
  expect_false(audit_confound(s$X, s$y, s$batch)$flagged)
  s3 <- simulate_omics(n = 90, p = 30, n_batches = 3, seed = 2)
  expect_true(is.finite(audit_confound(s3$X, s3$y, s3$batch)$auc_batch))
})

# audit_stability -------------------------------------------------------------
test_that("audit_stability: stable selector vs random selector", {
  s <- simulate_omics(n = 80, p = 60, n_signal = 8, effect = 2, seed = 3)
  stable <- audit_stability(top_k(5), s$X, s$y, n_runs = 6, seed = 1)
  rnd <- function(X, y) list(selected = sample(colnames(X), 5), performance = 0.5)
  unstable <- audit_stability(rnd, s$X, s$y, n_runs = 6, seed = 1)
  expect_gt(stable$jaccard, 0.7); expect_false(stable$flagged)
  expect_lt(unstable$jaccard, 0.3); expect_true(unstable$flagged)
  expect_true(all(stable$frequency <= 1))
})

# audit_variants --------------------------------------------------------------
test_that("audit_variants reports shares and attributes the decision that matters", {
  s <- simulate_omics(n = 60, p = 80, n_signal = 8, effect = 1.5, missing_rate = 0.3, seed = 4)
  g <- variant_grid(variant_pipeline, norm = c("none", "median"),
                    impute = c("min", "median"), max_missing = c(0.5, 1))
  expect_length(g$variants, 8)
  a <- audit_variants(g$variants, s$X, s$y, design = g$design)
  expect_s3_class(a, "audit_variants")
  expect_true(all(a$selection_share <= 1 & a$selection_share > 0))
  expect_setequal(a$attribution$decision, c("norm", "impute", "max_missing"))
  expect_true(all(a$attribution$n_pairs == 4))

  # a deliberately decision-sensitive pair: the decision that flips the output is ranked first
  f1 <- function(X, y) list(selected = c("a", "b"), performance = 0.7)
  f2 <- function(X, y) list(selected = c("c", "d"), performance = 0.7)
  d <- data.frame(flip = c("x", "y"), same = c("m", "m"))
  b <- audit_variants(list(f1, f2), s$X, s$y, design = d)
  expect_equal(b$attribution$decision[1], "flip")
  expect_equal(b$attribution$mean_selection_change[1], 1)
})

# standard audit and zoo scoring ------------------------------------------------
test_that("zoo_dataset reproduces the dataset defined in meta.yml", {
  skip_if_not_installed("yaml")
  a <- zoo_dataset("flawed_select_before_split"); b <- zoo_dataset("flawed_select_before_split")
  expect_identical(a$X, b$X)
  expect_equal(nrow(zoo_dataset("flawed_repeated_measures")$X), 80)
})

test_that("audit_standard separates a leaky pipeline from the reference", {
  skip_if_not_installed("yaml"); skip_on_cran()
  fl <- zoo_load("flawed_select_before_split"); rf <- zoo_load("reference_nested_cv")
  sim <- zoo_dataset(fl)
  a <- audit_standard(fl$pipeline, sim$X, sim$y, batch = sim$batch, n_perm = 15, stability = FALSE)
  b <- audit_standard(rf$pipeline, sim$X, sim$y, batch = sim$batch, n_perm = 15, stability = FALSE)
  expect_true(a$flagged); expect_false(b$flagged)
  expect_output(print(a), "FLAG")
})

test_that("zoo_score computes detection and false-alarm rates from a stub audit", {
  skip_if_not_installed("yaml")
  always <- function(pipeline, X, y, ...) list(flagged = TRUE)
  never <- function(pipeline, X, y, ...) list(flagged = FALSE)
  n_ref <- sum(vapply(zoo_list(), function(n) isTRUE(zoo_load(n)$meta$is_reference), logical(1)))
  za <- zoo_score(always); zn <- zoo_score(never)
  expect_equal(za$detection_rate, 1); expect_equal(za$false_alarm_rate, 1)
  expect_equal(zn$detection_rate, 0); expect_equal(zn$false_alarm_rate, 0)
  expect_equal(za$n_reference, n_ref)
  expect_equal(za$n_flawed + za$n_reference, length(zoo_list()))
  expect_output(print(za), "Detection rate")
})

test_that("the zoo has the required entries and both kinds of expected outcome", {
  skip_if_not_installed("yaml")
  meta <- lapply(zoo_list(), function(n) zoo_load(n)$meta)
  flawed <- vapply(meta, function(m) !isTRUE(m$is_reference), logical(1))
  expect_gte(sum(flawed), 5); expect_gte(sum(!flawed), 3)
  expect_true(all(vapply(meta[flawed], function(m) isTRUE(m$expected_audit_outcome$flagged), logical(1))))
  expect_true(all(vapply(meta[!flawed], function(m) isFALSE(m$expected_audit_outcome$flagged), logical(1))))
})

test_that("repeated-measures simulator keeps a subject's samples together", {
  s <- simulate_omics(n_subjects = 10, reps_per_subject = 3, p = 20, n_signal = 2, seed = 1)
  expect_equal(nrow(s$X), 30)
  expect_true(all(tapply(s$y, s$subject, function(v) length(unique(v))) == 1))
  expect_match(rownames(s$X)[1], "^subj[0-9]+_r1$")
})

# report ----------------------------------------------------------------------
test_that("audit_report writes a self-contained HTML file with verdict and plots", {
  s <- simulate_omics(n = 60, p = 40, n_signal = 5, effect = 1.5, seed = 5)
  a <- audit_standard(top_k(5), s$X, s$y, batch = s$batch, quick = TRUE, seed = 1)
  p <- audit_planted(top_k(5), s$X, s$y, effects = c(0, 1, 3), n_plant = 2, reps = 3,
                     progress = FALSE, seed = 1)
  g <- variant_grid(variant_pipeline, norm = c("none", "median"), impute = c("min", "median"))
  v <- audit_variants(g$variants, s$X, s$y, design = g$design)
  f <- tempfile(fileext = ".html")
  expect_equal(audit_report(a, p, v, file = f, title = "T <x>"), f)
  h <- paste(readLines(f), collapse = "\n")
  expect_match(h, "Verdict"); expect_match(h, "<svg"); expect_match(h, "Power curve")
  expect_match(h, "Decision attribution"); expect_match(h, "seed 1")
  expect_match(h, "T &lt;x&gt;", fixed = TRUE)          # title is escaped
  expect_error(audit_report(list()))
})
