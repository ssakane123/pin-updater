# language: ja

機能: 標準入力のメタデータから複数の pin を更新する

  シナリオ: 標準入力の JSON を読み取り、正規化した値を返す

    前提 標準入力のバイト列は次の通りである
      """
      {"version":"release-2","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}
      """
    もし ユーザーが 'pin-updater --stdin' を実行する
    ならば stderr は空である
    かつ stdout は JSON として {"version":"release-2","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"} と等しい
    かつ 終了コードは 0 である
    かつ API Mock はリクエストを受信しない

  シナリオ: URL と標準入力を同時に指定すると使用方法エラーになる

    前提 標準入力のバイト列は次の通りである
      """
      {"version":"release-2","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/metadata --stdin' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: --stdin cannot be used with metadata URL\n' である
    かつ 終了コードは 2 である
    かつ API Mock はリクエストを受信しない

  シナリオ: バージョンと任意の二つのハッシュを一緒に更新する

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=release-1
      HASH_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      HASH_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
      KEEP=unchanged
      """
    かつ 標準入力のバイト列は次の通りである
      """
      {"version":"release-2","sha256_a":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","sha256_b":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}
      """
    もし ユーザーが 'pin-updater --stdin --file pins.env --version-env VERSION --sha256-bind HASH_A=sha256_a --sha256-bind HASH_B=sha256_b' を実行する
    ならば stdout は空である
    かつ stderr は空である
    かつ 終了コードは 0 である
    かつ ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=release-2
      HASH_A=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
      HASH_B=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
      KEEP=unchanged
      """
    かつ API Mock はリクエストを受信しない

  シナリオ: 最後の source ハッシュが不正ならどの値も更新しない

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=release-1
      HASH_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      HASH_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
      KEEP=unchanged
      """
    かつ 標準入力のバイト列は次の通りである
      """
      {"version":"release-2","sha256_a":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","sha256_b":"invalid"}
      """
    もし ユーザーが 'pin-updater --stdin --file pins.env --version-env VERSION --sha256-bind HASH_A=sha256_a --sha256-bind HASH_B=sha256_b' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: metadata key "sha256_b" must be a lowercase 64-character hexadecimal string\n' である
    かつ 終了コードは 1 である
    かつ ファイル 'pins.env' のバイト列は実行前と完全に同じである
    かつ API Mock はリクエストを受信しない

  シナリオ: 最後の対象変数が欠落していればどの値も更新しない

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=release-1
      HASH_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      KEEP=unchanged
      """
    かつ 標準入力のバイト列は次の通りである
      """
      {"version":"release-2","sha256_a":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","sha256_b":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}
      """
    もし ユーザーが 'pin-updater --stdin --file pins.env --version-env VERSION --sha256-bind HASH_A=sha256_a --sha256-bind HASH_B=sha256_b' を実行する
    ならば stdout は空である
    かつ stderr は 'ERROR: variable "HASH_B" is missing or not unique\n' である
    かつ 終了コードは 1 である
    かつ ファイル 'pins.env' のバイト列は実行前と完全に同じである
    かつ API Mock はリクエストを受信しない

  シナリオアウトライン: ハッシュとバージョンの対象変数の重複を拒否する

    前提 ファイル 'pins.env' のバイト列は次の通りである
      """
      VERSION=release-1
      HASH_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      HASH_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
      KEEP=unchanged
      """
    かつ 標準入力のバイト列は次の通りである
      """
      {"version":"release-2","sha256_a":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","sha256_b":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}
      """
    もし ユーザーが 'pin-updater --stdin --file pins.env --version-env VERSION <bindings>' を実行する
    ならば stdout は空である
    かつ stderr は '<error>' である
    かつ 終了コードは 2 である
    かつ ファイル 'pins.env' のバイト列は実行前と完全に同じである
    かつ API Mock はリクエストを受信しない

    例:
      | bindings | error |
      | --sha256-bind HASH_A=sha256_a --sha256-bind HASH_A=sha256_b | ERROR: --sha256-bind target variables must be unique\n |
      | --sha256-bind VERSION=sha256_a | ERROR: --version-env and --sha256-bind targets must differ\n |
