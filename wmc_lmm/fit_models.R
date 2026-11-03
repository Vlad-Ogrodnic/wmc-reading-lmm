# Fits the models and writes the results. Called by run.py; reads the
# word-level table run.py wrote into the output folder.
#
# For each reading measure (TFT, FPRT), three nested models:
#   M0: word length + word frequency (+ the previous word's length and frequency)
#   M1: M0 + WMC
#   M2: M1 + WMC x length + WMC x frequency
# with random effects for participants and for words. See METHOD.md.
#
# Usage: Rscript fit_models.R <output_folder>

suppressPackageStartupMessages({
  library(data.table)
  library(lme4)
  library(lmerTest)
  library(performance)
})

this_file <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])
source(file.path(dirname(normalizePath(this_file)), "lmm_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: Rscript fit_models.R <output_folder>")
out_dir <- args[1]

input_csv <- file.path(out_dir, "word_table.csv")
cache_dir <- file.path(out_dir, "fitted_models")
stamp <- unname(tools::md5sum(input_csv))

log_progress("reading", input_csv)
data <- fread(input_csv, colClasses = list(character = c("participant_id", "item_id")))
data[, participant_id := factor(participant_id)]
data[, item_id := factor(item_id)]
scales <- fread(file.path(out_dir, "predictor_scales.csv"))

coefficients <- list()
comparisons <- list()
variance <- list()
summary <- summary_header(scales)

for (dv in DEPENDENT_VARIABLES) {
  dv_data <- data[get(paste0("use_", dv)) == TRUE]
  log_progress(dv, ":", nrow(dv_data), "rows,", uniqueN(dv_data$participant_id), "participants")

  chosen <- choose_random_structure(dv, dv_data, cache_dir, stamp)
  fits <- list(
    M0 = fit_model(dv, "M0", FIXED_M0, chosen$name, dv_data, cache_dir, stamp),
    M1 = fit_model(dv, "M1", FIXED_M1, chosen$name, dv_data, cache_dir, stamp),
    M2 = chosen$fit
  )

  for (model_name in names(fits)) {
    coefficients[[length(coefficients) + 1]] <- coefficient_table(fits[[model_name]]$model, dv, model_name)
  }

  comparison <- anova(fits$M0$model, fits$M1$model, fits$M2$model, refit = FALSE)
  comparisons[[dv]] <- data.table(
    dv = dv,
    model = names(fits),
    adds = c("length + frequency (+ previous word)", "+ WMC", "+ WMC x length, WMC x frequency"),
    chi_square_vs_previous = comparison$Chisq,
    df_vs_previous = comparison$Df,
    p_vs_previous = comparison$`Pr(>Chisq)`,
    random_structure = chosen$name,
    warnings = sapply(fits, function(f) paste(f$warnings, collapse = " | "))
  )

  r2 <- lapply(fits, function(f) r_squared(f$model))
  marginal <- sapply(r2, `[[`, "marginal")
  variance[[dv]] <- data.table(
    dv = dv,
    model = names(fits),
    r2_marginal = marginal,
    r2_conditional = sapply(r2, `[[`, "conditional"),
    r2_marginal_gain_vs_previous = c(NA, diff(marginal))
  )

  summary <- c(summary, summary_lines(
    fits, dv, uniqueN(dv_data$participant_id), nrow(dv_data), variance[[dv]], scales
  ))

  plots <- list(wmc_difference_by_frequency = plot_wmc_difference, reading_time_by_frequency = plot_reading_time)
  for (name in names(plots)) {
    plot_path <- file.path(out_dir, paste0(name, "_", dv, ".png"))
    plots[[name]](fits$M2$model, dv, scales, plot_path)
    log_progress("wrote", plot_path)
  }
}

outputs <- list(
  coefficients = rbindlist(coefficients),
  model_comparison = rbindlist(comparisons),
  variance_explained = rbindlist(variance)
)
for (name in names(outputs)) {
  path <- file.path(out_dir, paste0(name, ".csv"))
  fwrite(outputs[[name]], path)
  log_progress("wrote", path)
}

summary_path <- file.path(out_dir, "summary.md")
writeLines(summary, summary_path)
log_progress("wrote", summary_path)
