# FLAW (design level): a technically correct nested-CV pipeline that ignores
# batch, run on data in which batch is confounded with the outcome. Features
# that differ by batch look predictive; honest CV cannot tell batch from
# biology. The flaw is in the data/analysis design, so the code is the same
# as the reference; the audit must catch it from the data.

pipeline <- function(X, y, ...) nested_cv_pipeline(X, y, ...)
