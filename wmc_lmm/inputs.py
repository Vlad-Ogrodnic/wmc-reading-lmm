"""Read the input data: word-level reading measures and the WMC scores."""

import re

import pandas as pd

from wmc_lmm.config import Config

# Columns of the reading measures the analysis uses (the rest are ignored).
READING_MEASURE_COLUMNS = ["page", "word_idx", "word", "skipped", "FPF", "TFT", "FPRT"]

# File names written by the MultiplEYE preprocessing pipeline, e.g.
# "014_RO_RO_1_ET1_trial_3_Arg_PISACowsMilk_reading_measures.csv" or, for
# practice texts, "..._PRACTICE_trial_1_..._reading_measures.csv".
# Pattern taken from the pipeline's load_reading_measures (MultiplEYE, MIT License).
PIPELINE_FILE_PATTERN = re.compile(
    r".+?(?P<trial>(?:PRACTICE_)?trial_\d+)_(?P<text>.+)_reading_measures\.csv"
)


def normalize_id(value) -> str:
    """'014', 14, 14.0 -> '14'; anything non-numeric is kept as text."""
    text = str(value).strip()
    if re.fullmatch(r"\d+\.0", text):
        text = text[:-2]
    return str(int(text)) if text.isdigit() else text


def participant_from_session(session: str, pattern: str) -> str:
    """Participant id from a session id, e.g. '014_RO_RO_1_ET1' -> '14' with the default pattern."""
    match = re.search(pattern, str(session))
    return normalize_id(match.group(1) if match else session)


def read_reading_measures(config: Config) -> pd.DataFrame:
    """One row per word, per session, per text, with columns
    participant_id, session, text + READING_MEASURE_COLUMNS. Practice texts removed."""
    if config.reading_measures_folder is not None:
        df = _read_pipeline_folder(config)
    else:
        df = pd.read_csv(config.reading_measures_file)
        missing = [c for c in [config.session_column, config.text_column, *READING_MEASURE_COLUMNS] if c not in df.columns]
        if missing:
            raise ValueError(f"{config.reading_measures_file} is missing columns: {missing}")
        df = df.rename(columns={config.session_column: "session", config.text_column: "text"})
        df = df[["session", "text", *READING_MEASURE_COLUMNS]]

    df["participant_id"] = df["session"].map(lambda s: participant_from_session(s, config.participant_id_pattern))
    return df


def _read_pipeline_folder(config: Config) -> pd.DataFrame:
    frames = []
    for session_folder in sorted(p for p in config.reading_measures_folder.iterdir() if p.is_dir()):
        for file in sorted(session_folder.glob("*_reading_measures.csv")):
            match = PIPELINE_FILE_PATTERN.match(file.name)
            if match is None or match.group("trial").startswith("PRACTICE_"):
                continue
            df = pd.read_csv(file, usecols=READING_MEASURE_COLUMNS)
            df.insert(0, "session", session_folder.name)
            df.insert(1, "text", match.group("text"))
            frames.append(df)
    if not frames:
        raise ValueError(
            f"No '*_trial_N_<text>_reading_measures.csv' files found in the session folders of "
            f"{config.reading_measures_folder}."
        )
    return pd.concat(frames, ignore_index=True)


def read_wmc(config: Config) -> pd.Series:
    """WMC score per participant (index: participant id as text)."""
    df = pd.read_csv(config.psychometric_overview)
    for column in ("participant_id", config.wmc_column):
        if column not in df.columns:
            raise ValueError(f"{config.psychometric_overview} has no '{column}' column.")
    df["participant_id"] = df["participant_id"].map(normalize_id)
    wmc = df.set_index("participant_id")[config.wmc_column].dropna()
    if wmc.index.duplicated().any():
        raise ValueError(f"{config.psychometric_overview} has more than one WMC score for some participants.")
    return wmc


def read_frequency_list(config: Config) -> dict[str, float] | None:
    """Optional own word-frequency list: CSV with columns 'word' and 'zipf'
    (Zipf = log10 of frequency per billion words). Words are lowercased."""
    if config.word_frequency_file is None:
        return None
    df = pd.read_csv(config.word_frequency_file)
    for column in ("word", "zipf"):
        if column not in df.columns:
            raise ValueError(f"{config.word_frequency_file} has no '{column}' column.")
    return dict(zip(df["word"].astype(str).str.lower(), df["zipf"].astype(float)))
