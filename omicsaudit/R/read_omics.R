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
  df <- .read_raw(file, sheet, missing_values)
  if (!is.null(attr(df, "read_note"))) note(attr(df, "read_note"))
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
    cs <- apply(M, 2, function(x) { x <- x[is.finite(x)]; if (length(x) < 5 || stats::sd(x) == 0) NA_real_ else mean(((x - mean(x)) / stats::sd(x))^3) })
    skew <- stats::median(cs, na.rm = TRUE)
    scale <- if (is.finite(skew) && skew > 1) "linear" else if (any(v < 0)) "log2" else
      if (stats::quantile(v, 0.99) > 100 || stats::median(v) > 100) "linear" else "log2"
    note("Scale not given; guessed '", scale, "' (values ", signif(min(v), 3), " to ", signif(max(v), 3),
         ", median ", signif(stats::median(v), 3), ", typical skew ", signif(skew, 2), "). ",
         if (scale == "log2") "Roughly symmetric small values suggest a log scale; log2, ln and log10 cannot be told apart, so pass `scale` if you know it."
         else "Strongly right-skewed values suggest raw (linear) intensities; check that they are not already log-transformed.")
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
  if (ncol(X) < 20) add("Only ", ncol(X), " features: a small panel. Per-sample median normalisation is a poor choice here (the zoo pipelines skip it), and effect-size limits and chance-level recall are rough.")
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


# Read any supported table into a data frame of character columns -------------
.read_raw <- function(file, sheet = 1, missing_values = c("", "NA", "N/A", "n/a", "NaN", "#N/A",
                      "null", "NULL", "Filtered", "filtered", "-", "--", "ND")) {
  rn <- NULL
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
      rn <- paste0("Read '", basename(file), "' as delimited text (separator '",
                   if (sep == "\t") "\\t" else sep, "').")
      utils::read.table(file, header = TRUE, sep = sep, quote = "\"", comment.char = "",
                        check.names = FALSE, stringsAsFactors = FALSE, colClasses = "character",
                        na.strings = missing_values, fill = TRUE, strip.white = TRUE)
    }
  }
  attr(df, "read_note") <- rn
  df
}

#' Read an omics table and work out its layout automatically
#'
#' Like [read_omics()], but you only need to give the file. It guesses which
#' column is the outcome, the sample id, the batch, the clinical covariates and
#' which columns are the measured features, and whether samples are in rows or
#' columns. Every guess is recorded in `$notes` (and printed) so it can be
#' checked; anything you pass explicitly overrides the guess.
#'
#' Heuristics, in order: a two-valued column is the outcome (preferring names
#' like `outcome`, `status`, `group`, `class`, `disease`, `progress`...); a
#' name matching `id|sample|patient|subject` is the id; `batch|plate|run|site|
#' centre|lab|date|cohort|study` columns are batch; names like age/sex/bmi, any
#' column with few distinct values, and any numeric column whose typical size is
#' more than ~30x away from the others are covariates; everything else numeric
#' is a feature. **These are guesses**: always read the printout.
#'
#' @inheritParams read_omics
#' @param outcome,id,batch,covariates,features Override the guess for these. For
#'   `id` and `batch`, `FALSE` means "there is none" (`NULL` means "guess").
#' @return An `omics_data` object (see [read_omics()]) with an extra element
#'   `guess` listing what was guessed and which alternatives were considered.
#' @export
read_omics_auto <- function(file, outcome = NULL, id = NULL, batch = NULL,
                            covariates = NULL, features = NULL,
                            orientation = c("auto", "samples_in_rows", "samples_in_columns"),
                            scale = c("auto", "linear", "log2", "log10", "ln"),
                            positive_label = NULL, sheet = 1) {
  orientation <- match.arg(orientation); scale <- match.arg(scale)
  df <- .read_raw(file, sheet)
  rn <- attr(df, "read_note")
  guesses <- character(); alts <- list()
  g <- function(...) guesses <<- c(guesses, paste0(...))
  miss <- c("", "NA", "N/A", "n/a", "NaN", "#N/A", "null", "NULL", "Filtered", "filtered", "-", "--", "ND")
  df[] <- lapply(df, function(v) { v <- trimws(as.character(v)); v[v %in% miss] <- NA; v })
  nvals <- function(v) length(unique(v[!is.na(v)]))
  is_num <- function(v) { x <- suppressWarnings(as.numeric(sub(",", ".", v, fixed = TRUE))); mean(!is.na(x) | is.na(v)) > 0.9 && any(!is.na(x)) }

  # Orientation: if no column is a plausible outcome but a row is, transpose
  has_outcome_col <- function(d) any(vapply(d, nvals, numeric(1)) == 2)
  if (orientation == "auto") orientation <- if (!is.null(outcome) && outcome %in% names(df)) "samples_in_rows" else
    if (has_outcome_col(df)) "samples_in_rows" else "samples_in_columns"
  if (orientation == "samples_in_columns") {
    fe <- make.unique(as.character(df[[1]]))
    m <- t(as.matrix(df[-1])); colnames(m) <- fe
    df <- data.frame(sample = rownames(m), m, check.names = FALSE, stringsAsFactors = FALSE)
    rownames(df) <- NULL
    if (is.null(id)) id <- "sample"
    g("Samples were in columns (feature names in the first column); transposed.")
  }
  cols <- names(df)

  # Outcome ---------------------------------------------------------------------
  if (is.null(outcome)) {
    cand <- cols[vapply(df, nvals, numeric(1)) == 2]
    if (!length(cand)) stop("Could not find a two-valued column to use as the outcome. Columns: ",
                            paste(utils::head(cols, 12), collapse = ", "), ". Pass `outcome = `.")
    pri <- grepl("outcome|status|group|class|label|response|disease|case|control|diagnos|condition|progress|genotype|phenotype|event|target|treat",
                 cand, ignore.case = TRUE)
    outcome <- if (any(pri)) cand[pri][1] else cand[1]
    others <- setdiff(cand, outcome)
    g("Outcome: '", outcome, "' (a two-valued column", if (any(pri)) " with an outcome-like name" else "", ").",
      if (length(others)) paste0(" Other two-valued columns, treated as covariates: ", paste(others, collapse = ", "), "."))
    alts$outcome <- others
  }
  # Id --------------------------------------------------------------------------
  if (isFALSE(id)) id <- NULL else if (is.null(id)) {
    idc <- setdiff(cols[grepl("^(id|.*[_ .]id|id[_ .].*|sample.*|patient.*|subject.*|mouse.*|name|specimen.*)$", cols, ignore.case = TRUE)], outcome)
    if (length(idc)) { id <- idc[1]; g("Sample id: '", id, "'.") }
  }
  # Batch -----------------------------------------------------------------------
  if (isFALSE(batch)) batch <- NULL else if (is.null(batch)) {
    bc <- setdiff(cols[grepl("batch|plate|run|site|cent(er|re)|lab|date|cohort|study|instrument|day", cols, ignore.case = TRUE)], c(outcome, id))
    bc <- bc[vapply(bc, function(c) nvals(df[[c]]) %in% 2:30, logical(1))]
    if (length(bc)) { batch <- bc[1]; g("Batch: '", batch, "' (name suggests a batch/site/run variable).") }
  }
  # Covariates --------------------------------------------------------------------
  if (is.null(covariates)) {
    rest <- setdiff(cols, c(outcome, id, batch))
    name_cov <- grepl("^(age|sex|gender|bmi|wbc|weight|height|smok.*|ethnic.*|race|stage|grade|diabetes|treatment|behavior|behaviour|comorb.*|bp|sbp|dbp)$|age_|_age",
                      rest, ignore.case = TRUE)
    numc <- rest[vapply(df[rest], is_num, logical(1))]
    med <- vapply(df[numc], function(v) stats::median(abs(suppressWarnings(as.numeric(sub(",", ".", v, fixed = TRUE)))), na.rm = TRUE), numeric(1))
    size_out <- if (length(numc) >= 4) numc[abs(log10(pmax(med, 1e-9)) - stats::median(log10(pmax(med, 1e-9)))) > 1.5] else character()
    few <- rest[vapply(df[rest], nvals, numeric(1)) <= 8]
    nonnum <- rest[!vapply(df[rest], is_num, logical(1))]
    covariates <- unique(c(rest[name_cov], size_out, few, nonnum))
    if (length(covariates)) g("Set aside as covariates (not features): ", paste(covariates, collapse = ", "), ".")
  }
  fe <- setdiff(cols, c(outcome, id, batch, covariates))
  g("Features: ", length(fe), " numeric columns", if (length(fe)) paste0(" (", fe[1], " ... ", fe[length(fe)], ")"), ".")
  if (!length(fe)) stop("No feature columns left after setting aside the outcome, id, batch and covariates.")

  raw_ids <- if (!is.null(id)) df[[id]] else NULL
  d <- read_omics(df, outcome = outcome, id = id, features = fe, batch = batch, covariates = covariates,
                  orientation = "samples_in_rows", scale = scale, positive_label = positive_label)
  # Repeated measures: duplicated ids, or ids like "<subject>_<n>" whose prefix repeats
  subj <- NULL
  if (!is.null(raw_ids)) {
    ri <- as.character(raw_ids[!is.na(df[[outcome]])])
    if (anyDuplicated(ri)) subj <- ri else {
      pre <- sub("[_.-]?[0-9]+$", "", ri); pre[!grepl("[_.-]?[0-9]+$", ri)] <- NA
      u <- unique(stats::na.omit(pre))
      if (!anyNA(pre) && length(u) >= 4 && length(u) < 0.67 * length(ri) &&
          all(table(pre) >= 2) && !all(pre == pre[1])) subj <- pre
    }
  }
  if (!is.null(subj)) {
    consistent <- all(tapply(d$y, subj, function(v) length(unique(v))) == 1)
    if (consistent) {
      k <- stats::ave(seq_along(subj), subj, FUN = seq_along)
      rownames(d$X) <- paste0(subj, "_r", k); d$id <- rownames(d$X)
      d$groups <- subj
      guesses <- c(guesses, sprintf("Repeated measures detected: %d samples from %d subjects (%s); the outcome is constant within each subject. Audits will keep each subject together.",
                                    length(subj), length(unique(subj)), paste(utils::head(unique(subj), 3), collapse = ", ")))
    } else guesses <- c(guesses, "Repeated ids found but the outcome changes within a subject; treated as independent samples (check this).")
  }
  d$notes <- c(if (!is.null(rn)) rn, paste0("GUESS: ", guesses), d$notes)
  d$guess <- list(outcome = outcome, id = id, batch = batch, covariates = covariates, n_features = length(fe), repeated_measures = !is.null(d$groups))
  d
}
