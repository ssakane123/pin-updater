# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`pin-updater` is a single-file, stdlib-only Python CLI (`src/pin_updater.py`, Python >=3.14, no runtime dependencies). It fetches version (and optional SHA-256) metadata from one HTTPS URL or stdin, then either prints it as JSON or rewrites `NAME=value` literals in one local file (Dockerfile/env-style) in place.

```
pin-updater <HTTPS_URL | --stdin> [--input-format text|json] [--version-key K] [--sha256-key K]
            [--github-asset NAME] [--file PATH --version-env VAR [--sha256-env VAR] [--sha256-bind VAR=KEY]...] [--dry-run]
```

## Commands

Dependencies are managed with `uv` (dev group: behave, pytest-httpserver, PyYAML, trustme).

```bash
# Acceptance test (locked deps, JSON report)
uv sync --locked --group dev --python 3.14
uv run --locked python -m behave --no-snippets --format json features

# Day-to-day shortcuts
uv run behave                                   # full acceptance suite (~40s)
uv run behave features/update-file.feature      # one feature
uv run behave features/update-file.feature -n "<scenario name>"   # one scenario
uv run python src/pin_updater.py ...            # run the CLI directly
```

There is no linter, formatter, or unit-test suite configured; the BDD suite is the only test layer. `PIN_UPDATER_BDD_SCRIPT` overrides which script the suite executes (default `src/pin_updater.py`).

## Architecture

All logic lives in `src/pin_updater.py` as a pipeline run from `main()`:

1. `parse_args` – hand-rolled parser (not argparse) with many cross-option validations; usage errors raise `PinError(..., 2)`, runtime errors use exit code 1.
2. `fetch_metadata` (HTTPS only, redirects disabled via `NoRedirect`, 3s timeout, 1 MiB cap) or stdin (always treated as JSON, same cap).
3. `parse_metadata` – text (exactly one line) or JSON. JSON objects are parsed with `object_pairs_hook=JSONObject` (a `list` subclass of pairs) so **duplicate keys are detected and rejected** rather than last-wins. Also handles `--github-asset` (looks up `assets[].digest` `sha256:...`) and `--sha256-bind`.
4. `process_file` / `replace_literals` – with `--file`, replaces the value in exactly one `NAME=value` (optionally `export`/`ARG` prefixed) line per bound variable. `shell_context` is a mini shell/Dockerfile lexer used to refuse files where the target line could be inside quotes, heredocs, continuations, or unsupported syntax, so the match is provably an active, unambiguous literal. Writes via temp file + `os.replace`, preserving mode, with `O_NOFOLLOW`, regular-file check and an inode-changed check; `--dry-run` emits a unified diff instead.

Design stance to preserve: be strict and fail closed. Server-controlled values are never echoed in error messages (keys are quoted via `json.dumps(ensure_ascii=True)`), versions must match a conservative charset before being written to a file, and all errors go to stderr as `ERROR: <message>`; unexpected exceptions collapse to `ERROR: operation failed`.

## Tests (`features/`)

Behave acceptance tests written in Japanese Gherkin (`# language: ja`; keywords like 機能/シナリオ/前提/もし/ならば/かつ). The feature files are the de-facto spec for CLI behavior — read them before changing validation or error text, since stderr messages and exit codes are asserted exactly.

- `environment.py` starts a per-scenario TLS `pytest_httpserver` on 127.0.0.1 with a `trustme` CA.
- `steps/pin_steps.py` runs the CLI as a subprocess (`python -I`, scrubbed env, own session/process group, 15s watchdog). Scenarios use fake `*.example.test` URLs which `support.rebase` rewrites to the local mock server; any other HTTPS host is refused.
- Mock responses and file fixtures are given as YAML / literal Doc Strings in the scenarios; Examples cells get `\\` and `\n` decoded in specific places (see `environment.before_feature` and `support.doc_bytes`).
- Steps use the `re` matcher, so step text must match the regexes in `pin_steps.py` exactly.

## Environment

Runs in a devcontainer (`.devcontainer/python-egress` routes traffic through an egress-allowlist proxy; extra allowed hosts go in `allowlist.local.txt`).
