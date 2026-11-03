"""Build the word-level table the models are fitted on.

One row per word read by one participant, with the word's length and
frequency, the previous word's length and frequency, the participant's WMC
score, and which rows enter the TFT and the FPRT models. Every choice made
here is explained in METHOD.md.
"""

import re
from dataclasses import dataclass

import numpy as np
import pandas as pd
from wordfreq import available_languages, zipf_frequency

from wmc_lmm.config import Config
from wmc_lmm.inputs import read_frequency_list, read_reading_measures, read_wmc

# Reading times shorter than this are usually artefacts, not real word reading.
MIN_READING_TIME_MS = 80
# A reading time more than this many SDs from the participant's own mean (log scale) is an outlier.
OUTLIER_SD = 3

# Dependent variables and the rows where each is defined.
READING_TIMES = {
    "TFT": lambda df: df["skipped"] == 0,  # total fixation time: the word was fixated at all
    "FPRT": lambda df: df["FPF"] == 1,  # first-pass reading time: fixated in the first pass
}

WORD_KEYS = ["text", "page", "word_idx"]
EDGE_PUNCTUATION = re.compile(r"^[\W_]+|[\W_]+$")

# Romanian texts mix the legacy cedilla letters (ş, ţ) with the correct
# comma-below letters (ș, ț); word frequency lists use the comma-below ones.
# Romanian only: in e.g. Turkish the cedilla letters are the correct ones.
ROMANIAN_CEDILLA_TO_COMMA = str.maketrans({"ş": "ș", "Ş": "Ș", "ţ": "ț", "Ţ": "Ț"})


@dataclass
class Prepared:
    table: pd.DataFrame  # the word-level table for the models
    exclusions: pd.DataFrame  # rows and participants left after each step
    scales: pd.DataFrame  # what 1 SD of each predictor is in real units
    frequency_note: str


def clean_word(word, language: str) -> str:
    if pd.isna(word):
        return ""
    word = str(word)
    if language == "ro":
        word = word.translate(ROMANIAN_CEDILLA_TO_COMMA)
    return EDGE_PUNCTUATION.sub("", word.lower())


def zscore(series: pd.Series) -> pd.Series:
    return (series - series.mean()) / series.std(ddof=1)


def word_frequencies(words: pd.Series, config: Config) -> tuple[pd.Series, float, str]:
    """Zipf frequency of each (cleaned) word, the lowest value the source can
    give (rarer words come back as 0), and a description of the source."""
    own_list = read_frequency_list(config)
    if own_list is not None:
        zipf = words.map(lambda w: own_list.get(w, 0.0))
        return zipf, min(own_list.values()), f"own list {config.word_frequency_file.name}"

    if config.language in available_languages(wordlist="large"):
        wordlist, floor = "large", 1.0
    elif config.language in available_languages(wordlist="small"):
        wordlist, floor = "small", 3.0
    else:
        raise ValueError(
            f"wordfreq has no frequency list for language '{config.language}'. "
            "Provide your own with 'word_frequency_file' in the config (see README)."
        )
    try:
        zipf = words.map(lambda w: zipf_frequency(w, config.language, wordlist=wordlist))
    except ImportError as exc:
        # Chinese, Japanese and Korean need an extra tokenizer package in wordfreq.
        raise ValueError(
            f"wordfreq needs an extra package for language '{config.language}' ({exc}). "
            "Install it with: uv add 'wordfreq[cjk]' (see the wordfreq documentation), "
            "or provide your own list with 'word_frequency_file' in the config."
        ) from None
    return zipf, floor, f"wordfreq '{wordlist}' list"


def word_table(df: pd.DataFrame, config: Config) -> tuple[pd.DataFrame, str]:
    """One row per word position in the texts: its length and frequency, and
    the length and frequency of the previous real word on the same page."""
    words = df[WORD_KEYS + ["word"]].drop_duplicates(WORD_KEYS).sort_values(WORD_KEYS)

    words["clean"] = words["word"].map(lambda w: clean_word(w, config.language))
    words["length"] = words["clean"].map(lambda w: sum(ch.isalpha() for ch in w))
    words = words[words["length"] > 0].copy()  # drop spaces, punctuation, numbers

    zipf, floor, source = word_frequencies(words["clean"], config)
    words["freq_unknown"] = zipf == 0
    # Words missing from the list are rarer than its lowest value; put them
    # half a Zipf step under it instead of at 0, which would mean "never seen".
    words["zipf"] = zipf.where(zipf > 0, floor - 0.5)

    by_page = words.groupby(["text", "page"], sort=False)
    words["prev_length"] = by_page["length"].shift(1)
    words["prev_zipf"] = by_page["zipf"].shift(1)

    words["item_id"] = words["text"].astype(str) + "|" + words["page"].astype(str) + "|" + words["word_idx"].astype(str)

    unknown_pct = 100 * words["freq_unknown"].mean()
    note = f"{source}; {unknown_pct:.1f}% of text words not in it (set to Zipf {floor - 0.5})"
    return words.drop(columns=["word", "clean"]), note


def usable_rows(df: pd.DataFrame, dv: str) -> pd.Series:
    """Rows where the reading time is defined, at least MIN_READING_TIME_MS,
    and within OUTLIER_SD of that participant's own mean (log scale)."""
    usable = READING_TIMES[dv](df) & (df[dv] >= MIN_READING_TIME_MS)
    log_time = np.log(df[dv].where(usable))
    by_participant = log_time.groupby(df["participant_id"])
    z = (log_time - by_participant.transform("mean")) / by_participant.transform("std")
    return usable & (z.abs() <= OUTLIER_SD)


def prepare(config: Config) -> Prepared:
    exclusions = []

    def log_step(step: str, frame: pd.DataFrame) -> None:
        exclusions.append({"step": step, "rows": len(frame), "participants": frame["participant_id"].nunique()})

    df = read_reading_measures(config)
    log_step("all rows (practice texts already removed)", df)

    words, frequency_note = word_table(df, config)
    df = df.merge(words, on=WORD_KEYS, how="inner")
    log_step("words only (no spaces/punctuation/numbers)", df)

    df = df.dropna(subset=["prev_length", "prev_zipf"])
    log_step("has a previous word on the same page", df)

    # Standardize WMC over the participants in the analysis, one value per
    # person (not per row, which would weight people by how much they read).
    wmc = read_wmc(config)
    wmc = wmc[wmc.index.isin(df["participant_id"].unique())]
    df = df.join(zscore(wmc).rename("wmc_z"), on="participant_id", how="inner")
    log_step("participant has a WMC score", df)

    scales = []
    for name, column in [("length", "length"), ("freq", "zipf"), ("prev_length", "prev_length"), ("prev_freq", "prev_zipf")]:
        df[f"{name}_z"] = zscore(df[column])
        note = frequency_note if name == "freq" else ""
        scales.append({"predictor": name, "mean": df[column].mean(), "sd": df[column].std(ddof=1), "note": note})
    scales.append({"predictor": "wmc", "mean": wmc.mean(), "sd": wmc.std(ddof=1), "note": config.wmc_column})

    for dv in READING_TIMES:
        df[f"use_{dv}"] = usable_rows(df, dv)
        log_step(f"rows used for {dv}", df[df[f"use_{dv}"]])

    columns = [
        "participant_id", "session", "item_id", *READING_TIMES, *(f"use_{dv}" for dv in READING_TIMES),
        "length", "zipf", "freq_unknown", "length_z", "freq_z", "prev_length_z", "prev_freq_z", "wmc_z",
    ]
    return Prepared(
        table=df[columns],
        exclusions=pd.DataFrame(exclusions),
        scales=pd.DataFrame(scales),
        frequency_note=frequency_note,
    )
