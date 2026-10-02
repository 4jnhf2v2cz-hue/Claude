# REFERENCE (correct): preprocessing is fitted on training rows only, and the
# number of selected features is tuned by an inner CV that sees only the outer
# training rows. See nested_cv_pipeline() in _common.R.

pipeline <- function(X, y, ...) nested_cv_pipeline(X, y, ...)
