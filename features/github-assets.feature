# language: ja

機能: 指定した GitHub release asset のメタデータを pin に変換する

  選択済み release の assets 内で名前が完全一致する唯一の asset の digest を取得する。
  digest は sha256: に続く小文字 64 桁の 16 進数のみを受け付け、接頭辞を除いた値を既存の sha256 として扱う。

  シナリオ: 完全一致した asset の digest を返し、類似名とトップレベル sha256 を選ばない

    前提 API Mock が次のレスポンスを返す
      """
      route: /releases/latest
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          {"tag_name":"build 42 candidate","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","assets":[{"name":"uv-installer.sh.sig","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"name":"uv-installer.sh","digest":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"},{"name":"uv-installer.sh.old","digest":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}]}
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/releases/latest --version-key tag_name --github-asset uv-installer.sh' を実行する
    ならば stderr は空である
    かつ stdout は JSON として {"version":"build 42 candidate","sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"} と等しい
    かつ 終了コードは 0 である
    かつ API Mock は '/releases/latest' への GET リクエストを 1 回だけ受信する

  シナリオアウトライン: 不正な asset の選択または digest は取得後に拒否する

    前提 API Mock が次のレスポンスを返す
      """
      route: /releases/latest
      method: GET
      response:
        status: 200
        response_headers:
          content-type: application/json
        body: |
          <body>
      """
    もし ユーザーが 'pin-updater https://metadata.example.test/releases/latest --version-key tag_name --github-asset uv-installer.sh' を実行する
    ならば stdout は空である
    かつ stderr は '<error>' である
    かつ 終了コードは 1 である
    かつ API Mock は '/releases/latest' への GET リクエストを 1 回だけ受信する

    例:
      | body | error |
      | {"tag_name":"v1","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","assets":[{"name":"uv-installer.sh.sig","digest":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}]} | ERROR: github asset must match exactly one asset\n |
      | {"tag_name":"v1","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","assets":[{"name":"uv-installer.sh","digest":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"},{"name":"uv-installer.sh","digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111"}]} | ERROR: github asset must match exactly one asset\n |
      | {"tag_name":"v1","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","assets":[{"name":"uv-installer.sh"}]} | ERROR: github asset digest is missing\n |
      | {"tag_name":"v1","sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","assets":[{"name":"uv-installer.sh","digest":"sha512:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}]} | ERROR: github asset digest must be sha256: followed by 64 lowercase hexadecimal characters\n |
