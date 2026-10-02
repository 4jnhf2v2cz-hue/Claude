wide <- function() data.frame(PatientID = 1:30, Group = rep(c("ctrl", "case"), 15),
                              Age = 40:69, P1 = (1:30) * 1000 + 5000, P2 = rev(1:30) * 800 + 3000,
                              P3 = (1:30)^2 + 200, stringsAsFactors = FALSE)

test_that("reads a csv, finds features, codes the outcome and records notes", {
  f <- tempfile(fileext = ".csv"); write.csv(wide(), f, row.names = FALSE)
  d <- read_omics(f, outcome = "Group", id = "PatientID", covariates = "Age")
  expect_s3_class(d, "omics_data")
  expect_equal(dim(d$X), c(30, 3)); expect_equal(colnames(d$X), c("P1", "P2", "P3"))
  expect_equal(sum(d$y), 15)
  # default for text labels: 2nd level alphabetically ("case" < "ctrl") is coded 1,
  # and the choice is reported in the notes so it is never silent
  expect_equal(d$y[1], 1L)
  expect_true(any(grepl("coded 1 \\(value 'ctrl'\\)", d$notes)))
})

test_that("positive_label controls which class is 1", {
  f <- tempfile(fileext = ".csv"); write.csv(wide(), f, row.names = FALSE)
  d <- read_omics(f, outcome = "Group", id = "PatientID", covariates = "Age", positive_label = "case")
  expect_equal(d$y[2], 1L); expect_equal(d$y[1], 0L)
})

test_that("semicolon, tab and decimal-comma files are understood", {
  w <- wide(); w$P1 <- sub("\\.", ",", format(w$P1 + 0.5))
  f <- tempfile(fileext = ".csv"); write.table(w, f, sep = ";", row.names = FALSE, quote = FALSE)
  d <- read_omics(f, outcome = "Group", id = "PatientID", covariates = "Age")
  expect_equal(unname(d$X[1, "P1"]), 6000.5)
  f2 <- tempfile(fileext = ".tsv"); write.table(wide(), f2, sep = "\t", row.names = FALSE)
  expect_equal(ncol(read_omics(f2, outcome = "Group", id = "PatientID", covariates = "Age")$X), 3)
})

test_that("Excel input works", {
  skip_if_not_installed("readxl"); skip_if_not_installed("writexl")
  f <- tempfile(fileext = ".xlsx"); writexl::write_xlsx(wide(), f)
  d <- read_omics(f, outcome = "Group", id = "PatientID", covariates = "Age")
  expect_equal(dim(d$X), c(30, 3))
})

test_that("samples in columns are transposed (feature names in first column)", {
  w <- wide()
  long <- as.data.frame(rbind(Group = w$Group, P1 = w$P1, P2 = w$P2, P3 = w$P3))
  names(long) <- paste0("S", 1:30); long <- cbind(feature = rownames(long), long)
  f <- tempfile(fileext = ".csv"); write.csv(long, f, row.names = FALSE)
  d <- read_omics(f, outcome = "Group")
  expect_equal(dim(d$X), c(30, 3)); expect_equal(rownames(d$X)[1], "S1")
  expect_true(any(grepl("Transposed", d$notes)))
})

test_that("missing-value codes, zeros and log-scale data are handled and reported", {
  w <- wide(); w$P1[3] <- NA; w$P2[4] <- 0
  w$P3 <- as.character(w$P3); w$P3[5] <- "Filtered"
  f <- tempfile(fileext = ".csv"); write.csv(w, f, row.names = FALSE)
  d <- read_omics(f, outcome = "Group", id = "PatientID", covariates = "Age", scale = "linear")
  expect_true(is.na(d$X[3, "P1"])); expect_true(is.na(d$X[4, "P2"])); expect_true(is.na(d$X[5, "P3"]))
  expect_true(any(grepl("zero/negative", d$notes)))

  lg <- wide(); lg[c("P1", "P2", "P3")] <- log2(lg[c("P1", "P2", "P3")])
  d2 <- read_omics(lg, outcome = "Group", id = "PatientID", covariates = "Age")
  expect_equal(d2$scale, "log2"); expect_equal(unname(d2$X[1, "P1"]), 6000, tolerance = 1e-6)
  d3 <- read_omics(wide(), outcome = "Group", id = "PatientID", covariates = "Age")
  expect_equal(d3$scale, "linear")
  expect_output(print(d2), "log2")
})

test_that("clear errors for the cases that cannot work", {
  w <- wide(); f <- tempfile(fileext = ".csv"); write.csv(w, f, row.names = FALSE)
  expect_error(read_omics(f, outcome = "Nope"), "neither a column")
  w3 <- w; w3$Group <- rep(c("a", "b", "c"), 10)
  expect_error(read_omics(w3, outcome = "Group", id = "PatientID"), "binary outcome")
  expect_error(read_omics("missing.csv", outcome = "Group"))
})

test_that("check_omics_input finds duplicate, constant and identical columns", {
  X <- matrix(runif(500, 1, 10), 20, 25, dimnames = list(NULL, letters[1:25]))
  y <- rep(0:1, 10)
  X2 <- X; X2[, "b"] <- 5; X2[, "c"] <- X2[, "a"]
  r <- check_omics_input(X2, y, warn = FALSE)
  expect_true(any(grepl("constant", r$notes))); expect_true(any(grepl("identical", r$notes)))
  expect_warning(expect_warning(check_omics_input(X2, y), "constant"), "identical")
  Xd <- X; colnames(Xd)[2] <- "a"
  expect_error(check_omics_input(Xd, y), "Duplicate feature names")
  expect_error(check_omics_input(unname(X), y), "column")
})

test_that("audits refuse duplicate feature names", {
  s <- simulate_omics(n = 40, p = 30, seed = 1); X <- s$X; colnames(X)[2] <- colnames(X)[1]
  p <- function(X, y) list(selected = colnames(X)[1], performance = 0.5)
  expect_error(audit_standard(p, X, s$y), "Duplicate feature names")
  expect_error(audit_planted(p, X, s$y, quick = TRUE), "Duplicate feature names")
})
