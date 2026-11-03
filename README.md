# wmc-reading-lmm

Does working memory capacity (WMC) predict how long people spend reading each word?

This repository takes word-level eye-tracking data and working memory scores from the
[MultiplEYE](https://github.com/MultiplEYE-COST) project and fits linear mixed-effects models that answer two questions:

1. Do readers with higher WMC read faster overall, once word length and frequency are accounted for?
2. Does the WMC advantage grow for harder (rarer or longer) words?

Two reading measures are analysed separately: total fixation time (TFT, all time spent on a word, including re-reading)
and first-pass reading time (FPRT, the time spent on a word the first time the eyes reach it). For each, three models
are compared, each adding one step:

- M0: the word's length and frequency (and those of the previous word);
- M1: M0 + WMC;
- M2: M1 + whether the WMC effect changes with word length and frequency.

It works for any MultiplEYE language and lab. How the analysis works, and its limitations, are described in
[METHOD.md](METHOD.md).

## Relation to MultiplEYE

The input data (eye-tracking reading measures and psychometric test scores) are produced by the
[MultiplEYE preprocessing pipeline](https://github.com/MultiplEYE-COST/multipleye-preprocessing)
(MIT License, © MultiplEYE). This repository does not include any data and does not depend on the pipeline's code;
it only reads the files the pipeline writes.

## Requirements

- Python 3.10 or newer, with [uv](https://docs.astral.sh/uv/) (or pip).
- R 4.x, with the packages `data.table`, `lme4`, `lmerTest` and `performance`.

## Installation

```bash
git clone https://github.com/Vlad-Ogrodnic/wmc-reading-lmm.git
cd wmc-reading-lmm
uv sync                           # Python packages (or: pip install -e .)
Rscript install_r_packages.R      # R packages, once
```

If you use pip instead of uv, run the commands below without `uv run`.

`install_r_packages.R` installs into your personal R library, so it also works when R's own library folder isn't writable
(the default on Windows).

On Windows, `Rscript` is usually not on the PATH. Use its full path, e.g.
`"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" install_r_packages.R`. The analysis itself finds R on its own, also when run
from WSL.

## Try it on the example data

`example/` contains a small synthetic dataset (made-up words, reading times and scores, with a built-in WMC effect) in
the same format as the pipeline's output:

```bash
uv run python -m wmc_lmm.run --config example/config.yaml
```

This takes about a minute and writes the results to `example/results/`. If it finishes, your installation works.

## Run it on your data

### 1. Make a config file

Copy `config.example.yaml` to `config.yaml` and fill in your paths. Relative paths are relative
to the config file's folder.

| Setting | What it is |
|---|---|
| `language` | The [ISO 639-1](https://en.wikipedia.org/wiki/List_of_ISO_639_language_codes) code of the text language, used for word frequencies. In MultiplEYE it's the first code in your data collection name: `MultiplEYE_DE_CH_Zurich_...` → `de`. |
| `reading_measures_folder` or `reading_measures_file` | The reading measures, in one of two forms (see below). |
| `psychometric_overview` | The psychometric overview CSV written by the pipeline, e.g. `psychometric_overview_<data_collection>_merged.csv`. |
| `wmc_column` | *Optional.* The WMC score column in that file. Default: `LWMC_Total_score_mean`. |
| `output_folder` | *Optional.* Where results are written. Default: a `results` folder next to the config file. |
| `word_frequency_file` | *Optional.* Your own word-frequency list (see below). |

Reading measures can be given in either form:

- `reading_measures_folder`: the pipeline's `reading_measures/` folder, with one subfolder per session and one file
  per text (`<session>_trial_<n>_<text>_reading_measures.csv`). Practice texts are skipped automatically. This is the
  usual choice.
- `reading_measures_file`: a single CSV with all reading measures already merged. It needs a column with the session id
  and one with the text name (set their names with `session_column` and `text_column`; defaults: `participant_id`,
  `text_name`). Remove practice texts from it beforehand.

Either way, these columns are used: `page`, `word_idx`, `word`, `skipped`, `FPF`, `TFT`, `FPRT`. Any others are ignored.

Word frequencies come from [wordfreq](https://github.com/rspeer/wordfreq), which covers about 40 languages. For a
language it doesn't cover, provide your own list with `word_frequency_file`: a CSV with columns `word` and `zipf`
(Zipf = log10 of the word's frequency per billion words).

### 2. Run

```bash
uv run python -m wmc_lmm.run --config config.yaml
```

On a full dataset (a few hundred thousand words per reading measure) fitting the models takes roughly an hour. Every
fitted model is saved, so if anything stops after fitting, rerunning reuses them.

Two options:
- `--prepare-only`: only build the word-level table, without fitting the models.
- `--models-only`: skip the preparation and only redo the models' result tables and plots (reuses the saved models, so
  this takes a few minutes).

## Results

Everything is written to `output_folder`. Start with `summary.md`: the main results in a few sentences, with each
effect marked as reliable or not.

The other files hold the full details, explained in [METHOD.md](METHOD.md#outputs):

| File | What it tells |
|---|---|
| `coefficients.csv` | How big each effect is. One row per effect (e.g. word length, WMC) per model, as "reading time changes by X %", with a range of plausible values (95% confidence interval) and a p-value. |
| `model_comparison.csv` | Whether WMC matters at all. Tests whether adding WMC to a model that only knows the words makes it fit the data better, and then whether letting the WMC effect depend on word difficulty helps further. |
| `variance_explained.csv` | How much WMC matters. What share of the differences in reading times each model explains. |
| `wmc_difference_by_frequency_TFT.png`, `..._FPRT.png` | Where WMC matters. How much faster high-WMC readers are than low-WMC readers, from rare to frequent words. |
| `reading_time_by_frequency_TFT.png`, `..._FPRT.png` | The same, as predicted reading times (ms) for low- and high-WMC readers. |
| `exclusions.csv` | How many words and participants are left after each exclusion step (the numbers to report). |
| `word_table.csv`, `predictor_scales.csv`, `fitted_models/` | Intermediate files: the table the models are fitted on, what 1 SD of each predictor is in real units, and the saved models. |

## License

MIT, see [LICENSE](LICENSE).
