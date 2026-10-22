# Tests

Run from the repository root:

```bash
make test
uv run python -m pytest tests/test_audit_regressions.py -q
make coverage
```

`make check` also runs Markdown linting, Ruff, mypy, and ty. Coverage requires
at least 90% combined statement/branch coverage, configured once in
`pyproject.toml`; use `htmlcov/index.html` for the generated report. Python
warnings fail tests, including resource leaks and unraisable exceptions.

Use pytest's `home` fixture from `conftest.py` for filesystem integration tests.
It sets temporary HOME/XDG paths and resets confirmation flags. Use `tmp_path`
and `monkeypatch` for additional isolation. No test should need the network,
real user settings, live application processes, or an installed cloud client.
Mock subprocess interactions such as process detection and attribute utilities.

Key suites cover application operations, exclusion matching, configuration,
JSON, legacy migration, and audit regressions. When changing filesystem logic,
check failed staging/commit rollback, shared ownership, symlinks, permissions,
and dry-run's no-write guarantee. Compare resulting files and events rather
than only asserting implementation-specific call sequences.

Desktop unit and UI tests live in `desktop/Tests/`; see the
[desktop guide](../desktop/README.md#build-and-test).

Configuration fixtures are copied into temporary HOME before mutation. The
original fixture tree must remain unchanged. Low-level copy tests compare
nonempty bytes and directory structure, not only path existence.

`test_audit_regressions.py` also sends a real cancellation signal during a
synchronized copy and checks the completed application, ownership index, and
absence of the next application. Its child process has a deadline and guaranteed
cleanup. `fixtures/exclusion-cases.json` is a shared set of expected matcher
results consumed by Python and Swift tests; update both consumers together.

Desktop safety tests also exercise damaged-history recovery, private history
permissions, failed writes, restore-plan/configuration changes, scope mismatches,
and cancellation during preparation. Restore checks use the real Python CLI in
a temporary HOME. Process-stop tests verify that the child exits before the
operation finishes; they do not quit the test host or automate the UI.

`test_catalog.py` validates every bundled application definition, checks that the
runtime catalog loads without errors, and verifies sensitive markers for known
credential entries. Shared paths and trailing directory separators are allowed.
Ordinary `TestCLI` workflows model a non-root user; root refusal/acceptance is
tested independently in `test_mackeep.py`. Permission tests still require a real
unprivileged process: mocking the effective UID does not change OS permissions.
