# Generates the SYNTHETIC example data in this folder. Nothing here comes from
# real participants: words, reading times and WMC scores are all made up, with
# a small built-in WMC effect so the example has something to find.
#
# Run from the repository root:  Rscript example/make_example_data.R
#
# Output, in the same format as the MultiplEYE preprocessing pipeline:
#   example/reading_measures/<session>/<session>_trial_<n>_<text>_reading_measures.csv
#   example/psychometric_overview.csv

set.seed(42)
out <- "example"

words <- c(
  "the", "of", "and", "to", "in", "is", "was", "for", "on", "with", "that", "it", "as", "by", "at",
  "house", "water", "people", "children", "morning", "between", "important", "different", "government",
  "question", "language", "together", "something", "remember", "beautiful",
  "milk", "cows", "farm", "grass", "village", "market", "bridge", "garden", "letter", "window",
  "nutritional", "riboflavin", "agricultural", "cardiovascular", "metabolism", "photosynthesis",
  "ubiquitous", "ephemeral", "meticulous", "quintessential", "juxtaposition", "serendipity"
)
texts <- c("Milk", "Farm", "River")
n_pages <- 2
words_per_page <- 30
n_participants <- 40

# Same word sequence for everyone, as in a real experiment.
stimuli <- expand.grid(word_idx = seq_len(words_per_page) - 1, page = paste0("page_", seq_len(n_pages)), text = texts,
                       stringsAsFactors = FALSE)
stimuli$word <- sample(words, nrow(stimuli), replace = TRUE)
stimuli$word[stimuli$word_idx == 0] <- tools::toTitleCase(stimuli$word[stimuli$word_idx == 0])
stimuli$word[stimuli$word_idx == words_per_page - 1] <- paste0(stimuli$word[stimuli$word_idx == words_per_page - 1], ".")
stimuli$len <- nchar(gsub("[^A-Za-z]", "", stimuli$word))
stimuli$rank <- match(tolower(gsub("[^A-Za-z]", "", stimuli$word)), words)  # lower = more frequent
stimuli$item_effect <- rnorm(nrow(stimuli), 0, 0.08)

wmc <- round(pmin(1, pmax(0.3, rnorm(n_participants, 0.7, 0.14))), 3)
length_z <- as.numeric(scale(stimuli$len))
rarity_z <- as.numeric(scale(stimuli$rank))

dir.create(file.path(out, "reading_measures"), recursive = TRUE, showWarnings = FALSE)
for (p in seq_len(n_participants)) {
  session <- sprintf("%03d_EN_XX_1_ET1", p)
  session_dir <- file.path(out, "reading_measures", session)
  dir.create(session_dir, showWarnings = FALSE)
  wmc_z <- (wmc[p] - 0.7) / 0.14
  speed <- rnorm(1, 0, 0.12)

  for (t in seq_along(texts)) {
    rows <- stimuli[stimuli$text == texts[t], ]
    idx <- which(stimuli$text == texts[t])
    log_tft <- 5.4 + speed + 0.10 * length_z[idx] + 0.06 * rarity_z[idx] - 0.08 * wmc_z -
      0.04 * wmc_z * rarity_z[idx] + rows$item_effect + rnorm(nrow(rows), 0, 0.3)
    skip_probability <- plogis(-1 - 0.8 * length_z[idx] - 0.6 * rarity_z[idx])
    skipped <- as.integer(runif(nrow(rows)) < skip_probability)
    tft <- ifelse(skipped == 1, 0, round(exp(log_tft)))
    fpf <- ifelse(skipped == 1, 0, as.integer(runif(nrow(rows)) < 0.9))
    fprt <- ifelse(fpf == 1, round(tft * runif(nrow(rows), 0.6, 1)), 0)

    reading_measures <- data.frame(
      page = rows$page, word_idx = rows$word_idx, word = rows$word,
      skipped = skipped, FPF = fpf, TFT = tft, FPRT = fprt
    )
    file <- sprintf("%s_trial_%d_%s_reading_measures.csv", session, t, texts[t])
    write.csv(reading_measures, file.path(session_dir, file), row.names = FALSE)
  }

  # A practice text, which the analysis must skip.
  practice <- data.frame(page = "page_1", word_idx = 0:4, word = c("This", "is", "a", "practice", "text."),
                         skipped = 0, FPF = 1, TFT = 200, FPRT = 200)
  write.csv(practice, file.path(session_dir, sprintf("%s_PRACTICE_trial_1_Practice_reading_measures.csv", session)),
            row.names = FALSE)
}

# Psychometric overview; the last two participants have no WMC score, to show that exclusion.
overview <- data.frame(participant_id = sprintf("%03d", seq_len(n_participants)), LWMC_Total_score_mean = wmc)
overview$LWMC_Total_score_mean[(n_participants - 1):n_participants] <- NA
write.csv(overview, file.path(out, "psychometric_overview.csv"), row.names = FALSE, na = "")

cat("Example data written to", out, "\n")
