# Method

## Question

Do readers with higher working memory capacity (WMC) spend less time on each word, once word length and frequency are
taken into account? And is the WMC effect larger for longer or rarer words?

## Data

Two reading-time measures, analysed separately:

- TFT (total fixation time): all time spent on a word, including re-reading.
- FPRT (first-pass reading time): time spent on a word the first time the eyes reach it.

Reading times are log-transformed, as is usual: this reduces the influence of a few very long times, and makes effects
proportional (a word effect adds a percentage of each reader's usual time). All results are therefore percentages.

WMC is each participant's score from the psychometric overview (by default `LWMC_Total_score_mean`).

Exclusions, in this order (the numbers left after each step are in `exclusions.csv`):

1. practice texts;
2. tokens without letters (spaces, punctuation, numbers);
3. the first word on each page, which has no preceding word;
4. participants without a WMC score;
5. for each reading measure: words for which it is not defined (TFT: never fixated; FPRT: not fixated in the first
   pass), times under 80 ms, and times more than 3 SD from that participant's own average (on the log scale).

## Predictors

- Word length: number of letters.
- Word frequency: how common the exact word form is, on the Zipf scale (3 = once per million words, each extra point =
  ten times more frequent), from wordfreq or from a list you provide. Words missing from the list get a value half a
  point below the list's lowest value.
- Length and frequency of the preceding word, because difficulty on one word often carries over to the next.
- WMC.

All predictors are standardized (expressed in standard deviations from their mean), so each effect is "per 1 SD". What
1 SD is in real units (letters, Zipf points, WMC score) is in `predictor_scales.csv`.

## Models

Linear mixed-effects models (R package `lme4`), fitted separately for TFT and FPRT:

| Model | Contains |
|---|---|
| M0 | word length, word frequency, and the preceding word's length and frequency |
| M1 | M0 + WMC |
| M2 | M1 + WMC × length and WMC × frequency (whether the WMC effect changes with word length or frequency) |

Besides these effects, each model includes random effects, which account for each participant and each word appearing
many times:

- for each participant: their own baseline reading speed, and their own sensitivity to word length and frequency;
- for each word in the texts (identified by text, page and position): its own baseline difficulty.

Sometimes a model cannot be estimated with all of these (the estimation fails or one of them comes out as zero). In
that case the random effects are simplified step by step: first without the correlations between them, then keeping
only the participant's sensitivity to frequency, then keeping only the baselines. The first version that works for M2
is used for all three models, so that they stay comparable. `model_comparison.csv` shows which version was used.

For reference, in `lme4` notation the full model is:

```
log(RT) ~ length + freq + prev_length + prev_freq + WMC + WMC:length + WMC:freq
          + (1 + length + freq | participant) + (1 | word)
```

## Statistics

- Comparing models: each model is tested against the previous one with a likelihood-ratio test, which asks whether
  the added terms make the model fit the data clearly better.
- Individual effects: each effect gets a p-value (how likely an effect at least this large would be if there were no
  real effect) and a 95% confidence interval (the range of values compatible with the data). Both use the same
  t-test from `lmerTest` (Satterthwaite method), so the interval excludes 0 exactly when p < .05.
- Variance explained: R², the share of the variation in reading times that a model accounts for. Marginal R² counts only the effects in the table above (word
  properties and WMC); conditional R² also counts the random effects, i.e. the differences between participants and
  between words.
- Percentages: the models work on log reading times, so each effect β is converted to a percent change in reading time
  as (e^β − 1) × 100. For example, β = −0.032 means 3.2% less time per 1 SD of the predictor.
- The WMC effect is also given per 0.1 points of WMC score rather than per 1 SD. Unlike "per 1 SD", this doesn't
  depend on how much WMC varies in a given sample, so it can be compared across labs.

## Outputs

Click a file name to expand its description.

<details>
<summary><code>summary.md</code></summary>

Three results per reading measure, each marked "reliable" when p < .05 (its 95% confidence interval does not include 0):

- Overall WMC effect: the `wmc_z` effect in M1, converted to "per 0.1 WMC score" (see [Statistics](#statistics)). M1 is used because in
  M2 the `wmc_z` effect only applies to a word of average length and frequency.
- Rare vs frequent and short vs long words: the `freq_z:wmc_z` and `length_z:wmc_z` interactions in M2. They are shown
  as the effect of a 1 SD more frequent (or longer) word for a low-WMC reader (WMC 1 SD below the mean: the word effect
  minus the interaction) and a high-WMC reader (1 SD above: the word effect plus the interaction). When the interaction
  is reliable, the summary says for which words the WMC advantage is larger.
- How much WMC explains: the gain in marginal R² from M0 to M1 (WMC alone) and from M0 to M2 (WMC with its
  interactions).

</details>

<details>
<summary><code>coefficients.csv</code></summary>

One row per effect per model and reading measure.

| Column | Content |
|---|---|
| `dv`, `model`, `term` | Reading measure, model, and effect. Terms: `length_z`, `freq_z` (current word), `prev_length_z`, `prev_freq_z` (preceding word), `wmc_z`, and the interactions `length_z:wmc_z`, `freq_z:wmc_z`. |
| `percent_change`, `percent_ci_low`, `percent_ci_high` | The effect as a percent change in reading time per 1 SD, with its 95% confidence interval. Empty for the intercept, which is the baseline reading time (e^`estimate` ms for an average word and reader), not an effect. |
| `p_value` | p-value of the effect. |
| `estimate`, `std_error`, `df` | The effect on the log scale, its standard error, and the degrees of freedom used for the p-value. For WMC these are typically close to the number of participants rather than the number of words, since WMC varies only between participants. |

</details>

<details>
<summary><code>model_comparison.csv</code></summary>

One row per model and reading measure.

| Column | Content |
|---|---|
| `adds` | What the model adds to the previous one. |
| `chi_square_vs_previous`, `df_vs_previous`, `p_vs_previous` | The likelihood-ratio test against the previous model: test statistic, number of added terms, p-value. Empty for M0. |
| `random_structure` | The random-effects version used (`full`, `uncorrelated`, `freq_slope_only` or `intercepts_only`; see [Models](#models)). |
| `warnings` | Any problems reported during estimation. Empty if there were none. |

</details>

<details>
<summary><code>variance_explained.csv</code></summary>

`r2_marginal` and `r2_conditional` for each model, and `r2_marginal_gain_vs_previous`: how much marginal R² increases
over the previous model. The gain is usually small even when the WMC effect is reliable, because reading times vary a
lot from word to word, and a consistent difference of a few percent between readers is a small share of that variation.

</details>

<details>
<summary><code>wmc_difference_by_frequency_*.png</code></summary>

The predicted difference in reading time (%) between a reader 1 SD above and one 1 SD below the mean WMC, for word
frequencies from 2 SD below to 2 SD above the mean, from the M2 estimates, with all other predictors at their average.
The shaded band is the 95% confidence interval of this difference, computed from the uncertainty of the model's
estimates. Where it lies entirely below 0, high-WMC readers are reliably faster on words of that frequency.

</details>

<details>
<summary><code>reading_time_by_frequency_*.png</code></summary>

The same M2 estimates shown as predicted reading times (ms): one line for a reader 1 SD below and one for a reader
1 SD above the mean WMC, each with its own 95% confidence band, over the same range of word frequencies. It shows the
actual reading times behind the difference above.

</details>

## Language notes

- Length counts letters in any script; for scripts like Chinese this means characters.
- Frequency is per word form, not per dictionary form, so rare forms of common words get low values in languages with
  many word forms.
- "Preceding word" follows `word_idx`, which follows the order of the text in the pipeline's output.
- For languages written without spaces, a word is whatever the pipeline defined as a word area of interest.

## Limitations

- The results are correlational: vocabulary, reading experience and education are not controlled for.
- WMC varies only between participants, so the number of participants limits how precisely its effect can be estimated.
- wordfreq's smaller lists only contain words occurring more than about once per million; rarer words all get the
  same value (`predictor_scales.csv` reports how many words this affects).
- A rare word repeated within a text becomes familiar, but the model doesn't account for repetition.
- Length and frequency reflect word recognition, not working memory load.
- Words at the start and end of a line are not excluded, because the reading measures don't mark where lines start.
- The WMC effect is not allowed to differ between words, which can make its p-values slightly too small.
- TFT and FPRT mean two tests per question, so a single p-value just under .05 should be read with caution.
