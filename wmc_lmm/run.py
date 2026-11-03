"""Run the whole analysis: prepare the word-level table (Python), then fit the
models and write the results (R).

    python -m wmc_lmm.run --config config.yaml
"""

import argparse
import shutil
import subprocess
from pathlib import Path

from wmc_lmm.config import load_config
from wmc_lmm.prepare import prepare

R_SCRIPT = Path(__file__).with_name("fit_models.R")
WORD_TABLE = "word_table.csv"


def find_rscript() -> tuple[str, bool]:
    """Rscript to run the models with, and whether it is a Windows R called
    from WSL (which then needs Windows-style paths).

    Prefers an Rscript on PATH; otherwise falls back to a Windows R install,
    which isn't on PATH by default.
    """
    on_path = shutil.which("Rscript")
    if on_path:
        return on_path, False
    for root, from_wsl in [("/mnt/c/Program Files/R", True), ("C:/Program Files/R", False)]:
        installs = sorted(Path(root).glob("R-*/bin/Rscript.exe"))
        if installs:
            return str(installs[-1]), from_wsl
    raise FileNotFoundError("Rscript not found. Install R (https://cloud.r-project.org) or add Rscript to PATH.")


def run_models(output_folder: Path) -> None:
    rscript, from_wsl = find_rscript()

    def as_r_path(path: Path) -> str:
        if not from_wsl:
            return str(path)
        return subprocess.run(["wslpath", "-w", str(path)], check=True, capture_output=True, text=True).stdout.strip()

    subprocess.run([rscript, as_r_path(R_SCRIPT), as_r_path(output_folder)], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, required=True, help="Path to your YAML config file.")
    parser.add_argument("--prepare-only", action="store_true", help="Only write the word-level table; don't fit the models.")
    parser.add_argument(
        "--models-only",
        action="store_true",
        help="Skip the preparation and only rerun the R step on the existing word-level table "
        "(already-fitted models are reused, so this only recomputes the result tables and plots).",
    )
    args = parser.parse_args()

    config = load_config(args.config)
    output = config.output_folder

    if args.models_only:
        if not (output / WORD_TABLE).exists():
            raise FileNotFoundError(f"No {WORD_TABLE} in {output}; run without --models-only first.")
        run_models(output)
        return

    prepared = prepare(config)
    output.mkdir(parents=True, exist_ok=True)
    prepared.table.to_csv(output / WORD_TABLE, index=False)
    prepared.exclusions.to_csv(output / "exclusions.csv", index=False)
    prepared.scales.to_csv(output / "predictor_scales.csv", index=False)

    print(prepared.exclusions.to_string(index=False))
    print(f"Word frequency: {prepared.frequency_note}")

    if not args.prepare_only:
        run_models(output)


if __name__ == "__main__":
    main()
