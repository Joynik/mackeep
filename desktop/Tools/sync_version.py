"""Write the version of the release in the project of the application.

The application and the command line tool are released together, they
share the same version.
"""

import re
import sys
from pathlib import Path

# The project of the application
PROJECT: Path = Path(__file__).resolve().parents[1] / "project.yml"

# The line of the version of the application
VERSION = re.compile(r'(MARKETING_VERSION:\s*")[^"]*(")')


def main() -> None:
    """Write the version given in the arguments in the project file."""
    if len(sys.argv) != 2:
        print("Usage: sync_version.py <version>")
        raise SystemExit(1)

    version: str = sys.argv[1]
    text: str = PROJECT.read_text()
    new: str = VERSION.sub(rf"\g<1>{version}\g<2>", text)

    if new == text:
        print(f"The version of the application is already {version}")
        return

    PROJECT.write_text(new)
    print(f"The version of the application is {version}")


if __name__ == "__main__":
    main()
