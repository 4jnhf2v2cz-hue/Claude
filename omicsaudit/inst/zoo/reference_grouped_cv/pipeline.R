# REFERENCE (correct for repeated measures): all samples of one subject stay
# in the same fold at both CV levels.

pipeline <- function(X, y, ...) nested_cv_pipeline(X, y, grouped = TRUE, ...)
