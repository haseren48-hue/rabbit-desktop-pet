# 保存内容と復元方法

このリポジトリには、うさぎデスクトップペットのソースコード、画像素材、ビルド用スクリプトを保存しています。元のREADME.mdもそのまま収録しています。

非公開のRelease「local-archive-2026-11-16」には、次のファイルがあります。

- `rabbit-desktop-pet-full-backup.tar.gz`には、開発フォルダ全体、デスクトップのアプリ、日記、設定、関連する生成画像を保存しています。開発フォルダにはビルド生成物と元のGit管理情報も含みます。
- `rabbit-desktop-pet-macos.zip`には、デスクトップに置いていたアプリを保存しています。
- `file-manifest.json`には、元の保存場所、ファイルごとのSHA-256、サイズ、アクセス権、シンボリックリンクの参照先を記録しています。
- `SHA256SUMS`には、上記3ファイルのSHA-256を記録しています。

## アプリを戻す

1. Releaseから`rabbit-desktop-pet-macos.zip`をダウンロードします。
2. ZIPを展開し、アプリを任意のフォルダに置きます。
3. 必要に応じて、macOSの設定でアクセシビリティへのアクセスを許可します。

## 日記と開発フォルダを戻す

1. Releaseから完全バックアップと`file-manifest.json`をダウンロードします。
2. 完全バックアップを空のフォルダに展開します。
3. `development-project`を開発用フォルダへ戻します。日記は`application-data/.diary`にあります。`application-data`を`~/Library/Application Support/RabbitDesktopPet`へ戻すと、アプリから読み込めます。

完全バックアップには個人の日記が含まれます。保存先は非公開リポジトリです。
