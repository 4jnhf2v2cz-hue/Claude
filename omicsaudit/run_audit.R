# =============================================================================
#  omicsaudit: one-click audit of a biomarker analysis
#  ---------------------------------------------------------------------------
#  1. Set DATA_FILE (and any other setting) before running, or edit the block below.
#     Leave DATA_FILE unset to choose a file in a pop-up window.
#  2. Run the whole script:  source("run_audit.R")
#  Everything is written to the folder OUT_DIR: an HTML report, a plain-text
#  summary and the raw results (.rds).
# =============================================================================

# ---- SETTINGS ----------------------------------------------------------------
# Any setting you define BEFORE running this script (e.g. DATA_FILE <- "...") wins
# over the default shown here, so you do not have to edit the file.
cfg <- function(name, default) if (exists(name, envir = globalenv())) get(name, envir = globalenv()) else default
DATA_FILE   <- cfg("DATA_FILE",  NULL)    # path to your .csv/.tsv/.xlsx, or NULL to choose a file
# Everything below is GUESSED from the file when left as NULL / "auto". The guesses are
# printed in step 1: read them. Set a value to override a wrong guess.
OUTCOME     <- cfg("OUTCOME",    NULL)    # name of the two-valued outcome column
ID_COLUMN   <- cfg("ID_COLUMN",  NULL)    # sample id column (FALSE = none)
COVARIATES  <- cfg("COVARIATES", NULL)    # non-measurement columns to set aside, e.g. c("Age","Sex")
BATCH       <- cfg("BATCH",      NULL)    # batch / site / run column (FALSE = none)
SCALE       <- cfg("SCALE",      "auto")  # "log2", "log10", "ln", "linear" or "auto" (a guess!)
POSITIVE    <- cfg("POSITIVE",   NULL)    # value of OUTCOME to code as 1 (NULL = automatic)
QUICK       <- cfg("QUICK",      FALSE)   # TRUE = faster but rougher; FALSE = fuller (about a minute on small data)
SEED        <- cfg("SEED",       1)       # recorded in the report so results can be reproduced
OUT_DIR     <- cfg("OUT_DIR",    "audit_output")
TITLE       <- cfg("TITLE",      "Audit: biomarker analysis")
# -----------------------------------------------------------------------------

say <- function(...) cat(sprintf("\n=== %s ===\n", paste0(...)))
t0 <- Sys.time()

# 0. Packages ------------------------------------------------------------------
say("Checking packages")
need <- c("yaml", "readxl")
miss <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) install.packages(miss)
if (!requireNamespace("omicsaudit", quietly = TRUE))
  stop("The omicsaudit package is not installed. Install it first (see README), then re-run.")
suppressPackageStartupMessages(library(omicsaudit))
dir.create(OUT_DIR, showWarnings = FALSE)

# 1. Read the data ---------------------------------------------------------------
say("1/5 Reading the data")
if (is.null(DATA_FILE)) DATA_FILE <- file.choose()
d <- read_omics_auto(DATA_FILE, outcome = OUTCOME, id = ID_COLUMN, covariates = COVARIATES,
                     batch = BATCH, scale = SCALE, positive_label = POSITIVE)
cat("\nCHECK THE LINES STARTING 'GUESS' ABOVE: if the outcome, covariates or scale are wrong,\n",
    "set OUTCOME / COVARIATES / SCALE before running and run again.\n", sep = "")
print(d)

# 2. Core audit -------------------------------------------------------------------
say("2/5 Core audit (shuffled-label test, confounding, stability)")
# The analysis being audited: nested CV with train-only preprocessing. If repeated
# measures were detected, use the subject-grouped version and permute per subject.
PIPE_NAME <- if (is.null(d$groups)) "reference_nested_cv" else "reference_grouped_cv"
if (!is.null(d$groups)) cat("Repeated measures detected: using", PIPE_NAME, "\n")
pipe <- zoo_load(PIPE_NAME)$pipeline
aud <- audit_standard(pipe, d$X, d$y, batch = d$batch, groups = d$groups, quick = QUICK, seed = SEED)
print(aud)

# 3. Power curve --------------------------------------------------------------------
say("3/5 How small an effect can this analysis detect?")
n <- nrow(d$X)
effects <- if (QUICK) c(0, 0.25, 0.5, 1, 2) else c(0, 0.1, 0.2, 0.3, 0.5, 0.75, 1, 2)
pl <- audit_planted(pipe, d$X, d$y, effects = effects, n_plant = max(1, round(0.2 * ncol(d$X))),
                    reps = if (QUICK) 4 else 10,
                    n_grid = if (QUICK) n else unique(round(n * c(0.25, 0.5, 1))),
                    groups = d$groups, progress = TRUE, seed = SEED)
print(pl)

# 4. Which analysis decisions matter -----------------------------------------------------
say("4/5 Which analysis decisions change the answer?")
k <- c(3, 5)
g <- variant_grid(variant_pipeline, norm = c("none", "median"), impute = c("min", "median"), k = k)
va <- audit_variants(g$variants, d$X, d$y, design = g$design, seed = SEED)
print(va)

# 5. Report and summary --------------------------------------------------------------------
say("5/5 Writing the report")
report <- file.path(OUT_DIR, "audit_report.html")
audit_report(aud, planted = pl, variants = va, file = report, title = TITLE,
             pipeline_name = paste0(PIPE_NAME, " (nested CV, train-only preprocessing)"))

sum_txt <- c(
  TITLE, strrep("=", nchar(TITLE)), "",
  sprintf("Data file : %s", basename(DATA_FILE)),
  sprintf("Samples   : %d (%d cases, %d controls); %d features", n, sum(d$y), sum(1 - d$y), ncol(d$X)),
  sprintf("Seed      : %s   Mode: %s", SEED, if (QUICK) "quick" else "full"), "",
  sprintf("VERDICT: %s", if (aud$flagged) "FLAGGED" else "no problem found"), "",
  "What the importer did:", paste0("  - ", d$notes), "",
  "Checks:", paste0("  - ", aud$checks$check, ": ", aud$checks$evidence), "",
  "Power curve:", paste0("  - ", capture.output(print(pl))[-1]), "",
  "Decision attribution:", paste0("  - ", va$evidence), "",
  "Caveats:",
  "  - One dataset, no independent validation.",
  sprintf("  - Scale used: '%s'; check this with whoever supplied the data.", d$scale),
  if (ncol(d$X) < 100) "  - Small panel: the 'median' normalisation option is a poor choice here, so the 'norm' row of the attribution mostly reflects that, not a real analysis decision.",
  if (ncol(d$X) < 20) "  - Very small panel: effect-size limits are rough.",
  if (is.null(d$batch)) "  - No batch column found, so batch confounding was not checked.",
  "  - Outcome, covariates and (if SCALE is 'auto') scale were guessed from the file: confirm them.")
writeLines(unlist(sum_txt), file.path(OUT_DIR, "summary.txt"))
saveRDS(list(data_notes = d$notes, audit = aud, planted = pl, variants = va, seed = SEED),
        file.path(OUT_DIR, "results.rds"))

say("Done in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " minutes")
cat("Report : ", normalizePath(report), "\nSummary: ", normalizePath(file.path(OUT_DIR, "summary.txt")), "\n", sep = "")
cat("\nVERDICT:", if (aud$flagged) "FLAGGED" else "no problem found", "\n")
if (interactive()) try(utils::browseURL(report), silent = TRUE)
