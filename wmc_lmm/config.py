"""Read and check the YAML configuration file.

Relative paths in the config are resolved against the folder the config file
is in, so a config can sit next to the data it points to.
"""

from dataclasses import dataclass
from pathlib import Path

import yaml


@dataclass
class Config:
    language: str
    output_folder: Path
    psychometric_overview: Path
    # Exactly one of these two is set.
    reading_measures_folder: Path | None
    reading_measures_file: Path | None
    # Only used with reading_measures_file: which columns hold the session id and the text name.
    session_column: str
    text_column: str
    wmc_column: str
    participant_id_pattern: str
    word_frequency_file: Path | None


def load_config(path: Path) -> Config:
    path = Path(path)
    with open(path, encoding="utf-8") as f:
        try:
            raw = yaml.safe_load(f) or {}
        except yaml.YAMLError as exc:
            raise ValueError(
                f"{path} could not be read. Every setting must be written as 'name: value', "
                f"with a space after the colon.\nDetails: {exc}"
            ) from None

    def required(key: str):
        if not raw.get(key):
            raise ValueError(f"{path}: '{key}' is required.")
        return raw[key]

    def as_path(value) -> Path | None:
        if not value:
            return None
        value = Path(value)
        return value if value.is_absolute() else (path.parent / value).resolve()

    folder = as_path(raw.get("reading_measures_folder"))
    file = as_path(raw.get("reading_measures_file"))
    if (folder is None) == (file is None):
        raise ValueError(f"{path}: set exactly one of 'reading_measures_folder' or 'reading_measures_file'.")

    config = Config(
        language=str(required("language")).lower(),
        output_folder=as_path(raw.get("output_folder") or "results"),
        psychometric_overview=as_path(required("psychometric_overview")),
        reading_measures_folder=folder,
        reading_measures_file=file,
        session_column=raw.get("session_column", "participant_id"),
        text_column=raw.get("text_column", "text_name"),
        wmc_column=raw.get("wmc_column", "LWMC_Total_score_mean"),
        participant_id_pattern=raw.get("participant_id_pattern", r"^(\d+)_"),
        word_frequency_file=as_path(raw.get("word_frequency_file")),
    )

    for name in ("psychometric_overview", "reading_measures_folder", "reading_measures_file", "word_frequency_file"):
        value = getattr(config, name)
        if value is not None and not value.exists():
            raise FileNotFoundError(f"{path}: '{name}' points to {value}, which does not exist.")

    return config
