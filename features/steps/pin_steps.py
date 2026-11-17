import json
import os
from pathlib import Path
import shlex
import sys

from behave import given, then, use_step_matcher, when
from pytest_httpserver import RequestMatcher
from werkzeug.wrappers import Response

from features.support import (
    REPO, doc_bytes, equal, file_state, fixture_path, mock_spec, rebase,
    run_process, stop_server,
)

use_step_matcher("re")


@given(r"API Mock が次のレスポンスを返す")
def response(context):
    spec = mock_spec(context.text)
    reply = spec["response"]
    context.server.expect_request(spec["route"], method=spec["method"]).respond_with_data(
        reply["body"].encode("utf-8"), status=reply["status"], headers=reply["response_headers"]
    )


@given(r"API Mock の '(?P<route>[^']+)' は 'timeout' を返す")
def timeout_response(context, route):
    def body():
        # The public server log records the request before streaming starts,
        # so a received timeout request is counted without waiting for a reply.
        context.release.wait()
        yield b"late\n"

    context.server.expect_request(route, method="GET").respond_with_handler(
        lambda request: Response(body(), content_type="text/plain")
    )


@given(r"ファイル '(?P<name>[^']+)' の(?:(?:パーミッションが (?P<mode>[0-7]{4}) であり、)(?:inode を保持し、)?)?バイト列は次の通りである")
def file_fixture(context, name, mode):
    row = getattr(context.scenario, "_row", None)
    initial = row["initial"] if row is not None and "initial" in row.headings else None
    path = fixture_path(context, name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(doc_bytes(context.text, initial))
    path.chmod(int(mode, 8) if mode else 0o644)
    context.fixture_names = getattr(context, "fixture_names", set()) | {name}


@given(r"標準入力のバイト列は次の通りである")
def stdin_fixture(context):
    context.stdin_bytes = doc_bytes(context.text)


@when(r"ユーザーが '(?P<command>.*)' を実行する")
def execute(context, command):
    target = Path(os.environ.get("PIN_UPDATER_BDD_SCRIPT", REPO / "src" / "pin_updater.py")).resolve()
    assert target.is_file(), f"BDD target missing: {target}"
    args = shlex.split(command)
    assert args and args[0] == "pin-updater", f"unexpected logical command: {command!r}"
    if len(args) > 1 and "://" in args[1]:
        args[1] = rebase(context, args[1])
    context.before = {
        name: file_state(fixture_path(context, name))
        for name in getattr(context, "fixture_names", set())
    }
    try:
        context.result = run_process(
            [sys.executable, "-I", str(target), *args[1:]], context,
            input=getattr(context, "stdin_bytes", None),
        )
    finally:
        stop_server(context)


@then(r"stdout は JSON として (?P<expected>.*) と等しい")
def json_stdout(context, expected):
    actual, wanted = json.loads(context.result.stdout.decode("utf-8")), json.loads(expected)
    equal(actual, wanted, "stdout JSON structure/value")
    # All specified output fields are strings or null; bool/number equality is insufficient.
    assert isinstance(actual, dict) and all(type(actual[k]) is type(v) for k, v in wanted.items()), "stdout JSON types differ"


@then(r"(?P<stream>stdout|stderr) は空である")
def empty_stream(context, stream):
    equal(getattr(context.result, stream), b"", stream)


@then(r"(?P<stream>stdout|stderr) は '(?P<expected>.*)' である")
def exact_stream(context, stream, expected):
    equal(getattr(context.result, stream), expected.replace(r"\n", "\n").encode("utf-8"), stream)


@then(r"(?P<stream>stdout|stderr) は '(?P<value>.*)' を含まない")
def absent_stream(context, stream, value):
    assert value.replace(r"\n", "\n").encode("utf-8") not in getattr(context.result, stream), f"{stream} unexpectedly contains {value!r}"


@then(r"終了コードは (?P<code>\d+) である")
def exit_code(context, code):
    equal(context.result.returncode, int(code), "exit code")


@then(r"API Mock は '(?P<route>[^']+)' への GET リクエストを (?P<count>\d+) 回だけ受信する")
def receipt_count(context, route, count):
    context.server.check()
    context.server.assert_request_made(RequestMatcher(route, method="GET"), count=int(count))
    equal(len(context.server.log), int(count), "total received HTTP requests")


@then(r"API Mock はリクエストを受信しない")
def no_receipts(context):
    context.server.check()
    equal(context.server.log, [], "received HTTP requests")


@then(r"stdout のバイト列は次の通りである")
def exact_stdout(context):
    equal(context.result.stdout, doc_bytes(context.text), "stdout bytes")


@then(r"ファイル '(?P<name>[^']+)' のバイト列は次の通りである")
def exact_file(context, name):
    equal(fixture_path(context, name).read_bytes(), doc_bytes(context.text), f"{name} bytes")


@then(r"ファイル '(?P<name>[^']+)' のパーミッションは (?P<mode>[0-7]{4}) のままである")
def file_mode(context, name, mode):
    equal(file_state(fixture_path(context, name))[1], int(mode, 8), f"{name} mode")


@then(r"ファイル '(?P<name>[^']+)' の(?P<properties>バイト列|バイト列とパーミッション|バイト列、パーミッション、および inode )は実行前と完全に同じである")
def unchanged_file(context, name, properties):
    old, new = context.before[name], file_state(fixture_path(context, name))
    equal(new[0], old[0], f"{name} bytes")
    if "パーミッション" in properties:
        equal(new[1], old[1], f"{name} mode")
    if "inode" in properties:
        equal(new[2], old[2], f"{name} inode")
