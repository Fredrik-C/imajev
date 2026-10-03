"""Fetch pinned model files into the persistent volume, then start the API."""
import json
import os
from pathlib import Path
import sys

from huggingface_hub import snapshot_download

models = Path("/models")
models.mkdir(parents=True, exist_ok=True)
base_revision = os.environ["IMAJEV_BASE_REVISION"]
base_path = snapshot_download(
    repo_id=os.environ["IMAJEV_BASE_REPO"],
    revision=base_revision,
    local_files_only=False,
)
bundle_path = models / "model-qwen4b.json"
bundle_path.write_text(json.dumps({
    "repo": os.environ["IMAJEV_BASE_REPO"],
    "revision": base_revision,
    "path": base_path,
}, indent=2) + "\n")

adapter_path = snapshot_download(
    repo_id=os.environ["IMAJEV_MODEL_REPO"],
    revision=os.environ["IMAJEV_MODEL_REVISION"],
    allow_patterns=[
        "adapter_config.json",
        "adapter_model.safetensors",
        "decision_readout.json",
        "decision_readout.safetensors",
        "calibration*.json",
    ],
    local_files_only=False,
)
calibration = Path(adapter_path) / os.environ.get("IMAJEV_CALIBRATION", "calibration.json")
if not calibration.is_file():
    raise SystemExit(f"Calibration file not found in adapter snapshot: {calibration}")

command = [
    sys.executable, "/app/scripts/playground/server.py",
    "--backend", "torch",
    "--model-bundle", str(bundle_path),
    "--adapter", adapter_path,
    "--calibration", str(calibration),
    "--model-name", "imajev-4b",
    "--rotations", os.environ.get("IMAJEV_ROTATIONS", "1"),
    "--max-input-tokens", os.environ.get("IMAJEV_MAX_INPUT_TOKENS", "4096"),
    "--host", "0.0.0.0",
    "--port", "8765",
]
os.execvpe(command[0], command, os.environ)
