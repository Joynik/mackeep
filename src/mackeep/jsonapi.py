"""
Machine-readable JSON output for Mackeep.

The JSON interface is meant to be used by the graphical front-ends built on
top of Mackeep. Every answer holds a ``schema_version`` field, so a front-end
can tell which version of the schema it is talking to.
"""

import json
import sys
from typing import Any, TextIO

# The version of the JSON schema
SCHEMA_VERSION: int = 1


def dumps(obj: Any) -> str:
    """
    Serialize an object to JSON.

    Args:
        obj (Any): The object to serialize.

    Returns:
        str
    """
    return json.dumps(obj, ensure_ascii=False)


def emit(obj: Any, stream: TextIO | None = None) -> None:
    """
    Write an object as a JSON line.

    Args:
        obj (Any): The object to write.
        stream (TextIO): The stream to write to. Defaults to stdout.
    """
    out: TextIO = stream if stream is not None else sys.stdout
    out.write(dumps(obj) + "\n")
    out.flush()


def emit_error(code: str, message: str, stream: TextIO | None = None) -> None:
    """
    Write an error as a JSON line.

    Args:
        code (str): The code of the error.
        message (str): The message of the error.
        stream (TextIO): The stream to write to. Defaults to stdout.
    """
    emit(
        {
            "schema_version": SCHEMA_VERSION,
            "error": {"code": code, "message": message},
        },
        stream,
    )
