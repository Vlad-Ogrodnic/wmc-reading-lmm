# One-time installation of the R packages the models need.
# Run:  Rscript install_r_packages.R
#
# Installs into your personal R library, which also works when R's own
# library folder is not writable (the default on Windows).

packages <- c("data.table", "lme4", "lmerTest", "performance")

lib <- Sys.getenv("R_LIBS_USER")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))

missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  install.packages(missing, lib = lib, repos = "https://cloud.r-project.org")
}
cat("R packages ready:", paste(packages, collapse = ", "), "\n")
