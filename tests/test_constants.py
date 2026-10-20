import unittest
from unittest.mock import patch

from mackeep import constants


class TestConstants(unittest.TestCase):
    def test_get_version_returns_metadata_version(self):
        with patch("mackeep.constants.version", return_value="1.2.3"):
            assert constants.get_version() == "1.2.3"

    def test_get_version_falls_back_when_metadata_missing(self):
        with patch(
            "mackeep.constants.version",
            side_effect=constants.PackageNotFoundError("mackeep"),
        ):
            assert constants.get_version() == "unknown"
