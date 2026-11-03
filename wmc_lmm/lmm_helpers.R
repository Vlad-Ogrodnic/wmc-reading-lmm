# Functions used by fit_models.R: model formulas, fitting (with a cache),
# and turning fitted models into result tables and plots.

DEPENDENT_VARIABLES <- c("TFT", "FPRT")

FIXED_M0 <- "length_z + freq_z + prev_length_z + prev_freq_z"
FIXED_M1 <- paste(FIXED_M0, "+ wmc_z")
FIXED_M2 <- paste(FIXED_M1, "+ wmc_z:length_z + wmc_z:freq_z")

# Tried in order on the most complex model (M2); the first one that fits
# without warnings is then used for M0, M1 and M2 alike, so they can be compared.
RANDOM_CANDIDATES <- c(
  full = "(1 + length_z + freq_z | participant_id) + (1 | item_id)",
  uncorrelated = "(1 + length_z + freq_z || participant_id) + (1 | item_id)",
  freq_slope_only = "(1 + freq_z || participant_id) + (1 | item_id)",
  intercepts_only = "(1 | participant_id) + (1 | item_id)"
)

CONTROL <- lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))

# "Per SD" depends on how varied the sample is; "per 0.1 WMC score" doesn't,
# so it can be compared across labs using the same test.
WMC_SCORE_STEP <- 0.1

log_progress <- function(...) {
  cat(format(Sys.time(), "%H:%M:%S"), "-", ..., "\n")
}

# Every fitted model is saved in cache_dir and reused on a rerun as long as the
# input data (fingerprinted by `stamp`) is unchanged, so a crash or a change in
# the reporting code doesn't cost the fitting time again. Delete the folder to refit.
fit_model <- function(dv, model_name, fixed, random_name, data, cache_dir, stamp) {
  cache_path <- file.path(cache_dir, paste0(dv, "_", model_name, "_", random_name, ".rds"))
  if (file.exists(cache_path)) {
    cached <- readRDS(cache_path)
    if (identical(cached$stamp, stamp)) {
      log_progress(dv, ": reusing saved", model_name, "(", random_name, ")")
      return(cached[c("model", "warnings")])
    }
  }

  log_progress(dv, ": fitting", model_name, "with random structure", random_name)
  formula <- as.formula(paste0("log(", dv, ") ~ ", fixed, " + ", RANDOM_CANDIDATES[[random_name]]))
  warnings <- character(0)
  model <- withCallingHandlers(
    lmer(formula, data = data, REML = FALSE, control = CONTROL),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  warnings <- c(warnings, model@optinfo$conv$lme4$messages)
  if (isSingular(model)) warnings <- c(warnings, "singular fit")
  fit <- list(model = model, warnings = unique(warnings))

  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  saveRDS(c(fit, list(stamp = stamp)), cache_path)
  fit
}

choose_random_structure <- function(dv, data, cache_dir, stamp) {
  for (name in names(RANDOM_CANDIDATES)) {
    fit <- fit_model(dv, "M2", FIXED_M2, name, data, cache_dir, stamp)
    if (length(fit$warnings) == 0) return(list(name = name, fit = fit))
    log_progress(dv, ": rejected", name, "-", paste(fit$warnings, collapse = " | "))
  }
  log_progress(dv, ": WARNING, no structure fitted cleanly; using intercepts_only despite warnings")
  list(name = "intercepts_only", fit = fit)
}

scale_value <- function(scales, predictor, column) {
  value <- scales[[column]][scales$predictor == predictor]
  if (length(value) == 0) NA_real_ else value
}

percent <- function(log_effect) (exp(log_effect) - 1) * 100

per_wmc_score_step <- function(log_effect, scales) {
  log_effect * WMC_SCORE_STEP / scale_value(scales, "wmc", "sd")
}

wmc_level_label <- function(direction, scales) {
  score <- scale_value(scales, "wmc", "mean") + direction * scale_value(scales, "wmc", "sd")
  sd_label <- ifelse(direction < 0, "-1 SD", "+1 SD")
  if (is.na(score)) sd_label else sprintf("%s, score %.2f", sd_label, score)
}

# R names an interaction after the order the variables first appear in the
# formula (e.g. "freq_z:wmc_z"), so look it up in either order.
interaction_name <- function(term, estimates) {
  candidates <- c(paste0(term, ":wmc_z"), paste0("wmc_z:", term))
  found <- candidates[candidates %in% names(estimates)]
  if (length(found) == 0) NA_character_ else found[[1]]
}

coefficient_table <- function(model, dv, model_name) {
  coefs <- summary(model)$coefficients
  ci <- confint(model, method = "Wald", parm = "beta_")
  terms <- rownames(coefs)
  # The intercept is a baseline reading time, not an effect, so it has no percent change.
  as_percent <- function(values) ifelse(terms == "(Intercept)", NA_real_, percent(values))
  data.table(
    dv = dv,
    model = model_name,
    term = terms,
    percent_change = as_percent(coefs[, "Estimate"]),
    percent_ci_low = as_percent(ci[terms, 1]),
    percent_ci_high = as_percent(ci[terms, 2]),
    p_value = coefs[, "Pr(>|t|)"],
    estimate = coefs[, "Estimate"],
    std_error = coefs[, "Std. Error"],
    df = coefs[, "df"]
  )
}

# ---- summary.md: the main results in words ----

DV_LABELS <- c(TFT = "Total fixation time (TFT)", FPRT = "First-pass reading time (FPRT)")

# Estimate, 95% Wald confidence interval and p-value of one term (log scale).
term_stats <- function(model, term) {
  coefs <- summary(model)$coefficients
  ci <- confint(model, method = "Wald", parm = term)
  list(estimate = coefs[term, "Estimate"], low = ci[1, 1], high = ci[1, 2], p = coefs[term, "Pr(>|t|)"])
}

is_reliable <- function(stats) stats$low > 0 || stats$high < 0

reliability <- function(stats) {
  if (is_reliable(stats)) "Reliable." else "Not reliable (the confidence interval includes 0)."
}

format_p <- function(p) {
  if (p < 0.001) "p < .001" else paste("p =", sub("^0", "", sprintf("%.3f", p)))
}

# A percent change in reading time, as "2.3% less" / "1.5% more".
amount <- function(pct) sprintf("%.1f%% %s", abs(pct), ifelse(pct < 0, "less", "more"))

# A confidence interval of percent changes, in words.
amount_range <- function(low, high) {
  if (high < 0) return(sprintf("%.1f%% to %.1f%% less", abs(high), abs(low)))
  if (low > 0) return(sprintf("%.1f%% to %.1f%% more", low, high))
  sprintf("%.1f%% less to %.1f%% more", abs(low), high)
}

wmc_score <- function(direction, scales) {
  scale_value(scales, "wmc", "mean") + direction * scale_value(scales, "wmc", "sd")
}

summary_lines <- function(fits, dv, n_participants, n_words, variance, scales) {
  step <- function(x) percent(per_wmc_score_step(x, scales))
  wmc <- term_stats(fits$M1$model, "wmc_z")
  lines <- c(
    paste("##", DV_LABELS[[dv]]), "",
    sprintf("Data: %d participants, %s words read in total.", n_participants, format(n_words, big.mark = ",")), "",
    sprintf(
      "- **Overall WMC effect** (M1): readers with a %.1f higher WMC score spent %s time per word (95%% CI: %s; %s). %s",
      WMC_SCORE_STEP, amount(step(wmc$estimate)), amount_range(step(wmc$low), step(wmc$high)), format_p(wmc$p),
      reliability(wmc)
    )
  )

  b <- fixef(fits$M2$model)
  word_effects <- list(
    freq_z = list(title = "Rare vs frequent words", word = "a word 1 SD more frequent", harder = -1,
                  harder_words = "rare", easier_words = "frequent"),
    length_z = list(title = "Short vs long words", word = "a word 1 SD longer", harder = 1,
                    harder_words = "long", easier_words = "short")
  )
  for (main in names(word_effects)) {
    info <- word_effects[[main]]
    stats <- term_stats(fits$M2$model, interaction_name(main, b))
    conclusion <- if (!is_reliable(stats)) {
      "No reliable difference (the confidence interval includes 0)."
    } else {
      # WMC effect for harder vs easier words: more negative = bigger advantage for high-WMC readers.
      wmc_on_harder <- b[["wmc_z"]] + stats$estimate * info$harder
      wmc_on_easier <- b[["wmc_z"]] - stats$estimate * info$harder
      sprintf("Reliable: the WMC advantage is larger for %s words.",
              if (wmc_on_harder < wmc_on_easier) info$harder_words else info$easier_words)
    }
    lines <- c(lines, sprintf(
      "- **%s** (M2): %s takes %s time for low-WMC readers (score %.2f) and %s for high-WMC readers (score %.2f); %s. %s",
      info$title, info$word,
      amount(percent(b[[main]] - stats$estimate)), wmc_score(-1, scales),
      amount(percent(b[[main]] + stats$estimate)), wmc_score(1, scales),
      format_p(stats$p), conclusion
    ))
  }

  gain <- 100 * variance$r2_marginal_gain_vs_previous
  if (!any(is.na(gain[2:3]))) {
    lines <- c(lines, sprintf(
      "- **How much WMC explains:** %.1f%% of the variation in reading times (%.1f%% together with its interactions with frequency and length).",
      gain[2], gain[2] + gain[3]
    ))
  }
  c(lines, "")
}

summary_header <- function(scales) {
  wmc_column <- scales$note[scales$predictor == "wmc"]
  c(
    "# Results summary", "",
    sprintf(
      "WMC score (`%s`): mean %.2f, SD %.2f. \"Low WMC\" and \"high WMC\" below are 1 SD below and above the mean.",
      wmc_column, scale_value(scales, "wmc", "mean"), scale_value(scales, "wmc", "sd")
    ),
    "\"Reliable\" means the 95% confidence interval (CI) does not include 0.",
    "Full numbers: coefficients.csv, model_comparison.csv, variance_explained.csv. How to read them: METHOD.md.", ""
  )
}

r_squared <- function(model) {
  # A tiny tolerance: with the default, a random-effect variance that is
  # practically zero makes r2_nakagawa drop ALL random effects from the total
  # variance, which inflates R2. This way it just contributes ~0.
  r2 <- tryCatch(r2_nakagawa(model, tolerance = 1e-15), error = function(e) NULL)
  if (!is.list(r2)) return(c(marginal = NA_real_, conditional = NA_real_))
  c(marginal = unname(r2$R2_marginal), conditional = unname(r2$R2_conditional))
}

# Reading-time difference between high (+1 SD) and low (-1 SD) WMC readers,
# in percent, as a function of word frequency, with a 95% confidence band of
# the difference. Where the band lies entirely below 0, high-WMC readers are
# reliably faster. Other predictors are held at their mean.
plot_wmc_difference <- function(model, dv, scales, out_path) {
  b <- fixef(model)
  v <- as.matrix(vcov(model))
  freq_z <- seq(-2, 2, length.out = 100)
  x <- matrix(0, nrow = length(freq_z), ncol = length(b), dimnames = list(NULL, names(b)))
  x[, "wmc_z"] <- 2
  x[, interaction_name("freq_z", b)] <- 2 * freq_z
  diff_log <- drop(x %*% b)
  se <- sqrt(rowSums((x %*% v) * x))
  fit <- percent(diff_log)
  low <- percent(diff_log - 1.96 * se)
  high <- percent(diff_log + 1.96 * se)

  freq_mean <- scale_value(scales, "freq", "mean")
  freq_sd <- scale_value(scales, "freq", "sd")
  has_scale <- !is.na(freq_mean) && !is.na(freq_sd)
  xs <- if (has_scale) freq_mean + freq_z * freq_sd else freq_z
  x_label <- if (has_scale) "word frequency (Zipf; higher = more frequent)" else "word frequency (z-score)"

  png(out_path, width = 1500, height = 1100, res = 200)
  plot(xs, fit, type = "n", ylim = range(c(low, high, 0)),
       xlab = x_label, ylab = "reading time difference (%)",
       main = sprintf("%s: high vs low WMC readers (%s vs %s)", dv,
                      wmc_level_label(1, scales), wmc_level_label(-1, scales)))
  polygon(c(xs, rev(xs)), c(low, rev(high)), col = adjustcolor("#0072B2", alpha.f = 0.2), border = NA)
  abline(h = 0, lty = 2, col = "grey40")
  lines(xs, fit, lwd = 2, col = "#0072B2")
  mtext("model M2; below 0 = high-WMC readers faster; shaded: 95% confidence band of the difference",
        side = 3, line = 0.3, cex = 0.65)
  dev.off()
}
