# omicsaudit

Black-box audit toolkit for omics biomarker pipelines, plus a "zoo" of
deliberately flawed pipelines with known answers. **Prototype**: working name,
not yet checked against CRAN/Bioconductor/GitHub; no novelty claim is made.

A pipeline is a function `pipeline(X, y)` (raw samples x features matrix, 0/1
outcome) returning `list(selected, performance)`. The audits control `X` and
`y`; they never read the pipeline's code.

```r
sim <- simulate_omics(n = 80, p = 150, n_signal = 10, effect = 1.5, seed = 1)
pipe <- zoo_load("reference_nested_cv")$pipeline

audit_standard(pipe, sim$X, sim$y, batch = sim$batch)      # null + confound + stability
audit_planted(pipe, sim$X, sim$y)                          # power curve, minimum detectable effect
audit_variants(variants, sim$X, sim$y, design = design)    # which decision matters
zoo_score(audit_standard)                                  # benchmark an audit on the zoo
audit_report(audit, planted = p, variants = v)             # one-page HTML
```

See `vignette("getting-started")`.

**One-click audit:** set `DATA_FILE <- "yourfile.csv"` and run `source("run_audit.R")`. It reads the file (guessing the layout and printing its guesses), audits it, tests how small an effect it could detect, and writes an HTML report and a text summary to `audit_output/`.

## What is in the package

| Function | Purpose |
|---|---|
| `read_omics_auto()` | Give it only a file: it guesses outcome, id, batch, covariates, features, orientation, scale and repeated measures, and prints every guess |
| `read_omics()`, `check_omics_input()` | Read CSV/TSV/Excel in varied layouts (samples in rows or columns, any column order, text missing codes, log or linear scale); flags duplicate, constant and identical columns |
| `simulate_omics()` | Raw intensities with planted signal, batch effect (optionally confounded), MNAR missingness, optional repeated measures |
| `audit_planted()`, `plant_signal()`, `samples_needed()` | Planted-signal recovery, power curve, minimum detectable effect |
| `audit_null()` | Shuffled-label test through the whole pipeline (group-aware) |
| `audit_confound()` | Is batch tied to the outcome? Can batch be predicted as well as the outcome? |
| `audit_stability()` | Jaccard agreement of `selected` under resampling |
| `audit_variants()`, `variant_grid()` | Selection share per feature; decision attribution |
| `audit_standard()` | Runs the null, confound and stability checks |
| `audit_report()` | One-page self-contained HTML report |
| `zoo_list()`, `zoo_load()`, `zoo_dataset()`, `zoo_score()` | The flawed-pipeline zoo and its benchmark |

## Zoo detection rate

`zoo_score(audit_standard, quick = FALSE, n_perm = 30)`, seed 1, simulated
datasets defined in each entry's `meta.yml`:

| Entry | Flaw | Reference? | Flagged | By |
|---|---|---|---|---|
| `flawed_select_before_split` | features selected on all labels | no | yes | `audit_null` |
| `flawed_tune_on_test` | hyperparameter tuned on test fold | no | yes | `audit_null` |
| `flawed_repeated_measures` | one subject in train and test | no | yes | `audit_null` (group-aware) |
| `flawed_batch_confounded` | batch confounded with outcome | no | yes | `audit_confound` |
| `flawed_norm_before_cv` | preprocessing fitted before CV | no | **no** | - |
| `reference_nested_cv` | none | yes | no | - |
| `reference_grouped_cv` | none | yes | no | - |
| `reference_batch_unconfounded` | none | yes | no | - |

**Detection rate 4/5 (80%), false-alarm rate 0/3 (0%).**

Read this with care: it is one dataset per entry, one seed, 8 entries, and the
zoo was written alongside the audits, so it shows the checks do what they were
designed to do, not that they generalise. The miss is genuine and expected:
label-free preprocessing leaks very little (mean null AUC 0.48 against 0.49 for
the reference), so a shuffled-label test cannot see it.

## Real public data: Mice Protein Expression

`data-raw/mice_protein.R` downloads the UCI Mice Protein Expression data
(Higuera et al. 2015; 77 proteins, 1080 samples from 72 mice, 15 repeats each;
nothing is committed) and audits a naive and a mouse-grouped pipeline on the
genotype outcome:

| Pipeline | Reported AUC | Shuffled-label AUC | Audit |
|---|---|---|---|
| Random-row CV (ignores mouse) | 0.851 | 0.666 | **flagged** |
| Mouse-grouped CV | 0.752 | 0.508 | pass |

The naive estimate is inflated by about 0.10 and the audit flags it; the grouped
pipeline is clean. This is one real dataset and one flaw, so it is a
demonstration, not a validation.

## Name and prior work (checked 2 Oct 2026)

* `omicsaudit` does not exist on CRAN, Bioconductor or the CRAN archive
  (`pipeaudit` and several variants also do not). GitHub was **not** searched;
  do that before settling on the name.
* `bioLeak` (CRAN) already provides permutation-gap auditing, batch/fold
  association tests, subject-grouped splits and guarded preprocessing, so
  `audit_null` and `audit_confound` overlap with it. What omicsaudit does
  differently is treat any pipeline as a black box `pipeline(X, y)`.
* Leakage in omics biomarker work is well documented, and an in-silico
  spike-in framework for microbiome biomarker recovery exists (bioRxiv), so
  planted-signal recovery is **not** claimed as new. No novelty claim is made;
  a proper literature review has not been done (the search above only read
  titles and summaries).

## Not done / limits

* `bioLeak` and `nestedcv` are not called; overlap has been noted, not integrated.
* The proteomics example dataset covers repeated measures only; no public dataset
  exercises batch confounding or MNAR missingness.
* Survival outcomes are not supported.
* `renv` is not set up. The GitHub Actions `R CMD check` workflow is written but
  has not run on GitHub.
* `audit_planted` plants only upward shifts and cannot restore values lost to MNAR
  dropout (see the vignette).
* `samples_needed()` is an extrapolation.
* Preprocessing leakage fitted before cross-validation is not detected by any check.
* Per-sample median normalisation in the zoo pipelines is applied only to panels
  of 100+ features.
