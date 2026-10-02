#' Read an omics table in whatever layout it arrives in
#'
#' Reads a CSV/TSV/TXT file, an Excel workbook (needs the `readxl` package) or
#' a data frame, and returns the raw-scale matrix `X` and 0/1 outcome `y` that
#' every audit expects. Everything it assumes or changes is recorded in
#' `$notes` and printed, so nothing happens silently.
#'
#' What it handles: delimiter detection, samples in rows **or** in columns,
#' sample-id/outcome/batch/covariate columns anywhere in the table, text
#' missing-value codes (`NA`, `N/A`, `#N/A`, `Filtered`, ...), decimal commas,
#' zeros or non-positive values in linear data (set to missing), and log-scaled
#' data (converted back to the linear scale the pipelines expect).
#'
#' **Scale detection is a heuristic.** `scale = "auto"` can tell linear
#' intensities (large, strictly positive, skewed) from log-scale values (small
#' range, or negatives) but cannot tell log2 from natural log or log10, and
#' assumes log2. Pass `scale` explicitly if you know it.
#'
#' @param file Path to a `.csv`, `.tsv`, `.txt`, `.xlsx`, `.xls` or `.rds`
#'   file, or a data frame.
#' @param outcome Name of the outcome column (or, if samples are in columns,
#'   the outcome row label).
#' @param id Name of the sample-id column. Default: row names / first column
#'   if it looks like an id.
#' @param features Character vector of feature columns, or a regular
#'   expression matching them. Default: every numeric-looking column that is
#'   not the id, outcome, batch or a covariate.
#' @param batch Name of a batch/site/run column (kept separately, never used
#'   as a feature).
#' @param covariates Names of other non-feature columns (age, sex, ...).
#' @param orientation `"samples_in_rows"`, `"samples_in_columns"` or `"auto"`.
#'   With samples in columns the first column holds feature names.
#' @param scale `"auto"`, `"linear"`, `"log2"`, `"log10"` or `"ln"`.
#' @param positive_label Value of `outcome` to code as 1. Default: the larger
#'   numeric value, or the second level alphabetically.
#' @param missing_values Strings treated as missing.
#' @param sheet Excel sheet name or number.
#' @return An object of class `omics_data`: list with `X`, `y`, `batch`,
#'   `covariates`, `id`, `scale`, `notes`.
#' @export
read_omics <- function(file, outcome, id = NULL, features = NULL, batch = NULL,
                       covariates = NULL,
                       orientation = c("auto", "samples_in_rows", "samples_in_columns"),
                       scale = c("auto", "linear", "log2", "log10", "ln"),
                       positive_label = NULL,
                       missing_values = c("", "NA", "N/A", "n/a", "NaN", "#N/A", "null",
                                          "NULL", "Filtered", "filtered", "-", "--", "ND"),
                       sheet = 1) {
  orientation <- match.arg(orientation); scale <- match.arg(scale)
  notes <- character()
  note <- function(...) notes <<- c(notes, paste0(...))

  # 1. Read ---------------------------------------------------------------
  df <- if (is.data.frame(file)) as.data.frame(file, stringsAsFactors = FALSE) else {
    stopifnot(is.character(file), length(file) == 1, file.exists(file))
    ext <- tolower(tools::file_ext(file))
    if (ext %in% c("xlsx", "xls")) {
      if (!requireNamespace("readxl", quietly = TRUE))
        stop("Reading Excel files needs the 'readxl' package: install.packages('readxl')")
      as.data.frame(readxl::read_excel(file, sheet = sheet, col_types = "text",
                                       na = missing_values), stringsAsFactors = FALSE)
    } else if (ext == "rds") as.data.frame(readRDS(file)) else {
      l1 <- readLines(file, n = 1, warn = FALSE)
      sep <- c(",", ";", "\t")[which.max(vapply(c(",", ";", "\t"), function(s)
        lengths(regmatches(l1, gregexpr(s, l1, fixed = TRUE))), numeric(1)))]
      note("Read '", basename(file), "' as delimited text (separator '",
           if (sep == "\t") "\\t" else sep, "').")
      utils::read.table(file, header = TRUE, sep = sep, quote = "\"", comment.char = "",
                        check.names = FALSE, stringsAsFactors = FALSE, colClasses = "character",
                        na.strings = missing_values, fill = TRUE, strip.white = TRUE)
    }
  }
  df[] <- lapply(df, function(v) { v <- as.character(v); v[trimws(v) %in% missing_values] <- NA; v })

  # 2. Orientation --------------------------------------------------------
  if (orientation == "auto")
    orientation <- if (outcome %in% names(df)) "samples_in_rows" else
      if (outcome %in% trimws(df[[1]])) "samples_in_columns" else
        stop("Outcome '", outcome, "' is neither a column name nor a row label. Columns: ",
             paste(utils::head(names(df), 12), collapse = ", "))
  if (orientation == "samples_in_columns") {
    fe <- make.unique(trimws(as.character(df[[1]])))
    m <- t(as.matrix(df[-1])); colnames(m) <- fe
    df <- data.frame(m, check.names = FALSE, stringsAsFactors = FALSE)
    df <- cbind(sample = rownames(m), df); rownames(df) <- NULL
    if (is.null(id)) id <- "sample"
    note("Transposed: samples were in columns, feature names in the first column.")
  }
  if (!outcome %in% names(df)) stop("Outcome column '", outcome, "' not found.")
  for (nm in c(id, batch, covariates)) if (!nm %in% names(df)) stop("Column '", nm, "' not found.")

  # 3. Outcome -> 0/1 ----------------------------------------------------
  yr <- df[[outcome]]
  keep <- !is.na(yr)
  if (any(!keep)) note("Dropped ", sum(!keep), " sample(s) with missing outcome.")
  df <- df[keep, , drop = FALSE]; yr <- yr[keep]
  lv <- sort(unique(yr))
  if (length(lv) != 2)
    stop("Outcome '", outcome, "' has ", length(lv), " distinct values (",
         paste(utils::head(lv, 5), collapse = ", "), "); a binary outcome is required.")
  num <- suppressWarnings(as.numeric(lv))
  if (is.null(positive_label)) positive_label <- if (!anyNA(num)) lv[which.max(num)] else lv[2]
  y <- as.integer(yr == as.character(positive_label))
  note("Outcome '", outcome, "': ", sum(y == 1), " samples coded 1 (value '", positive_label,
       "'), ", sum(y == 0), " coded 0 (value '", setdiff(lv, positive_label), "').")

  # 4. Sample ids ---------------------------------------------------------
  ids <- if (!is.null(id)) df[[id]] else if (!identical(rownames(df), as.character(seq_len(nrow(df)))))
    rownames(df) else sprintf("sample%0*d", nchar(nrow(df)), seq_len(nrow(df)))
  if (anyDuplicated(ids)) {
    note("Duplicate sample ids found (", sum(duplicated(ids)), "); made unique. ",
         "If these are repeated measures, name them '<subject>_r<n>' so subject-aware pipelines can group them.")
    ids <- make.unique(as.character(ids), sep = "_dup")
  }

  # 5. Features ----------------------------------------------------------
  non_feat <- c(id, outcome, batch, covariates)
  cand <- if (is.null(features)) setdiff(names(df), non_feat) else if (length(features) == 1 &&
        !features %in% names(df)) grep(features, names(df), value = TRUE) else features
  cand <- setdiff(cand, non_feat)
  if (!length(cand)) stop("No feature columns found.")
  to_num <- function(v) {
    x <- suppressWarnings(as.numeric(v))
    bad <- is.na(x) & !is.na(v)
    if (any(bad)) x[bad] <- suppressWarnings(as.numeric(sub(",", ".", v[bad], fixed = TRUE)))
    x
  }
  M <- vapply(cand, function(j) to_num(df[[j]]), numeric(nrow(df)))
  if (is.null(dim(M))) M <- matrix(M, nrow(df), dimnames = list(NULL, cand))
  parsable <- vapply(cand, function(j) { v <- df[[j]]; mean(!is.na(to_num(v)) | is.na(v)) }, numeric(1))
  if (is.null(features) && any(parsable < 0.9)) {
    note("Skipped ", sum(parsable < 0.9), " non-numeric column(s) not named as covariates: ",
         paste(utils::head(cand[parsable < 0.9], 8), collapse = ", "), ".")
    M <- M[, parsable >= 0.9, drop = FALSE]
  } else if (any(parsable < 0.9)) stop("Feature column(s) are not numeric: ",
                                       paste(cand[parsable < 0.9], collapse = ", "))
  rownames(M) <- ids
  if (anyDuplicated(colnames(M))) {
    note("Duplicate feature names: ", paste(unique(colnames(M)[duplicated(colnames(M))]), collapse = ", "),
         "; made unique (name, name.1, ...).")
    colnames(M) <- make.unique(colnames(M))
  }

  # 6. Scale -> linear ---------------------------------------------------------
  v <- M[is.finite(M)]
  if (scale == "auto") {
    scale <- if (any(v < 0)) "log2" else if (stats::quantile(v, 0.99) > 100 ||
        stats::median(v) > 100) "linear" else "log2"
    note("Scale not given; guessed '", scale, "' (values ", signif(min(v), 3), " to ", signif(max(v), 3),
         ", median ", signif(stats::median(v), 3), "). ",
         if (scale == "log2") "log2, ln and log10 cannot be told apart from the values alone; pass `scale` if you know it."
         else "Check that these are not already log-transformed.")
  }
  M <- switch(scale, linear = M, log2 = 2^M, log10 = 10^M, ln = exp(M))
  if (scale != "linear") note("Converted from ", scale, " back to the linear scale (pipelines apply their own log).")
  nonpos <- is.finite(M) & M <= 0
  if (any(nonpos)) { M[nonpos] <- NA
    note("Set ", sum(nonpos), " zero/negative value(s) to missing (log is undefined; zeros are usually 'not detected').") }

  # 7. Batch, covariates, validation ------------------------------------
  bt <- if (!is.null(batch)) factor(df[[batch]]) else NULL
  cov_df <- if (length(covariates)) { cv <- df[covariates]; cv[] <- lapply(cv, function(z) {
    n <- to_num(z); if (mean(!is.na(n) | is.na(z)) > 0.9) n else factor(z) })
    rownames(cv) <- ids; cv } else NULL
  chk <- check_omics_input(M, y, warn = FALSE)
  notes <- c(notes, chk$notes)
  structure(list(X = M, y = y, batch = bt, covariates = cov_df, id = ids, scale = scale,
                 notes = notes), class = "omics_data")
}

#' Check an input matrix for problems that distort audits
#'
#' Finds: duplicate or empty column names (error), entirely-missing columns,
#' constant columns, groups of identical columns, non-positive values, tiny
#' classes and very few features. Used by [read_omics()], [audit_standard()]
#' and [audit_planted()].
#'
#' @param X Samples x features matrix.
#' @param y 0/1 outcome.
#' @param warn Emit R warnings for findings (otherwise only return them).
#' @return Invisibly, a list with `notes` (character) and `ok` (logical).
#' @export
check_omics_input <- function(X, y, warn = TRUE) {
  stopifnot(is.matrix(X), is.numeric(X), length(y) == nrow(X))
  if (is.null(colnames(X)) || any(!nzchar(colnames(X))) || anyNA(colnames(X)))
    stop("X needs non-empty column (feature) names.")
  if (anyDuplicated(colnames(X)))
    stop("Duplicate feature names in X: ",
         paste(utils::head(unique(colnames(X)[duplicated(colnames(X))]), 5), collapse = ", "),
         ". Name-based results (selected features, planted recall) would be ambiguous.")
  notes <- character()
  add <- function(...) notes <<- c(notes, paste0(...))
  allna <- colSums(!is.na(X)) == 0
  if (any(allna)) add(sum(allna), " feature(s) are entirely missing: ", paste(utils::head(colnames(X)[allna], 5), collapse = ", "), ".")
  const <- !allna & apply(X, 2, function(v) length(unique(v[!is.na(v)])) <= 1)
  if (any(const)) add(sum(const), " constant feature(s): ", paste(utils::head(colnames(X)[const], 5), collapse = ", "),
                      ". Constant columns can become spuriously 'predictive' after per-sample normalisation.")
  ok <- !allna & !const
  key <- apply(X[, ok, drop = FALSE], 2, function(v) paste(round(v, 8), collapse = "|"))
  dup <- split(names(key), key); dup <- dup[lengths(dup) > 1]
  if (length(dup)) add(length(dup), " group(s) of identical columns, e.g. ",
                       paste(dup[[1]][1:min(3, length(dup[[1]]))], collapse = " = "),
                       ". Copies of one feature crowd other features out of the selected set.")
  if (any(X <= 0, na.rm = TRUE)) add("Non-positive values present; pipelines expect linear-scale intensities > 0.")
  if (min(table(y)) < 10) add("Smaller class has only ", min(table(y)), " samples; estimates will be very noisy.")
  if (ncol(X) < 20) add("Only ", ncol(X), " features: per-sample median normalisation and feature selection behave poorly on small panels.")
  if (warn && length(notes)) for (n in notes) warning(n, call. = FALSE)
  invisible(list(notes = notes, ok = !length(notes)))
}

#' @export
print.omics_data <- function(x, ...) {
  cat("<omics_data> ", nrow(x$X), " samples x ", ncol(x$X), " features; ", sum(x$y), " cases / ",
      sum(1 - x$y), " controls\n", sep = "")
  if (!is.null(x$batch)) cat("  batch: ", nlevels(x$batch), " levels\n", sep = "")
  if (!is.null(x$covariates)) cat("  covariates: ", paste(names(x$covariates), collapse = ", "), "\n", sep = "")
  cat("What was done / found:\n"); for (n in x$notes) cat("  - ", n, "\n", sep = "")
  invisible(x)
}
