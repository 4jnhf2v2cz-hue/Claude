# omicsaudit

Black-box audit toolkit for omics biomarker pipelines (R package + benchmark zoo).
Working name is a placeholder, NOT checked: search CRAN, Bioconductor and GitHub
before settling. Do not use `pipeaudit`.

A pipeline is `pipeline(X, y)`: raw samples x features matrix and outcome in,
`list(selected = <character>, performance = <number>)` out. Audits control the
inputs; they never parse the user's code.

Existing work to call or document overlap with, not rebuild: `bioLeak`, `nestedcv`.
Make no novelty claims until a literature/CRAN/Bioconductor search is done.

Build order: 1 skeleton, 2 simulator, 3 first zoo entries, 4 `audit_planted`,
5 `zoo_score` + rest of zoo, 6 `audit_variants`/`stability`/`null`/`confound`,
7 public proteomics data (data-raw/), 8 report + vignette.
Show tests before moving on from each step. Public or simulated data only.
Record the seed in every output. Planted signals must respect MNAR missingness.
