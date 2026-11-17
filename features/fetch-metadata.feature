# language: ja

機能: URL からの pin メタデータの取得

  1つの HTTPS メタデータ URL を受け取り、配布元で確定済みのバージョン文字列と、任意の SHA-256 ハッシュを読み取る。

  使用方法: pin-updater <HTTPS_URL> [--input-format text|json] [--version-key KEY] [--sha256-key KEY]

  --input-format オプションは、入力メタデータのパーサーを明示的に指定する。省略時はレスポンスの Content-Type メディアタイプに基づき、text/plain または application/json を自動選択する。

  application/json と text/plain はともに charset パラメータの付与を許容し、UTF-8 として読み取る。text/plain の場合は、末尾の単一の LF または CRLF をレコード区切り文字として除去し、それ以外の改行は許容しない。

  version の値は、読み取り専用出力（read-only output）においては非 semver 形式や空白を含む文字列も許容するが、空文字列、改行を含む値、およびその他の制御文字は拒否する。

  --file 指定なしの読み取り専用フェッチが成功した場合、stdout 全体を UTF-8 の JSON オブジェクトとして解析でき、その値は `{"version":<JSON string>,"sha256":<JSON string または null>}` とする。キーの順序、空白、改行の表記は規定しない。

  JSON のキー指定はトップレベルオブジェクトのキーのみを対象とし、配列の走査、JSONPath の評価、リリースの順序付け、およびアセットの選択は行わない。選択対象のキーが重複している場合は、後勝ち（last-wins）とはせずエラーとして拒否する。

  本機能における API Mock の Doc String は UTF-8 の YAML 形式で記述し、body は YAML のブロックスカラー値（YAML が付与する末尾の LF を含む）として扱う。stdout の JSON アサーションは stdout 全体を JSON として解析し、意味的等価性（semantic equivalence）によって比較する。

  シナリオ: text/plain から単一のバージョンを取得し、ハッシュなしで返す

    前提 API Mock が次のレスポンスを返す
      """
      route: /releases/text
      method: GET
      response:
        status: 200
        response_headers:
          content-type: text/plain; charset=utf-8
        body: |
          build-2026.10+linux
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/releases/text' を実行する
    ならば stdout は JSON として {"version":"build-2026.10+linux","sha256":null} と等しい
    かつ stderr は空である
    かつ 終了コードは 0 である
    かつ API Mock は '/releases/text' への GET リクエストを 1 回だけ受信する

  シナリオ: application/json の既定のトップレベルキーを正規化して返す

    前提 API Mock が次のレスポンスを返す
      """
      route: /releases/json-default
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"v7.4.0","sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/releases/json-default' を実行する
    ならば stdout は JSON として {"version":"v7.4.0","sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"} と等しい
    かつ stderr は空である
    かつ 終了コードは 0 である
    かつ API Mock は '/releases/json-default' への GET リクエストを 1 回だけ受信する

  シナリオ: charset パラメータ付きの JSON レスポンスをメディアタイプに基づいて処理する

    前提 API Mock が次のレスポンスを返す
      """
      route: /releases/json-charset
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json; charset=UTF-8
        body: |
          {"version":"2026-r1"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/releases/json-charset' を実行する
    ならば stdout は JSON として {"version":"2026-r1","sha256":null} と等しい
    かつ stderr は空である
    かつ 終了コードは 0 である

  シナリオ: 明示的に指定したトップレベルキーからバージョンとハッシュを取得する

    前提 API Mock が次のレスポンスを返す
      """
      route: /releases/custom-keys
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"release":"2026.10-rc+5","digest":"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd","version":"ignore-me"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/releases/custom-keys --version-key release --sha256-key digest' を実行する
    ならば stdout は JSON として {"version":"2026.10-rc+5","sha256":"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"} と等しい
    かつ stderr は空である
    かつ 終了コードは 0 である

  シナリオ: 任意項目である既定の sha256 キーが存在しない JSON は、ハッシュなしで返す

    前提 API Mock が次のレスポンスを返す
      """
      route: /releases/no-hash
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"release_18"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/releases/no-hash' を実行する
    ならば stdout は JSON として {"version":"release_18","sha256":null} と等しい
    かつ stderr は空である
    かつ 終了コードは 0 である

  シナリオ: 明示的な入力形式指定を Content-Type による自動選択より優先する

    前提 API Mock が次のレスポンスを返す
      """
      route: /releases/json-as-text
      method: GET
      response:
        status: 200
        response_headers:
          content-type: text/plain; charset=utf-8
        body: |
          {"version":"v1"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/releases/json-as-text --input-format json' を実行する
    ならば stdout は JSON として {"version":"v1","sha256":null} と等しい
    かつ stderr は空である
    かつ 終了コードは 0 である

  シナリオ: バージョンが semver 形式でなくても有効な文字列であればそのまま返す

    前提 API Mock が次のレスポンスを返す
      """
      route: /releases/non-semver
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"version":"2026-10-29 build 42"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/releases/non-semver' を実行する
    ならば stdout は JSON として {"version":"2026-10-29 build 42","sha256":null} と等しい
    かつ stderr は空である
    かつ 終了コードは 0 である

  シナリオ: 配列形式の JSON から最新リリースを推測せずエラーとする

    前提 API Mock が次のレスポンスを返す
      """
      route: /releases/list
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          [{"version":"v8"},{"version":"v9"}]
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/releases/list' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: metadata JSON must be a top-level object\n' である
    かつ 終了コードは 1 である
    かつ API Mock は '/releases/list' への GET リクエストを 1 回だけ受信する
