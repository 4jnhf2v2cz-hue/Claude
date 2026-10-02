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
