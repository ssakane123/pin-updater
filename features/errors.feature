# language: ja

機能: URL 起点の pin 更新における失敗の決定的かつ非破壊的な処理

  使用方法（usage）やフラグの組み合わせが不正な場合は、HTTP リクエストおよびファイル書き込みを行う前に終了コード 2 で停止する。

  取得元（source）、レスポンス、タイムアウト、または対象ファイルの実行時検証（operational validation）に失敗した場合は、終了コード 1 で停止する。

  いかなる失敗においても stdout は空とし、stderr には `ERROR: ` で始まる UTF-8 の 1 行（末尾の単一 LF を含む）のみを出力する。レスポンスボディ、トークン、クエリパラメータ、および URL 全体は stderr に出力しない。

  本機能における API Mock の Doc String は UTF-8 の YAML 形式で記述し、body は YAML のブロックスカラー値（YAML が付与する末尾の LF を含む）として扱う。ファイル前提の Doc String は、表示した UTF-8 の内容に末尾 LF 一つを加えたバイト列を表す。シングルクォートで囲まれたステップ値およびテーブル値内の `\n` は、単一バイトの LF としてデコードする。

  メタデータのレスポンスバイト列をアーティファクト本体とみなしてダウンロードしたり、その SHA-256 を計算したりする処理は行わない。また、リトライも一切行わない。

  シナリオアウトライン: 不正なコマンド呼び出しは、リクエスト送信およびファイル書き込みの前に usage エラーとする

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=old
      """
    もし ユーザーが '<command>' を実行する
    ならば stdout は空である
    かつ stderr は '<error>' である
    かつ 終了コードは 2 である
    かつ API Mock はリクエストを受信しない
    かつ ファイル 'pins.env' のバイト列は実行前と完全に同じである

    例:
      | command | error |
      | pin-updater | ERROR: missing metadata URL\n |
      | pin-updater https://metadata.example.test/a --unknown | ERROR: unknown option: --unknown\n |
      | pin-updater https://metadata.example.test/a --input-format | ERROR: missing value for --input-format\n |
      | pin-updater https://metadata.example.test/a --input-format yaml | ERROR: --input-format must be text or json\n |
      | pin-updater https://metadata.example.test/a --version-key | ERROR: missing value for --version-key\n |
      | pin-updater https://metadata.example.test/a --sha256-key | ERROR: missing value for --sha256-key\n |
      | pin-updater https://metadata.example.test/a --input-format text --version-key version | ERROR: --input-format text cannot be used with --version-key or --sha256-key\n |
      | pin-updater https://metadata.example.test/a --input-format text --sha256-key sha256 | ERROR: --input-format text cannot be used with --version-key or --sha256-key\n |
      | pin-updater https://metadata.example.test/a --file pins.env | ERROR: --file requires --version-env\n |
      | pin-updater https://metadata.example.test/a --version-env VERSION | ERROR: --version-env requires --file\n |
      | pin-updater https://metadata.example.test/a --sha256-env SHA256 | ERROR: --sha256-env requires --file and --version-env\n |
      | pin-updater https://metadata.example.test/a --dry-run | ERROR: --dry-run requires --file and --version-env\n |
      | pin-updater https://metadata.example.test/a --file pins.env --version-env VERSION --sha256-env VERSION | ERROR: --version-env and --sha256-env must differ\n |
      | pin-updater http://metadata.example.test/a | ERROR: metadata URL must use HTTPS\n |

  シナリオ: 未サポートの Content-Type ではメタデータを推測せずエラーとする

    前提 API Mock が次のレスポンスを返す
      """
      route: /metadata/html
      method: GET
      response:
        status: 200
        response_headers:
          content-type: text/html; charset=utf-8
        body: |
          <html><body>v99</body></html>
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/html' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: unsupported metadata Content-Type\n' である
    かつ 終了コードは 1 である
    かつ API Mock は '/metadata/html' への GET リクエストを 1 回だけ受信する

  シナリオアウトライン: 自動選択された text パーサー使用時に、キー指定オプションを無視せずエラーとする

    前提 API Mock が次のレスポンスを返す
      """
      route: /metadata/text-with-selector
      method: GET
      response:
        status: 200
        response_headers:
          content-type: text/plain; charset=utf-8
        body: |
          v1
      """
    もし ユーザーが '<command>' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: metadata key selectors require JSON metadata\n' である
    かつ 終了コードは 1 である
    かつ API Mock は '/metadata/text-with-selector' への GET リクエストを 1 回だけ受信する

    例:
      | command |
      | pin-updater https://metadata.example.test/metadata/text-with-selector --version-key version |
      | pin-updater https://metadata.example.test/metadata/text-with-selector --sha256-key sha256 |

  シナリオ: text/plain にバージョン行が 2 行ある場合はメタデータエラーとする

    前提 API Mock が次のレスポンスを返す
      """
      route: /metadata/two-text-lines
      method: GET
      response:
        status: 200
        response_headers:
          content-type: text/plain; charset=utf-8
        body: |
          first
          second
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/two-text-lines' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: text metadata must contain exactly one version line\n' である
    かつ 終了コードは 1 である
    かつ API Mock は '/metadata/two-text-lines' への GET リクエストを 1 回だけ受信する

  シナリオアウトライン: JSON のバージョンは、指定されたトップレベルキーの文字列でなければならない

    前提 API Mock が次のレスポンスを返す
      """
      route: /metadata/bad-version
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          <body>
      """
    もし ユーザーが '<command>' を実行する
    ならば stdout は空である
    かつ stderr は '<error>' である
    かつ 終了コードは 1 である
    かつ API Mock は '/metadata/bad-version' への GET リクエストを 1 回だけ受信する

    例:
      | body | command | error |
      | {not-json | pin-updater https://metadata.example.test/metadata/bad-version | ERROR: metadata JSON is invalid\n |
      | {"version":7} | pin-updater https://metadata.example.test/metadata/bad-version | ERROR: metadata key "version" must be a string\n |
      | {"version":null} | pin-updater https://metadata.example.test/metadata/bad-version | ERROR: metadata key "version" must be a string\n |
      | {"version":["v1"]} | pin-updater https://metadata.example.test/metadata/bad-version | ERROR: metadata key "version" must be a string\n |
      | {"release":"v1"} | pin-updater https://metadata.example.test/metadata/bad-version | ERROR: metadata key "version" is missing\n |
      | {"version":"v1"} | pin-updater https://metadata.example.test/metadata/bad-version --version-key release | ERROR: metadata key "release" is missing\n |

  シナリオアウトライン: 空文字列、複数行、または制御文字を含むバージョンは拒否する

    前提 API Mock が次のレスポンスを返す
      """
      route: /metadata/invalid-version-content
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          <body>
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/invalid-version-content' を実行する
    ならば stdout は空である
    かつ stderr は '<error>' である
    かつ 終了コードは 1 である
    かつ API Mock は '/metadata/invalid-version-content' への GET リクエストを 1 回だけ受信する

    例:
      | body | error |
      | {"version":""} | ERROR: metadata version must not be empty\n |
      | {"version":"first\\u000asecond"} | ERROR: metadata version must not contain control characters\n |
      | {"version":"nul\\u0000byte"} | ERROR: metadata version must not contain control characters\n |

  シナリオアウトライン: 選択対象の JSON キーが重複している場合は、フォールバックや後勝ち（last-wins）にせずエラーとする

    前提 API Mock が次のレスポンスを返す
      """
      route: /metadata/duplicate-key
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          <body>
      """
    もし ユーザーが '<command>' を実行する
    ならば stdout は空である
    かつ stderr は '<error>' である
    かつ 終了コードは 1 である
    かつ API Mock は '/metadata/duplicate-key' への GET リクエストを 1 回だけ受信する

    例:
      | body | command | error |
      | {"version":"v1","version":"v2"} | pin-updater https://metadata.example.test/metadata/duplicate-key | ERROR: metadata JSON contains duplicate selected key "version"\n |
      | {"release":"v1","release":"v2"} | pin-updater https://metadata.example.test/metadata/duplicate-key --version-key release | ERROR: metadata JSON contains duplicate selected key "release"\n |
      | {"version":"v1","sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","sha256":"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"} | pin-updater https://metadata.example.test/metadata/duplicate-key | ERROR: metadata JSON contains duplicate selected key "sha256"\n |

  シナリオ: 明示的に指定した sha256 キーが存在しない場合は、ハッシュなしへフォールバックせずエラーとする

    前提 API Mock が次のレスポンスを返す
      """
      route: /metadata/missing-required-hash
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"v1"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/missing-required-hash --sha256-key digest' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: metadata key "digest" is missing\n' である
    かつ 終了コードは 1 である

  シナリオ: 読み取り専用フェッチであっても、既定の sha256 キーの形式を検証する

    前提 API Mock が次のレスポンスを返す
      """
      route: /metadata/invalid-default-sha
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"v1","sha256":"ABCDEF"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/invalid-default-sha' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: metadata key "sha256" must be a lowercase 64-character hexadecimal string\n' である
    かつ 終了コードは 1 である
    かつ API Mock は '/metadata/invalid-default-sha' への GET リクエストを 1 回だけ受信する

  シナリオアウトライン: --sha256-env 指定時は、正確な小文字 64 文字の 16 進数文字列を必須とする

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=old
      SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      """
    かつ API Mock が次のレスポンスを返す
      """
      route: /metadata/bad-hash
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"new","sha256":<hash>}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/bad-hash --file pins.env --version-env VERSION --sha256-env SHA256' を実行する
    ならば stdout は空である
    かつ stderr は '<error>' である
    かつ 終了コードは 1 である
    かつ ファイル 'pins.env' のバイト列は実行前と完全に同じである

    例:
      | hash | error |
      | null | ERROR: metadata key "sha256" must be a lowercase 64-character hexadecimal string\n |
      | "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD" | ERROR: metadata key "sha256" must be a lowercase 64-character hexadecimal string\n |
      | "abcdef" | ERROR: metadata key "sha256" must be a lowercase 64-character hexadecimal string\n |

  シナリオ: --sha256-env 指定時にメタデータにハッシュが存在しない場合は、ファイルを変更せずエラーとする

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=old
      SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      """
    かつ API Mock が次のレスポンスを返す
      """
      route: /metadata/no-hash-for-binding
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"new"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/no-hash-for-binding --file pins.env --version-env VERSION --sha256-env SHA256' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: metadata sha256 is required by --sha256-env\n' である
    かつ 終了コードは 1 である
    かつ ファイル 'pins.env' のバイト列は実行前と完全に同じである

  シナリオアウトライン: HTTP エラー時はレスポンスボディやクエリを出力せず、リトライもしない

    前提 API Mock が次のレスポンスを返す
      """
      route: /metadata/http-error
      method: GET
      response:
        status: <status>
        response_headers:
          content-type: text/plain
        body: |
          token=super-secret-response-body
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/http-error?access_token=secret-query' を実行する
    ならば stdout は空である
    かつ stderr は '<error>' である
    かつ stderr は 'super-secret-response-body' を含まない
    かつ stderr は 'secret-query' を含まない
    かつ 終了コードは 1 である
    かつ API Mock は '/metadata/http-error' への GET リクエストを 1 回だけ受信する

    例:
      | status | error |
      | 403 | ERROR: metadata request failed: HTTP 403\n |
      | 429 | ERROR: metadata request failed: HTTP 429\n |
      | 500 | ERROR: metadata request failed: HTTP 500\n |

  シナリオ: タイムアウト時は、受信済み HTTP GET をリトライせずファイルも変更しない

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=old
      """
    かつ API Mock の '/metadata/transport' は 'timeout' を返す
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata/transport --file pins.env --version-env VERSION' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: metadata request timed out\n' である
    かつ 終了コードは 1 である
    かつ API Mock は '/metadata/transport' への GET リクエストを 1 回だけ受信する
    かつ ファイル 'pins.env' のバイト列は実行前と完全に同じである

  シナリオアウトライン: 対象ファイル内の変数宣言にエラーがある場合は、更新値を書き込まない

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      <initial>
      """
    かつ API Mock が次のレスポンスを返す
      """
      route: /metadata/file-validation
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"new","sha256":"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"}
      """
    もし ユーザーが '<command>' を実行する
    ならば stdout は空である
    かつ stderr は '<error>' である
    かつ 終了コードは 1 である
    かつ ファイル 'pins.env' のバイト列は実行前と完全に同じである

    例:
      | initial | command | error |
      | OTHER=old | pin-updater https://metadata.example.test/metadata/file-validation --file pins.env --version-env VERSION | ERROR: variable "VERSION" is missing or not unique\n |
      | VERSION=old\nVERSION=older | pin-updater https://metadata.example.test/metadata/file-validation --file pins.env --version-env VERSION | ERROR: variable "VERSION" is missing or not unique\n |
      | VERSION=old\nSHA256=one\nSHA256=two | pin-updater https://metadata.example.test/metadata/file-validation --file pins.env --version-env VERSION --sha256-env SHA256 | ERROR: variable "SHA256" is missing or not unique\n |
      | export VERSION=old | pin-updater https://metadata.example.test/metadata/file-validation --file pins.env --version-env VERSION | ERROR: variable "VERSION" is missing or not unique\n |
