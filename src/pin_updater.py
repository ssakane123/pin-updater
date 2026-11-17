#!/usr/bin/env python3
"""Fetch HTTPS pin metadata and optionally replace single-file literals."""

import difflib
import json
import os
from pathlib import Path
import re
import ssl
import stat
import sys
import tempfile
from types import SimpleNamespace
import unicodedata
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import build_opener, HTTPRedirectHandler, HTTPSHandler, Request


METADATA_LIMIT = 1024 * 1024


class PinError(Exception):
    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


class JSONObject(list):
    """Keep JSON objects distinct from arrays without losing duplicate keys."""


def parse_args(argv):
    options = dict.fromkeys(("input_format", "version_key", "sha256_key", "github_asset", "file",
                             "version_env", "sha256_env"))
    flags = {"--" + name.replace("_", "-"): name for name in options}
    flags["--sha256-bind"] = "sha256_bind"
    options.update(dry_run=False, stdin=False, sha256_bind=[])
    url = None
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--dry-run":
            options["dry_run"] = True
        elif arg == "--stdin":
            options["stdin"] = True
        elif arg.startswith("-"):
            if arg not in flags:
                label = f": {arg}" if re.fullmatch(r"--[a-z][a-z-]*", arg) else ""
                raise PinError(f"unknown option{label}", 2)
            index += 1
            if index == len(argv) or argv[index].startswith("--"):
                raise PinError(f"missing value for {arg}", 2)
            if arg == "--sha256-bind":
                options["sha256_bind"].append(argv[index])
            else:
                options[flags[arg]] = argv[index]
        elif url is None:
            url = arg
        else:
            raise PinError("expected exactly one metadata URL", 2)
        index += 1
    if options["stdin"] and url is not None:
        raise PinError("--stdin cannot be used with metadata URL", 2)
    if url is None and not options["stdin"]:
        raise PinError("missing metadata URL", 2)
    args = SimpleNamespace(url=url, **options)
    if args.input_format is not None and args.input_format not in ("text", "json"):
        raise PinError("--input-format must be text or json", 2)
    if args.input_format == "text" and (args.version_key is not None or args.sha256_key is not None):
        raise PinError("--input-format text cannot be used with --version-key or --sha256-key", 2)
    if args.input_format == "text" and args.github_asset is not None:
        raise PinError("--input-format text cannot be used with --github-asset", 2)
    if args.github_asset is not None and args.sha256_key is not None:
        raise PinError("--github-asset cannot be used with --sha256-key", 2)
    if args.sha256_bind and args.input_format == "text":
        raise PinError("--input-format text cannot be used with --sha256-bind", 2)
    if args.sha256_bind and any(value is not None for value in (args.sha256_env, args.sha256_key, args.github_asset)):
        raise PinError("--sha256-bind cannot be used with --sha256-env, --sha256-key or --github-asset", 2)
    if args.sha256_bind and (args.file is None or args.version_env is None):
        raise PinError("--sha256-bind requires --file and --version-env", 2)
    if args.file is not None and args.version_env is None:
        raise PinError("--file requires --version-env", 2)
    if args.version_env is not None and args.file is None:
        raise PinError("--version-env requires --file", 2)
    if args.sha256_env is not None and (args.file is None or args.version_env is None):
        raise PinError("--sha256-env requires --file and --version-env", 2)
    if args.dry_run and (args.file is None or args.version_env is None):
        raise PinError("--dry-run requires --file and --version-env", 2)
    if args.sha256_env is not None and args.version_env == args.sha256_env:
        raise PinError("--version-env and --sha256-env must differ", 2)
    for name in ("version_env", "sha256_env"):
        value = getattr(args, name)
        if value is not None and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value) is None:
            raise PinError(f"--{name.replace('_', '-')} must be a variable name", 2)
    for name in ("version_key", "sha256_key", "github_asset"):
        value = getattr(args, name)
        if value is not None and (not value or any(unicodedata.category(c).startswith("C") for c in value)):
            raise PinError(f"invalid value for --{name.replace('_', '-')}", 2)
    bindings = []
    for binding in args.sha256_bind:
        target, separator, key = binding.partition("=")
        if (not separator or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", target) is None
                or not key or any(unicodedata.category(c).startswith("C") for c in key)):
            raise PinError("invalid value for --sha256-bind", 2)
        bindings.append((target, key))
    targets = [target for target, _ in bindings]
    if len(targets) != len(set(targets)):
        raise PinError("--sha256-bind target variables must be unique", 2)
    if args.version_env in targets:
        raise PinError("--version-env and --sha256-bind targets must differ", 2)
    args.sha256_bind = bindings
    if args.file is not None and (not args.file or any(ord(c) < 32 or ord(c) == 127 for c in args.file)):
        raise PinError("invalid value for --file", 2)
    if url is not None:
        try:
            parsed = urlsplit(url)
            if parsed.scheme != "https":
                raise PinError("metadata URL must use HTTPS", 2)
            if (not parsed.hostname or parsed.username is not None or parsed.password is not None
                    or parsed.fragment or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in url)):
                raise ValueError
            parsed.port
        except ValueError:
            raise PinError("invalid metadata URL", 2) from None
    return args


def fetch_metadata(url):
    try:
        context = ssl.create_default_context()
        opener = build_opener(HTTPSHandler(context=context), NoRedirect())
        with opener.open(Request(url, method="GET"), timeout=3) as response:
            # Metadata is small; do not buffer an unbounded response as an artifact.
            body = response.read(METADATA_LIMIT + 1)
            if len(body) > METADATA_LIMIT:
                raise PinError("metadata response is too large")
            return body, response.headers.get("Content-Type", "")
    except HTTPError as error:
        code = error.code
        error.close()
        raise PinError(f"metadata request failed: HTTP {code}") from None
    except TimeoutError:
        raise PinError("metadata request timed out") from None
    except URLError as error:
        if isinstance(error.reason, TimeoutError):
            raise PinError("metadata request timed out") from None
        raise PinError("metadata request failed") from None
    except (OSError, ValueError, UnicodeError):
        raise PinError("metadata request failed") from None


def reject_json_constant(value):
    raise ValueError("non-JSON constant")


def selected_values(document, key):
    # Quote selectors as data; never include server values in diagnostics.
    label = json.dumps(key, ensure_ascii=True)
    values = [value for name, value in document if name == key]
    if len(values) > 1:
        raise PinError(f"metadata JSON contains duplicate selected key {label}")
    return values


def parse_metadata(body, content_type, args):
    input_format = args.input_format
    if input_format is None:
        media_type = content_type.partition(";")[0].strip().lower()
        input_format = {"text/plain": "text", "application/json": "json"}.get(media_type)
        if input_format is None:
            raise PinError("unsupported metadata Content-Type")
    if input_format == "text" and (args.version_key is not None or args.sha256_key is not None):
        raise PinError("metadata key selectors require JSON metadata")
    if input_format == "text" and args.github_asset is not None:
        raise PinError("--github-asset requires JSON metadata")
    if input_format == "text" and getattr(args, "sha256_bind", []):
        raise PinError("--sha256-bind requires JSON metadata")
    try:
        text = body.decode("utf-8")
    except UnicodeError:
        raise PinError("metadata is not valid UTF-8") from None
    sha256 = None
    if input_format == "text":
        version = text[:-2] if text.endswith("\r\n") else text[:-1] if text.endswith("\n") else text
        if "\n" in version or "\r" in version:
            raise PinError("text metadata must contain exactly one version line")
    else:
        try:
            document = json.loads(text, object_pairs_hook=JSONObject, parse_constant=reject_json_constant)
        except (ValueError, RecursionError):
            raise PinError("metadata JSON is invalid") from None
        if not isinstance(document, JSONObject):
            raise PinError("metadata JSON must be a top-level object")
        keys = (args.version_key if args.version_key is not None else "version",
                args.sha256_key if args.sha256_key is not None else "sha256")
        selected = []
        for index, key in enumerate(keys[:1] if args.github_asset is not None else keys):
            values = selected_values(document, key)
            if not values and (index == 0 or args.sha256_key is not None):
                raise PinError(f"metadata key {json.dumps(key, ensure_ascii=True)} is missing")
            selected.append(values)
        if args.github_asset is not None:
            assets = selected_values(document, "assets")
            if not assets or not isinstance(assets[0], list) or isinstance(assets[0], JSONObject):
                raise PinError("metadata assets must be an array")
            matches = []
            for asset in assets[0]:
                if not isinstance(asset, JSONObject):
                    raise PinError("metadata asset must be an object")
                name = selected_values(asset, "name")
                if not name or not isinstance(name[0], str):
                    raise PinError("metadata asset name must be a string")
                if name[0] == args.github_asset:
                    matches.append(asset)
            if len(matches) != 1:
                raise PinError("github asset must match exactly one asset")
            digest = selected_values(matches[0], "digest")
            if not digest:
                raise PinError("github asset digest is missing")
            if not isinstance(digest[0], str) or not digest[0].startswith("sha256:"):
                raise PinError("github asset digest must be sha256: followed by 64 lowercase hexadecimal characters")
            selected.append([digest[0][len("sha256:"):]])
        version = selected[0][0]
        if not isinstance(version, str):
            raise PinError(f"metadata key {json.dumps(keys[0], ensure_ascii=True)} must be a string")
        hashes = [(keys[1], selected[1])]
        for _, key in getattr(args, "sha256_bind", []):
            values = selected_values(document, key)
            if not values:
                raise PinError(f"metadata key {json.dumps(key, ensure_ascii=True)} is missing")
            hashes.append((key, values))
        for key, values in hashes:
            if values and (not isinstance(values[0], str) or re.fullmatch(r"[0-9a-f]{64}", values[0]) is None):
                raise PinError(f"metadata key {json.dumps(key, ensure_ascii=True)} must be a lowercase 64-character hexadecimal string")
        sha256 = selected[1][0] if selected[1] else None
    if not version:
        raise PinError("metadata version must not be empty")
    if any(unicodedata.category(c) in ("Cc", "Cs", "Zl", "Zp") for c in version):
        raise PinError("metadata version must not contain control characters")
    if args.sha256_env is not None and sha256 is None:
        raise PinError("metadata sha256 is required by --sha256-env")
    metadata = {"version": version, "sha256": sha256}
    if getattr(args, "sha256_bind", []):
        metadata["sha256_bind"] = [(target, values[0])
                                   for (target, _), (_, values) in zip(args.sha256_bind, hashes[1:])]
    return metadata


def shell_context(line, context, docker, multiline=False):
    """Check active syntax in either dialect; retain state across removed newlines."""
    quoted, word_start, previous, escaped = context or (None, True, None, False)
    docker_join = docker and line.endswith(b"\\")
    if docker_join:
        line = line[:-1]
    if quoted == 35:
        return (35, True, None, False) if docker_join else None
    index = 0
    while index < len(line):
        byte = line[index]
        if quoted == 39:
            if byte == 39:
                quoted = None
        elif escaped:
            escaped = False
            word_start = False
            previous = None
        elif byte == 92:
            escaped = True
        elif byte == 96 or (previous == 36 and (byte == 40 or (quoted is None and byte in (34, 39)))):
            raise PinError("unsupported local shell syntax")
        elif previous == 36 and byte == 123:
            # Only simple ${NAME} references are modeled, not expansion operators/nesting.
            parameter = re.match(rb"\{[A-Za-z_][A-Za-z0-9_]*\}", line[index:])
            if parameter is None:
                raise PinError("unsupported local parameter expansion")
            index += parameter.end() - 1
            previous = None
        elif previous == 36 and byte == 36:
            previous = None
        elif quoted == 34:
            if byte == 34:
                quoted = None
            previous = byte if byte == 36 else None
        elif byte in (34, 39):
            quoted = byte
            word_start = False
            previous = None
        elif byte == 35 and word_start:
            # Docker removes newlines before a RUN shell sees its inline comment.
            return (35, True, None, False) if docker_join else None
        elif byte in (40, 41):
            raise PinError("unsupported local grouping syntax")
        elif previous == 60 and byte == 60:
            raise PinError("unsupported local heredoc syntax")
        else:
            word_start = byte in b" \t;|&()<>"
            previous = byte if byte in (36, 60) else None
        index += 1
    if docker_join:
        return quoted, word_start, previous, escaped
    if escaped:
        # Shell backslash-newline vanishes without ending a word or syntax prefix.
        return quoted, word_start, previous, False
    if quoted is not None:
        if multiline:
            return quoted, word_start, previous, False
        raise PinError("unsupported multiline local syntax")
    return None


def replace_literals(data, bindings):
    docker_instruction = re.compile(
        rb"[ \t]*(?:ADD|ARG|CMD|COPY|ENTRYPOINT|ENV|EXPOSE|FROM|HEALTHCHECK|LABEL|"
        rb"MAINTAINER|ONBUILD|RUN|SHELL|STOPSIGNAL|USER|VOLUME|WORKDIR)(?:[ \t]|$)", re.IGNORECASE
    )
    heredoc_start = re.compile(
        rb"[ \t]*(?:[A-Za-z0-9_./:+-]+(?:[ \t]+[A-Za-z0-9_./:=+-]+)*)?[ \t]*"
        rb"<<(?P<tabs>-?)[ \t]*(?P<quote>['\"]?)(?P<delimiter>[A-Za-z_][A-Za-z0-9_]*)"
        rb"(?P=quote)[ \t]*(?:#[^\r\n]*)?\r?"
    )
    replacements = []
    for name, value in bindings:
        encoded_name = name.encode("ascii")
        candidate = re.compile(rb"[ \t]*(?:(?:export|ARG)[ \t]+)?" + re.escape(encoded_name) + rb"(?=[ \t=]|$)")
        literal = re.compile(rb"(?:ARG )?" + re.escape(encoded_name) + rb"=([A-Za-z0-9._+:-]*)\r?")
        matches = []
        offset = 0
        continued = False
        docker_continued = False
        context = None
        raw_context = None
        heredoc = None
        for line in data.split(b"\n"):
            if heredoc is not None:
                delimiter, strip_tabs = heredoc
                closing = line.rstrip(b"\r").lstrip(b"\t") if strip_tabs else line.rstrip(b"\r")
                if closing == delimiter:
                    heredoc = None
                offset += len(line) + 1
                continue
            directive = re.match(rb"[ \t]*#[ \t]*escape[ \t]*=(.*)", line, re.IGNORECASE)
            if ((not continued or docker_continued) and directive is not None
                    and directive.group(1).strip(b" \t\r") != b"\\"):
                raise PinError("unsupported Docker escape directive")
            if candidate.match(line):
                match = literal.fullmatch(line)
                if match is None or continued or raw_context is not None:
                    raise PinError(f'variable "{name}" is missing or not unique')
                matches.append((offset + match.start(1), offset + match.end(1), value.encode("ascii")))
            if not continued:
                docker_continued = docker_instruction.match(line) is not None
            stripped = line.lstrip(b" \t").rstrip(b"\r")
            comment = stripped.startswith(b"#")
            opener = heredoc_start.fullmatch(line)
            if opener is not None:
                if continued or raw_context is not None:
                    raise PinError("unsupported local heredoc syntax")
                heredoc = (opener.group("delimiter"), bool(opener.group("tabs")))
                docker_continued = False
            else:
                # Never let Docker newline removal change the raw shell safety scan.
                # Raw quotes remain tracked even when a Docker join permits a newline.
                raw_context = shell_context(line.rstrip(b"\r"), raw_context, False, multiline=True)
                if not (docker_continued and continued and (comment or not stripped)):
                    context = shell_context(line.rstrip(b"\r"), context, docker_continued)
                    continued = context is not None
            offset += len(line) + 1
        if heredoc is not None:
            raise PinError("unterminated local heredoc")
        if raw_context is not None:
            raise PinError("unsupported multiline local syntax")
        if len(matches) != 1:
            raise PinError(f'variable "{name}" is missing or not unique')
        replacements.extend(matches)
    for start, end, value in sorted(replacements, reverse=True):
        data = data[:start] + value + data[end:]
    return data


def process_file(args, metadata):
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+:-]{0,199}", metadata["version"]) is None:
        raise PinError("version is unsafe for an unquoted literal")
    bindings = [(args.version_env, metadata["version"])]
    if args.sha256_env is not None:
        bindings.append((args.sha256_env, metadata["sha256"]))
    bindings.extend(metadata.get("sha256_bind", []))
    path = Path(args.file)
    temporary = None
    try:
        # Refuse symlinks and special files rather than following or executing them.
        with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise PinError("target file must be a regular file")
            original = source.read()
        updated = replace_literals(original, bindings)
        if updated == original:
            return b""
        if args.dry_run:
            label = os.fsencode(args.file)
            lines = difflib.diff_bytes(difflib.unified_diff, original.splitlines(keepends=True),
                                      updated.splitlines(keepends=True), fromfile=label, tofile=label)
            return b"".join(line if line.endswith(b"\n") else line + b"\n\\ No newline at end of file\n"
                            for line in lines)
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".pin-updater-", delete=False) as target:
            temporary = target.name
            target.write(updated)
            target.flush()
            os.fchmod(target.fileno(), stat.S_IMODE(info.st_mode))
        current = path.stat(follow_symlinks=False)
        if (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
            raise PinError("target file changed during update")
        os.replace(temporary, path)
        temporary = None
        return b""
    except OSError:
        raise PinError("target file could not be processed") from None
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary)
            except OSError:
                pass


def main(argv=None):
    try:
        args = parse_args(sys.argv[1:] if argv is None else argv)
        if args.stdin:
            try:
                body = sys.stdin.buffer.read(METADATA_LIMIT + 1)
            except OSError:
                raise PinError("metadata input could not be read") from None
            if len(body) > METADATA_LIMIT:
                raise PinError("metadata response is too large")
            content_type = "application/json"
        else:
            body, content_type = fetch_metadata(args.url)
        metadata = parse_metadata(body, content_type, args)
        output = (json.dumps(metadata, ensure_ascii=True) + "\n").encode("utf-8") if args.file is None else process_file(args, metadata)
        sys.stdout.buffer.write(output)
        return 0
    except PinError as error:
        sys.stderr.write(f"ERROR: {error}\n")
        return error.code
    except Exception:
        sys.stderr.write("ERROR: operation failed\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
