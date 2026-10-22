"""The translations of the interface, by language.

Every language has its own file, in the folder "languages", so a language can
be added or changed without touching the other ones. The file of a language
holds a dictionary of the strings of the interface, the keys are the ones of
the string catalog.
"""

import importlib

# The codes of the languages, the file of every language is in the folder
# "languages", with the code as its name.
LANGUAGE_CODES: list[str] = [
    "en",
    "ru",
    "uk",
    "es",
    "de",
    "fr",
    "it",
    "pt-BR",
    "ja",
    "ko",
    "zh-Hans",
]


def _load(code: str) -> dict[str, str]:
    """
    Read the translation of a language.

    - Parameter code: The code of the language.
    - Returns: The strings of the language.
    """
    module = importlib.import_module(f"languages.{code}")
    return dict(module.TRANSLATION)


# The translations of the interface, by language.
TRANSLATIONS: dict[str, dict[str, str]] = {
    code: _load(code) for code in LANGUAGE_CODES
}
