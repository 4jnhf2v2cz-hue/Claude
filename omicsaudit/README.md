# omicsaudit

Black-box audit toolkit for omics biomarker pipelines, plus a "zoo" of
deliberately flawed pipelines with known answers. **Early development**:
build steps 1-3 only (skeleton, simulator, first two zoo entries).

```r
sim <- simulate_omics(n = 80, p = 200, n_signal = 15, effect = 1.5, seed = 1)
sim
zoo_load("reference_nested_cv")$pipeline(sim$X, sim$y)
```

`simulate_omics()` generates raw intensities with a planted signal, per-feature
batch shifts (optionally confounded with the outcome) and abundance-dependent
(MNAR) missingness.

Detection rates against the zoo will be recorded here once `zoo_score()` exists.
