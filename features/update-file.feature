# language: ja

機能: 解決した pin の単一ローカルファイルへの安全な反映

  使用方法: pin-updater <HTTPS_URL> --file FILE --version-env NAME [--sha256-env NAME] [--version-key KEY] [--sha256-key KEY] [--input-format text|json] [--dry-run]

  --file と --version-env は常に対で指定する。エディタ処理は、行頭（カラム 0）から始まるプレーンなシェル変数定義（NAME=value）または Dockerfile の ARG 宣言（ARG NAME=value）のリテラルのみを読み取る。

  対象ファイルの source や実行（execute）は一切行わない。メタデータレスポンスの値はデータとしてのみ扱い、コマンドとして実行しない。対象の変数宣言はファイル内で一意でなければならず、バージョン用とハッシュ用の変数名は互いに異なる必要がある。

  読み取り専用フェッチ（read-only fetch）では空白を含む非 semver 形式のバージョンも返せるが、クォートなしリテラル（unquoted literal）へ書き込むバージョンは ASCII の `[A-Za-z0-9][A-Za-z0-9._+:-]{0,199}` のみを許容し、それ以外の値はシェルや Dockerfile へのインジェクションを防ぐため書き込み前に拒否する。

  バージョンとハッシュは全 source/local validation の完了後に更新し、成功時は両方の期待値を保持する。validation error では元のバイト列を保持する。書き換え回数や OS レベルの atomicity、途中状態・クラッシュ耐性は規定しない。

  --file を伴う通常の更新処理および変更なし（no-op）が正常終了した場合、stdout と stderr はともに空とし、終了コードは 0 とする。変更なし（no-op）の場合はファイルを書き換えない。

  --dry-run の使用には --file と --version-env の指定を必須とする。差分がある場合は stdout に JSON サマリーを出力せず、1行の `--- FILE`、1行の `+++ FILE`、および unified diff のみをこの順序で出力する。差分がない場合は stdout と stderr をともに空とする。dry-run は対象ファイルを一切書き換えない。

  「バイト列は次の通りである」で示すファイルおよび stdout の Doc String は、記載された UTF-8 の各行に末尾の単一 LF を加えた正確なバイト列（exact bytes）を表す。API Mock の Doc String は UTF-8 の YAML 形式で記述し、body は YAML のブロックスカラー値として扱う。

  シナリオ: Dockerfile のバージョンリテラルのみを更新する

    前提 ファイル 'Containerfile' のパーミッションが 0640 であり、バイト列は次の通りである
      """
      FROM example/base:1
      ARG TOOL_VERSION=old-release
      RUN install-tool "$TOOL_VERSION"
      """
    かつ API Mock が次のレスポンスを返す
      """
      route: /metadata/version-only
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"release-2026.10"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/version-only --file Containerfile --version-env TOOL_VERSION' を実行する
    ならば stdout は空である
    かつ stderr は空である
    かつ 終了コードは 0 である
    かつ ファイル 'Containerfile' のバイト列は次の通りである
      """
      FROM example/base:1
      ARG TOOL_VERSION=release-2026.10
      RUN install-tool "$TOOL_VERSION"
      """
    かつ ファイル 'Containerfile' のパーミッションは 0640 のままである

  シナリオ: シェル形式のバージョンとハッシュを検証後、両方の値を更新する

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=old
      SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      KEEP=this-line-is-unrelated
      """
    かつ API Mock が次のレスポンスを返す
      """
      route: /metadata/tuple
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"2026.10","sha256":"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/tuple --file pins.env --version-env VERSION --sha256-env SHA256' を実行する
    ならば stdout は空である
    かつ stderr は空である
    かつ 終了コードは 0 である
    かつ ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=2026.10
      SHA256=abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd
      KEEP=this-line-is-unrelated
      """

  シナリオ: dry-run ではファイルを変更せず、規定の unified diff を出力する

    前提 ファイル 'pins.env' のパーミッションが 0600 であり、バイト列は次の通りである
      """
      VERSION=old
      """
    かつ API Mock が次のレスポンスを返す
      """
      route: /metadata/dry-run
      method: GET
      response:
        status: 200
        response_headers:
          content-type: text/plain; charset=utf-8
        body: |
          new
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/dry-run --file pins.env --version-env VERSION --dry-run' を実行する
    ならば stdout のバイト列は次の通りである
      """
      --- pins.env
      +++ pins.env
      @@ -1 +1 @@
      -VERSION=old
      +VERSION=new
      """
    かつ stdout は '{"version":' を含まない
    かつ stderr は空である
    かつ 終了コードは 0 である
    かつ ファイル 'pins.env' のバイト列とパーミッションは実行前と完全に同じである

  シナリオ: すべての値が同一の場合は変更なし（no-op）とし、ファイルのバイト列・パーミッション・inode を維持する

    前提 ファイル 'pins.env' のパーミッションが 0644 であり、inode を保持し、バイト列は次の通りである
      """
      VERSION=v3
      SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
      """
    かつ API Mock が次のレスポンスを返す
      """
      route: /metadata/no-op
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"v3","sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/no-op --file pins.env --version-env VERSION --sha256-env SHA256' を実行する
    ならば stdout は空である
    かつ stderr は空である
    かつ 終了コードは 0 である
    かつ ファイル 'pins.env' のバイト列、パーミッション、および inode は実行前と完全に同じである

  シナリオ: --sha256-env を指定しない更新では、メタデータ内のハッシュをファイルに書き込まない

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=v1
      OTHER_SHA=unchanged
      """
    かつ API Mock が次のレスポンスを返す
      """
      route: /metadata/unbound-hash
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"v2","sha256":"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/unbound-hash --file pins.env --version-env VERSION' を実行する
    ならば stdout は空である
    かつ stderr は空である
    かつ 終了コードは 0 である
    かつ ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=v2
      OTHER_SHA=unchanged
      """

  シナリオ: dry-run で変更がない（no-op）場合は、stdout と stderr を空のままにする

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=v2
      """
    かつ API Mock が次のレスポンスを返す
      """
      route: /metadata/dry-no-op
      method: GET
      response:
        status: 200
        response_headers:
          content-type: text/plain
        body: |
          v2
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/dry-no-op --file pins.env --version-env VERSION --dry-run' を実行する
    ならば stdout は空である
    かつ stderr は空である
    かつ 終了コードは 0 である
    かつ ファイル 'pins.env' のバイト列とパーミッションは実行前と完全に同じである

  シナリオ: クォートなしリテラルに安全でない値は拒否する

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=old
      """
    かつ API Mock が次のレスポンスを返す
      """
      route: /metadata/unsafe-write-value
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"release;candidate"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/unsafe-write-value --file pins.env --version-env VERSION' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: version is unsafe for an unquoted literal\n' である
    かつ 終了コードは 1 である
    かつ ファイル 'pins.env' のバイト列は実行前と完全に同じである
