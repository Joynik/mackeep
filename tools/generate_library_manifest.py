"""Generate the library index from a source revision; never edit it manually."""

import argparse
import configparser
import hashlib
import json
from pathlib import Path

from mackeep.jsonapi import SCHEMA_VERSION
from mackeep.library import MANIFEST_VERSION, NAME, REVISION, validate_definition


def generate(root: Path, revision: str) -> dict[str, object]:
    """Index validated definitions and pin downloads to their source commit."""
    if not REVISION.fullmatch(revision):
        raise ValueError("Expected a full 40-character Git revision")
    files = {}
    names = {}
    for path in sorted((root / "src/mackeep/applications").glob("*.cfg")):
        if not NAME.fullmatch(path.name):
            raise ValueError(f"Unsupported library filename: {path.name}")
        data = path.read_bytes()
        if not data.endswith(b"\n"):
            raise ValueError(f"Missing final newline: {path.name}")
        validate_definition(data)
        files[path.name] = hashlib.sha256(data).hexdigest()
        parser = configparser.RawConfigParser(allow_no_value=True, strict=False)
        parser.read_string(data.decode("utf-8"))
        names[path.name] = parser.get("application", "name")
    if not files:
        raise ValueError("No library definitions found")
    return {
        "version": MANIFEST_VERSION,
        "schema_version": SCHEMA_VERSION,
        "revision": revision,
        "files": files,
        "names": names,
    }


def main() -> None:
    """Write a deterministic manifest for the current source tree."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = generate(root, args.revision)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
