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

## What is in the package

| Function | Purpose |
|---|---|
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

## Not done / limits

* `bioLeak` and `nestedcv` are not called; overlap has been noted, not integrated.
* No public proteomics dataset is selected. `data-raw/pride_download.R` lists and
  downloads files from PRIDE (listing and a download were tested), but most
  projects ship raw files only and need a usable quantification table plus
  outcome labels.
* `renv` is not set up. The GitHub Actions `R CMD check` workflow is written but
  has not run on GitHub.
* `audit_planted` plants only upward shifts and cannot restore values lost to MNAR
  dropout (see the vignette).
* `samples_needed()` is an extrapolation.
