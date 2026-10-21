"""Add the translations of the interface to the String Catalog of the application."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from Translations import ENGLISH, RUSSIAN, TRANSLATIONS  # noqa: E402

CATALOG = (
    Path(__file__).resolve().parents[1]
    / "Sources/App/Resources/Localizable.xcstrings"
)


def main() -> None:
    """Add every translation to the catalog."""
    data: dict = json.loads(CATALOG.read_text())

    for language, items in [("en", ENGLISH), ("ru", RUSSIAN)] + list(
        TRANSLATIONS.items()
    ):
        for key, value in items.items():
            entry: dict = data["strings"].setdefault(
                key,
                {
                    "comment": "The string of the interface",
                    "extractionState": "manual",
                    "localizations": {},
                },
            )
            entry.setdefault("localizations", {})[language] = {
                "stringUnit": {"state": "translated", "value": value}
            }

    CATALOG.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    )
    count: int = sum(len(items) for items in TRANSLATIONS.values())
    print(f"Added {count} translations for {len(TRANSLATIONS)} languages")


if __name__ == "__main__":
    main()
