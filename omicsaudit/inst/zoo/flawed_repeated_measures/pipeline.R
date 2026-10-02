# FLAW: several samples per subject (row names `<subject>_r<n>`) are split at
# random across train and test folds, so the model is tested on subjects it has
# already seen. Subject-specific offsets let it "recognise" them.

pipeline <- function(X, y, ...) nested_cv_pipeline(X, y, grouped = FALSE, ...)
