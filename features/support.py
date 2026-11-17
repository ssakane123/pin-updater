"""Small acceptance-only helpers; no CLI implementation or execution instrumentation."""

import os
from pathlib import Path
import signal
import stat
import subprocess
from urllib.parse import urlsplit, urlunsplit

import yaml


REPO = Path(__file__).resolve().parents[1]


def equal(actual, expected, label):
    assert actual == expected, f"{label}: expected {expected!r}, got {actual!r}"


def doc_bytes(text, initial=None):
    # Only Examples' file snippets decode \n; ordinary Doc Strings remain literal.
    value = initial.replace(r"\n", "\n") if initial is not None else str(text)
    return (value + "\n").encode("utf-8")


def mock_spec(text):
    # Restore the LF Behave removes, before YAML applies block-scalar chomping.
    data = yaml.safe_load(str(text) + "\n")
    assert isinstance(data, dict) and set(data) == {"route", "method", "response"}, "invalid API Mock fields"
    assert isinstance(data["route"], str) and data["route"].startswith("/"), "invalid route"
    assert data["method"] == "GET", "only GET fixtures are supported"
    response = data["response"]
    assert isinstance(response, dict) and set(response) == {"status", "response_headers", "body"}, "invalid response fields"
    assert type(response["status"]) is int and 100 <= response["status"] <= 599, "invalid status"
    headers = response["response_headers"]
    assert isinstance(headers, dict) and all(isinstance(k, str) and isinstance(v, str) for k, v in headers.items()), "invalid headers"
    assert all("\n" not in k + v and "\r" not in k + v for k, v in headers.items()), "invalid header newline"
    assert isinstance(response["body"], str), "body must be literal text"
    return data


def fixture_path(context, name):
    path = context.work / name
    assert not Path(name).is_absolute() and path.resolve().is_relative_to(context.work), "fixture path escapes workspace"
    return path


def file_state(path):
    info = path.stat()
    return path.read_bytes(), stat.S_IMODE(info.st_mode), info.st_ino


def child_environment(context):
    # Do not inherit credentials, proxies, Python startup injection or caller HOME.
    return {
        "PATH": os.defpath, "HOME": str(context.home), "LANG": "C.UTF-8",
        "SSL_CERT_FILE": str(context.ca_file),
        "REQUESTS_CA_BUNDLE": str(context.ca_file), "CURL_CA_BUNDLE": str(context.ca_file),
        "NO_PROXY": "*", "no_proxy": "*",
    }


def rebase(context, value):
    url = urlsplit(value)
    if url.scheme != "https":
        return value  # Invalid non-HTTPS arguments must reach CLI validation unchanged.
    assert url.hostname and url.hostname.endswith(".example.test"), "non-fixture HTTPS URL refused"
    assert url.username is None and url.password is None and url.port is None, "invalid fixture authority"
    return urlunsplit(("https", f"127.0.0.1:{context.server.port}", url.path, url.query, url.fragment))


def run_process(argv, context, timeout=15, input=None):
    with subprocess.Popen(argv, cwd=context.work, env=child_environment(context), shell=False,
                          stdin=subprocess.PIPE if input is not None else None,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True) as child:
        try:
            stdout, stderr = child.communicate(input=input, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            os.killpg(child.pid, signal.SIGKILL)
            child.communicate()
            raise AssertionError(f"acceptance watchdog expired after {timeout}s; not a CLI transport timeout") from error
        finally:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    return subprocess.CompletedProcess(argv, child.returncode, stdout, stderr)


def stop_server(context):
    context.release.set()
    if context.server.is_running():
        listener = context.server.server
        try:
            context.server.stop()
        finally:
            listener.server_close()
