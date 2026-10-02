# REFERENCE: same code as the confounded entry, but run on data with a strong
# batch effect that is NOT confounded with the outcome. A good audit must
# not raise a confounding alarm here just because batch is visible in the data.

pipeline <- function(X, y, ...) nested_cv_pipeline(X, y, ...)
