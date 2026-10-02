#' Locate the zoo directory
#' @return Path to the installed `zoo/` directory.
#' @export
zoo_path <- function() {
  p <- system.file("zoo", package = "omicsaudit")
  if (!nzchar(p)) stop("zoo directory not found; is omicsaudit installed?")
  p
}

#' List zoo entries
#' @return Character vector of entry names (one folder each).
#' @export
zoo_list <- function() {
  d <- list.dirs(zoo_path(), recursive = FALSE, full.names = FALSE)
  d[file.exists(file.path(zoo_path(), d, "pipeline.R"))]
}

#' Load a zoo entry
#'
#' Sources the shared helpers (`_common.R`) and the entry's `pipeline.R` into a
#' fresh environment. The pipeline is treated as a black box by the audits;
#' it is only ever called as `pipeline(X, y)`.
#'
#' @param name Entry name, see [zoo_list()].
#' @return A list with `pipeline` (function), `meta` (parsed `meta.yml`),
#'   `env` (the environment holding the pipeline and its helpers) and `name`.
#' @export
zoo_load <- function(name) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' is required to load zoo metadata.")
  }
  dir <- file.path(zoo_path(), name)
  if (!file.exists(file.path(dir, "pipeline.R"))) {
    stop("No zoo entry named '", name, "'. Available: ",
         paste(zoo_list(), collapse = ", "))
  }
  env <- new.env(parent = asNamespace("omicsaudit"))
  sys.source(file.path(zoo_path(), "_common.R"), envir = env)
  sys.source(file.path(dir, "pipeline.R"), envir = env)
  list(
    name = name,
    pipeline = get("pipeline", envir = env),
    meta = yaml::read_yaml(file.path(dir, "meta.yml")),
    env = env
  )
}

#' Generate the dataset a zoo entry is defined on
#'
#' @param name Entry name, or a list returned by [zoo_load()].
#' @return An `omics_sim` object (see [simulate_omics()]).
#' @export
zoo_dataset <- function(name) {
  e <- if (is.list(name)) name else zoo_load(name)
  do.call(simulate_omics, e$meta$dataset$args)
}

#' Score an audit method against the zoo
#'
#' For each zoo entry the dataset is generated, the pipeline loaded, and
#' `audit_fn(pipeline, X, y, batch = , groups = , quick = )` is called. The
#' result must carry a logical `flagged`. Detection rate is the share of
#' flawed entries flagged; false-alarm rate is the share of reference entries
#' flagged.
#'
#' @param audit_fn Audit function, default [audit_standard()].
#' @param entries Entry names (default: all).
#' @param quick Passed to `audit_fn` (cheap mode).
#' @param seed Passed to `audit_fn` if it accepts `seed`.
#' @param ... Further arguments for `audit_fn`.
#' @return Object of class `zoo_score` with `table`, `detection_rate`,
#'   `false_alarm_rate` and `seed`.
#' @export
zoo_score <- function(audit_fn = audit_standard, entries = zoo_list(),
                      quick = TRUE, seed = 1L, ...) {
  rows <- lapply(entries, function(nm) {
    e <- zoo_load(nm); sim <- zoo_dataset(e)
    t0 <- Sys.time()
    a <- audit_fn(e$pipeline, sim$X, sim$y, batch = sim$batch,
                  groups = if (nlevels(sim$subject) < nrow(sim$X)) as.character(sim$subject) else NULL,
                  quick = quick, seed = seed, ...)
    data.frame(entry = nm, is_reference = isTRUE(e$meta$is_reference),
               flaw_type = e$meta$flaw_type, flagged = isTRUE(a$flagged),
               checks = if (!is.null(a$checks)) paste(a$checks$check[a$checks$flagged & a$checks$drives_verdict], collapse = "+") else "",
               seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1))
  })
  tab <- do.call(rbind, rows)
  structure(list(
    table = tab,
    detection_rate = mean(tab$flagged[!tab$is_reference]),
    false_alarm_rate = mean(tab$flagged[tab$is_reference]),
    n_flawed = sum(!tab$is_reference), n_reference = sum(tab$is_reference),
    seed = seed), class = "zoo_score")
}

#' @export
print.zoo_score <- function(x, ...) {
  cat("<zoo_score> seed ", x$seed, "\n", sep = "")
  print(x$table, row.names = FALSE)
  cat(sprintf("\nDetection rate:   %d/%d flawed pipelines flagged (%.0f%%)\n",
              sum(x$table$flagged[!x$table$is_reference]), x$n_flawed, 100 * x$detection_rate))
  cat(sprintf("False-alarm rate: %d/%d reference pipelines flagged (%.0f%%)\n",
              sum(x$table$flagged[x$table$is_reference]), x$n_reference, 100 * x$false_alarm_rate))
  invisible(x)
}
