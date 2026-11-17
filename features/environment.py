import ssl
import tempfile
from pathlib import Path
from threading import Event

from pytest_httpserver import HTTPServer
import trustme

from features.support import stop_server


def before_feature(context, feature):
    # Behave 1.3.3 leaves doubled backslashes in Examples cells intact.
    # Decode only those cells, before expansion; ordinary Doc Strings stay raw.
    for scenario in feature.scenarios:
        for example in getattr(scenario, "examples", ()):
            for row in example.table:
                row.cells[:] = [cell.replace("\\\\", "\\") for cell in row.cells]


def before_scenario(context, scenario):
    temporary = tempfile.TemporaryDirectory(prefix="pin-updater-acceptance-")
    context.add_cleanup(temporary.cleanup)
    context.root = Path(temporary.name)
    context.work = context.root / "work"
    context.home = context.root / "home"
    context.work.mkdir()
    context.home.mkdir()
    ca = trustme.CA()
    context.ca_file = context.root / "ca.pem"
    ca.cert_pem.write_to_path(context.ca_file)
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ca.issue_cert("127.0.0.1").configure_cert(tls)
    context.server = HTTPServer(host="127.0.0.1", port=0, ssl_context=tls, threaded=True)
    context.release = Event()
    context.add_cleanup(stop_server, context)
    context.server.start()
